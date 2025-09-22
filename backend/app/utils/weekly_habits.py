from datetime import date, timedelta
from typing import Optional, Tuple
from supabase._async.client import AsyncClient
from models.schemas import WeeklyHabitProgress, WeeklyHabitProgressCreate
import logging
import pytz
from datetime import datetime

logger = logging.getLogger(__name__)

def get_week_dates(target_date: date, week_start_day: int = 0) -> Tuple[date, date]:
    """
    Get start and end dates for the week containing the given date.
    
    Args:
        target_date: The date to find the week for
        week_start_day: Day week starts on (0=Sunday, 1=Monday, etc.)
    
    Returns:
        Tuple of (week_start_date, week_end_date)
    """
    # Calculate days since the configured week start day
    # weekday() returns 0 for Monday, 1 for Tuesday, etc.
    # We need to convert to 0=Sunday, 1=Monday format
    current_weekday = (target_date.weekday() + 1) % 7  # Convert to Sunday=0 format
    days_since_week_start = (current_weekday - week_start_day) % 7
    
    week_start = target_date - timedelta(days=days_since_week_start)
    week_end = week_start + timedelta(days=6)
    
    return week_start, week_end

def calculate_first_week_target(weekly_target: int, habit_creation_date: date, week_start_day: int = 0) -> int:
    """
    Calculate target for partial first week using the formula:
    max(1, floor(weekly_target * days_remaining / 7))
    
    Days remaining excludes the creation day itself, as users typically
    create habits in the evening and can't complete them the same day.
    
    Args:
        weekly_target: The full weekly target
        habit_creation_date: When the habit was created
        week_start_day: Day week starts on (0=Sunday, 1=Monday)
    
    Returns:
        Target for the first (potentially partial) week
    """
    week_start, week_end = get_week_dates(habit_creation_date, week_start_day)
    
    # Days remaining in first week (excluding creation day)
    # If created Thursday night, only count Fri, Sat, Sun as available days
    days_remaining = (week_end - habit_creation_date).days
    
    # If no days remaining (created on last day of week), ensure minimum of 1
    if days_remaining == 0:
        return 1
    
    # Apply the formula: max(1, floor(weekly_target * days_remaining / 7))
    first_week_target = max(1, int(weekly_target * days_remaining / 7))
    
    return first_week_target

async def initialize_weekly_progress(supabase: AsyncClient, habit: dict) -> dict:
    """
    Initialize weekly progress for a new weekly habit.
    
    Args:
        supabase: Async Supabase client
        habit: Habit dictionary containing habit data
    
    Returns:
        Created weekly progress record
    """
    
    creation_date = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00')).date()
    week_start, _ = get_week_dates(creation_date, habit.get('week_start_day', 0))
    
    # Always use the full weekly target for consistency and better UX
    # Users expect their weekly goals to be the same regardless of when they start
    target = habit['weekly_target']
    
    # Ensure UUIDs are serialized as strings before inserting into Supabase
    progress_data = {
        "habit_id": str(habit['id']),
        "user_id": str(habit['user_id']),
        "week_start_date": week_start.isoformat(),
        "current_completions": 0,
        "target_completions": target,
        "is_week_complete": False
    }
    
    try:
        result = await supabase.table("weekly_habit_progress").insert(progress_data).execute()
        logger.info(f"Initialized weekly progress for habit {habit['id']} with target {target}")
        return result.data[0]
    except Exception as e:
        logger.error(f"Failed to initialize weekly progress for habit {habit['id']}: {e}")
        raise

async def get_or_create_weekly_progress(supabase: AsyncClient, habit_id: str, user_id: str, verification_date: date, weekly_target: int, week_start_day: int = 0) -> dict:
    """
    Get existing weekly progress or create new one for subsequent weeks.
    
    Args:
        supabase: Supabase client (sync or async)
        habit_id: Habit ID
        user_id: User ID
        verification_date: Date of verification
        weekly_target: Weekly target for this habit
        week_start_day: Day week starts on
    
    Returns:
        Weekly progress record
    """
    week_start, _ = get_week_dates(verification_date, week_start_day)
    
    # Determine if we are using the async or sync client
    is_async_client = isinstance(supabase, AsyncClient)
    
    try:
        # --- Try fetching existing progress for this week ---
        if is_async_client:
            result = await supabase.table("weekly_habit_progress") \
                .select("*") \
                .eq("habit_id", habit_id) \
                .eq("week_start_date", week_start.isoformat()) \
                .execute()
        else:
            result = supabase.table("weekly_habit_progress") \
                .select("*") \
                .eq("habit_id", habit_id) \
                .eq("week_start_date", week_start.isoformat()) \
                .execute()
        
        if result.data:
            return result.data[0]
        
        # --- Create new progress record if none exists ---
        progress_data = {
            "habit_id": habit_id,
            "user_id": user_id,
            "week_start_date": week_start.isoformat(),
            "current_completions": 0,
            "target_completions": weekly_target,  # Full week target for subsequent weeks
            "is_week_complete": False
        }
        
        if is_async_client:
            create_result = await supabase.table("weekly_habit_progress").insert(progress_data).execute()
        else:
            create_result = supabase.table("weekly_habit_progress").insert(progress_data).execute()
        
        logger.info(f"Created new weekly progress for habit {habit_id}, week {week_start}")
        return create_result.data[0]
        
    except Exception as e:
        logger.error(f"Failed to get/create weekly progress for habit {habit_id}: {e}")
        raise

