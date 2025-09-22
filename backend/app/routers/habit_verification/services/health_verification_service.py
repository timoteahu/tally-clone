from typing import Optional, Dict, Any
from datetime import datetime, date
from fastapi import HTTPException, UploadFile
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory, disable_print, memory_optimized
from utils.timezone_utils import get_user_timezone
from utils.health_processing import verify_health_habit, is_health_habit_type
from utils.recipient_analytics import update_analytics_on_habit_verified
from .image_verification_service import process_image_verification
from .habit_verification_service import check_existing_verification, increment_habit_streak
from services.notification_service import notification_service
import pytz

# Disable verbose printing for performance
print = disable_print()

@memory_optimized(cleanup_args=False)
async def verify_health_habit_service(
    habit_id: str, 
    selfie_image: Optional[UploadFile], 
    content_image: Optional[UploadFile], 
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Verify health habit service - handles both image verification and health data verification
    
    If images are provided: Verifies using image processing (like regular habits)
    If no images: Verifies using health data from HealthKit integration
    """
    try:
        # Get habit data first
        habit_result = await supabase.table("habits").select("*").eq("id", habit_id).execute()
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        habit_data = habit_result.data[0]
        user_id = habit_data["user_id"]
        habit_type = habit_data["habit_type"]
        
        # Verify it's a health habit
        if not is_health_habit_type(habit_type):
            raise HTTPException(status_code=400, detail="Not a health habit type")
        
        # Check if already verified today
        existing_verification = await check_existing_verification(habit_id, user_id, supabase)
        if existing_verification:
            current_streak = habit_data.get("streak", 0)
            cleanup_memory(habit_result)
            return {
                "message": "✅ Already verified for today! Keep up the healthy lifestyle!",
                "status": "already_verified",
                "is_verified": True,
                "streak": current_streak
            }
        
        # Case 1: Images provided - use image verification (health habit becomes a post)
        if selfie_image and content_image:
            print("Images provided, verifying using image verification")
            return await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type=habit_type,  # Pass actual health habit type for better OpenAI prompts
                supabase=supabase
            )
        
        # Case 2: No images - verify using health data
        else:
            print("No images provided, verifying using health data")
            return await verify_health_data_only(habit_id, user_id, habit_data, supabase)
            
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in health habit verification: {e}")
        raise HTTPException(status_code=500, detail="Health verification failed")

@memory_optimized(cleanup_args=False)
async def verify_health_data_only(
    habit_id: str, 
    user_id: str, 
    habit_data: Dict[str, Any], 
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Verify health habit using only health data (no images)
    This creates a verification record but no post
    
    Note: iOS app already validates health targets before calling this endpoint,
    so we trust that the user has met their goal and just create the verification.
    """
    try:
        print(f"🔍 Starting health data verification for habit {habit_id}, user {user_id}")
        
        # Get user timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        today = datetime.now(user_tz).date()
        
        print(f"🔍 User timezone: {user_timezone}, today: {today}")
        
        # Since iOS app already validated the health target was met,
        # we just create the verification record directly
        now_utc = datetime.utcnow()
        verification_data = {
            "habit_id": habit_id,
            "user_id": user_id,
            "verification_type": habit_data["habit_type"],
            "verified_at": now_utc.isoformat(),
            "status": "verified",
            "verification_result": True
        }
        
        print(f"🔍 Created verification data: {verification_data}")
        
        verification_result = await supabase.table("habit_verifications").insert(verification_data).execute()
        
        print(f"🔍 Verification insert result: {verification_result}")
        
        # Increment habit streak
        print(f"🔍 Incrementing streak for habit {habit_id}")
        # OPTIMIZATION: Fixed parameter order to match new function signature
        new_streak = await increment_habit_streak(habit_id, supabase)
        
        print(f"🔍 New streak: {new_streak}")
        
        # Update recipient analytics if habit has a recipient
        if habit_data.get("recipient_id"):
            try:
                print(f"🔍 Updating recipient analytics for recipient {habit_data['recipient_id']}")
                await update_analytics_on_habit_verified(
                    supabase=supabase,
                    habit_id=habit_id,
                    recipient_id=habit_data["recipient_id"],
                    verification_date=today
                )
                print(f"🔍 Recipient analytics updated successfully")
                
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
                        habit_type=habit_data["habit_type"],
                        supabase_client=supabase
                    )
                    print(f"🔍 Recipient notification sent successfully")
                except Exception as notification_error:
                    # Don't fail the verification if notification fails
                    print(f"Failed to send recipient notification: {notification_error}")
                    
            except Exception as e:
                # Don't fail the verification if analytics update fails
                print(f"Failed to update recipient analytics: {e}")
        
        # Cleanup
        cleanup_memory(verification_data, verification_result)
        
        # Success message for health habit completion
        habit_name = habit_data.get('name', 'Health habit')
        
        print(f"🔍 Returning success response for {habit_name}")
        
        return {
            "message": f"✅ {habit_name} verified! Great job reaching your health goal!",
            "status": "verified",
            "is_verified": True,
            "streak": new_streak,
            "verification_id": verification_result.data[0]["id"] if verification_result.data else None
        }
        
    except HTTPException:
        print(f"❌ HTTPException in health data verification")
        raise
    except Exception as e:
        print(f"❌ Exception in health data verification: {e}")
        print(f"❌ Exception type: {type(e)}")
        import traceback
        print(f"❌ Full traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=f"Health data verification failed: {str(e)}")

async def share_health_habit_photo_service(habit_id: str, selfie_image, supabase):
    """Share health habit photo service - placeholder"""
    return {"message": "Health photo sharing service not implemented yet"} 