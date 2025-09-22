from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, Query, Form
from typing import Optional
from supabase._async.client import AsyncClient
from config.database import get_async_supabase_client
from utils.memory_optimization import cleanup_memory, disable_print
from utils.memory_monitoring import MemoryMonitor, log_memory_usage
from utils.timezone_utils import get_user_timezone  # Re-export for backward compatibility
from routers.auth import get_current_user_lightweight
from models.schemas import User
# OPTIMIZATION: Use optimized habit queries
from utils.habit_queries import get_habit_by_id, HABIT_VERIFICATION_COLUMNS
# Add imports for image endpoints
from datetime import datetime
import pytz

# Import all service functions
from .services import (
    process_image_verification,
    # Context validators deprecated - using OpenAI Vision API
    # is_gym_related,
    # is_bathroom_related,
    # is_yoga_related,
    # is_outdoors_related,
    # is_cycling_related,
    # is_cooking_related,
    # is_health_activity_related,
    # is_custom_habit_related,
    start_study_session_service,
    complete_study_session_service,
    get_screen_time_status_service,
    update_screen_time_status_service,
    verify_health_habit_service,
    share_health_habit_photo_service,
    get_latest_verification_service,
    get_verifications_by_habit_service,
    get_verification_by_date_service,
    get_custom_habit_type_cached  # OPTIMIZATION: Use cached function
)

# Import utils for backward compatibility
from .utils import (
    generate_verification_image_url,
    generate_verification_image_urls
)

# Create selective print function - disable verbose prints
_original_print = print
def selective_print(*args, **kwargs):
    # Suppress verbose prints
    pass

print = disable_print()


# Memory monitoring helper (keep for internal use but no output)
def get_current_memory():
    """Get current memory usage for monitoring"""
    import psutil
    import os
    process = psutil.Process(os.getpid())
    memory = process.memory_info()
    return memory.rss / 1024 / 1024  # Convert to MB

router = APIRouter()

# MARK: - Verification Endpoints

@router.post("/gym/{habit_id}/verify")
async def verify_gym_habit(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    content_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify gym habit with face verification and OpenAI Vision"""
    with MemoryMonitor("gym_verification") as monitor:
        try:
            result = await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type="gym",
                supabase=supabase
            )
            monitor.checkpoint("verification_complete")
            cleanup_memory(selfie_image, content_image)
            return result
        except HTTPException:
            cleanup_memory(selfie_image, content_image)
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image, content_image)
            raise HTTPException(status_code=500, detail=str(e))

@router.post("/alarm/{habit_id}/verify")
async def verify_alarm_habit(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    content_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify alarm habit with face verification and OpenAI Vision"""
    with MemoryMonitor("alarm_verification") as monitor:
        try:
            result = await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type="alarm",
                supabase=supabase
            )
            monitor.checkpoint("verification_complete")
            cleanup_memory(selfie_image, content_image)
            return result
        except HTTPException:
            cleanup_memory(selfie_image, content_image)
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image, content_image)
            raise HTTPException(status_code=500, detail=str(e))

@router.post("/custom/{habit_id}/verify")
async def verify_custom_habit(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    content_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify custom habit with face verification and OpenAI Vision - OPTIMIZED"""
    with MemoryMonitor("custom_verification") as monitor:
        try:
            # OPTIMIZATION: Get habit data to construct proper habit_type
            habit_data = await get_habit_by_id(
                supabase=supabase,
                habit_id=habit_id,
                columns="custom_habit_type_id"
            )
            
            if not habit_data:
                raise HTTPException(status_code=404, detail="Habit not found")
            
            custom_habit_type_id = habit_data.get("custom_habit_type_id")
            
            if not custom_habit_type_id:
                raise HTTPException(status_code=400, detail="Custom habit type not specified")
            
            # Get custom type data to construct proper habit_type
            custom_type_data = await get_custom_habit_type_cached(supabase, custom_habit_type_id)
            if not custom_type_data:
                raise HTTPException(status_code=400, detail="Custom habit type not found")
            
            # Construct proper habit_type format: "custom_" + type_identifier
            type_identifier = custom_type_data.get("type_identifier", "unknown")
            habit_type = f"custom_{type_identifier}"
            
            monitor.checkpoint("custom_type_loaded")
            
            result = await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type=habit_type,  # Now properly formatted
                supabase=supabase
            )
            
            monitor.checkpoint("verification_complete")
            cleanup_memory(selfie_image, content_image, habit_data, custom_type_data)
            return result
            
        except HTTPException:
            cleanup_memory(selfie_image, content_image)
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image, content_image)
            raise HTTPException(status_code=500, detail=str(e))

@router.post("/yoga/{habit_id}/verify")
async def verify_yoga_habit(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    content_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify yoga habit with face verification and OpenAI Vision"""
    with MemoryMonitor("yoga_verification") as monitor:
        try:
            result = await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type="yoga",
                supabase=supabase
            )
            monitor.checkpoint("verification_complete")
            cleanup_memory(selfie_image, content_image)
            return result
        except HTTPException:
            cleanup_memory(selfie_image, content_image)
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image, content_image)
            raise HTTPException(status_code=500, detail=str(e))

