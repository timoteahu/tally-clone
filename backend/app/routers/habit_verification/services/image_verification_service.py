import uuid
import asyncio
from typing import Dict, Any, Optional, List
from fastapi import HTTPException, UploadFile
from supabase._async.client import AsyncClient
from datetime import datetime

import pytz
from utils.memory_optimization import cleanup_memory, memory_optimized, disable_print
from utils.memory_monitoring import MemoryMonitor, log_memory_usage
from utils.timezone_utils import get_user_timezone, get_user_date_range_in_timezone
from utils.monitoring import get_aws_rekognition_client
from utils.storage import async_upload_to_supabase_storage_with_retry
from utils.recipient_analytics import update_analytics_on_habit_verified
from utils.health_processing import is_health_habit_type
from utils.weekly_habits import update_weekly_progress
from .aws_rekognition_service import perform_face_verification, perform_content_moderation
from .habit_verification_service import check_existing_verification, increment_habit_streak
# OPTIMIZATION: Use optimized habit queries
from utils.habit_queries import get_habit_by_id, HABIT_VERIFICATION_COLUMNS
from services.openai_vision_service import openai_vision_service
from .habit_verification_service import get_custom_habit_type_cached
from services.notification_service import notification_service
import json
import logging

logger = logging.getLogger(__name__)

