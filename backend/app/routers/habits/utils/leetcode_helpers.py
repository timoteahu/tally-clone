from supabase._async.client import AsyncClient
from typing import Optional, Dict, Any, Tuple
from datetime import datetime, date, timedelta
from utils.timezone_utils import get_user_timezone
from utils.leetcode_api import LeetCodeAPI
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
import pytz
import logging

logger = logging.getLogger(__name__)

@memory_optimized(cleanup_args=False)
@memory_profile("get_leetcode_username_for_user")
async def get_leetcode_username_for_user(
    supabase: AsyncClient, 
    user_id: str
) -> Optional[str]:
    """
    Get LeetCode username for a user.
    Memory optimized helper for frequent username lookups.
    
    Args:
        supabase: Database client
        user_id: User ID
        
    Returns:
        LeetCode username or None if not connected
    """
    try:
        result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .execute()
        
        if result.data and result.data[0].get("leetcode_username"):
            return result.data[0]["leetcode_username"]
        
        return None
        
    except Exception as e:
        logger.error(f"Error getting LeetCode username for user {user_id}: {e}")
        return None

@memory_optimized(cleanup_args=False)
@memory_profile("validate_leetcode_connection")
async def validate_leetcode_connection(
    supabase: AsyncClient, 
    user_id: str
) -> str:
    """
    Validate LeetCode connection and return username.
    Raises HTTPException if not connected.
    
    Args:
        supabase: Database client
        user_id: User ID
        
    Returns:
        LeetCode username
        
    Raises:
        HTTPException: If LeetCode not connected
    """
    from fastapi import HTTPException
    
    username = await get_leetcode_username_for_user(supabase, user_id)
    if not username:
        raise HTTPException(status_code=404, detail="LeetCode account not connected")
    
    return username

@memory_optimized(cleanup_args=False)
@memory_profile("calculate_week_boundaries")
async def calculate_week_boundaries(
    supabase: AsyncClient,
    user_id: str,
    week_start_day: int = 0
) -> Tuple[date, date, str]:
    """
    Calculate week start and end dates in user's timezone.
    Memory optimized for frequent week calculations.
    
    Args:
        supabase: Database client
        user_id: User ID
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
        
    Returns:
        Tuple of (week_start_date, week_end_date, user_timezone)
    """
    try:
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        now = datetime.now(user_tz)
        
        # Calculate week boundaries
        # Convert week_start_day to match Python's weekday() where Monday=0, Sunday=6
        # But our week_start_day uses Sunday=0, Monday=1, etc.
        current_weekday = (now.weekday() + 1) % 7  # Convert to Sunday=0 format
        days_since_week_start = (current_weekday - week_start_day) % 7
        
        week_start = now.date() - timedelta(days=days_since_week_start)
        week_end = week_start + timedelta(days=6)
        
        return week_start, week_end, user_timezone
        
    except Exception as e:
        logger.error(f"Error calculating week boundaries for user {user_id}: {e}")
        # Fallback to current date
        return now.date(), now.date() + timedelta(days=6), "UTC"

@memory_optimized(cleanup_args=False)
@memory_profile("get_weekly_problems_solved")
async def get_weekly_problems_solved(
    username: str,
    week_start: date,
    week_end: date,
    user_timezone: str = "UTC"
) -> int:
    """
    Get the total number of unique problems solved in a week.
    Memory optimized for frequent weekly calculations.
    
    Args:
        username: LeetCode username
        week_start: Start date of the week
        week_end: End date of the week
        user_timezone: User's timezone for accurate date calculations
        
    Returns:
        Total number of unique problems solved in the week
    """
    try:
        # Get user's current date in their timezone
        user_tz = pytz.timezone(user_timezone)
        today_in_user_tz = datetime.now(user_tz).date()
        
        # Sum up problems solved for each day in the week
        total_problems = 0
        current_date = week_start
        
        while current_date <= week_end and current_date <= today_in_user_tz:
            daily_problems = await LeetCodeAPI.get_daily_problems_solved(username, current_date)
            if daily_problems is not None:
                total_problems += daily_problems
            current_date += timedelta(days=1)
        
        return total_problems
        
    except Exception as e:
        logger.error(f"Error getting weekly problems solved for {username}: {e}")
        return 0

