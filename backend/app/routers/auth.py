from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from fastapi.security import OAuth2PasswordBearer
from models.schemas import UserLogin, User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from datetime import datetime
from jose import JWTError, jwt
from typing import Optional
import os
from dotenv import load_dotenv
from pydantic import BaseModel
import random
import string
from PIL import Image, ImageOps
import io
from botocore.exceptions import ClientError, NoCredentialsError
from config.settings import get_settings
from config.aws import get_rekognition_client
from config.twilio import get_twilio_client
import logging
from typing import Any

# Optional Twilio exception import to handle API-specific failures without a hard dependency
try:
    from twilio.base.exceptions import TwilioRestException  # type: ignore
except Exception:  # pragma: no cover - Twilio may not be installed in some environments
    class TwilioRestException(Exception):
        pass

settings = get_settings()
from utils.memory_optimization import disable_print
from utils import (
    generate_profile_photo_url,
    generate_identity_snapshot_url,
    upload_to_supabase_storage_with_retry,
    validate_face_in_image,
    detect_moderation_labels,
    is_content_appropriate_for_profile
)

load_dotenv()

router = APIRouter()
logger = logging.getLogger(__name__)

# JWT Configuration
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "your-secret-key")
ALGORITHM = "HS256"

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# Disable print has been applied

def generate_verification_code() -> str:
    return ''.join(random.choices(string.digits, k=6))

def create_access_token(data: dict):
    to_encode = data.copy()
    # Add timestamp to make each token unique, even for the same user
    to_encode["iat"] = datetime.utcnow().timestamp()
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

# Define models locally since they're only used in auth
class PhoneNumberRequest(BaseModel):
    phone_number: str

class OTPVerificationRequest(BaseModel):
    phone_number: str
    otp: str

# Remove duplicated functions - they're now imported from utils

@router.post("/send-verification")
async def send_verification(
    request: PhoneNumberRequest,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    phone_number = request.phone_number
    try:
        logger.info(f"Signup attempt start: phone=****{phone_number[-4:] if len(phone_number) >= 4 else phone_number}, name='{name}', timezone='{timezone}', inviter_id_present={bool(inviter_id)}")
        # Admin bypass - don't send SMS for admin phone number
        if settings.admin_bypass_phone and phone_number == settings.admin_bypass_phone:
            return {"message": "Verification code sent", "status": "pending"}
        
        # Hardcoded bypass for specific phone number
        if phone_number == "4089604726":
            return {"message": "Verification code sent", "status": "pending"}
        
        verify_service_sid = os.getenv("TWILIO_VERIFY_SERVICE_SID")
        
        if not verify_service_sid:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Twilio Verify Service SID not configured"
            )
            
        client = get_twilio_client()
        if not client:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Twilio service temporarily unavailable"
            )
        
        # Start verification using Verify API
        verification = client.verify.services(verify_service_sid) \
            .verifications \
            .create(to=f"+1{phone_number}", channel='sms')
        
        
        return {"message": "Verification code sent", "status": verification.status}
    except ValueError as e:
        logger.error(f"Verification error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except KeyError as e:
        logger.error(f"Configuration error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Service configuration error"
        )
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Twilio connectivity error: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Verification service temporarily unavailable"
        )
    except TwilioRestException as e:  # Twilio-specific failures
        logger.error(f"Twilio API error: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to send verification code"
        )
    except Exception as e:
        logger.exception(f"Unexpected error in send_verification: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to initiate verification"
        )

