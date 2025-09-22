"""
Utility functions for LeetCode habit verification and tracking.
"""
import logging
from typing import Optional, Dict, Any
from datetime import datetime, date, timedelta
from supabase._async.client import AsyncClient
import pytz
from utils.leetcode_api import LeetCodeAPI
from utils.timezone_utils import get_user_timezone
from utils.weekly_habits import get_week_dates

logger = logging.getLogger(__name__)

async def get_leetcode_problems_solved(
    supabase: AsyncClient,
    user_id: str
) -> Optional[int]:
    """
    Get the total number of LeetCode problems solved by the user.
    """
    try:
        # Get LeetCode username
        result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            logger.error(f"No LeetCode account connected for user {user_id}")
            return None
        
        username = result.data[0]["leetcode_username"]
        
        # Get current total solved count
        stats = await LeetCodeAPI.get_user_stats(username)
        if not stats:
            logger.error(f"Failed to fetch LeetCode stats for {username}")
            return None
        
        # Calculate total solved problems
        current_total = 0
        if stats.get("submitStats") and stats["submitStats"].get("acSubmissionNum"):
            for submission in stats["submitStats"]["acSubmissionNum"]:
                current_total += submission.get("count", 0)
        
        return current_total
            
    except Exception as e:
        logger.error(f"Error getting LeetCode problems count: {e}")
        return None

async def get_current_week_leetcode_problems(
    supabase: AsyncClient,
    user_id: str,
    week_start_day: int = 0
) -> Optional[Dict[str, Any]]:
    """
    Get current week's LeetCode problems solved by summing daily counts.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
    
    Returns:
        Dict with count, goal, week dates, etc.
    """
    try:
        # Get LeetCode username
        result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            logger.error(f"No LeetCode account connected for user {user_id}")
            return None
        
        username = result.data[0]["leetcode_username"]
        
        # Get user's timezone for week calculations
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
        
        # Get problems solved this week by summing daily counts
        problems_this_week = await get_weekly_problems_solved(
            username, week_start, week_end, user_timezone
        )
        
        # Get current total solved count for stats
        stats = await LeetCodeAPI.get_user_stats(username)
        current_total = 0
        if stats and stats.get("submitStats") and stats["submitStats"].get("acSubmissionNum"):
            for submission in stats["submitStats"]["acSubmissionNum"]:
                if submission.get("difficulty") == "All":
                    current_total = submission.get("count", 0)
                    break
        
        # Get weekly LeetCode habit to show the goal
        habit_result = await supabase.table("habits") \
            .select("id, name, commit_target") \
            .eq("user_id", user_id) \
            .eq("habit_type", "leetcode") \
            .eq("habit_schedule_type", "weekly") \
            .eq("is_active", True) \
            .execute()
        
        goal = None
        habit_id = None
        if habit_result.data:
            # Use commit_target field for LeetCode problems target
            goal = habit_result.data[0].get("commit_target", 1)
            habit_id = habit_result.data[0].get("id")
        
        return {
            "count": problems_this_week,
            "goal": goal,
            "week_start_date": week_start.isoformat(),
            "week_end_date": week_end.isoformat(),
            "total_solved": current_total,
            "habit_id": habit_id,
            "user_timezone": user_timezone
        }
        
    except Exception as e:
        logger.error(f"Error getting current week LeetCode problems: {e}")
        return None

async def verify_leetcode_habit(
    supabase: AsyncClient,
    habit_id: str,
    user_id: str,
    target_date: Optional[date] = None
) -> Dict[str, Any]:
    """
    Verify a LeetCode habit for a specific date.
    
    Returns:
        Dict with verification status and details
    """
    try:
        # Get habit details
        habit_result = await supabase.table("habits") \
            .select("*") \
            .eq("id", habit_id) \
            .eq("user_id", user_id) \
            .single() \
            .execute()
        
        if not habit_result.data:
            return {
                "success": False,
                "error": "Habit not found"
            }
        
        habit = habit_result.data
        
        if habit.get("habit_type") != "leetcode":
            return {
                "success": False,
                "error": "Not a LeetCode habit"
            }
        
        # Use user's timezone if no target date specified
        if not target_date:
            user_timezone = await get_user_timezone(supabase, user_id)
            user_tz = pytz.timezone(user_timezone)
            target_date = datetime.now(user_tz).date()
        
        # Get problems solved based on schedule type
        if habit.get("habit_schedule_type") == "weekly":
            week_start_day = habit.get("week_start_day", 0)
            week_data = await get_current_week_leetcode_problems(supabase, user_id, week_start_day)
            
            if not week_data:
                return {
                    "success": False,
                    "error": "Failed to get weekly LeetCode data"
                }
            
            problems_solved = week_data["count"]
            target = habit["commit_target"]  # All LeetCode targets are stored in commit_target
            met = problems_solved >= target
            
            return {
                "success": True,
                "verified": met,
                "problems_solved": problems_solved,
                "target": target,
                "week_start_date": week_data["week_start_date"],
                "week_end_date": week_data["week_end_date"]
            }
        else:
            # Daily habit
            problems_today = await get_leetcode_problems_for_date(supabase, user_id, target_date)
            
            if problems_today is None:
                return {
                    "success": False,
                    "error": "Failed to get daily LeetCode data"
                }
            
            target = habit["commit_target"]  # All LeetCode targets are stored in commit_target
            met = problems_today >= target
            
            return {
                "success": True,
                "verified": met,
                "problems_solved": problems_today,
                "target": target,
                "date": target_date.isoformat()
            }
            
    except Exception as e:
        logger.error(f"Error verifying LeetCode habit: {e}")
        return {
            "success": False,
            "error": str(e)
        }