@memory_optimized(cleanup_args=False)
@memory_profile("format_leetcode_response")
def format_leetcode_response(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Format LeetCode response data with consistent structure.
    Memory optimized response formatter.
    
    Args:
        data: Raw response data
        
    Returns:
        Formatted response data
    """
    try:
        # Ensure consistent timestamp format
        if "timestamp" not in data:
            data["timestamp"] = datetime.utcnow().isoformat()
        
        # Ensure service identifier
        data["service"] = "leetcode"
        
        return data
        
    except Exception as e:
        logger.error(f"Error formatting LeetCode response: {e}")
        return {
            "service": "leetcode",
            "timestamp": datetime.utcnow().isoformat(),
            "error": "Failed to format response",
            **data
        }

@memory_optimized(cleanup_args=False)
@memory_profile("get_leetcode_habit_context")
async def get_leetcode_habit_context(
    supabase: AsyncClient,
    user_id: str,
    habit_type: str = "daily"
) -> Dict[str, Any]:
    """
    Get contextual information about user's LeetCode habits.
    Memory optimized context builder.
    
    Args:
        supabase: Database client
        user_id: User ID
        habit_type: Type of habit context (daily/weekly)
        
    Returns:
        Dict with habit context information
    """
    try:
        # Get active LeetCode habits
        habits_result = await supabase.table("habits") \
            .select("id, name, commit_target, habit_schedule_type, week_start_day") \
            .eq("user_id", user_id) \
            .eq("habit_type", "leetcode") \
            .eq("is_active", True) \
            .execute()
        
        if habit_type == "weekly":
            weekly_habits = [h for h in habits_result.data if h.get("habit_schedule_type") == "weekly"]
            return {
                "has_weekly_habits": len(weekly_habits) > 0,
                "weekly_habits": weekly_habits,
                "total_weekly_goal": sum(h.get("commit_target", 3) for h in weekly_habits)
            }
        else:
            daily_habits = [h for h in habits_result.data if h.get("habit_schedule_type") == "daily"]
            return {
                "has_daily_habits": len(daily_habits) > 0,
                "daily_habits": daily_habits,
                "total_daily_goal": sum(h.get("commit_target", 1) for h in daily_habits)
            }
        
    except Exception as e:
        logger.error(f"Error getting LeetCode habit context for user {user_id}: {e}")
        return {
            "has_weekly_habits": False,
            "has_daily_habits": False,
            "weekly_habits": [],
            "daily_habits": [],
            "total_weekly_goal": 0,
            "total_daily_goal": 0
        }

@memory_optimized(cleanup_args=False)
@memory_profile("validate_leetcode_habit_data")
def validate_leetcode_habit_data(habit_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and sanitize LeetCode habit data.
    Memory optimized data validator.
    
    Args:
        habit_data: Raw habit data
        
    Returns:
        Validated and sanitized habit data
    """
    try:
        validated_data = habit_data.copy()
        
        # Ensure commit_target is set for LeetCode habits
        if "commit_target" not in validated_data or validated_data["commit_target"] is None:
            if validated_data.get("habit_schedule_type") == "weekly":
                validated_data["commit_target"] = 3  # Default weekly goal
            else:
                validated_data["commit_target"] = 1  # Default daily goal
        
        # Ensure positive values
        if validated_data.get("commit_target", 0) <= 0:
            validated_data["commit_target"] = 1
        
        # Validate week_start_day for weekly habits
        if validated_data.get("habit_schedule_type") == "weekly":
            week_start_day = validated_data.get("week_start_day", 0)
            if not isinstance(week_start_day, int) or week_start_day < 0 or week_start_day > 6:
                validated_data["week_start_day"] = 0  # Default to Sunday
        
        return validated_data
        
    except Exception as e:
        logger.error(f"Error validating LeetCode habit data: {e}")
        return habit_data  # Return original data if validation fails

@memory_optimized(cleanup_args=False)
@memory_profile("calculate_leetcode_streak")
async def calculate_leetcode_streak(
    supabase: AsyncClient,
    user_id: str,
    habit_id: str
) -> int:
    """
    Calculate current streak for a LeetCode habit.
    Memory optimized streak calculator.
    
    Args:
        supabase: Database client
        user_id: User ID
        habit_id: Habit ID
        
    Returns:
        Current streak count
    """
    try:
        # Get habit details
        habit_result = await supabase.table("habits") \
            .select("habit_schedule_type, commit_target, week_start_day") \
            .eq("id", habit_id) \
            .eq("user_id", user_id) \
            .execute()
        
        if not habit_result.data:
            return 0
        
        habit = habit_result.data[0]
        
        # Get LeetCode username
        username = await get_leetcode_username_for_user(supabase, user_id)
        if not username:
            return 0
        
        # Calculate streak based on habit type
        if habit.get("habit_schedule_type") == "weekly":
            # For weekly habits, check consecutive weeks
            return await _calculate_weekly_streak(
                username, habit["commit_target"], habit.get("week_start_day", 0), user_id, supabase
            )
        else:
            # For daily habits, check consecutive days
            return await _calculate_daily_streak(
                username, habit["commit_target"], user_id, supabase
            )
        
    except Exception as e:
        logger.error(f"Error calculating LeetCode streak for habit {habit_id}: {e}")
        return 0

async def _calculate_weekly_streak(
    username: str, 
    weekly_target: int, 
    week_start_day: int, 
    user_id: str, 
    supabase: AsyncClient
) -> int:
    """Calculate weekly streak for LeetCode habits."""
    try:
        streak = 0
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        now = datetime.now(user_tz)
        
        # Start from current week and go backwards
        current_date = now.date()
        
        for week_offset in range(52):  # Check up to 52 weeks back
            # Calculate week boundaries for this week
            current_weekday = (current_date.weekday() + 1) % 7
            days_since_week_start = (current_weekday - week_start_day) % 7
            week_start = current_date - timedelta(days=days_since_week_start + (week_offset * 7))
            week_end = week_start + timedelta(days=6)
            
            # Get problems solved this week
            problems_solved = await get_weekly_problems_solved(username, week_start, week_end, user_timezone)
            
            if problems_solved >= weekly_target:
                streak += 1
            else:
                break  # Streak broken
        
        return streak
        
    except Exception as e:
        logger.error(f"Error calculating weekly streak: {e}")
        return 0

async def _calculate_daily_streak(
    username: str, 
    daily_target: int, 
    user_id: str, 
    supabase: AsyncClient
) -> int:
    """Calculate daily streak for LeetCode habits."""
    try:
        streak = 0
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        now = datetime.now(user_tz)
        
        # Start from today and go backwards
        current_date = now.date()
        
        for day_offset in range(365):  # Check up to 365 days back
            check_date = current_date - timedelta(days=day_offset)
            
            # Get problems solved on this date
            problems_solved = await LeetCodeAPI.get_daily_problems_solved(username, check_date)
            
            if problems_solved is not None and problems_solved >= daily_target:
                streak += 1
            else:
                break  # Streak broken
        
        return streak
        
    except Exception as e:
        logger.error(f"Error calculating daily streak: {e}")
        return 0 