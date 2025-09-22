from typing import Optional, Dict, Any
from fastapi import HTTPException
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory, memory_optimized
from utils.memory_monitoring import MemoryMonitor, memory_profile
from ..utils import generate_verification_image_urls

# OPTIMIZATION: Define common verification columns to avoid SELECT *
VERIFICATION_COLUMNS = "id, habit_id, user_id, verification_type, verified_at, status, verification_result, image_filename, selfie_image_filename"
HABIT_PRIVACY_COLUMNS = "private, name"

@memory_optimized(cleanup_args=False)
@memory_profile("get_latest_verification")
async def get_latest_verification_service(habit_id: str, supabase: AsyncClient) -> Dict[str, Any]:
    """Get the latest verification for a habit - OPTIMIZED"""
    with MemoryMonitor("get_latest_verification") as monitor:
        try:
            # OPTIMIZATION: Use selective columns instead of SELECT *
            verification = await supabase.table("habit_verifications").select(
                VERIFICATION_COLUMNS
            ).eq("habit_id", habit_id).order("verified_at", desc=True).limit(1).execute()
            
            if not verification.data:
                raise HTTPException(status_code=404, detail="No verifications found for this habit")
            
            verification_data = verification.data[0]
            monitor.checkpoint("verification_data_loaded")
            
            # OPTIMIZATION: Get only the privacy field we need
            habit = await supabase.table("habits").select("private").eq("id", verification_data["habit_id"]).execute()
            is_private = habit.data[0]["private"] if habit.data else False
            
            monitor.checkpoint("habit_privacy_checked")
            
            # Generate URLs for both selfie and content images
            image_urls = await generate_verification_image_urls(supabase, verification_data, is_private)
            verification_data.update(image_urls)
            
            # Keep backward compatibility - use content image as main image_url
            if "content_image_url" in image_urls and image_urls["content_image_url"]:
                verification_data["image_url"] = image_urls["content_image_url"]
            
            # Clean up the temporary image_urls dict - we've already copied its contents
            cleanup_memory(image_urls)
            
            # Ensure all expected fields are present for iOS compatibility
            # Only set defaults for fields that are actually missing
            if "id" not in verification_data:
                verification_data["id"] = None
            if "habit_id" not in verification_data:
                verification_data["habit_id"] = habit_id
            if "user_id" not in verification_data:
                verification_data["user_id"] = None
            if "verification_type" not in verification_data:
                verification_data["verification_type"] = None
            if "verified_at" not in verification_data:
                verification_data["verified_at"] = None
            if "status" not in verification_data:
                verification_data["status"] = None
            if "verification_result" not in verification_data:
                verification_data["verification_result"] = None
            
            # These fields might not exist in the DB
            verification_data.setdefault("image_verification_id", None)
            verification_data.setdefault("image_filename", None)
            verification_data.setdefault("selfie_image_filename", None)
            verification_data.setdefault("image_url", None)
            verification_data.setdefault("selfie_image_url", None)
            
            # Ensure verification_result is a boolean (iOS expects Bool?)
            if "verification_result" in verification_data:
                # Convert string "true"/"false" to boolean if needed
                result = verification_data["verification_result"]
                if isinstance(result, str):
                    verification_data["verification_result"] = result.lower() == "true"
                elif result is None:
                    verification_data["verification_result"] = None
                else:
                    verification_data["verification_result"] = bool(result)
            
            monitor.checkpoint("image_urls_generated")
            cleanup_memory(verification, habit)
            
            return verification_data
        except HTTPException:
            raise
        except Exception as e:
            print(f"Error getting latest verification: {e}")
            raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("get_verifications_by_habit")
async def get_verifications_by_habit_service(habit_id: str, supabase: AsyncClient) -> Dict[str, Any]:
    """Get all verifications for a specific habit - OPTIMIZED"""
    with MemoryMonitor("get_habit_verifications") as monitor:
        try:
            # OPTIMIZATION: Use selective columns instead of SELECT *
            verifications = await supabase.table("habit_verifications").select(
                VERIFICATION_COLUMNS
            ).eq("habit_id", habit_id).order("verified_at", desc=True).execute()
            
            if not verifications.data:
                return {"verifications": [], "count": 0}
            
            monitor.checkpoint("verifications_loaded")
            
            # OPTIMIZATION: Get only the privacy field we need
            habit = await supabase.table("habits").select("private").eq("id", habit_id).execute()
            is_private = habit.data[0]["private"] if habit.data else False
            
            monitor.checkpoint("habit_privacy_checked")
            
            # Process each verification with image URLs
            processed_verifications = []
            for verification_data in verifications.data:
                # Generate URLs for both selfie and content images
                image_urls = await generate_verification_image_urls(supabase, verification_data, is_private)
                verification_data.update(image_urls)
                
                # Keep backward compatibility
                if "content_image_url" in image_urls and image_urls["content_image_url"]:
                    verification_data["image_url"] = image_urls["content_image_url"]
                
                # Clean up the temporary image_urls dict
                cleanup_memory(image_urls)
                
                processed_verifications.append(verification_data)
            
            monitor.checkpoint("image_urls_generated")
            cleanup_memory(verifications, habit)
            
            return {
                "verifications": processed_verifications,
                "count": len(processed_verifications)
            }
        except Exception as e:
            print(f"Error getting habit verifications: {e}")
            raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("get_verification_by_date")
