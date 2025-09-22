from fastapi import HTTPException
from models.schemas import User, WeeklyHabitProgress
from supabase._async.client import AsyncClient
from typing import List, Optional
from utils.weekly_habits import get_weekly_progress_summary
from datetime import datetime
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
import logging

logger = logging.getLogger(__name__)

@memory_optimized(cleanup_args=False)
@memory_profile("get_user_weekly_progress_service")
async def get_user_weekly_progress_service(
    user_id: str,
    week_start_date: Optional[str] = None,
    current_user: User = None,
    supabase: AsyncClient = None
) -> List[WeeklyHabitProgress]:
    """
    Get weekly progress for all weekly habits for a user.
    
    Args:
        user_id: User ID to get progress for
        week_start_date: Optional week start date (YYYY-MM-DD), defaults to current week
        
    Returns:
        List of weekly progress records with habit details
    """
    try:
        # Validate that the user can only access their own progress
        if str(current_user.id).lower() != user_id.lower():
            raise HTTPException(status_code=403, detail="Cannot access another user's weekly progress")
        
        # Parse week_start_date if provided
        target_week_start = None
        if week_start_date:
            try:
                target_week_start = datetime.strptime(week_start_date, "%Y-%m-%d").date()
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
        
        # Get weekly progress summary
        progress_data = await get_weekly_progress_summary(supabase, user_id, target_week_start)
        
        return progress_data
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting weekly progress for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve weekly progress")

@memory_optimized(cleanup_args=False)
@memory_profile("get_habit_weekly_progress_service")
async def get_habit_weekly_progress_service(
    habit_id: str,
    current_user: User,
    supabase: AsyncClient
) -> List[WeeklyHabitProgress]:
    """
    Get all weekly progress records for a specific habit.
    
    Args:
        habit_id: Habit ID to get progress for
        
    Returns:
        List of weekly progress records for the habit
    """
    try:
        # OPTIMIZATION: Use selective column fetching for habit validation
        habit_result = await supabase.table("habits").select("user_id, habit_schedule_type").eq("id", habit_id).eq("is_active", True).execute()
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        habit = habit_result.data[0]
        
        # Validate that the user owns this habit
        if str(current_user.id).lower() != habit['user_id'].lower():
            raise HTTPException(status_code=403, detail="Cannot access another user's habit progress")
        
        # Verify this is a weekly habit
        if habit.get('habit_schedule_type') != 'weekly':
            raise HTTPException(status_code=400, detail="This endpoint is only for weekly habits")
        
        # Get all weekly progress records for this habit
        progress_result = await supabase.table("weekly_habit_progress") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .order("week_start_date", desc=True)
        
        return progress_result.data
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting weekly progress for habit {habit_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve habit weekly progress")

@memory_optimized(cleanup_args=False)
@memory_profile("fix_weekly_habit_targets_service")
async def fix_weekly_habit_targets_service(
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """
    OPTIMIZED: Fix weekly habit progress records that have incorrect target_completions.
    This updates them to match the habit's actual weekly_target using batch operations.
    """
    try:
        user_id = str(current_user.id)
        
        # OPTIMIZATION: Get all weekly habits with only needed columns
        habits_result = await supabase.table("habits") \
            .select("id, weekly_target") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("is_active", True).execute()
        
        if not habits_result.data:
            return {"message": "No weekly habits found", "fixed_count": 0}
        
        # OPTIMIZATION: Batch fetch all progress records at once
        habit_ids = [habit['id'] for habit in habits_result.data]
        progress_result = await supabase.table("weekly_habit_progress") \
            .select("id, habit_id, target_completions, current_completions") \
            .in_("habit_id", habit_ids).execute()
        
        # Create lookup for habit targets
        habit_targets = {habit['id']: habit['weekly_target'] for habit in habits_result.data}
        
        # OPTIMIZATION: Collect all updates for batch processing
        updates_to_make = []
        
        for progress in progress_result.data:
            habit_id = progress['habit_id']
            correct_target = habit_targets.get(habit_id)
            
            if correct_target and progress['target_completions'] != correct_target:
                # Calculate new completion status
                new_is_complete = progress['current_completions'] >= correct_target
                
                updates_to_make.append({
                    "id": progress['id'],
                    "target_completions": correct_target,
                    "is_week_complete": new_is_complete
                })
        
        fixed_count = 0
        
        # OPTIMIZATION: Process updates in batches to avoid overwhelming the database
        batch_size = 50
        for i in range(0, len(updates_to_make), batch_size):
            batch = updates_to_make[i:i + batch_size]
            
            # Use upsert for batch updating
            try:
                await supabase.table("weekly_habit_progress").upsert(batch).execute()
                fixed_count += len(batch)
                logger.info(f"Fixed batch of {len(batch)} weekly progress records")
            except Exception as e:
                logger.error(f"Error updating batch {i//batch_size + 1}: {e}")
                # Continue with next batch even if one fails
        
        return {
            "message": f"Fixed {fixed_count} weekly progress records in {len(updates_to_make)//batch_size + 1} batches",
            "fixed_count": fixed_count,
            "total_habits_checked": len(habits_result.data),
            "total_progress_records": len(progress_result.data)
        }
        
    except Exception as e:
        logger.error(f"Error fixing weekly targets: {e}")
        raise HTTPException(status_code=500, detail=str(e)) 