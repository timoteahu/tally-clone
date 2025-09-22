from fastapi import HTTPException
from models.schemas import User
from supabase._async.client import AsyncClient
from typing import List, Optional, Dict, Any
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from utils.leetcode_api import LeetCodeAPI
from utils.timezone_utils import get_user_timezone
from utils.weekly_habits import get_week_dates
from datetime import datetime, date, timedelta
import pytz
import logging
from ..utils.leetcode_helpers import (
    get_leetcode_username_for_user,
    calculate_week_boundaries,
    get_weekly_problems_solved,
    validate_leetcode_connection,
    format_leetcode_response
)

logger = logging.getLogger(__name__)

@memory_optimized(cleanup_args=False)
@memory_profile("get_leetcode_problems_solved_service")
async def get_leetcode_problems_solved_service(
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Get the total number of LeetCode problems solved by the user.
    
    Args:
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        Dict with total problems solved and user stats
    """
    try:
        user_id = str(current_user.id)
        
        # Get LeetCode username
        username = await get_leetcode_username_for_user(supabase, user_id)
        if not username:
            raise HTTPException(status_code=404, detail="LeetCode account not connected")
        
        # Get current total solved count
        stats = await LeetCodeAPI.get_user_stats(username)
        if not stats:
            raise HTTPException(status_code=503, detail="Failed to fetch LeetCode stats")
        
        # Calculate total solved problems
        current_total = 0
        if stats.get("submitStats") and stats["submitStats"].get("acSubmissionNum"):
            for submission in stats["submitStats"]["acSubmissionNum"]:
                current_total += submission.get("count", 0)
        
        return format_leetcode_response({
            "total_solved": current_total,
            "username": username,
            "stats": stats
        })
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting LeetCode problems count for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to get problems count")

@memory_optimized(cleanup_args=False)
@memory_profile("get_leetcode_problems_today_service")
async def get_leetcode_problems_today_service(
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Get problems solved today for the authenticated user in their timezone.
    
    Args:
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        Dict with today's problem count and date info
    """
    try:
        user_id = str(current_user.id)
        
        # Validate LeetCode connection
        username = await validate_leetcode_connection(supabase, user_id)
        
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        # Get today's date in user's timezone
        today = datetime.now(user_tz).date()
        
        # Get problems solved today
        count = await LeetCodeAPI.get_daily_problems_solved(username, today)
        
        if count is None:
            raise HTTPException(status_code=503, detail="Failed to fetch daily problems data")
        
        return format_leetcode_response({
            "count": count,
            "date": today.isoformat(),
            "timezone": user_timezone,
            "username": username
        })
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting today's LeetCode problems for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to get today's problem count")

@memory_optimized(cleanup_args=False)
@memory_profile("get_leetcode_problems_yesterday_service")
async def get_leetcode_problems_yesterday_service(
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Get problems solved yesterday for the authenticated user.
    
    Args:
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        Dict with yesterday's problem count and date info
    """
    try:
        user_id = str(current_user.id)
        
        # Validate LeetCode connection
        username = await validate_leetcode_connection(supabase, user_id)
        
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        # Get yesterday's date in user's timezone
        yesterday = (datetime.now(user_tz) - timedelta(days=1)).date()
        
        # Get problems solved yesterday
        count = await LeetCodeAPI.get_daily_problems_solved(username, yesterday)
        
        if count is None:
            raise HTTPException(status_code=503, detail="Failed to fetch daily problems data")
        
        return format_leetcode_response({
            "count": count,
            "date": yesterday.isoformat(),
            "timezone": user_timezone,
            "username": username
        })
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting yesterday's LeetCode problems for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to get yesterday's problem count")

@memory_optimized(cleanup_args=False)
@memory_profile("get_leetcode_current_week_service")
async def get_leetcode_current_week_service(
    week_start_day: int = 0,
    current_user: User = None,
    supabase: AsyncClient = None
) -> Dict[str, Any]:
    """
    Get current week's problem count for weekly LeetCode habits.
    For weekly LeetCode habits, the problem goal is stored in commit_target field.
    
    Args:
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
        current_user: Current authenticated user
        supabase: Database client
    
    Returns:
        Dict with current week's problem count and goal with live data
    """
    try:
        user_id = str(current_user.id)
        
        # Validate LeetCode connection
        username = await validate_leetcode_connection(supabase, user_id)
        
        # Calculate week boundaries
        week_start, week_end, user_timezone = await calculate_week_boundaries(
            supabase, user_id, week_start_day
        )
        
        # Get problems solved this week
        problems_this_week = await get_weekly_problems_solved(
            username, week_start, week_end, user_timezone
        )
        
        # Get user's weekly LeetCode habits to find the weekly problem goal
        habits_result = await supabase.table("habits") \
            .select("id, commit_target, name") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("habit_type", "leetcode") \
            .eq("is_active", True) \
            .execute()
        
        if not habits_result.data:
            # No weekly habits but we have LeetCode connected
            return format_leetcode_response({
                "current_problems": problems_this_week,
                "weekly_goal": 0,
                "week_start_date": week_start.isoformat(),
                "week_end_date": week_end.isoformat(),
                "habits": [],
                "progress_percentage": 0,
                "message": "No active weekly LeetCode habits"
            })
        
        # Get the maximum goal among all habits
        weekly_goals = []
        habit_info = []
        
        for habit in habits_result.data:
            problem_goal = habit.get("commit_target", 3)  # Default to 3 if not set
            weekly_goals.append(problem_goal)
            habit_info.append({
                "id": habit["id"],
                "name": habit["name"],  
                "weekly_goal": problem_goal
            })
        
        max_weekly_goal = max(weekly_goals) if weekly_goals else 3
        
        # Calculate progress percentage
        progress_percentage = min(100, (problems_this_week / max_weekly_goal) * 100) if max_weekly_goal > 0 else 0
        
        return format_leetcode_response({
            "current_problems": problems_this_week,
            "weekly_goal": max_weekly_goal,
            "week_start_date": week_start.isoformat(),
            "week_end_date": week_end.isoformat(),
            "habits": habit_info,
            "progress_percentage": progress_percentage,
            "username": username,
            "timezone": user_timezone
        })
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting current week LeetCode problems for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to get current week problem count")

@memory_optimized(cleanup_args=False)
@memory_profile("verify_leetcode_habit_service")
async def verify_leetcode_habit_service(
    habit_id: str,
    target_date: Optional[date] = None,
    current_user: User = None,
    supabase: AsyncClient = None
) -> Dict[str, Any]:
    """
    Verify a LeetCode habit for a specific date.
    
    Args:
        habit_id: Habit ID to verify
        target_date: Optional target date, defaults to today
        current_user: Current authenticated user
        supabase: Database client
    
    Returns:
        Dict with verification status and details
    """
    try:
        user_id = str(current_user.id)
        
        # Get habit details
        habit_result = await supabase.table("habits") \
            .select("*") \
            .eq("id", habit_id) \
            .eq("user_id", user_id) \
            .single() \
            .execute()
        
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        habit = habit_result.data
        
        if habit.get("habit_type") != "leetcode":
            raise HTTPException(status_code=400, detail="Not a LeetCode habit")
        
        # Validate LeetCode connection
        username = await validate_leetcode_connection(supabase, user_id)
        
        # Use user's timezone if no target date specified
        if not target_date:
            user_timezone = await get_user_timezone(supabase, user_id)
            user_tz = pytz.timezone(user_timezone)
            target_date = datetime.now(user_tz).date()
        
        # Get problems solved based on schedule type
        if habit.get("habit_schedule_type") == "weekly":
            week_start_day = habit.get("week_start_day", 0)
            week_start, week_end, user_timezone = await calculate_week_boundaries(
                supabase, user_id, week_start_day
            )
            
            problems_solved = await get_weekly_problems_solved(
                username, week_start, week_end, user_timezone
            )
            
            target = habit["commit_target"]  # All LeetCode targets are stored in commit_target
            met = problems_solved >= target
            
            return format_leetcode_response({
                "success": True,
                "verified": met,
                "problems_solved": problems_solved,
                "target": target,
                "week_start_date": week_start.isoformat(),
                "week_end_date": week_end.isoformat(),
                "habit_type": "weekly"
            })
        else:
            # Daily habit
            problems_today = await LeetCodeAPI.get_daily_problems_solved(username, target_date)
            
            if problems_today is None:
                raise HTTPException(status_code=503, detail="Failed to get daily LeetCode data")
            
            target = habit["commit_target"]  # All LeetCode targets are stored in commit_target
            met = problems_today >= target
            
            return format_leetcode_response({
                "success": True,
                "verified": met,
                "problems_solved": problems_today,
                "target": target,
                "date": target_date.isoformat(),
                "habit_type": "daily"
            })
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error verifying LeetCode habit {habit_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to verify habit: {str(e)}")

@memory_optimized(cleanup_args=False)
@memory_profile("update_leetcode_weekly_progress_service")
async def update_leetcode_weekly_progress_service(
    habit_id: str,
    week_start_date: date,
    weekly_target: int,
    week_start_day: int = 0,
    current_user: User = None,
    supabase: AsyncClient = None
) -> Dict[str, Any]:
    """
    Update weekly progress for a LeetCode weekly habit based on actual problem counts.
    For weekly LeetCode habits, the commit_target field contains the weekly problem goal.
    
    Args:
        habit_id: Habit ID to update progress for
        week_start_date: Start date of the week
        weekly_target: Weekly target (usually from commit_target field)
        week_start_day: Day week starts on (0=Sunday)
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        Dict with update status and progress data
    """
    try:
        user_id = str(current_user.id)
        
        # Validate LeetCode connection
        username = await validate_leetcode_connection(supabase, user_id)
        
        # Calculate week end date
        week_end_date = week_start_date + timedelta(days=6)
        
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        
        # Get problems solved for the week
        problems_solved = await get_weekly_problems_solved(
            username, 
            week_start_date, 
            week_end_date, 
            user_timezone
        )
        
        # Get the habit to find the actual weekly problem goal (stored in commit_target)
        habit_result = await supabase.table("habits") \
            .select("commit_target") \
            .eq("id", habit_id) \
            .execute()
        
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        actual_weekly_goal = habit_result.data[0]["commit_target"]  # All LeetCode targets are stored in commit_target
        
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
            operation = "updated"
        else:
            # Create new record
            progress_data.update({
                "habit_id": habit_id,
                "user_id": user_id,
                "week_start_date": week_start_str
            })
            
            await supabase.table("weekly_habit_progress").insert(progress_data).execute()
            logger.info(f"Created LeetCode weekly progress for habit {habit_id}: {problems_solved}/{actual_weekly_goal}")
            operation = "created"
        
        return format_leetcode_response({
            "success": True,
            "operation": operation,
            "habit_id": habit_id,
            "week_start_date": week_start_str,
            "problems_solved": problems_solved,
            "weekly_goal": actual_weekly_goal,
            "is_complete": is_complete,
            "username": username
        })
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating LeetCode weekly progress for habit {habit_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to update weekly progress")

@memory_optimized(cleanup_args=False)
@memory_profile("connect_leetcode_account_service")
async def connect_leetcode_account_service(
    username: str,
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Connect a LeetCode account by username after validating it's public.
    
    Args:
        username: LeetCode username to connect
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        Dict with connection status and details
    """
    try:
        username = username.strip()
        
        if not username:
            raise HTTPException(status_code=400, detail="Username cannot be empty")
        
        # Check if profile exists and is public
        profile_check = await LeetCodeAPI.check_profile_public(username)
        
        if not profile_check["exists"]:
            raise HTTPException(status_code=404, detail=profile_check["message"])
        
        if not profile_check["is_public"]:
            raise HTTPException(status_code=403, detail=profile_check["message"])
        
        # Save to database
        user_id = str(current_user.id)
        update_payload = {
            "user_id": user_id,
            "leetcode_username": username,
            "leetcode_connected_at": datetime.utcnow().isoformat()
        }
        
        await supabase.table("user_tokens").upsert(update_payload, on_conflict="user_id").execute()
        
        logger.info(f"User {user_id} connected LeetCode account: {username}")
        
        return format_leetcode_response({
            "status": "connected",
            "message": "LeetCode account connected successfully",
            "username": username,
            "connected_at": update_payload["leetcode_connected_at"]
        })
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error connecting LeetCode account for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to connect LeetCode account")

@memory_optimized(cleanup_args=False)
@memory_profile("disconnect_leetcode_account_service")
async def disconnect_leetcode_account_service(
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Disconnect LeetCode account for the current user.
    
    Args:
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        Dict with disconnection status
    """
    try:
        user_id = str(current_user.id)
        
        # Clear LeetCode data
        update_payload = {
            "user_id": user_id,
            "leetcode_username": None,
            "leetcode_connected_at": None
        }
        
        await supabase.table("user_tokens").upsert(update_payload, on_conflict="user_id").execute()
        
        logger.info(f"User {user_id} disconnected LeetCode account")
        
        return format_leetcode_response({
            "status": "disconnected", 
            "message": "LeetCode account disconnected successfully"
        })
        
    except Exception as e:
        logger.error(f"Error disconnecting LeetCode account for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to disconnect LeetCode account")

@memory_optimized(cleanup_args=False)
@memory_profile("get_leetcode_connection_status_service")
async def get_leetcode_connection_status_service(
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Get LeetCode connection status for the current user.
    
    Args:
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        Dict with connection status and details
    """
    try:
        user_id = str(current_user.id)
        result = await supabase.table("user_tokens") \
            .select("leetcode_username, leetcode_connected_at") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            return format_leetcode_response({"status": "not_connected"})
        
        username = result.data[0]["leetcode_username"]
        connected_at = result.data[0].get("leetcode_connected_at")
        
        # Verify the profile is still public
        profile_check = await LeetCodeAPI.check_profile_public(username)
        
        if not profile_check["exists"]:
            # User deleted their LeetCode account
            return format_leetcode_response({
                "status": "error",
                "message": "LeetCode account no longer exists",
                "username": username
            })
        
        if not profile_check["is_public"]:
            # User made their profile private
            return format_leetcode_response({
                "status": "error", 
                "message": "LeetCode profile is now private. Please make it public again.",
                "username": username
            })
        
        return format_leetcode_response({
            "status": "connected",
            "username": username,
            "connected_at": connected_at
        })
        
    except Exception as e:
        logger.error(f"Error checking LeetCode status for user {current_user.id}: {e}")
        return format_leetcode_response({
            "status": "error", 
            "message": "Failed to check LeetCode status"
        }) 