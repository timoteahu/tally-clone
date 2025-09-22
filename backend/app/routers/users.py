from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from models.schemas import User, UserCreate
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from typing import List, Optional
import pytz
import uuid
from routers.auth import get_current_user, get_current_user_lightweight
from utils import (
    get_user_timezone,
    generate_profile_photo_url,
    upload_to_supabase_storage_with_retry,
    upload_to_supabase_storage_with_cache_control,
    validate_face_in_image,
    detect_moderation_labels,
    is_content_appropriate_for_profile
)
from PIL import Image, ImageOps
import io
from botocore.exceptions import ClientError, NoCredentialsError
import os
from config.settings import get_settings
from config.aws import get_rekognition_client
from datetime import datetime, timedelta
from pydantic import BaseModel
import logging
import time
import random
from utils.friends_filter import get_eligible_friends_with_stripe
from fastapi import Request
from typing import Any

logger = logging.getLogger(__name__)

router = APIRouter()


class ProfilePhotoUploadResponse(BaseModel):
    message: str
    profile_photo_url: str

class AvatarUploadResponse(BaseModel):
    message: str
    avatar_version: int
    avatar_url_80: str
    avatar_url_200: str
    avatar_url_original: str

class UserProfileUpdate(BaseModel):
    name: Optional[str] = None
    timezone: Optional[str] = None

class BatchPhoneCheckRequest(BaseModel):
    phone_numbers: List[str]

class BatchPhoneCheckResponse(BaseModel):
    results: List[dict]

# Remove duplicated functions - they're now imported from utils

@router.post("/", response_model=User)
async def create_user(user: UserCreate, supabase: AsyncClient = Depends(get_async_supabase_client)):
    try:
        result = await supabase.table("users").insert(user.dict()).execute()
        user_data = result.data[0]
        
        # Generate profile photo URL from filename if it exists
        profile_photo_url = await generate_profile_photo_url(supabase, user_data.get("profile_photo_filename"))
        
        # Return a User object with complete data including profile photo URL
        return User(
            **user_data,
            profile_photo_url=profile_photo_url
        )
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Database/service connectivity error in create_user: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in create_user: {e}")
        raise HTTPException(status_code=500, detail="Failed to create user")

@router.get("/", response_model=List[User])
async def list_users(supabase: AsyncClient = Depends(get_async_supabase_client)):
    try:
        result = await supabase.table("users").select("*").execute()
        return result.data
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Database/service connectivity error in list_users: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in list_users: {e}")
        raise HTTPException(status_code=500, detail="Failed to list users")

@router.post("/check-phone")
async def check_phone_exists(phone_data: dict, supabase: AsyncClient = Depends(get_async_supabase_client)):
    try:
        result = await supabase.table("users").select("id").eq("phone_number", phone_data["phone_number"]).execute()
        exists = len(result.data) > 0
        return {
            "exists": exists,
            "user_id": str(result.data[0]["id"]) if exists else None
        }
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Database/service connectivity error in check_phone_exists: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in check_phone_exists: {e}")
        raise HTTPException(status_code=500, detail="Failed to check phone")

@router.post("/check-name")
async def check_name_availability(name_data: dict, supabase: AsyncClient = Depends(get_async_supabase_client)):
    try:
        name = name_data.get("name", "").strip()
        if not name:
            raise HTTPException(status_code=400, detail="Name is required")
        
        # Validate name length
        if len(name) < 2:
            raise HTTPException(status_code=400, detail="Name must be at least 2 characters")
        
        if len(name) > 30:
            raise HTTPException(status_code=400, detail="Name must be 30 characters or less")
        
        # Validate name characters (letters, numbers, spaces, hyphens, underscores)
        import re
        if not re.match(r'^[a-zA-Z0-9\s\-_]+$', name):
            raise HTTPException(status_code=400, detail="Name can only contain letters, numbers, spaces, hyphens, and underscores")
        
        # Check if name already exists (case-sensitive)
        result = await supabase.table("users").select("id").eq("name", name).execute()
        exists = len(result.data) > 0
        
        return {
            "available": not exists,
            "exists": exists
        }
    except HTTPException:
        raise
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Database/service connectivity error in check_name_availability: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in check_name_availability: {e}")
        raise HTTPException(status_code=500, detail="Failed to check name availability")

