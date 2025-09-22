from fastapi import APIRouter, Depends, HTTPException
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user_lightweight
from models.schemas import User
from utils.leetcode_api import LeetCodeAPI
from utils.timezone_utils import get_user_timezone
from utils.leetcode_habits import get_problems_solved_today, get_problems_solved_last_day, get_problems_solved_last_week
from utils.weekly_habits import get_week_dates
from pydantic import BaseModel
import logging
from typing import Optional
from datetime import datetime, timedelta, date
import pytz

logger = logging.getLogger(__name__)
router = APIRouter()

class LeetCodeConnectRequest(BaseModel):
    username: str

class LeetCodeConnectResponse(BaseModel):
    status: str
    message: str
    username: Optional[str] = None

@router.post("/connect", response_model=LeetCodeConnectResponse)
async def connect_leetcode(
    request: LeetCodeConnectRequest,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Connect a LeetCode account by username after validating it's public"""
    try:
        username = request.username.strip()
        
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
        
        return LeetCodeConnectResponse(
            status="connected",
            message="LeetCode account connected successfully",
            username=username
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error connecting LeetCode account: {e}")
        raise HTTPException(status_code=500, detail="Failed to connect LeetCode account")

@router.get("/status")
async def leetcode_status(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get LeetCode connection status"""
    try:
        user_id = str(current_user.id)
        result = await supabase.table("user_tokens") \
            .select("leetcode_username, leetcode_connected_at") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            return {"status": "not_connected"}
        
        username = result.data[0]["leetcode_username"]
        connected_at = result.data[0].get("leetcode_connected_at")
        
        # Verify the profile is still public
        profile_check = await LeetCodeAPI.check_profile_public(username)
        
        if not profile_check["exists"]:
            # User deleted their LeetCode account
            return {
                "status": "error",
                "message": "LeetCode account no longer exists",
                "username": username
            }
        
        if not profile_check["is_public"]:
            # User made their profile private
            return {
                "status": "error", 
                "message": "LeetCode profile is now private. Please make it public again.",
                "username": username
            }
        
        return {
            "status": "connected",
            "username": username,
            "connected_at": connected_at
        }
        
    except Exception as e:
        logger.error(f"Error checking LeetCode status: {e}")
        return {"status": "error", "message": "Failed to check LeetCode status"}

@router.delete("/disconnect")
async def disconnect_leetcode(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Disconnect LeetCode account"""
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
        
        return {"status": "disconnected", "message": "LeetCode account disconnected"}
        
    except Exception as e:
        logger.error(f"Error disconnecting LeetCode account: {e}")
        raise HTTPException(status_code=500, detail="Failed to disconnect LeetCode account")

@router.get("/validate/{username}")
async def validate_leetcode_username(
    username: str,
    current_user: User = Depends(get_current_user_lightweight)
):
    """Validate a LeetCode username and check if profile is public"""
    try:
        if not username:
            return {
                "valid": False,
                "exists": False,
                "is_public": False,
                "message": "Username cannot be empty"
            }
        
        profile_check = await LeetCodeAPI.check_profile_public(username.strip())
        
        return {
            "valid": profile_check["exists"] and profile_check["is_public"],
            "exists": profile_check["exists"],
            "is_public": profile_check.get("is_public", False),
            "message": profile_check["message"]
        }
        
    except Exception as e:
        logger.error(f"Error validating LeetCode username: {e}")
        return {
            "valid": False,
            "exists": False,
            "is_public": False,
            "message": f"Error validating username: {str(e)}"
        }

@router.get("/stats/{username}")
async def get_leetcode_stats(
    username: str,
    current_user: User = Depends(get_current_user_lightweight)
):
    """Get LeetCode statistics for a user"""
    try:
        stats = await LeetCodeAPI.get_user_stats(username)
        
        if not stats:
            raise HTTPException(status_code=404, detail="Failed to get user statistics")
        
        return {"username": username, "stats": stats}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting LeetCode stats: {e}")
        raise HTTPException(status_code=500, detail="Failed to get statistics")

@router.get("/problems-count")
async def get_total_problems_solved(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get total problems solved for the authenticated user"""
    try:
        user_id = str(current_user.id)
        
        # Get LeetCode username
        result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            raise HTTPException(status_code=404, detail="LeetCode account not connected")
        
        username = result.data[0]["leetcode_username"]
        
        # Get user stats
        stats = await LeetCodeAPI.get_user_stats(username)
        if not stats:
            raise HTTPException(status_code=503, detail="Failed to fetch LeetCode stats")
        
        # Calculate total solved problems from all difficulties
        total_solved = 0
        if stats.get("submitStats") and stats["submitStats"].get("acSubmissionNum"):
            for submission in stats["submitStats"]["acSubmissionNum"]:
                total_solved += submission.get("count", 0)
        
        return {"count": total_solved, "username": username}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting LeetCode problems count: {e}")
        raise HTTPException(status_code=500, detail="Failed to get problems count")


@router.get("/today-count")
async def leetcode_today_problem_count(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Return today's problem count for the authenticated user in their timezone."""
    try:
        user_id = str(current_user.id)
        
        # Get problems solved today using the utility function
        count = await get_problems_solved_today(supabase, user_id)
        
        if count is None:
            raise HTTPException(status_code=404, detail="LeetCode not connected")
        
        return {"count": count}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting today's LeetCode problem count: {e}")
        raise HTTPException(status_code=500, detail="Failed to get problem count")

@router.get("/yesterday-count")
async def leetcode_yesterday_problem_count(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Return yesterday's problem count for the authenticated user."""
    try:
        user_id = str(current_user.id)
        
        # Get problems solved yesterday using the utility function
        count = await get_problems_solved_last_day(supabase, user_id)
        
        if count is None:
            raise HTTPException(status_code=404, detail="LeetCode not connected")
        
        # Get user's timezone for date display
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        user_now = datetime.now(user_tz)
        yesterday = user_now.date() - timedelta(days=1)
        
        return {"count": count, "date": yesterday.isoformat(), "timezone": user_timezone}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting yesterday's LeetCode problem count: {e}")
        raise HTTPException(status_code=500, detail="Failed to get problem count")

@router.get("/current-week-count-original")
async def leetcode_current_week_problems_count_original(
    week_start_day: int = 0,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get current week's problems solved count for weekly LeetCode habits.
    Uses the weekly_habit_progress table that already exists.
    
    Args:
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
    
    Returns:
        Current week's problems solved count
    """
    try:
        user_id = str(current_user.id)
        
        # Get LeetCode username
        result = await supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("leetcode_username"):
            raise HTTPException(status_code=404, detail="LeetCode account not connected")
        
        username = result.data[0]["leetcode_username"]
        
        # Get current total solved count
        stats = await LeetCodeAPI.get_user_stats(username)
        if not stats:
            raise HTTPException(status_code=503, detail="Failed to fetch LeetCode stats")
        
        # Calculate total solved problems
        current_total = 0
        if stats.get("submitStats") and stats["submitStats"].get("acSubmissionNum"):
            for submission in stats["submitStats"]["acSubmissionNum"]:
                current_total += submission.get("count", 0)
        
        # Get user's timezone for week calculations
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        now = datetime.now(user_tz)
        
        # Calculate week boundaries
        days_since_week_start = (now.weekday() - week_start_day + 7) % 7
        week_start = now.date() - timedelta(days=days_since_week_start)
        week_end = week_start + timedelta(days=6)
        
        # Get weekly LeetCode habit
        habit_result = await supabase.table("habits") \
            .select("id, name, commit_target, weekly_target") \
            .eq("user_id", user_id) \
            .eq("habit_type", "leetcode") \
            .eq("habit_schedule_type", "weekly") \
            .eq("is_active", True) \
            .execute()
        
        if not habit_result.data:
            return {
                "count": 0,
                "goal": None,
                "week_start_date": week_start.isoformat(),
                "week_end_date": week_end.isoformat(),
                "total_solved": current_total,
                "message": "No active weekly LeetCode habit found"
            }
        
        habit = habit_result.data[0]
        habit_id = habit["id"]
        # Use commit_target field for LeetCode problems target
        goal = habit.get("commit_target", habit.get("weekly_target", 1))
        
        # Check if there's a weekly progress record
        progress_result = await supabase.table("weekly_habit_progress") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .eq("week_start_date", week_start.isoformat()) \
            .execute()
        
        if progress_result.data:
            # Return existing progress
            progress = progress_result.data[0]
            return {
                "count": progress["current_completions"],
                "goal": goal,
                "week_start_date": week_start.isoformat(),
                "week_end_date": week_end.isoformat(),
                "total_solved": current_total
            }
        else:
            # For new week, start with 0
            return {
                "count": 0,
                "goal": goal,
                "week_start_date": week_start.isoformat(),
                "week_end_date": week_end.isoformat(),
                "total_solved": current_total
            }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting current week LeetCode problems: {e}")
        raise HTTPException(status_code=500, detail="Failed to get current week problems count")

@router.get("/current-week-count")
async def leetcode_current_week_problem_count(
    week_start_day: int = 0,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get current week's problem count for weekly LeetCode habits.
    For weekly LeetCode habits, the problem goal is stored in commit_target field.
    
    Args:
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
    
    Returns:
        Current week's problem count and goal with live data
    """
    try:
        user_id = str(current_user.id)
        
        # Get week data using the utility function
        result = await get_problems_solved_last_week(supabase, user_id, week_start_day)
        
        if result is None:
            raise HTTPException(status_code=404, detail="LeetCode not connected")
        
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
            return {
                "current_problems": result["problems_solved"],
                "weekly_goal": 0,
                "week_start_date": result["week_start"].isoformat(),
                "week_end_date": result["week_end"].isoformat(),
                "habits": [],
                "progress_percentage": 0,
                "message": "No active weekly LeetCode habits"
            }
        
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
        current_problems = result.get("problems_solved", 0) if result else 0
        progress_percentage = min(100, (current_problems / max_weekly_goal) * 100) if max_weekly_goal > 0 and current_problems is not None else 0
        
        return {
            "current_problems": current_problems,
            "weekly_goal": max_weekly_goal,
            "week_start_date": result["week_start"].isoformat(),
            "week_end_date": result["week_end"].isoformat(),
            "habits": habit_info,
            "progress_percentage": progress_percentage
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting current week LeetCode problems: {e}")
        raise HTTPException(status_code=500, detail="Failed to get current week problem count")