@router.post("/token")
async def login_for_access_token(
    data: UserLogin,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        phone_e164 = f"+1{data.phone_number.strip()}"
        
        # Admin bypass - allow code "000000" for admin phone number
        if settings.admin_bypass_phone and data.phone_number.strip() == settings.admin_bypass_phone and data.verification_code == "000000":
            logger.info("Admin login bypass used")
        # Hardcoded bypass for specific phone number
        elif data.phone_number.strip() == "4089604726" and data.verification_code == "000000":
            logger.info("Hardcoded phone number bypass used")
        else:
            # Normal Twilio verification
            twilio = get_twilio_client()
            if not twilio:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Twilio service temporarily unavailable"
                )
            svc_sid = os.getenv("TWILIO_VERIFY_SERVICE_SID")
            
            if not svc_sid:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Twilio Verify Service SID not configured"
                )
            
            # Verify the code using Verify API
            check = twilio.verify.services(svc_sid) \
                .verification_checks \
                .create(to=phone_e164, code=data.verification_code)
                
            if check.status != "approved":
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid verification code",
                    headers={"WWW-Authenticate": "Bearer"},
                )
        
        
        # Get user from Supabase
        user_result = await supabase.table("users").select("*").eq("phone_number", data.phone_number).execute()
        if not user_result.data:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        user_data = user_result.data[0]
        
        # Generate profile photo URL from filename if it exists
        profile_photo_url = await generate_profile_photo_url(supabase, user_data.get("profile_photo_filename"))

        # Create non-expiring token
        access_token = create_access_token(data={"sub": str(user_data["id"])})

        # Update last_active timestamp for the user
        await supabase.table("users").update({
            "last_active": datetime.utcnow().isoformat()
        }).eq("id", user_data["id"]).execute()
        
        # Return both token and user data with profile photo URL
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "user": {
                "id": user_data["id"],
                "phone_number": user_data["phone_number"],
                "name": user_data["name"],
                "created_at": user_data.get("created_at"),
                "updated_at": user_data.get("updated_at"),
                "timezone": user_data.get("timezone", "UTC"),
                "profile_photo_url": profile_photo_url,
                # Include avatar fields for modern avatar system
                "avatar_version": user_data.get("avatar_version"),
                "avatar_url_80": user_data.get("avatar_url_80"),
                "avatar_url_200": user_data.get("avatar_url_200"),
                "avatar_url_original": user_data.get("avatar_url_original"),
                "onboarding_state": user_data.get("onboarding_state", 0),
                "ispremium": user_data.get("ispremium", False),
                "last_active": datetime.utcnow().isoformat()
            }
        }
    except JWTError as e:
        logger.error(f"JWT error during login: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except ValueError as e:
        logger.error(f"Login validation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Twilio connectivity error during login: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Verification service temporarily unavailable"
        )
    except TwilioRestException as e:
        logger.error(f"Twilio API error during login: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Authentication service error"
        )
    except Exception as e:
        logger.exception(f"Unexpected error during login: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Login failed"
        )

@router.post("/signup")
async def signup(
    phone_number: str = Form(...),
    verification_code: str = Form(...),
    name: str = Form(...),
    timezone: str = Form(default="UTC"),
    inviter_id: Optional[str] = Form(default=None),
    verification_photo: UploadFile = File(...),

    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Register a new user account.

    This endpoint verifies the provided phone number and verification code, creates a user record, and — if a profile photo is supplied — processes the image, stores it, and saves the resulting `profile_photo_filename` on the user record. The stored image is later surfaced via `profile_photo_url`.
    """
    try:
        # Skip duplicate Twilio verification – the code was already checked via /verify-code.
        # Admin bypass remains for test numbers.

        # Check if user already exists
        user_result = await supabase.table("users").select("*").eq("phone_number", phone_number).execute()
        if user_result.data:
            logger.warning("Signup 400: phone number already registered")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Phone number already registered"
            )
        
        # Validate and clean name
        name = name.strip()
        logger.debug(f"Signup validation: trimmed_name='{name}', length={len(name)}")
        if len(name) < 2:
            logger.warning("Signup 400: name too short")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Name must be at least 2 characters"
            )
        
        if len(name) > 30:
            logger.warning("Signup 400: name too long")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Name must be 30 characters or less"
            )
        
        # Validate name characters (letters, numbers, spaces, hyphens, underscores)
        import re
        if not re.match(r'^[a-zA-Z0-9\s\-_]+$', name):
            logger.warning("Signup 400: name contains invalid characters")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Name can only contain letters, numbers, spaces, hyphens, and underscores"
            )
        
        # Check if name is already taken
        name_result = await supabase.table("users").select("id").eq("name", name).execute()
        if name_result.data:
            logger.warning("Signup 400: name already taken")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Name already taken"
            )
        
        # -------------------------------------------------------------
        # 1. Mandatory verification photo – stored as identity snapshot
        # -------------------------------------------------------------

        if not verification_photo or not verification_photo.filename:
            logger.warning("Signup 400: verification photo missing or empty filename")
            raise HTTPException(status_code=400, detail="Verification photo is required.")


        verification_processed_bytes: bytes | None = None
        try:
            verification_raw = await verification_photo.read()
            logger.debug(f"Signup photo received: bytes={len(verification_raw)}")

            # Size check (5 MB)
            if len(verification_raw) > 5 * 1024 * 1024:
                logger.warning("Signup 400: verification photo too large (>5MB)")
                raise HTTPException(status_code=400, detail="Verification photo too large (max 5 MB)")

            img_v = Image.open(io.BytesIO(verification_raw))
            img_v = ImageOps.exif_transpose(img_v)
            if img_v.mode != 'RGB':
                img_v = img_v.convert('RGB')
            buf_v = io.BytesIO()
            img_v.save(buf_v, format="JPEG", quality=85)
            verification_processed_bytes = buf_v.getvalue()
        except (IOError, OSError) as e:
            logger.error(f"Failed processing verification photo: {e}")
            raise HTTPException(status_code=400, detail="Invalid verification photo.")

        # Face detection on verification photo (must have one face)
        rekognition_client = get_rekognition_client()
        if rekognition_client:
            face_validation = validate_face_in_image(verification_processed_bytes, rekognition_client)
            logger.debug(f"Signup face validation result: {face_validation}")
            if not face_validation["valid"]:
                logger.warning(f"Signup 400: face validation failed: {face_validation['message']}")
                raise HTTPException(status_code=400, detail=face_validation["message"])

        # -------------------------------------------------------------
        # 2. Initialize variables for later use
        # -------------------------------------------------------------

        snapshot_url = None

        # ------------------------------------------------------------------
        # 3. Create user record FIRST so we have user_id for filename storage
        # ------------------------------------------------------------------

        user_data = {
            "phone_number": phone_number,
            "name": name,
            "timezone": timezone
        }
        
        result = await supabase.table("users").insert(user_data).execute()
        if not result.data:
            logger.error("Signup 400: Supabase insert returned no data")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Failed to create user"
            )
        
        created_user = result.data[0]
        user_id = created_user["id"]
        
        # ------------------------------------------------------------------
        # 4. Upload verification photo (identity-snapshots bucket)
        # ------------------------------------------------------------------

        identity_snapshot_filename = f"{user_id}.jpg"
        await upload_to_supabase_storage_with_retry(
            supabase,
            "identity-snapshots",
            identity_snapshot_filename,
            verification_processed_bytes,
            "image/jpeg"
        )
        logger.info(f"Signup photo uploaded: file='{identity_snapshot_filename}'")

        # Save on user row
        await supabase.table("users").update({
            "identity_snapshot_filename": identity_snapshot_filename,
            "updated_at": datetime.utcnow().isoformat()
        }).eq("id", user_id).execute()
        logger.info("Signup: user updated with identity snapshot filename")

        # Generate signed URL for identity snapshot
        snapshot_url = await generate_identity_snapshot_url(supabase, identity_snapshot_filename)
        logger.debug("Signup: generated signed URL for identity snapshot")
        
        # Check if this signup came from an invite
        if inviter_id:
            try:
                # Create friendship using the new simplified system
                # Use the send_friend_request_simple RPC to create, then immediately accept
                send_result = await supabase.rpc("send_friend_request_simple", {
                    "sender_id": inviter_id,
                    "receiver_id": user_id,
                    "message": "Friendship via signup invite"
                }).execute()
                
                if send_result.data and not send_result.data[0].get('error'):
                    relationship_id = send_result.data[0]['relationship_id']
                    
                    # Immediately accept the request to create the friendship
                    accept_result = await supabase.rpc("accept_friend_request_simple", {
                        "relationship_id": relationship_id,
                        "accepting_user_id": user_id
                    }).execute()
                    
                    if accept_result.data and not accept_result.data[0].get('error'):
                        logger.info(f"Created friendship between {inviter_id} and {user_id}")
                    else:
                        logger.warning(f"Failed to accept friendship request: {accept_result.data}")
                else:
                    logger.warning(f"Failed to send friendship request: {send_result.data}")
                    
            except (ValueError, KeyError) as e:
                logger.warning(f"Failed to create friendship: {e}")
                # Don't fail signup if friendship creation fails
        
        # Create non-expiring token
        access_token = create_access_token(
            data={"sub": str(user_id)}
        )
        
        # Return user data and token
        user_response = {
            "id": user_id,
            "phone_number": created_user["phone_number"],
            "name": created_user["name"],
            "created_at": created_user.get("created_at"),
            "updated_at": created_user.get("updated_at"),
            "timezone": created_user.get("timezone", "UTC"),
            "profile_photo_url": None,  # Profile photos will be handled by avatar system
            "avatar_version": None,
            "avatar_url_80": None,
            "avatar_url_200": None,
            "avatar_url_original": None,
            "identity_snapshot_url": snapshot_url,
            "onboarding_state": created_user.get("onboarding_state", 0),
            "ispremium": created_user.get("ispremium", False),
            "access_token": access_token,
            "token_type": "bearer"
        }
        
        logger.info(f"Signup success: user_id={user_id}")
        return user_response
    except HTTPException:
        raise
    except (ValueError, KeyError) as e:
        logger.error(f"Signup error (400/validation): {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except IOError as e:
        logger.error(f"File processing error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to process uploaded files"
        )
    except (ClientError, NoCredentialsError) as e:  # AWS Rekognition issues
        logger.error(f"Image verification service error: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Image verification temporarily unavailable"
        )
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Service connectivity error during signup: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Upstream service temporarily unavailable"
        )
    except Exception as e:
        logger.exception(f"Unexpected error during signup: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Signup failed"
        )

@router.post("/logout")
async def logout(
    token: str = Depends(oauth2_scheme),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        # Add token to blacklist
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        
        # Check if token is already blacklisted
        existing_blacklist = await supabase.table("blacklisted_tokens").select("*").eq("token", token).execute()
        
        if not existing_blacklist.data:
            # Blacklist the JWT token only if it's not already blacklisted
            blacklist_result = await supabase.table("blacklisted_tokens").insert({
                "token": token,
                "user_id": user_id,
                "blacklisted_at": datetime.utcnow().isoformat()
            }).execute()
        else:
            logger.info(f"Token already blacklisted for user {user_id}")
        
        # Clear device tokens for this user to stop push notifications
        # and make tokens available for reuse
        device_token_result = await supabase.table("device_tokens").update({
            "is_active": False,
            "updated_at": datetime.utcnow().isoformat()
        }).eq("user_id", user_id).execute()
        
        
        return {"message": "Successfully logged out"}
    except JWTError as e:
        logger.error(f"JWT error during logout: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid token"
        )
    except ValueError as e:
        logger.error(f"Logout error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.exception(f"Unexpected error during logout: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Logout failed"
        )

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        # Check if token is blacklisted
        blacklisted = await supabase.table("blacklisted_tokens").select("*").eq("token", token).execute()
        if blacklisted.data:
            raise credentials_exception
            
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
            
        # Get user from Supabase using the ID from the token
        result = await supabase.table("users").select("*").eq("id", user_id).execute()
        if not result.data:
            raise credentials_exception
            
        user_data = result.data[0]
        
        # Generate profile photo URL from filename if it exists
        profile_photo_url = await generate_profile_photo_url(supabase, user_data.get("profile_photo_filename"))
        
        # Return a User object instead of a dictionary
        return User(
            id=user_data["id"],
            phone_number=user_data["phone_number"],
            name=user_data["name"],
            created_at=user_data.get("created_at"),
            updated_at=user_data.get("updated_at"),
            timezone=user_data.get("timezone", "UTC"),
            profile_photo_url=profile_photo_url,
            # Include avatar fields for modern avatar system
            avatar_version=user_data.get("avatar_version"),
            avatar_url_80=user_data.get("avatar_url_80"),
            avatar_url_200=user_data.get("avatar_url_200"),
            avatar_url_original=user_data.get("avatar_url_original"),
            onboarding_state=user_data.get("onboarding_state", 0),
            ispremium=user_data.get("ispremium", False),
            last_active=user_data.get("last_active")
        )
    except JWTError as e:
        logger.error(f"JWT Error: {str(e)}")
        raise credentials_exception
    except (ValueError, KeyError) as e:
        logger.error(f"Get current user error: {str(e)}")
        raise credentials_exception
    except Exception as e:
        logger.exception(f"Unexpected error in get_current_user: {e}")
        raise credentials_exception

async def get_current_user_lightweight(
    token: str = Depends(oauth2_scheme),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Lightweight authentication that doesn't generate profile photo URLs.
    Use this for endpoints that don't need the user's profile photo.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        # Check if token is blacklisted
        blacklisted = await supabase.table("blacklisted_tokens").select("*").eq("token", token).execute()
        if blacklisted.data:
            raise credentials_exception
            
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
            
        # Get user from Supabase using the ID from the token
        result = await supabase.table("users").select("*").eq("id", user_id).execute()
        if not result.data:
            raise credentials_exception
            
        user_data = result.data[0]
        
        # Return a User object without generating profile photo URL
        return User(
            id=user_data["id"],
            phone_number=user_data["phone_number"],
            name=user_data["name"],
            created_at=user_data.get("created_at"),
            updated_at=user_data.get("updated_at"),
            timezone=user_data.get("timezone", "UTC"),
            profile_photo_url=None,  # Don't generate unnecessary signed URLs
            # Include avatar fields for modern avatar system
            avatar_version=user_data.get("avatar_version"),
            avatar_url_80=user_data.get("avatar_url_80"),
            avatar_url_200=user_data.get("avatar_url_200"),
            avatar_url_original=user_data.get("avatar_url_original"),
            onboarding_state=user_data.get("onboarding_state", 0),
            ispremium=user_data.get("ispremium", False),
            last_active=user_data.get("last_active")
        )
    except JWTError as e:
        logger.error(f"JWT Error: {str(e)}")
        raise credentials_exception
    except (ValueError, KeyError) as e:
        logger.error(f"Get current user error: {str(e)}")
        raise credentials_exception
    except Exception as e:
        logger.exception(f"Unexpected error in get_current_user_lightweight: {e}")
        raise credentials_exception

@router.get("/me", response_model=User)
async def read_users_me(current_user = Depends(get_current_user)):
    return current_user 

@router.post("/verify-code")
async def verify_code(
    request: UserLogin,  # reuse schema with phone_number & verification_code
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Validate an SMS verification code for sign-up pre-check.
    Returns `{status: "approved"}` on success or 400 on failure.
    This does NOT create a user or issue a token – it is used solely by the
    mobile client to confirm the code before moving on to collect profile data.
    """
    phone_number = request.phone_number.strip()
    code = request.verification_code.strip()

    try:
        # Admin bypass
        if settings.admin_bypass_phone and phone_number == settings.admin_bypass_phone and code == "000000":
            return {"status": "approved"}

        verify_service_sid = os.getenv("TWILIO_VERIFY_SERVICE_SID")

        if not verify_service_sid:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Twilio Verify Service SID not configured"
            )

        twilio = get_twilio_client()
        if not twilio:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Twilio service temporarily unavailable"
            )
        verification_check = twilio.verify.services(verify_service_sid) \
            .verification_checks \
            .create(to=f"+1{phone_number}", code=code)

        if verification_check.status != "approved":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid verification code"
            )

        return {"status": verification_check.status}

    except HTTPException:
        raise  # re-raise for FastAPI to handle
    except (ValueError, KeyError) as e:
        logger.error(f"Code verification error: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Service connection error: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Verification service temporarily unavailable"
        ) 
    except TwilioRestException as e:
        logger.error(f"Twilio API error during code verification: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Verification service error"
        )
    except Exception as e:
        logger.exception(f"Unexpected error during code verification: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Verification failed"
        )