async def get_verification_by_date_service(date: str, user_id: str, supabase: AsyncClient) -> Dict[str, Any]:
    """Get all verifications for a user on a specific date - OPTIMIZED"""
    with MemoryMonitor("get_verifications_by_date") as monitor:
        try:
            # Parse date and create date range
            from datetime import datetime, timedelta
            target_date = datetime.fromisoformat(date).date()
            start_datetime = datetime.combine(target_date, datetime.min.time())
            end_datetime = datetime.combine(target_date, datetime.max.time())
            
            monitor.checkpoint("date_range_calculated")
            
            # OPTIMIZATION: Use selective columns in the join instead of SELECT *
            verifications = await supabase.table("habit_verifications").select(
                f"{VERIFICATION_COLUMNS}, habits!inner({HABIT_PRIVACY_COLUMNS})"
            ).eq("user_id", user_id).gte("verified_at", start_datetime.isoformat()).lte("verified_at", end_datetime.isoformat()).order("verified_at", desc=True).execute()
            
            if not verifications.data:
                return {"verifications": [], "date": date, "count": 0}
            
            monitor.checkpoint("verifications_loaded")
            
            # Process each verification with image URLs
            processed_verifications = []
            for verification_data in verifications.data:
                is_private = verification_data["habits"]["private"]
                habit_name = verification_data["habits"]["name"]
                
                # Remove joined data
                verification_data.pop("habits", None)
                verification_data["habit_name"] = habit_name
                
                # Generate URLs for both selfie and content images
                image_urls = await generate_verification_image_urls(supabase, verification_data, is_private)
                verification_data.update(image_urls)
                
                # Keep backward compatibility
                if "content_image_url" in image_urls and image_urls["content_image_url"]:
                    verification_data["image_url"] = image_urls["content_image_url"]
                
                # Clean up the temporary image_urls dict
                cleanup_memory(image_urls)
                
                processed_verifications.append(verification_data)
            
            monitor.checkpoint("image_urls_generated")
            cleanup_memory(verifications)
            
            return {
                "verifications": processed_verifications,
                "date": date,
                "count": len(processed_verifications)
            }
        except Exception as e:
            print(f"Error getting verifications by date: {e}")
            raise HTTPException(status_code=400, detail=str(e))

# OPTIMIZATION: Add batch verification retrieval for better performance
@memory_optimized(cleanup_args=False)
@memory_profile("get_verifications_batch")
async def get_verifications_batch_service(habit_ids: list, supabase: AsyncClient) -> Dict[str, Any]:
    """Get latest verifications for multiple habits in a single query - NEW OPTIMIZATION"""
    with MemoryMonitor("get_verifications_batch") as monitor:
        try:
            if not habit_ids:
                return {"verifications": {}, "count": 0}
            
            # OPTIMIZATION: Batch fetch verifications for multiple habits
            verifications = await supabase.table("habit_verifications").select(
                VERIFICATION_COLUMNS
            ).in_("habit_id", habit_ids).order("verified_at", desc=True).execute()
            
            if not verifications.data:
                return {"verifications": {}, "count": 0}
            
            monitor.checkpoint("verifications_loaded")
            
            # OPTIMIZATION: Batch fetch habit privacy settings
            habits = await supabase.table("habits").select("id, private").in_("id", habit_ids).execute()
            privacy_map = {h["id"]: h["private"] for h in habits.data} if habits.data else {}
            
            monitor.checkpoint("privacy_data_loaded")
            
            # Group verifications by habit_id and keep only the latest for each
            latest_verifications = {}
            for verification_data in verifications.data:
                habit_id = verification_data["habit_id"]
                
                # Keep only the latest verification per habit (data is already ordered by verified_at desc)
                if habit_id not in latest_verifications:
                    is_private = privacy_map.get(habit_id, False)
                    
                    # Generate URLs
                    image_urls = await generate_verification_image_urls(supabase, verification_data, is_private)
                    verification_data.update(image_urls)
                    
                    if "content_image_url" in image_urls and image_urls["content_image_url"]:
                        verification_data["image_url"] = image_urls["content_image_url"]
                    
                    cleanup_memory(image_urls)
                    latest_verifications[habit_id] = verification_data
            
            monitor.checkpoint("batch_processing_complete")
            cleanup_memory(verifications, habits)
            
            return {
                "verifications": latest_verifications,
                "count": len(latest_verifications)
            }
            
        except Exception as e:
            print(f"Error getting batch verifications: {e}")
            raise HTTPException(status_code=400, detail=str(e)) 