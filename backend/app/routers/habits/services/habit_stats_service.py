from fastapi import HTTPException
from models.schemas import User
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from utils.activity_tracking import track_user_activity
import logging

logger = logging.getLogger(__name__)

@memory_optimized(cleanup_args=False)
@memory_profile("get_user_habit_stats_service")
async def get_user_habit_stats_service(
    user_id: str,
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """
    Get basic habit statistics for any user (public information).
    This is used for profile views where users can see other users' basic stats.
    
    Args:
        user_id: ID of the user to get stats for
        
    Returns:
        Dict with basic habit statistics
    """
    try:
        # Track user activity when viewing user stats
        await track_user_activity(supabase, str(current_user.id))
        
        # Get all habits for the user and calculate stats manually
        habits_result = await supabase.table("habits") \
            .select("id, is_active, habit_schedule_type, completed_at, streak") \
            .eq("user_id", user_id) \
            .execute()
        
        if not habits_result.data:
            return {
                "user_id": user_id,
                "total_habits": 0,
                "completed_habits": 0,
                "total_streak": 0,
                "total_saved": 0.0
            }
        
        # Calculate stats from the data
        total_habits = sum(1 for h in habits_result.data if h.get('is_active', True))
        completed_one_time = sum(1 for h in habits_result.data 
                               if h.get('habit_schedule_type') == 'one_time' 
                               and h.get('completed_at') is not None)
        
        # Get max streak from active habits
        max_streak = 0
        for habit in habits_result.data:
            if habit.get('is_active', True) and habit.get('streak') is not None:
                max_streak = max(max_streak, habit.get('streak', 0))
        
        # Calculate estimated total saved (based on completed one-time habits)
        total_saved = float(completed_one_time * 5.0)  # Assuming $5 per completed habit
        
        return {
            "user_id": user_id,
            "total_habits": total_habits,
            "completed_habits": completed_one_time,
            "total_streak": max_streak,
            "total_saved": total_saved
        }
        
    except Exception as e:
        logger.error(f"Error getting habit stats for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e)) 