# Disable verbose printing
@memory_optimized(cleanup_args=True)
async def process_image_verification(
    habit_id: str,
    selfie_image: UploadFile,
    content_image: UploadFile,
    habit_type: str,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Process image verification with face detection, content validation, and habit streak management.
    OPTIMIZED: Uses selective column fetching instead of SELECT *.
    """
    
    with MemoryMonitor("image_verification") as monitor:
        # Variables for cleanup tracking
        habit_data = None
        identity_snapshot_bytes = None
        selfie_contents = None
        content_contents = None
        
        try:
            log_memory_usage("verification_start")
            
            # OPTIMIZATION: Use optimized habit query with selective columns
            habit_data = await get_habit_by_id(
                supabase=supabase,
                habit_id=habit_id,
                columns=HABIT_VERIFICATION_COLUMNS + ", private, recipient_id, habit_schedule_type, weekly_target, week_start_day"
            )
            
            if not habit_data:
                raise HTTPException(status_code=404, detail="Habit not found")

            user_id = habit_data["user_id"]
            
            monitor.checkpoint("habit_data_loaded")
            
            # Get user timezone and current time
            user_timezone = await get_user_timezone(supabase, user_id)
            now_utc = datetime.utcnow()
            today_start, today_end = get_user_date_range_in_timezone(user_timezone)
            
            monitor.checkpoint("timezone_data_loaded")
            
            # Check if already verified today
            existing_verification = await check_existing_verification(habit_id, user_id, supabase)
            if existing_verification:
                already_verified_messages = {
                    "gym": "✅ Already verified for today! Great job staying consistent.",
                    "alarm": "✅ Already verified for today! You're already up and at 'em!"
                }
                current_streak = habit_data.get("streak", 0)
                cleanup_memory(habit_data)
                
                return {
                    "message": already_verified_messages.get(habit_type, "✅ Already verified for today!"),
                    "status": "already_verified",
                    "is_verified": True,
                    "streak": current_streak
                }
            
            monitor.checkpoint("verification_check_complete")
            
            # Read and validate image files
            selfie_contents = await selfie_image.read()
            content_contents = await content_image.read()
            
            monitor.checkpoint("image_files_read")
            log_memory_usage("images_loaded")
            
            # Get AWS Rekognition client
            rekognition_client = get_aws_rekognition_client()
            if not rekognition_client:
                raise HTTPException(status_code=503, detail="Face verification service temporarily unavailable")
            
            monitor.checkpoint("aws_client_loaded")
            
            # OPTIMIZATION: Get only needed user field for identity snapshot
            identity_result = await supabase.table("users").select("identity_snapshot_filename").eq("id", user_id).execute()
            if not identity_result.data or not identity_result.data[0].get("identity_snapshot_filename"):
                raise HTTPException(status_code=400, detail="Identity snapshot not found. Please update your profile photo.")
            
            identity_filename = identity_result.data[0]["identity_snapshot_filename"]
            
            # Get identity snapshot from storage
            try:
                identity_response = await supabase.storage.from_("identity-snapshots").download(identity_filename)
                identity_snapshot_bytes = identity_response
            except Exception as e:
                raise HTTPException(status_code=400, detail="Failed to load identity snapshot for verification")
            
            monitor.checkpoint("identity_snapshot_loaded")
            log_memory_usage("identity_loaded")
            
            # Perform face verification
            face_success, face_message, similarity = await perform_face_verification(
                identity_snapshot_bytes, selfie_contents
            )
            
            monitor.checkpoint("face_verification_complete")
            log_memory_usage("face_verified")
            
            if not face_success:
                raise HTTPException(status_code=400, detail=face_message)
            
            # Perform NSFW content moderation
            is_appropriate, moderation_reason = await perform_content_moderation(content_contents)
            
            monitor.checkpoint("content_moderation_complete")
            log_memory_usage("content_moderated")
            
            if not is_appropriate:
                raise HTTPException(status_code=400, detail=moderation_reason)
            
            # Check if this is a health habit type using the centralized utility function
            is_health_habit = is_health_habit_type(habit_type)
            
            # Initialize variables
            openai_metadata = {"valid": True, "is_screen": False}
            custom_description = None
            custom_type_data = None
            verification_failed = False
            error_message = None
            is_screen_detected = False
            
            # Skip OpenAI verification for health habits (they're already verified via HealthKit)
            if not is_health_habit:
                # Get custom habit description if needed
                if habit_type.startswith("custom_"):
                    if habit_data.get("custom_habit_type_id"):
                        custom_type_data = await get_custom_habit_type_cached(
                            supabase, habit_data.get("custom_habit_type_id")
                        )
                        custom_description = custom_type_data.get("description") if custom_type_data else None
                
                # Verify with OpenAI Vision
                openai_metadata = await openai_vision_service.verify_habit(
                    content_contents,
                    habit_type,
                    habit_data.get("name"),
                    custom_description
                )
                
                # Debug logging
                logger.info(f"OpenAI verification result: {json.dumps(openai_metadata)}")
                
                monitor.checkpoint("openai_verification_complete")
                log_memory_usage("openai_verified")
                
                # Store screen detection flag for later
                is_screen_detected = openai_metadata.get("is_screen", False)
                
                # Check if we need to fail the verification
                if is_screen_detected:
                    verification_failed = True
                    error_message = "nice try! 📱 take a real photo, not a picture of a screen"
                elif not openai_metadata.get("valid", False):
                    verification_failed = True
                # Use consistent error messages for each habit type
                error_messages = {
                    "gym": "can't see gym equipment or fitness environment. take a photo at the gym showing equipment or gym space",
                    "alarm": "can't see a bathroom. take a photo in your bathroom to prove you're awake and out of bed",
                    "yoga": "can't see yoga-related items. show your yoga mat, poses, or studio",
                    "outdoors": "can't see outdoor environment. take a photo showing you're outside",
                    "cycling": "can't see cycling-related items. show your bike, helmet, or cycling path",
                    "cooking": "can't see cooking-related items. show your kitchen, ingredients, or food prep"
                }
                
                # For custom habits
                if habit_type.startswith("custom_"):
                    # Extract the custom type identifier from habit_type
                    type_identifier = habit_type.replace("custom_", "")
                    display_name = type_identifier.replace("_", " ").title()
                    # Use custom type name if available, otherwise use the formatted identifier
                    if custom_type_data:
                        display_name = custom_type_data.get("name", display_name)
                    error_message = f"can't see {display_name}-related items. take a photo related to your {display_name} activity"
                else:
                    error_message = error_messages.get(
                        habit_type, 
                        "verification failed. please take a photo that clearly shows you doing the habit"
                    )
            
            # Upload original images to storage
            selfie_filename = f"{user_id}_{habit_id}_{int(now_utc.timestamp())}_selfie.jpg"
            content_filename = f"{user_id}_{habit_id}_{int(now_utc.timestamp())}.jpg"
            
            # Determine bucket based on habit privacy
            bucket_name = "private_images" if habit_data.get("private", False) else "public_images"
            
            # Upload images concurrently
            import asyncio
            upload_tasks = [
                async_upload_to_supabase_storage_with_retry(
                    supabase, bucket_name, selfie_filename, selfie_contents, "image/jpeg"
                ),
                async_upload_to_supabase_storage_with_retry(
                    supabase, bucket_name, content_filename, content_contents, "image/jpeg"
                )
            ]
            await asyncio.gather(*upload_tasks)
            
            monitor.checkpoint("images_uploaded")
            log_memory_usage("images_uploaded")
            
            # If verification failed, store training data ONLY for screen detections
            # Skip custom habits as they only use OpenAI
            if verification_failed:
                # Only store screen detections for training (excluding custom habits)
                if is_screen_detected and not habit_type.startswith("custom_"):
                    try:
                        training_data = {
                            "habit_type": habit_type,
                            "is_valid": False,  # Screen detections are never valid
                            "confidence": openai_metadata.get("openai_confidence", 0.5),
                            "is_screen": True,
                            "image_path": f"{bucket_name}/{content_filename}"  # Reference to actual image
                        }
                        await supabase.table("ml_training_data").insert(training_data).execute()
                        monitor.checkpoint("screen_training_data_recorded")
                    except Exception as e:
                        print(f"Failed to record screen detection for training: {e}")
                
                # Now throw the error
                raise HTTPException(status_code=400, detail=error_message)
            
            # Only create verification record for successful verifications
            verification_data = {
                "habit_id": habit_id,
                "user_id": user_id,
                "verification_type": habit_type,
                "verified_at": now_utc.isoformat(),
                "status": "verified",
                "verification_result": True,  # Always true for saved verifications
                "image_filename": content_filename,
                "selfie_image_filename": selfie_filename
            }
            
            verification_result = await supabase.table("habit_verifications").insert(verification_data).execute()
            
            monitor.checkpoint("verification_record_created")
            
            # Store training data for successful verifications with decent confidence
            # Skip custom habits and health habits as they only use OpenAI or no AI
            confidence = openai_metadata.get("openai_confidence", 0)
            is_custom = habit_type.startswith("custom_")
            logger.info(
                f"Checking training data storage: confidence={confidence}, threshold=0.6, "
                f"is_custom={is_custom}, is_health={is_health_habit}, "
                f"should_store={confidence > 0.6 and not is_custom and not is_health_habit}"
            )
            
            if confidence > 0.6 and not is_custom and not is_health_habit:
                try:
                    training_data = {
                        "habit_type": habit_type,
                        "is_valid": True,
                        "confidence": confidence,
                        "is_screen": False,  # Successful verifications are never screens
                        "image_path": f"{bucket_name}/{content_filename}"
                    }
                    logger.info(f"Storing training data: {json.dumps(training_data)}")
                    await supabase.table("ml_training_data").insert(training_data).execute()
                    monitor.checkpoint("training_data_recorded")
                    logger.info("Training data stored successfully")
                except Exception as e:
                    logger.error(f"Failed to record training data: {e}")
            
            # Increment habit streak
            new_streak = await increment_habit_streak(habit_id, supabase)
            
            monitor.checkpoint("streak_updated")

            # Increment weekly progress if applicable
            if habit_data.get("habit_schedule_type") == "weekly":
                try:
                    user_tz_str = await get_user_timezone(supabase, user_id)
                    verification_date = datetime.now(pytz.timezone(user_tz_str)).date()
                    await update_weekly_progress(
                        supabase=supabase,
                        habit_id=habit_id,
                        user_id=user_id,
                        verification_date=verification_date,
                        weekly_target=habit_data.get("weekly_target", 1),
                        week_start_day=habit_data.get("week_start_day", 0)
                    )
                    monitor.checkpoint("weekly_progress_updated")
                except Exception as e:
                    print(f"⚠️ update_weekly_progress failed for {habit_id}: {e}")
            
            # Update recipient analytics if habit has a recipient
            if habit_data.get("recipient_id"):
                try:
                    # Get verification date in user's timezone
                    user_tz_str = await get_user_timezone(supabase, user_id)
                    user_tz = pytz.timezone(user_tz_str)
                    verification_date = datetime.now(user_tz).date()
                    
                    await update_analytics_on_habit_verified(
                        supabase=supabase,
                        habit_id=habit_id,
                        recipient_id=habit_data["recipient_id"],
                        verification_date=verification_date
                    )
                    monitor.checkpoint("recipient_analytics_updated")
                    
                    # Send push notification to recipient
                    try:
                        # Get the verifier's name
                        user_result = await supabase.table("users").select("username").eq("id", user_id).execute()
                        verifier_name = "Someone"
                        if user_result.data and user_result.data[0].get("username"):
                            verifier_name = user_result.data[0]["username"]
                        
                        # Send notification to recipient
                        await notification_service.send_habit_verification_notification(
                            recipient_user_id=habit_data["recipient_id"],
                            verifier_name=verifier_name,
                            habit_name=habit_data.get("name", "habit"),
                            habit_type=habit_type,
                            supabase_client=supabase
                        )
                        monitor.checkpoint("recipient_notification_sent")
                    except Exception as notification_error:
                        # Don't fail the verification if notification fails
                        print(f"Failed to send recipient notification: {notification_error}")
                        
                except Exception as e:
                    # Don't fail the verification if analytics update fails
                    print(f"Failed to update recipient analytics: {e}")
            
            log_memory_usage("verification_complete")
            
            # Clean up all temporary data
            cleanup_memory(
                habit_data, identity_snapshot_bytes,
                selfie_contents, content_contents, verification_data, verification_result
            )
            
            # Create consistent success messages for each habit type
            success_messages = {
                "gym": "gym verified",
                "alarm": "alarm verified - you're up",
                "yoga": "yoga verified",
                "outdoors": "outdoor activity verified",
                "cycling": "cycling verified",
                "cooking": "cooking verified"
            }
            
            # For custom habits
            if habit_type.startswith("custom_"):
                # Extract the custom type identifier from habit_type
                type_identifier = habit_type.replace("custom_", "")
                display_name = type_identifier.replace("_", " ").title()
                # Use custom type name if available, otherwise use the formatted identifier
                if custom_type_data:
                    display_name = custom_type_data.get("name", display_name)
                success_message = f"{display_name} verified"
            else:
                success_message = success_messages.get(habit_type, "habit verified")
            
            return {
                "message": success_message,
                "status": "verified", 
                "is_verified": True,
                "streak": new_streak,
                "verification_id": verification_result.data[0]["id"] if verification_result.data else None
            }
            
        except HTTPException:
            # Clean up on error
            cleanup_memory(
                habit_data, identity_snapshot_bytes,
                selfie_contents, content_contents
            )
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            log_memory_usage("verification_error")
            
            # Clean up on error
            cleanup_memory(
                habit_data, identity_snapshot_bytes,
                selfie_contents, content_contents
            )
            
            raise HTTPException(status_code=500, detail=f"Verification failed: {str(e)}") 