from fastapi import HTTPException
from models.schemas import User
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
import logging

logger = logging.getLogger(__name__)

@memory_optimized(cleanup_args=False)
@memory_profile("get_staged_deletion_service")
async def get_staged_deletion_service(
    habit_id: str,
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """Check if a habit has a pending deletion scheduled"""
    try:
        # First verify the habit belongs to the user
        habit_result = await supabase.table("habits").select("user_id").eq("id", habit_id).eq("is_active", True).execute()
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        if str(current_user.id).lower() != habit_result.data[0]['user_id'].lower():
            raise HTTPException(status_code=403, detail="Cannot access another user's habit")
        
        # Check for staged deletion
        staging_result = await supabase.table("habit_change_staging") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .eq("change_type", "delete") \
            .eq("applied", False) \
            .execute()
        
        if staging_result.data:
            staged_deletion = staging_result.data[0]
            return {
                "scheduled_for_deletion": True,
                "effective_date": staged_deletion["effective_date"],
                "user_timezone": staged_deletion["user_timezone"],
                "staging_id": staged_deletion["id"],
                "created_at": staged_deletion["created_at"]
            }
        else:
            return {
                "scheduled_for_deletion": False
            }
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error checking staged deletion for habit {habit_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to check deletion status")

@memory_optimized(cleanup_args=False)
@memory_profile("restore_habit_service")
async def restore_habit_service(
    habit_id: str,
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """Restore a habit that is scheduled for deletion"""
    try:
        # First verify the habit belongs to the user
        habit_result = await supabase.table("habits").select("user_id").eq("id", habit_id).eq("is_active", True).execute()
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        if str(current_user.id).lower() != habit_result.data[0]['user_id'].lower():
            raise HTTPException(status_code=403, detail="Cannot restore another user's habit")
        
        # Check for staged deletion
        staging_result = await supabase.table("habit_change_staging") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .eq("change_type", "delete") \
            .eq("applied", False) \
            .execute()
        
        if not staging_result.data:
            raise HTTPException(status_code=404, detail="No pending deletion found for this habit")
        
        # Delete the staging record to cancel the deletion
        staging_id = staging_result.data[0]["id"]
        await supabase.table("habit_change_staging") \
            .delete() \
            .eq("id", staging_id) \
            .execute()
        
        return {
            "message": "Habit deletion has been cancelled successfully",
            "habit_id": habit_id,
            "restored": True
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error restoring habit {habit_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to restore habit") 