@router.post("/batch-check-phones", response_model=BatchPhoneCheckResponse)
async def batch_check_phones(request: BatchPhoneCheckRequest, supabase: AsyncClient = Depends(get_async_supabase_client)):
    """
    Check multiple phone numbers at once to see which ones are registered users.
    Much more efficient than individual calls.
    """
    try:
        # Add validation and logging
        
        # Check if phone_numbers is empty
        if not request.phone_numbers:
            raise HTTPException(status_code=400, detail="No phone numbers provided")
        
        # Limit batch size to prevent abuse
        if len(request.phone_numbers) > 500:
            raise HTTPException(status_code=400, detail="Too many phone numbers. Maximum 500 allowed per batch.")
        
        # Validate phone numbers format (basic validation)
        invalid_numbers = []
        for phone in request.phone_numbers:
            if not phone or not isinstance(phone, str) or len(phone.strip()) == 0:
                invalid_numbers.append(phone)
            else:
                # Basic phone number validation
                cleaned = phone.strip()
                # Must start with + and have at least 10 digits
                if not cleaned.startswith('+') or len(cleaned.replace('+', '').replace(' ', '').replace('-', '').replace('(', '').replace(')', '')) < 10:
                    invalid_numbers.append(phone)
        
        if invalid_numbers:
            logger.warning(f"Invalid phone numbers found: {invalid_numbers}")
            raise HTTPException(status_code=400, detail=f"Invalid phone numbers: {invalid_numbers}")
        
        # Clean and normalize phone numbers
        clean_phone_numbers = [phone.strip() for phone in request.phone_numbers]
        
        # Normalize phone numbers for consistent matching
        normalized_phone_numbers = []
        phone_mapping = {}  # Maps normalized number back to original

        for phone in clean_phone_numbers:
            # Remove +1 prefix if present (database stores without +1)
            if phone.startswith('+1'):
                normalized = phone[2:]  # Remove +1
            elif phone.startswith('+'):
                # For other country codes, keep as is for now
                normalized = phone
            else:
                normalized = phone

            normalized_phone_numbers.append(normalized)
            phone_mapping[normalized] = phone

            # Also try without country code for broader matching
            if phone.startswith('+'):
                normalized_without_plus = phone[1:]  # Remove just the +
                normalized_phone_numbers.append(normalized_without_plus)
                phone_mapping[normalized_without_plus] = phone

        # Query all phone numbers in a single database call using normalized numbers
        result = await supabase.table("users").select("id, phone_number, name").in_("phone_number", normalized_phone_numbers).execute()
        
        # Create a lookup dict for fast access (using original phone format as key)
        existing_users = {}
        for user in result.data:
            # Map back to original phone format for response
            original_phone = phone_mapping.get(user["phone_number"], user["phone_number"])
            existing_users[original_phone] = {"user_id": user["id"], "name": user["name"]}
        
        # Build response for all requested phone numbers
        results = []
        for phone_number in clean_phone_numbers:
            if phone_number in existing_users:
                results.append({
                    "phone_number": phone_number,
                    "exists": True,
                    "user_id": existing_users[phone_number]["user_id"],
                    "name": existing_users[phone_number]["name"]
                })
            else:
                results.append({
                    "phone_number": phone_number,
                    "exists": False,
                    "user_id": None,
                    "name": None
                })
        
        return BatchPhoneCheckResponse(results=results)
    except HTTPException:
        raise
    except (ValueError, KeyError, TypeError) as e:
        logger.error(f"Unexpected error in batch_check_phones: {str(e)}")
        raise HTTPException(status_code=400, detail=f"Server error: {str(e)}")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in batch_check_phones: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in batch_check_phones: {e}")
        raise HTTPException(status_code=500, detail="Failed to process batch phone check")