async def update_weekly_progress(supabase: AsyncClient, habit_id: str, user_id: str, verification_date: date, weekly_target: int, week_start_day: int = 0) -> dict:
    """
    Update weekly progress after successful verification.
    
    Args:
        supabase: Supabase client (sync or async)
        habit_id: Habit ID
        user_id: User ID
        verification_date: Date of verification
        weekly_target: Weekly target for this habit
        week_start_day: Day week starts on
    
    Returns:
        Updated weekly progress record
    """
    is_async_client = isinstance(supabase, AsyncClient)
    
    # --- Check for multiple verifications today to avoid double-counting ---
    try:
        if is_async_client:
            today_verifications = await supabase.table("habit_verifications") \
                .select("id") \
                .eq("habit_id", habit_id) \
                .eq("user_id", user_id) \
                .gte("verified_at", verification_date.isoformat()) \
                .lt("verified_at", (verification_date + timedelta(days=1)).isoformat()) \
                .eq("status", "completed") \
                .execute()
        else:
            today_verifications = supabase.table("habit_verifications") \
                .select("id") \
                .eq("habit_id", habit_id) \
                .eq("user_id", user_id) \
                .gte("verified_at", verification_date.isoformat()) \
                .lt("verified_at", (verification_date + timedelta(days=1)).isoformat()) \
                .eq("status", "completed") \
                .execute()
    except Exception as tv_err:
        # If there's an error fetching verifications, log it but proceed (to avoid blocking user verification)
        logger.error(f"Failed to fetch today's verifications for habit {habit_id}: {tv_err}")
        today_verifications = type("obj", (object,), {"data": []})()  # empty fallback
    
    # Skip incrementing if there is already a completed verification today (only 1 allowed)
    if len(today_verifications.data) >= 1:
        logger.warning(f"Multiple verifications found for habit {habit_id} on {verification_date}, skipping progress update")
        return await get_or_create_weekly_progress(supabase, habit_id, user_id, verification_date, weekly_target, week_start_day)
    
    # --- Get or create the progress record for this week ---
    progress = await get_or_create_weekly_progress(supabase, habit_id, user_id, verification_date, weekly_target, week_start_day)
    new_completions = progress["current_completions"] + 1
    is_complete = new_completions >= progress["target_completions"]
    
    # --- Persist the updated values ---
    try:
        if is_async_client:
            update_result = await supabase.table("weekly_habit_progress") \
                .update({
                    "current_completions": new_completions,
                    "is_week_complete": is_complete,
                    "updated_at": verification_date.isoformat()
                }) \
                .eq("id", progress["id"]) \
                .execute()
        else:
            update_result = supabase.table("weekly_habit_progress") \
                .update({
                    "current_completions": new_completions,
                    "is_week_complete": is_complete,
                    "updated_at": verification_date.isoformat()
                }) \
                .eq("id", progress["id"]) \
                .execute()
        
        logger.info(f"Updated weekly progress for habit {habit_id}: {new_completions}/{progress['target_completions']}, complete: {is_complete}")
        return update_result.data[0]
        
    except Exception as e:
        logger.error(f"Failed to update weekly progress for habit {habit_id}: {e}")
        raise

async def get_weekly_progress_summary(supabase: AsyncClient, user_id: str, week_start_date: Optional[date] = None) -> list:
    """
    Get weekly progress summary for a user's habits.
    
    Args:
        supabase: Async Supabase client
        user_id: User ID
        week_start_date: Specific week to get (defaults to current week in user's timezone)
    
    Returns:
        List of weekly progress records with habit details
    """
    if week_start_date is None:
        # Use user's timezone to determine current week, not server time
        from utils.timezone_utils import get_user_timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        user_now = datetime.now(user_tz)
        today_user_tz = user_now.date()
        
        week_start_date = get_week_dates(today_user_tz)[0]
        logger.info(f"Weekly progress summary for user {user_id} in timezone {user_timezone}: "
                   f"today={today_user_tz}, week_start={week_start_date}")

    # Expand the range to cover the entire 7-day window so we capture habits that
    # use a custom `week_start_day` other than Sunday.
    week_end_date = week_start_date + timedelta(days=6)

    try:
        # Get weekly progress with habit details for any records whose week_start_date
        # falls inside the target calendar week.
        result = await supabase.table("weekly_habit_progress") \
            .select("""
                *,
                habit:habits(
                    id,
                    name,
                    habit_type,
                    weekly_target,
                    week_start_day
                )
            """) \
            .eq("user_id", user_id) \
            .gte("week_start_date", week_start_date.isoformat()) \
            .lte("week_start_date", week_end_date.isoformat()) \
            .execute()

        return result.data

    except Exception as e:
        logger.error(f"Failed to get weekly progress summary for user {user_id}: {e}")
        raise 