async def get_leetcode_problems_for_date(
    supabase: AsyncClient,
    user_id: str,
    target_date: date
) -> Optional[int]:
    """
    Get the number of unique LeetCode problems solved on a specific date.
    Always fetches fresh data from LeetCode API for live updates.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        target_date: Date to check problems for
        
    Returns:
        Number of unique problems solved on the date, or None if error
    """
    try:
        # Get LeetCode username
        result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            logger.error(f"No LeetCode account connected for user {user_id}")
            return None
        
        username = result.data[0]["leetcode_username"]
        
        # Always fetch fresh data from LeetCode API for live updates
        problems_solved = await LeetCodeAPI.get_daily_problems_solved(username, target_date)
        
        return problems_solved
        
    except Exception as e:
        logger.error(f"Error getting LeetCode problems for date: {e}")
        return None

async def get_weekly_problems_solved(
    username: str,
    week_start: date,
    week_end: date,
    user_timezone: str = "UTC"
) -> int:
    """
    Get the total number of unique problems solved in a week.
    
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
        logger.error(f"Error getting weekly problems solved: {e}")
        return 0

async def get_problems_solved_today(
    supabase: AsyncClient,
    user_id: str
) -> Optional[int]:
    """
    Get the number of problems solved today.
    Uses user's timezone for accurate day boundary.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        
    Returns:
        Number of problems solved today, or None if error
    """
    try:
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        # Get today's date in user's timezone
        today = datetime.now(user_tz).date()
        
        # Get problems solved today
        return await get_leetcode_problems_for_date(supabase, user_id, today)
        
    except Exception as e:
        logger.error(f"Error getting problems solved today: {e}")
        return None

async def get_problems_solved_last_day(
    supabase: AsyncClient,
    user_id: str
) -> Optional[int]:
    """
    Get the number of problems solved yesterday (not last 24 hours).
    Uses user's timezone for accurate day boundary.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        
    Returns:
        Number of problems solved yesterday, or None if error
    """
    try:
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        # Get yesterday's date in user's timezone
        yesterday = (datetime.now(user_tz) - timedelta(days=1)).date()
        
        # Get problems solved yesterday
        return await get_leetcode_problems_for_date(supabase, user_id, yesterday)
        
    except Exception as e:
        logger.error(f"Error getting problems solved last day: {e}")
        return None

async def get_problems_solved_last_week(
    supabase: AsyncClient,
    user_id: str,
    week_start_day: int = 0
) -> Optional[Dict[str, Any]]:
    """
    Get the number of problems solved in the last complete week.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
        
    Returns:
        Dict with count and week dates, or None if error
    """
    try:
        # Get LeetCode username
        result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            logger.error(f"No LeetCode account connected for user {user_id}")
            return None
        
        username = result.data[0]["leetcode_username"]
        
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        now = datetime.now(user_tz)
        
        # Calculate last week's boundaries
        # First get to the start of current week
        current_weekday = (now.weekday() + 1) % 7  # Convert to Sunday=0 format
        days_since_week_start = (current_weekday - week_start_day) % 7
        current_week_start = now.date() - timedelta(days=days_since_week_start)
        
        # Then go back one week
        last_week_start = current_week_start - timedelta(days=7)
        last_week_end = last_week_start + timedelta(days=6)
        
        # Get problems solved for the current week (not last week)
        # This matches how GitHub habits work - they show current week progress
        problems_count = await get_weekly_problems_solved(
            username, current_week_start, current_week_start + timedelta(days=6), user_timezone
        )
        
        return {
            "problems_solved": problems_count,  # Changed from "count" to match expected format
            "week_start": current_week_start,  # Return date object, not string
            "week_end": current_week_start + timedelta(days=6)  # Return date object, not string
        }
        
    except Exception as e:
        logger.error(f"Error getting problems solved last week: {e}")
        return None

async def update_leetcode_weekly_progress(supabase: AsyncClient, user_id: str, habit_id: str, week_start_date: date, weekly_target: int, week_start_day: int = 0):
    """
    Update weekly progress for a LeetCode weekly habit based on actual problem counts.
    For weekly LeetCode habits, the commit_target field contains the weekly problem goal.
    """
    try:
        # Get user's LeetCode username
        token_result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .single() \
            .execute()
        
        if not token_result.data or not token_result.data.get("leetcode_username"):
            logger.warning(f"No LeetCode username found for user {user_id}")
            return
        
        leetcode_username = token_result.data["leetcode_username"]
        
        # Calculate week end date
        week_end_date = week_start_date + timedelta(days=6)
        
        # Get user's timezone
        user_tz_str = await get_user_timezone(supabase, user_id)
        
        # Get problems solved for the week
        problems_solved = await get_weekly_problems_solved(
            leetcode_username, 
            week_start_date, 
            week_end_date, 
            user_tz_str
        )
        
        # Get the habit to find the actual weekly problem goal (stored in commit_target)
        habit_result = await supabase.table("habits") \
            .select("commit_target") \
            .eq("id", habit_id) \
            .execute()
        
        if not habit_result.data:
            logger.error(f"Habit {habit_id} not found")
            return
        
        actual_weekly_goal = habit_result.data[0]["commit_target"]  # All LeetCode targets are stored in commit_target
        
        # Handle None or invalid values for weekly goal
        if actual_weekly_goal is None:
            logger.warning(f"LeetCode habit {habit_id} has no commit_target set, using default of 3")
            actual_weekly_goal = 3  # Default to 3 problems per week
        
        logger.info(f"LeetCode weekly progress for habit {habit_id}: {problems_solved} problems, goal: {actual_weekly_goal}")
        
        # Update or create weekly progress record
        week_start_str = week_start_date.isoformat()
        is_complete = problems_solved >= actual_weekly_goal
        
        # Check if progress record exists
        progress_result = await supabase.table("weekly_habit_progress") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .eq("week_start_date", week_start_str) \
            .execute()
        
        progress_data = {
            "current_completions": problems_solved,
            "target_completions": actual_weekly_goal,
            "is_week_complete": is_complete
        }
        
        if progress_result.data:
            # Update existing record
            await supabase.table("weekly_habit_progress") \
                .update(progress_data) \
                .eq("habit_id", habit_id) \
                .eq("week_start_date", week_start_str) \
                .execute()
            
            logger.info(f"Updated LeetCode weekly progress for habit {habit_id}: {problems_solved}/{actual_weekly_goal}")
        else:
            # Create new record
            progress_data.update({
                "habit_id": habit_id,
                "user_id": user_id,
                "week_start_date": week_start_str
            })
            
            await supabase.table("weekly_habit_progress").insert(progress_data).execute()
            logger.info(f"Created LeetCode weekly progress for habit {habit_id}: {problems_solved}/{actual_weekly_goal}")
            
    except Exception as e:
        logger.error(f"Error updating LeetCode weekly progress for habit {habit_id}: {e}")

async def update_all_leetcode_weekly_progress(supabase: AsyncClient, user_id: str = None):
    """
    Update weekly progress for all LeetCode weekly habits.
    
    Args:
        supabase: Supabase client
        user_id: Optional user ID to limit updates to specific user
    """
    try:
        # Get all active weekly LeetCode habits
        query = supabase.table("habits") \
            .select("*") \
            .eq("habit_schedule_type", "weekly") \
            .eq("habit_type", "leetcode") \
            .eq("is_active", True)
        
        if user_id:
            query = query.eq("user_id", user_id)
        
        habits_result = await query.execute()
        
        if not habits_result.data:
            logger.info("No active LeetCode weekly habits found")
            return
        
        logger.info(f"Updating weekly progress for {len(habits_result.data)} LeetCode habits")
        
        for habit in habits_result.data:
            try:
                habit_id = habit['id']
                habit_user_id = habit['user_id']
                weekly_target = habit.get('weekly_target', 3)
                week_start_day = habit.get('week_start_day', 0)
                
                # Get current week dates for this habit using USER'S timezone
                user_timezone = await get_user_timezone(supabase, habit_user_id)
                user_tz = pytz.timezone(user_timezone)
                user_now = datetime.now(user_tz)
                today = user_now.date()
                
                week_start, week_end = get_week_dates(today, week_start_day)
                
                # Update progress for current week
                await update_leetcode_weekly_progress(
                    supabase=supabase,
                    user_id=habit_user_id,
                    habit_id=habit_id,
                    week_start_date=week_start,
                    weekly_target=weekly_target,
                    week_start_day=week_start_day
                )
                
            except Exception as e:
                logger.error(f"Error updating LeetCode habit {habit.get('id')}: {e}")
                continue
        
        logger.info("Completed updating LeetCode weekly progress")
        
    except Exception as e:
        logger.error(f"Error updating all LeetCode weekly progress: {e}")