@router.post("/upload-avatar", response_model=AvatarUploadResponse)
async def upload_avatar(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Upload user avatar with versioned, cacheable URLs.
    Creates multiple sizes (80px, 200px, original) in versioned directories.
    """
    try:
        
        # Read and validate file content
        file_content = await file.read()
        
        # Validate file size (5MB)
        if len(file_content) > 5 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="File size too large. Maximum 5MB allowed.")
        
        # Process image
        try:
            img = Image.open(io.BytesIO(file_content))
            
            # Handle EXIF orientation
            try:
                img = ImageOps.exif_transpose(img)
            except (IOError, OSError) as exif_error:
                logger.warning(f"Could not apply EXIF orientation: {exif_error}")
            
            # Convert to RGB
            if img.mode in ('RGBA', 'LA', 'P'):
                background = Image.new('RGB', img.size, (255, 255, 255))
                if img.mode == 'P':
                    img = img.convert('RGBA')
                background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                img = background
            elif img.mode != 'RGB':
                img = img.convert('RGB')
            
            # Convert original to JPEG bytes
            original_buffer = io.BytesIO()
            img.save(original_buffer, format="JPEG", quality=90)
            original_bytes = original_buffer.getvalue()
            
        except (IOError, OSError, ValueError) as e:
            logger.error(f"Image processing failed: {e}")
            raise HTTPException(status_code=400, detail="Invalid image file. Could not process the image.")
        
        # Validate file type
        valid_content_types = ["image/jpeg", "image/png", "image/gif", "image/jpg"]
        is_valid_content_type = file.content_type in valid_content_types if file.content_type else False
        
        # Check file signature
        file_signature = file_content[:8]
        is_jpeg = file_signature.startswith(b'\xff\xd8\xff')
        is_png = file_signature.startswith(b'\x89PNG\r\n\x1a\n')
        is_gif = file_signature.startswith(b'GIF8')
        is_valid_signature = is_jpeg or is_png or is_gif
        
        if not is_valid_content_type and not is_valid_signature:
            raise HTTPException(status_code=400, detail="Invalid file type. Only JPEG, PNG, and GIF are allowed.")
        
        # Optional content moderation
        rekognition_client = get_rekognition_client()
        if rekognition_client:
            try:
                moderation_response = detect_moderation_labels(original_bytes, rekognition_client)
                is_appropriate, moderation_reason = is_content_appropriate_for_profile(moderation_response)
                if not is_appropriate:
                    logger.warning(f"Content moderation failed: {moderation_reason}")
                    raise HTTPException(status_code=400, detail=moderation_reason)
            except (ClientError, ValueError) as moderation_error:
                logger.warning(f"Content moderation error (continuing anyway): {moderation_error}")
        
        # Generate version timestamp and paths
        user_id = current_user.id
        version = int(datetime.utcnow().timestamp() * 1000)  # milliseconds timestamp
        base_path = f"{user_id}/v{version}"
        
        # Generate derivative sizes
        sizes = [
            {"size": 80, "filename": "80.jpg"},
            {"size": 200, "filename": "200.jpg"}
        ]
        
        generated_images = {}
        
        # Create derivatives
        for size_config in sizes:
            size = size_config["size"]
            filename = size_config["filename"]
            
            # Resize image maintaining aspect ratio, then crop to square
            img_copy = img.copy()
            img_copy.thumbnail((size * 2, size * 2), Image.Resampling.LANCZOS)  # 2x for quality
            
            # Create square crop from center
            width, height = img_copy.size
            if width > height:
                left = (width - height) // 2
                img_copy = img_copy.crop((left, 0, left + height, height))
            elif height > width:
                top = (height - width) // 2
                img_copy = img_copy.crop((0, top, width, top + width))
            
            # Resize to exact dimensions
            img_copy = img_copy.resize((size, size), Image.Resampling.LANCZOS)
            
            # Convert to bytes
            buffer = io.BytesIO()
            img_copy.save(buffer, format="JPEG", quality=85)
            generated_images[filename] = buffer.getvalue()
        
        # Upload all versions with long-lived cache headers
        cache_control = "public, max-age=31536000, immutable"  # 1 year TTL
        
        # Upload original
        try:
            await upload_to_supabase_storage_with_cache_control(
                supabase, 
                "profile-photos", 
                f"{base_path}/orig.jpg", 
                original_bytes, 
                "image/jpeg",
                cache_control
            )
        except (IOError, ClientError) as e:
            logger.error(f"Failed to upload original avatar: {e}")
            raise HTTPException(status_code=500, detail="Failed to upload original avatar")
        
        # Upload derivatives
        for size_config in sizes:
            filename = size_config["filename"]
            try:
                await upload_to_supabase_storage_with_cache_control(
                    supabase, 
                    "profile-photos", 
                    f"{base_path}/{filename}", 
                    generated_images[filename], 
                    "image/jpeg",
                    cache_control
                )
            except (IOError, ClientError) as e:
                logger.error(f"Failed to upload {filename}: {e}")
                # Continue with other uploads
        
        # Update user with new avatar version and URLs
        supabase_cdn = os.getenv("SUPABASE_URL", "").replace("/rest/v1", "")
        avatar_urls = {
            "avatar_version": version,
            "avatar_url_80": f"{supabase_cdn}/storage/v1/object/public/profile-photos/{base_path}/80.jpg",
            "avatar_url_200": f"{supabase_cdn}/storage/v1/object/public/profile-photos/{base_path}/200.jpg",
            "avatar_url_original": f"{supabase_cdn}/storage/v1/object/public/profile-photos/{base_path}/orig.jpg",
            "updated_at": datetime.utcnow().isoformat()
        }
        
        update_response = await supabase.table("users").update(avatar_urls).eq("id", user_id).execute()
        
        if update_response.data:
            return AvatarUploadResponse(
                message="Avatar uploaded and processed successfully",
                avatar_version=version,
                avatar_url_80=avatar_urls["avatar_url_80"],
                avatar_url_200=avatar_urls["avatar_url_200"],
                avatar_url_original=avatar_urls["avatar_url_original"]
            )
        else:
            raise HTTPException(status_code=500, detail="Failed to update user profile with avatar URLs")
            
    except HTTPException:
        raise
    except (IOError, ValueError, ClientError) as e:
        logger.error(f"Unexpected error in avatar upload: {e}")
        raise HTTPException(status_code=500, detail="An unexpected error occurred")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in upload_avatar: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in upload_avatar: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload avatar")

# Remove duplicated functions - they're now imported from utils

@router.get("/avatar")
async def get_avatar(
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get user's cached avatar URLs.
    Returns versioned URLs for 80px, 200px, and original sizes.
    """
    try:
        user_id = current_user.id
        
        # Get avatar URLs from database
        result = await supabase.table("users").select(
            "avatar_version, avatar_url_80, avatar_url_200, avatar_url_original"
        ).eq("id", user_id).execute()
        
        if result.data and len(result.data) > 0:
            user_data = result.data[0]
            return {
                "avatar_version": user_data.get("avatar_version"),
                "avatar_url_80": user_data.get("avatar_url_80"),
                "avatar_url_200": user_data.get("avatar_url_200"),
                "avatar_url_original": user_data.get("avatar_url_original")
            }
        else:
            return {
                "avatar_version": None,
                "avatar_url_80": None,
                "avatar_url_200": None,
                "avatar_url_original": None
            }
            
    except (ValueError, KeyError) as e:
        logger.error(f"Error getting avatar: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get avatar")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_avatar: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_avatar: {e}")
        raise HTTPException(status_code=500, detail="Failed to get avatar")

@router.get("/profile-photo")
async def get_profile_photo(
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        user_id = current_user.id
        
        # Check if user has a profile photo filename
        result = await supabase.table("users").select("profile_photo_filename").eq("id", user_id).execute()
        
        if result.data and result.data.get("profile_photo_filename"):
            filename = result.data["profile_photo_filename"]
            
            # Ensure filename has .jpg extension for storage lookup
            if not filename.endswith('.jpg'):
                storage_filename = f"{filename}.jpg"
            else:
                storage_filename = filename
                
            # Generate signed URL (expires in 1 hour)
            signed_url_response = await supabase.storage.from_("profile-photos").create_signed_url(
                storage_filename, 
                expires_in=3600
            )
            signed_url = signed_url_response.get('signedURL') if isinstance(signed_url_response, dict) else signed_url_response
            return {"profile_photo_url": signed_url}
        else:
            return {"profile_photo_url": None}
            
    except (ValueError, KeyError) as e:
        logger.error(f"Error getting profile photo: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get profile photo")

@router.delete("/avatar")
async def delete_avatar(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Delete the current user's avatar.
    Clears all avatar URLs and version.
    """
    try:
        user_id = current_user.id
        
        # Get current avatar version and URLs
        result = await supabase.table("users").select(
            "avatar_version, avatar_url_80, avatar_url_200, avatar_url_original"
        ).eq("id", user_id).execute()
        
        if not result.data or not result.data[0].get("avatar_version"):
            return {"message": "No avatar to delete"}
        
        # Clear avatar fields in database
        await supabase.table("users").update({
            "avatar_version": None,
            "avatar_url_80": None,
            "avatar_url_200": None,
            "avatar_url_original": None,
            "updated_at": datetime.utcnow().isoformat()
        }).eq("id", user_id).execute()
        
        return {"message": "Avatar deleted successfully"}
        
    except (ValueError, KeyError, ClientError) as e:
        logger.error(f"Error deleting avatar: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to delete avatar")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in delete_avatar: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in delete_avatar: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete avatar")

@router.delete("/profile-photo")
async def delete_profile_photo(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Delete the current user's profile photo.
    """
    try:
        user_id = current_user.id
        
        # Get the current filename
        result = await supabase.table("users").select("profile_photo_filename").eq("id", user_id).execute()
        if not result.data or not result.data.get("profile_photo_filename"):
            return {"message": "No profile photo to delete"}
            
        profile_photo_filename = result.data["profile_photo_filename"]
        
        # Delete the file from storage
        try:
            await supabase.storage.from_("profile-photos").remove([profile_photo_filename])
        except ClientError as storage_error:
            logger.warning(f"Could not delete profile photo from storage: {storage_error}")
            # Continue anyway to update the database
        
        # Update the user record
        await supabase.table("users").update({
            "profile_photo_filename": None,
            "profile_photo_url": None,
            "updated_at": datetime.utcnow().isoformat()
        }).eq("id", user_id).execute()
        
        return {"message": "Profile photo deleted successfully"}
        
    except (ValueError, KeyError, ClientError) as e:
        logger.error(f"Error deleting profile photo: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to delete profile photo")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in delete_profile_photo: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in delete_profile_photo: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete profile photo")

@router.get("/identity-snapshot")
async def get_identity_snapshot(
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get the current user's identity snapshot URL.
    This is a read-only photo taken during account creation.
    """
    try:
        user_id = current_user.id
        
        # Check if user has an identity snapshot filename
        result = await supabase.table("users").select("identity_snapshot_filename").eq("id", user_id).execute()
        
        if result.data and result.data.get("identity_snapshot_filename"):
            filename = result.data["identity_snapshot_filename"]
            
            # Ensure filename has .jpg extension for storage lookup
            if not filename.endswith('.jpg'):
                storage_filename = f"{filename}.jpg"
            else:
                storage_filename = filename
                
            # Generate signed URL (expires in 1 hour)
            signed_url_response = await supabase.storage.from_("identity-snapshots").create_signed_url(
                storage_filename, 
                expires_in=3600
            )
            signed_url = signed_url_response.get('signedURL') if isinstance(signed_url_response, dict) else signed_url_response
            return {"identity_snapshot_url": signed_url}
        else:
            return {"identity_snapshot_url": None}
            
    except (ValueError, KeyError) as e:
        logger.error(f"Error getting identity snapshot: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get identity snapshot")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_identity_snapshot: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_identity_snapshot: {e}")
        raise HTTPException(status_code=500, detail="Failed to get identity snapshot")

@router.put("/profile")
async def update_user_profile(
    profile_update: UserProfileUpdate,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        user_id = current_user.id
        
        # Build update dictionary from non-None fields
        update_data = {}
        if profile_update.name is not None:
            update_data["name"] = profile_update.name
        if profile_update.timezone is not None:
            update_data["timezone"] = profile_update.timezone
        
        # Only proceed if there's something to update
        if not update_data:
            raise HTTPException(status_code=400, detail="No fields provided for update")
        
        # Add updated timestamp
        update_data["updated_at"] = datetime.utcnow().isoformat()
        
        # Get current timezone before updating (if timezone is being changed)
        current_timezone = None
        timezone_changing = profile_update.timezone is not None
        if timezone_changing:
            current_user_result = await supabase.table("users").select("timezone").eq("id", user_id).execute()
            current_timezone = current_user_result.data[0]['timezone'] if current_user_result.data else None
        
        # Update user in database
        update_response = await supabase.table("users").update(update_data).eq("id", user_id).execute()
        
        if update_response.data:
            # If timezone changed, reschedule all notifications
            if timezone_changing and current_timezone != profile_update.timezone:
                try:
                    from services.habit_notification_scheduler import habit_notification_scheduler
                    await habit_notification_scheduler.reschedule_all_notifications_for_user(str(user_id), supabase)
                    logger.info(f"Rescheduled all notifications for user {user_id} due to timezone change from {current_timezone} to {profile_update.timezone}")
                except (ValueError, RuntimeError) as e:
                    logger.error(f"Failed to reschedule notifications for user {user_id} after timezone change: {e}")
                    # Don't fail the profile update if notification rescheduling fails
            
            return {
                "message": "Profile updated successfully",
                "updated_fields": list(update_data.keys())
            }
        else:
            raise HTTPException(status_code=500, detail="Failed to update profile")
            
    except HTTPException:
        raise
    except (ValueError, KeyError) as e:
        logger.error(f"Error updating user profile: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to update profile")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in update_user_profile: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in update_user_profile: {e}")
        raise HTTPException(status_code=500, detail="Failed to update profile")

@router.get("/{user_id}", response_model=User)
async def get_user(user_id: str, supabase: AsyncClient = Depends(get_async_supabase_client)):
    try:
        result = await supabase.table("users").select("*").eq("id", user_id).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_data = result.data[0]
        
        # Generate profile photo URL from filename if it exists
        profile_photo_url = await generate_profile_photo_url(supabase, user_data.get("profile_photo_filename"))
        
        # Return a User object with complete data including profile photo URL
        return User(
            id=user_data["id"],
            phone_number=user_data["phone_number"],
            name=user_data["name"],
            created_at=user_data.get("created_at"),
            updated_at=user_data.get("updated_at"),
            timezone=user_data.get("timezone", "UTC"),
            profile_photo_url=profile_photo_url,
            onboarding_state=user_data.get("onboarding_state", 0),
            ispremium=user_data.get("ispremium", False)
        )
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_user: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_user: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve user")

@router.patch("/{user_id}/timezone", response_model=User)
async def update_timezone(
    user_id: str,
    timezone: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        logger.info(f"User timezone: {timezone}")
        
        # Handle timezone abbreviations by mapping them to proper pytz names
        timezone_mapping = {
            'PDT': 'America/Los_Angeles',
            'PST': 'America/Los_Angeles',
            'EDT': 'America/New_York',
            'EST': 'America/New_York',
            'CDT': 'America/Chicago',
            'CST': 'America/Chicago',
            'MDT': 'America/Denver',
            'MST': 'America/Denver',
        }
        
        # If it's an abbreviation, convert it
        if timezone in timezone_mapping:
            timezone = timezone_mapping[timezone]
        
        # Validate timezone
        try:
            pytz.timezone(timezone)
        except pytz.exceptions.UnknownTimeZoneError:
            raise HTTPException(status_code=400, detail=f"Invalid timezone: {timezone}")
        
        # Get current timezone before updating
        current_user_result = await supabase.table("users").select("timezone").eq("id", user_id).execute()
        current_timezone = current_user_result.data[0]['timezone'] if current_user_result.data else None
        
        # Update user's timezone
        update_response = await supabase.table("users").update({"timezone": timezone}).eq("id", user_id).execute()
        if not update_response.data:
            raise HTTPException(status_code=404, detail="User not found")
        
        # If timezone actually changed, reschedule all notifications
        if current_timezone != timezone:
            try:
                from services.habit_notification_scheduler import habit_notification_scheduler
                await habit_notification_scheduler.reschedule_all_notifications_for_user(user_id, supabase)
                logger.info(f"Rescheduled all notifications for user {user_id} due to timezone change from {current_timezone} to {timezone}")
            except Exception as e:
                logger.error(f"Failed to reschedule notifications for user {user_id} after timezone change: {e}")
                # Don't fail the timezone update if notification rescheduling fails
        
        user_data = update_response.data[0]
        
        # Generate profile photo URL from filename if it exists
        profile_photo_url = await generate_profile_photo_url(supabase, user_data.get("profile_photo_filename"))
        
        # Return a User object with complete data including profile photo URL
        return User(
            id=user_data["id"],
            phone_number=user_data["phone_number"],
            name=user_data["name"],
            created_at=user_data.get("created_at"),
            updated_at=user_data.get("updated_at"),
            timezone=user_data.get("timezone", "UTC"),
            profile_photo_url=profile_photo_url,
            onboarding_state=user_data.get("onboarding_state", 0),
            ispremium=user_data.get("ispremium", False)
        )
    except (ValueError, KeyError) as e:
        logger.error(f"Error updating timezone: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in update_timezone: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in update_timezone: {e}")
        raise HTTPException(status_code=500, detail="Failed to update timezone")

@router.get("/{user_id}/profile-photo")
async def get_user_profile_photo(
    user_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get a specific user's profile photo URL (public endpoint for viewing other users).
    """
    try:
        # Get user data including profile photo filename
        result = await supabase.table("users").select("profile_photo_filename").eq("id", user_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=404, detail="User not found")
        
        profile_photo_filename = result.data[0].get("profile_photo_filename")
        
        if not profile_photo_filename:
            return {
                "profile_photo_url": None,
                "message": "No profile photo found"
            }
        
        # Ensure filename has .jpg extension for storage lookup
        if not profile_photo_filename.endswith('.jpg'):
            storage_filename = f"{profile_photo_filename}.jpg"
        else:
            storage_filename = profile_photo_filename
        
        # Generate signed URL (expires in 1 hour)
        signed_url_response = await supabase.storage.from_("profile-photos").create_signed_url(
            storage_filename, 
            expires_in=3600
        )
        signed_url = signed_url_response.get('signedURL') if isinstance(signed_url_response, dict) else signed_url_response
        
        return {
            "profile_photo_url": signed_url
        }
        
    except (ValueError, KeyError) as e:
        logger.error(f"Error getting user profile photo: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_user_profile_photo: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_user_profile_photo: {e}")
        raise HTTPException(status_code=500, detail="Failed to get profile photo")

@router.get("/{user_id}/identity-snapshot")
async def get_user_identity_snapshot(
    user_id: str,
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get a specific user's identity snapshot URL.
    This endpoint is only accessible by admins.
    """
    try:
        # Check if requesting user is an admin
        admin_check = await supabase.table("admins").select("id").eq("user_id", current_user.id).execute()
        if not admin_check.data:
            raise HTTPException(status_code=403, detail="Not authorized to access identity snapshots")
        
        # Get user data including identity snapshot filename
        result = await supabase.table("users").select("identity_snapshot_filename").eq("id", user_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=404, detail="User not found")
        
        identity_snapshot_filename = result.data[0].get("identity_snapshot_filename")
        
        if not identity_snapshot_filename:
            return {
                "identity_snapshot_url": None,
                "message": "No identity snapshot found"
            }
        
        # Ensure filename has .jpg extension for storage lookup
        if not identity_snapshot_filename.endswith('.jpg'):
            storage_filename = f"{identity_snapshot_filename}.jpg"
        else:
            storage_filename = identity_snapshot_filename
        
        # Generate signed URL (expires in 1 hour)
        signed_url_response = await supabase.storage.from_("identity-snapshots").create_signed_url(
            storage_filename, 
            expires_in=3600
        )
        signed_url = signed_url_response.get('signedURL') if isinstance(signed_url_response, dict) else signed_url_response
        
        return {
            "identity_snapshot_url": signed_url
        }
        
    except (ValueError, KeyError) as e:
        logger.error(f"Error getting user identity snapshot: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_user_identity_snapshot: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_user_identity_snapshot: {e}")
        raise HTTPException(status_code=500, detail="Failed to get identity snapshot")

@router.get("/friends-with-stripe-connect/{user_id}")
async def get_friends_with_stripe_connect(
    user_id: str,
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all friends of the user, including their Stripe Connect status for accountability partnerships."""
    try:
        # Validate that the user can only access their own friends (case-insensitive UUID comparison)
        if str(current_user.id).lower() != user_id.lower():
            raise HTTPException(status_code=403, detail="Cannot access another user's friends")
        
        # Get user's friends with Stripe Connect info using the new simplified system
        friends_result = await supabase.rpc("get_user_friends", {
            "user_id": user_id
        }).execute()
        
        all_friends = []
        
        if friends_result.data:
            # Get friend IDs and check their Stripe Connect status
            friend_ids = [friend_data['friend_id'] for friend_data in friends_result.data]
            
            if friend_ids:
                # Get Stripe Connect info for all friends
                friends_info_result = await supabase.table("users").select(
                    "id, name, phone_number, stripe_connect_status, stripe_connect_account_id, avatar_version, avatar_url_80, avatar_url_200, avatar_url_original"
                ).in_("id", friend_ids).execute()
                
                for user_data in friends_info_result.data:
                    # Find the friendship_id for this friend
                    friendship_id = None
                    for friend_data in friends_result.data:
                        if friend_data['friend_id'] == user_data["id"]:
                            friendship_id = friend_data.get('id')  # The friendship record ID
                            break
                    
                    stripe_status = user_data.get("stripe_connect_status")
                    stripe_account_id = user_data.get("stripe_connect_account_id")
                    
                    all_friends.append({
                        "id": friendship_id or user_data["id"],  # Use friendship_id if available, otherwise user_id
                        "friend_id": user_data["id"],  # The actual user ID of the friend
                        "name": user_data.get("name", ""),
                        "phone_number": user_data.get("phone_number", ""),
                        "stripe_connect_status": bool(stripe_status) if stripe_status is not None else False,
                        "stripe_connect_account_id": stripe_account_id,
                        "has_stripe": bool(stripe_status is True and stripe_account_id),  # Helper field to indicate if friend has active Stripe
                        # Avatar fields – may be null if user hasn't uploaded an avatar yet
                        "avatar_version": user_data.get("avatar_version"),
                        "avatar_url_80": user_data.get("avatar_url_80"),
                        "avatar_url_200": user_data.get("avatar_url_200"),
                        "avatar_url_original": user_data.get("avatar_url_original"),
                        "friendship_id": friendship_id  # Include the friendship_id for iOS compatibility
                    })
        
        # Note: We're no longer filtering by Stripe status or applying the unique recipients restriction
        # The frontend will handle displaying appropriate UI based on the has_stripe field
        
        logger.info(f"Returning {len(all_friends)} total friends for user {user_id}")
        return {"friends": all_friends}
        
    except HTTPException:
        raise
    except (ValueError, KeyError, TypeError) as e:
        logger.error(f"Error getting friends: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_friends_with_stripe_connect: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_friends_with_stripe_connect: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve friends")

@router.patch("/{user_id}/onboarding-state/{onboarding_state}", response_model=User)
async def update_onboarding_state(
    user_id: str,
    onboarding_state: int,
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Update user's onboarding state.
    Onboarding states:
    0: Terms of Service
    1: Intro Text  
    2: AddHabit Demo
    3: Payment Demo
    4: Payment Setup
    5: Completed
    """
    try:
        # Validate onboarding state - now accepts 0-5
        if onboarding_state not in [0, 1, 2, 3, 4, 5]:
            raise HTTPException(status_code=400, detail="Invalid onboarding state. Must be 0, 1, 2, 3, 4, or 5.")
        
        # Ensure user can only update their own onboarding state
        if str(current_user.id).lower() != user_id.lower():
            raise HTTPException(status_code=403, detail="You can only update your own onboarding state")
        
        # Update user's onboarding state
        update_response = await supabase.table("users").update({
            "onboarding_state": onboarding_state
        }).eq("id", user_id).execute()
        
        if not update_response.data:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_data = update_response.data[0]
        
        # Generate profile photo URL from filename if it exists
        profile_photo_url = await generate_profile_photo_url(supabase, user_data.get("profile_photo_filename"))
        
        # Return updated User object
        return User(
            id=user_data["id"],
            phone_number=user_data["phone_number"],
            name=user_data["name"],
            created_at=user_data.get("created_at"),
            updated_at=user_data.get("updated_at"),
            timezone=user_data.get("timezone", "UTC"),
            profile_photo_url=profile_photo_url,
            onboarding_state=user_data.get("onboarding_state", 0),
            ispremium=user_data.get("ispremium", False)
        )
    except (ValueError, KeyError) as e:
        logger.error(f"Error updating onboarding state: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in update_onboarding_state: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in update_onboarding_state: {e}")
        raise HTTPException(status_code=500, detail="Failed to update onboarding state")

@router.patch("/{user_id}/premium-status", response_model=User)
async def update_premium_status(
    user_id: str,
    ispremium: bool,
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Update user's premium status.
    Note: In production, this should typically be called by payment webhooks
    or admin endpoints, not directly by users.
    """
    try:
        # For now, allow users to update their own status
        # In production, you might want to restrict this to admin or payment system
        if str(current_user.id).lower() != user_id.lower():
            raise HTTPException(status_code=403, detail="You can only update your own premium status")
        
        # Update user's premium status
        update_response = await supabase.table("users").update({
            "ispremium": ispremium
        }).eq("id", user_id).execute()
        
        if not update_response.data:
            raise HTTPException(status_code=404, detail="User not found")
        
        user_data = update_response.data[0]
        
        # Generate profile photo URL from filename if it exists
        profile_photo_url = await generate_profile_photo_url(supabase, user_data.get("profile_photo_filename"))
        
        # Return updated User object
        return User(
            id=user_data["id"],
            phone_number=user_data["phone_number"],
            name=user_data["name"],
            created_at=user_data.get("created_at"),
            updated_at=user_data.get("updated_at"),
            timezone=user_data.get("timezone", "UTC"),
            profile_photo_url=profile_photo_url,
            onboarding_state=user_data.get("onboarding_state", 0),
            ispremium=user_data.get("ispremium", False)
        )
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in update_premium_status: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in update_premium_status: {e}")
        raise HTTPException(status_code=500, detail="Failed to update premium status")

class IdentitySnapshotUploadResponse(BaseModel):
    message: str
    identity_snapshot_url: str

@router.post("/upload-identity-snapshot", response_model=IdentitySnapshotUploadResponse)
async def upload_identity_snapshot(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Upload or update an identity snapshot photo for verification purposes.
    This photo is used for verifying identity during habit verifications.
    """
    try:
        user_id = current_user.id
        # The check for an existing snapshot has been removed to allow updates.
        
        # Read file content
        file_content = await file.read()
        
        # Validate file size (5MB)
        if len(file_content) > 5 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="File size too large. Maximum 5MB allowed.")
        
        # Process image
        try:
            img = Image.open(io.BytesIO(file_content))
            
            # Handle EXIF orientation
            try:
                img = ImageOps.exif_transpose(img)
            except (IOError, OSError) as exif_error:
                logger.warning(f"Could not apply EXIF orientation: {exif_error}")
            
            # Convert to RGB if necessary
            if img.mode in ('RGBA', 'LA', 'P'):
                background = Image.new('RGB', img.size, (255, 255, 255))
                if img.mode == 'P':
                    img = img.convert('RGBA')
                background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                img = background
            elif img.mode != 'RGB':
                img = img.convert('RGB')
            
            # Convert to JPEG bytes
            buffered = io.BytesIO()
            img.save(buffered, format="JPEG", quality=85)
            processed_image_bytes = buffered.getvalue()
            
        except (IOError, OSError, ValueError) as e:
            logger.error(f"Image processing failed: {e}")
            raise HTTPException(status_code=400, detail="Invalid image file. Could not process the image.")
        
        # Validate file type
        valid_content_types = ["image/jpeg", "image/png", "image/gif", "image/jpg"]
        is_valid_content_type = file.content_type in valid_content_types if file.content_type else False
        
        # Check file signature
        file_signature = file_content[:8]
        is_jpeg = file_signature.startswith(b'\xff\xd8\xff')
        is_png = file_signature.startswith(b'\x89PNG\r\n\x1a\n')
        is_gif = file_signature.startswith(b'GIF8')
        is_valid_signature = is_jpeg or is_png or is_gif
        
        if not is_valid_content_type and not is_valid_signature:
            raise HTTPException(status_code=400, detail="Invalid file type. Only JPEG, PNG, and GIF are allowed.")
        
        # Perform facial recognition
        rekognition_client = get_rekognition_client()
        if rekognition_client:
            # Validate face in image
            face_validation = validate_face_in_image(processed_image_bytes, rekognition_client)
            if not face_validation["valid"]:
                raise HTTPException(status_code=400, detail=face_validation["message"])
            
            
            # Content moderation
            moderation_response = detect_moderation_labels(processed_image_bytes, rekognition_client)
            is_appropriate, moderation_reason = is_content_appropriate_for_profile(moderation_response)
            
            if not is_appropriate:
                raise HTTPException(status_code=400, detail=moderation_reason)
        else:
            logger.warning("AWS Rekognition not available, skipping face detection")
        
        # Generate filename using user ID
        identity_snapshot_filename = f"{user_id}.jpg"
        
        # Delete existing snapshot if it exists to avoid 409 Duplicate errors
        try:
            existing_files = await supabase.storage.from_("identity-snapshots").list(path="")
            existing_file = next((f for f in existing_files if f["name"] == identity_snapshot_filename), None)
            if existing_file:
                await supabase.storage.from_("identity-snapshots").remove([identity_snapshot_filename])
        except ClientError as e:
            logger.warning(f"Could not remove existing identity snapshot: {e}")
        
        # Upload to Supabase storage
        upload_response = await upload_to_supabase_storage_with_retry(
            supabase, 
            "identity-snapshots", 
            identity_snapshot_filename, 
            processed_image_bytes, 
            "image/jpeg"
        )
        
        if upload_response:
            # Update user with identity snapshot filename
            update_response = await supabase.table("users").update({
                "identity_snapshot_filename": identity_snapshot_filename,
                "updated_at": datetime.utcnow().isoformat()
            }).eq("id", user_id).execute()
            
            if update_response.data:
                # Generate signed URL for response
                signed_url_response = await supabase.storage.from_("identity-snapshots").create_signed_url(
                    identity_snapshot_filename, 
                    expires_in=3600
                )
                signed_url = signed_url_response.get('signedURL') if isinstance(signed_url_response, dict) else signed_url_response
                
                return IdentitySnapshotUploadResponse(
                    message="Identity snapshot uploaded and validated successfully",
                    identity_snapshot_url=signed_url
                )
            else:
                # Clean up uploaded file if database update fails
                try:
                    await supabase.storage.from_("identity-snapshots").remove([identity_snapshot_filename])
                except:
                    pass
                raise HTTPException(status_code=500, detail="Failed to update user profile")
        else:
            raise HTTPException(status_code=500, detail="Failed to upload identity snapshot")
            
    except HTTPException:
        raise
    except (IOError, ValueError, ClientError) as e:
        logger.error(f"Unexpected error in identity snapshot upload: {str(e)}")
        raise HTTPException(status_code=500, detail="An unexpected error occurred")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in upload_identity_snapshot: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in upload_identity_snapshot: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload identity snapshot")

@router.get("/{user_id}/verification-stats")
async def get_user_verification_stats(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Return lifetime verifications and per-day counts for the current Sunday-to-Saturday week."""
    try:
        if str(current_user.id) != user_id and not current_user.is_admin:
            raise HTTPException(status_code=403, detail="Cannot access another user's stats")

        # Get lifetime
        user_result = await supabase.table("users").select("lifetime_verifications, lifetime_habits_completed").eq("id", user_id).single().execute()
        lifetime_verifications = user_result.data.get("lifetime_verifications", 0) if user_result.data else 0
        lifetime_habits_completed = user_result.data.get("lifetime_habits_completed", 0) if user_result.data else 0

        # Determine user's timezone and current local date
        timezone_str = await get_user_timezone(supabase, user_id)
        tz = pytz.timezone(timezone_str)

        today_local = datetime.now(tz).date()
        # date.weekday(): Monday=0; want Sunday=0, so shift
        sunday_offset = (today_local.weekday() + 1) % 7  # days since last Sunday
        week_start = today_local - timedelta(days=sunday_offset)
        week_end = week_start + timedelta(days=6)

        # Fetch per-day counts
        daily_result = await supabase.table("user_verification_daily_counts") \
            .select("verification_date, count") \
            .eq("user_id", user_id) \
            .gte("verification_date", week_start.isoformat()) \
            .lte("verification_date", week_end.isoformat()) \
            .order("verification_date", asc=True) \
            .execute()

        # Aggregated table already stores dates in user timezone – use directly.
        daily_counts = {row["verification_date"]: row["count"] for row in (daily_result.data or [])}

        # Build complete week list (Sun-Sat)
        week_counts = []
        for i in range(7):
            day = week_start + timedelta(days=i)
            week_counts.append({
                "date": day.isoformat(),
                "count": daily_counts.get(day.isoformat(), 0)
            })

        return {
            "lifetime_verifications": lifetime_verifications,
            "lifetime_habits_completed": lifetime_habits_completed,
            "week_start": week_start.isoformat(),
            "week_end": week_end.isoformat(),
            "weekly_counts": week_counts
        }
    except HTTPException:
        raise
    except (ValueError, KeyError, TypeError) as e:
        logger.error(f"Error getting verification stats for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve stats") 
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_user_verification_stats: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_user_verification_stats: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve stats")

from pydantic import BaseModel
from datetime import datetime
import pytz

class HabitStatsTodayResponse(BaseModel):
    total_habits_today: int
    completed_habits_today: int
    longest_streak: Optional[int] = None  # Make it optional with a default of None

@router.get("/{user_id}/habit-stats-today", response_model=HabitStatsTodayResponse)
async def get_habit_stats_today(
    user_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Return the number of daily habits scheduled for today and the number completed for today for the given user.
    """
    try:
        # Get user's timezone (or default to UTC)
        timezone_str = await get_user_timezone(supabase, user_id)
        tz = pytz.timezone(timezone_str)
        today = datetime.now(tz)
        day_index = (today.weekday() + 1) % 7  # 0=Sunday, 1=Monday, etc.

        # Fetch all habits for the user
        habits_result = await supabase.table("habits").select("*").eq("user_id", user_id).execute()
        habits = habits_result.data or []

        # Filter for daily habits scheduled for today
        today_habits = [
            h for h in habits
            if h.get("habit_schedule_type", "daily") == "daily"
            and day_index in (h.get("weekdays") or [])
        ]
        total_habits_today = len(today_habits)

        # Fetch today's verifications for this user
        today_str = today.date().isoformat()
        verifications_result = await supabase.table("habit_verifications") \
            .select("habit_id, verified_at") \
            .eq("user_id", user_id) \
            .gte("verified_at", today_str + "T00:00:00") \
            .lte("verified_at", today_str + "T23:59:59") \
            .execute()
        verified_habit_ids = {v["habit_id"] for v in (verifications_result.data or [])}

        # Count how many of today's habits are completed
        completed_habits_today = sum(1 for h in today_habits if h["id"] in verified_habit_ids)

        # Get longest streak from habits table
        longest_streak = 0
        for habit in habits:
            current_streak = habit.get("streak", 0)  # Correct field name is 'streak'
            if current_streak is None:
                current_streak = 0
            longest_streak = max(longest_streak, current_streak)
        
        return HabitStatsTodayResponse(
            total_habits_today=total_habits_today,
            completed_habits_today=completed_habits_today,
            longest_streak=longest_streak
        )
    except (ValueError, KeyError, TypeError) as e:
        raise HTTPException(status_code=500, detail=f"Failed to get today's habit stats: {e}") 
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in get_habit_stats_today: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in get_habit_stats_today: {e}")
        raise HTTPException(status_code=500, detail="Failed to get today's habit stats")

@router.post("/request-account-deletion")
async def request_account_deletion(
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    User requests account deletion. This inserts a row into the delete_account_request table.
    """
    try:
        await supabase.table("delete_account_request").insert({
            "user_id": str(current_user.id),  # Convert UUID to string
            "created_at": datetime.utcnow().isoformat()
        }).execute()
        return {"message": "Your account deletion request has been received. Our team will process it soon."}
    except (ValueError, KeyError) as e:
        logger.error(f"Error handling account deletion request: {e}")
        raise HTTPException(status_code=500, detail="Failed to process account deletion request") 
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in request_account_deletion: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in request_account_deletion: {e}")
        raise HTTPException(status_code=500, detail="Failed to process account deletion request")

@router.delete("/cancel-account-deletion")
async def cancel_account_deletion(
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Cancel the user's account deletion request by removing their entry from the delete_account_request table.
    """
    try:
        response = await supabase.table("delete_account_request").delete().eq("user_id", str(current_user.id)).execute()
        if response.data and len(response.data) > 0:
            return {"message": "Your account deletion request has been cancelled."}
        else:
            return {"message": "No account deletion request found to cancel."}
    except (ValueError, KeyError) as e:
        logger.error(f"Error cancelling account deletion request: {e}")
        raise HTTPException(status_code=500, detail="Failed to cancel account deletion request") 
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in cancel_account_deletion: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in cancel_account_deletion: {e}")
        raise HTTPException(status_code=500, detail="Failed to cancel account deletion request")
    
@router.get("/account/has-account-deletion-request", name="check_deletion_request")
async def has_account_deletion_request(
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Check if the current user has a pending account deletion request.
    """
    try:
        response = await supabase.table("delete_account_request").select("id").eq("user_id", str(current_user.id)).execute()
        has_request = bool(response.data and len(response.data) > 0)
        return {"has_request": has_request}
    except (ValueError, KeyError) as e:
        logger.error(f"Error checking account deletion request: {e}")
        raise HTTPException(status_code=500, detail="Failed to check account deletion request")
    except (ConnectionError, TimeoutError, OSError) as e:
        logger.error(f"Connectivity error in has_account_deletion_request: {e}")
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    except Exception as e:
        logger.exception(f"Unexpected error in has_account_deletion_request: {e}")
        raise HTTPException(status_code=500, detail="Failed to check account deletion request")