@router.post("/outdoors/{habit_id}/verify")
async def verify_outdoors_habit(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    content_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify outdoors activity habit with face verification and OpenAI Vision"""
    with MemoryMonitor("outdoors_verification") as monitor:
        try:
            result = await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type="outdoors",
                supabase=supabase
            )
            monitor.checkpoint("verification_complete")
            cleanup_memory(selfie_image, content_image)
            return result
        except HTTPException:
            cleanup_memory(selfie_image, content_image)
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image, content_image)
            raise HTTPException(status_code=500, detail=str(e))

@router.post("/cycling/{habit_id}/verify")
async def verify_cycling_habit(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    content_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify cycling habit with face verification and OpenAI Vision"""
    with MemoryMonitor("cycling_verification") as monitor:
        try:
            result = await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type="cycling",
                supabase=supabase
            )
            monitor.checkpoint("verification_complete")
            cleanup_memory(selfie_image, content_image)
            return result
        except HTTPException:
            cleanup_memory(selfie_image, content_image)
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image, content_image)
            raise HTTPException(status_code=500, detail=str(e))

@router.post("/cooking/{habit_id}/verify")
async def verify_cooking_habit(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    content_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify cooking habit with face verification and OpenAI Vision"""
    with MemoryMonitor("cooking_verification") as monitor:
        try:
            result = await process_image_verification(
                habit_id=habit_id,
                selfie_image=selfie_image,
                content_image=content_image,
                habit_type="cooking",
                supabase=supabase
            )
            monitor.checkpoint("verification_complete")
            cleanup_memory(selfie_image, content_image)
            return result
        except HTTPException:
            cleanup_memory(selfie_image, content_image)
            raise
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image, content_image)
            raise HTTPException(status_code=500, detail=str(e))

@router.post("/health/{habit_id}/verify")
async def verify_health_habit(
    request: Request,
    habit_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Verify health habit with optional images or simple data verification"""
    with MemoryMonitor("health_verification") as monitor:
        try:
            # Check if request contains multipart form data (images)
            content_type = request.headers.get("content-type", "")
            print(f"🔍 [HealthVerification] Content-Type: {content_type}")
            
            if content_type.startswith("multipart/form-data"):
                print("🔍 [HealthVerification] Detected multipart/form-data, parsing form...")
                # Handle multipart request with images
                form = await request.form()
                print(f"🔍 [HealthVerification] Form keys: {list(form.keys())}")
                
                selfie_image = form.get("selfie_image")
                content_image = form.get("content_image")
                
                print(f"🔍 [HealthVerification] selfie_image type: {type(selfie_image)}")
                print(f"🔍 [HealthVerification] content_image type: {type(content_image)}")
                
                # Convert to UploadFile objects if present
                selfie_upload = selfie_image if (selfie_image and hasattr(selfie_image, 'file') and hasattr(selfie_image, 'filename')) else None
                content_upload = content_image if (content_image and hasattr(content_image, 'file') and hasattr(content_image, 'filename')) else None
                
                print(f"🔍 [HealthVerification] selfie_upload: {selfie_upload is not None}")
                print(f"🔍 [HealthVerification] content_upload: {content_upload is not None}")
                
                result = await verify_health_habit_service(
                    habit_id=habit_id,
                    selfie_image=selfie_upload,
                    content_image=content_upload,
                    supabase=supabase
                )
            else:
                print(f"🔍 [HealthVerification] Non-multipart request, content-type: {content_type}")
                # Handle simple POST request (health data only)
                result = await verify_health_habit_service(
                    habit_id=habit_id,
                    selfie_image=None,
                    content_image=None,
                    supabase=supabase
                )
            
            monitor.checkpoint("verification_complete")
            return result
        except Exception as e:
            print(f"Health verification error: {e}")
            monitor.checkpoint(f"error_{type(e).__name__}")
            raise HTTPException(status_code=400, detail=str(e))

@router.post("/health/{habit_id}/share-photo")
async def share_health_habit_photo(
    habit_id: str,
    selfie_image: UploadFile = File(...),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Share a photo for a health habit after verification"""
    with MemoryMonitor("health_photo_share") as monitor:
        try:
            result = await share_health_habit_photo_service(
                habit_id=habit_id,
                selfie_image=selfie_image,
                supabase=supabase
            )
            monitor.checkpoint("photo_share_complete")
            cleanup_memory(selfie_image)
            return result
        except Exception as e:
            monitor.checkpoint(f"error_{type(e).__name__}")
            cleanup_memory(selfie_image)
            raise HTTPException(status_code=400, detail=str(e))

# MARK: - Study Session Endpoints

@router.post("/study/{habit_id}/start")
async def start_study_session(
    habit_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Start a study session"""
    try:
        log_memory_usage("study_session_start")
        result = await start_study_session_service(habit_id, supabase)
        cleanup_memory(habit_id)
        return result
    except Exception as e:
        print(f"Study session start error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/study/{habit_id}/complete")
async def complete_study_session(
    habit_id: str,
    request: Request,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Complete a study session"""
    try:
        log_memory_usage("study_session_complete")
        result = await complete_study_session_service(habit_id, request, supabase)
        cleanup_memory(request)
        return result
    except Exception as e:
        print(f"Study session complete error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

# MARK: - Screen Time Endpoints

@router.get("/screen-time/{habit_id}/status")
async def get_screen_time_status(
    habit_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get screen time status for a habit"""
    try:
        log_memory_usage("screen_time_status")
        result = await get_screen_time_status_service(habit_id, supabase)
        cleanup_memory(habit_id)
        return result
    except Exception as e:
        print(f"Screen time status error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/screen-time/{habit_id}/update")
async def update_screen_time_status(
    habit_id: str,
    request: Request,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Update screen time status"""
    try:
        log_memory_usage("screen_time_update")
        result = await update_screen_time_status_service(habit_id, request, supabase)
        cleanup_memory(request)
        return result
    except Exception as e:
        print(f"Screen time update error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

# MARK: - Data Retrieval Endpoints

@router.get("/get-latest/{habit_id}")
async def get_latest_verification(
    habit_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get the latest verification for a habit"""
    try:
        result = await get_latest_verification_service(habit_id, supabase)
        return result
    except HTTPException:
        raise
    except Exception as e:
        print(f"Get latest verification error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/get-verifications/{habit_id}")
async def get_verifications_by_habit(
    habit_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all verifications for a specific habit"""
    try:
        result = await get_verifications_by_habit_service(habit_id, supabase)
        return result
    except Exception as e:
        print(f"Get habit verifications error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/get/{date}")
async def get_verifications_by_date(
    date: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all verifications for a user on a specific date"""
    try:
        result = await get_verification_by_date_service(date, str(current_user.id), supabase)
        return result
    except Exception as e:
        print(f"Get verifications by date error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

# MARK: - Additional Data Endpoints (for backward compatibility)

@router.get("/get-week")
async def get_weekly_verifications(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all verifications for the current week"""
    try:
        from datetime import datetime, timedelta
        from utils.timezone_utils import get_user_timezone
        import pytz
        
        # Get user timezone and calculate week range
        user_timezone = await get_user_timezone(supabase, str(current_user.id))
        user_tz = pytz.timezone(user_timezone)
        now = datetime.now(user_tz)
        
        # Get start of week (Sunday)
        days_since_sunday = (now.weekday() + 1) % 7
        week_start = (now - timedelta(days=days_since_sunday)).date()
        
        # Get all days in the week
        weekly_data = {"verifications": [], "week_start": week_start.isoformat(), "count": 0}
        
        for i in range(7):
            day_date = week_start + timedelta(days=i)
            day_result = await get_verification_by_date_service(day_date.isoformat(), str(current_user.id), supabase)
            weekly_data["verifications"].extend(day_result.get("verifications", []))
        
        weekly_data["count"] = len(weekly_data["verifications"])
        
        return weekly_data
    except Exception as e:
        print(f"Get weekly verifications error: {e}")
        raise HTTPException(status_code=400, detail=str(e))

# MARK: - Image Serving Endpoints

@router.get("/image/{verification_id}")
async def get_verification_image_url(
    verification_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get a signed URL for a verification image by verification ID - OPTIMIZED.
    """
    with MemoryMonitor("get_verification_image") as monitor:
        try:
            # OPTIMIZATION: Use selective columns instead of SELECT *
            verification = await supabase.table("habit_verifications").select(
                "id, habit_id, user_id, image_filename"
            ).eq("id", verification_id).execute()
            
            if not verification.data:
                raise HTTPException(status_code=404, detail="Verification not found")
            
            verification_data = verification.data[0]
            habit_id = verification_data["habit_id"]
            image_filename = verification_data.get("image_filename")
            
            monitor.checkpoint("verification_data_loaded")
            
            # If no filename, try to construct from legacy data
            if not image_filename:
                user_id = verification_data["user_id"]
                image_filename = f"{user_id}_{verification_id}.jpg"
            
            # OPTIMIZATION: Get only the privacy field we need
            habit = await supabase.table("habits").select("private").eq("id", habit_id).execute()
            if not habit.data:
                raise HTTPException(status_code=404, detail="Habit not found")
            
            is_private = habit.data[0]["private"]
            
            monitor.checkpoint("privacy_checked")
            
            # Generate signed URL using helper function
            signed_url = await generate_verification_image_url(supabase, image_filename, is_private)
            
            if not signed_url:
                raise HTTPException(status_code=404, detail="Image not found in storage")
            
            cleanup_memory(verification, habit)
            monitor.checkpoint("url_generated")
            
            return {"image_url": signed_url}
                
        except HTTPException:
            raise
        except Exception as e:
            print(f"Error getting verification image URL: {e}")
            raise HTTPException(status_code=500, detail="Failed to get verification image URL")

@router.get("/image/habit/{habit_id}/today")
async def get_todays_verification_image_url(
    habit_id: str,
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get today's verification image URL for a specific habit - OPTIMIZED.
    """
    with MemoryMonitor("get_todays_verification_image") as monitor:
        try:
            # OPTIMIZATION: Get only the user_id we need
            habit = await supabase.table("habits").select("user_id, private").eq("id", habit_id).execute()
            if not habit.data:
                raise HTTPException(status_code=404, detail="Habit not found")
            
            user_id = habit.data[0]["user_id"]
            is_private = habit.data[0]["private"]
            
            monitor.checkpoint("habit_data_loaded")
            
            # Get today's date in user's timezone
            timezone = await get_user_timezone(supabase, user_id)
            tz = pytz.timezone(timezone)
            now = datetime.now(tz)
            today = now.date()
            
            # Get start and end of day in user's timezone
            start_of_day = tz.localize(datetime.combine(today, datetime.min.time()))
            end_of_day = tz.localize(datetime.combine(today, datetime.max.time()))
            
            monitor.checkpoint("timezone_calculated")
            
            # OPTIMIZATION: Use selective columns for today's verification
            verification = await supabase.table("habit_verifications").select(
                "id, image_filename"
            ).eq("habit_id", habit_id).gte("verified_at", start_of_day.isoformat()).lte(
                "verified_at", end_of_day.isoformat()
            ).order("verified_at", desc=True).limit(1).execute()
            
            if not verification.data:
                raise HTTPException(status_code=404, detail="No verification found for today")
            
            verification_data = verification.data[0]
            verification_id = verification_data["id"]
            image_filename = verification_data.get("image_filename")
            
            monitor.checkpoint("verification_found")
            
            # If no filename, construct from legacy data
            if not image_filename:
                image_filename = f"{user_id}_{verification_id}.jpg"
            
            # Generate signed URL using helper function
            signed_url = await generate_verification_image_url(supabase, image_filename, is_private)
            
            if not signed_url:
                raise HTTPException(status_code=404, detail="Image not found in storage")
            
            cleanup_memory(habit, verification)
            monitor.checkpoint("url_generated")
            
            return {"image_url": signed_url}
            
        except HTTPException:
            raise
        except Exception as e:
            print(f"Error getting today's verification image URL: {e}")
            raise HTTPException(status_code=500, detail="Failed to get today's verification image URL") 