import httpx
import logging
from datetime import datetime, timedelta, date, time, timezone
from typing import Optional
import pytz
from utils.weekly_habits import get_week_dates
from supabase import Client
from supabase._async.client import AsyncClient

logger = logging.getLogger(__name__)

async def get_user_timezone(supabase: AsyncClient, user_id: str) -> str:
    """Get user's timezone from the database"""
    user = await supabase.table("users").select("timezone").eq("id", user_id).execute()
    if not user.data:
        return "UTC"
    
    timezone_str = user.data[0]["timezone"]
    
    # Handle timezone abbreviations by mapping them to proper pytz names
    timezone_mapping = {
        'PDT': 'America/Los_Angeles',
        'PST': 'America/Los_Angeles',
        'EDT': 'America/New_York',
        'EST': 'America/New_York',
        'CDT': 'America/Chicago',
        'CST': 'America/Chicago',
        'MDT': 'America/Denver',
        'MST': 'America/Denver',
    }
    
    # If it's an abbreviation, convert it
    if timezone_str in timezone_mapping:
        timezone_str = timezone_mapping[timezone_str]
    
    # Validate the timezone exists in pytz
    try:
        pytz.timezone(timezone_str)
        return timezone_str
    except pytz.exceptions.UnknownTimeZoneError:
        logger.warning(f"Unknown timezone: {timezone_str}, falling back to UTC")
        return "UTC"

async def get_commit_count(access_token: str, start_date: datetime, end_date: datetime) -> Optional[int]:
    """
    Get the number of commits made by the authenticated user in the given date range.
    
    Args:
        access_token: GitHub access token
        start_date: Start date (UTC, timezone-naive)
        end_date: End date (UTC, timezone-naive)
        
    Returns:
        Number of commits or None if there was an error
    """
    # Format dates for GitHub API (ISO format without microseconds)
    # GitHub GraphQL API expects YYYY-MM-DDTHH:MM:SSZ format
    start_iso = start_date.strftime("%Y-%m-%dT%H:%M:%SZ")
    end_iso = end_date.strftime("%Y-%m-%dT%H:%M:%SZ")
    
    # GraphQL query to get commit count
    query = """
    query($startDate: DateTime!, $endDate: DateTime!) {
        viewer {
            contributionsCollection(from: $startDate, to: $endDate) {
                totalCommitContributions
            }
        }
    }
    """
    
    variables = {
        "startDate": start_iso,
        "endDate": end_iso
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                "https://api.github.com/graphql",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github.v3+json"
                },
                json={
                    "query": query,
                    "variables": variables
                },
                timeout=30.0
            )
            
            if response.status_code == 200:
                data = response.json()
                if "data" in data and "viewer" in data["data"]:
                    return data["data"]["viewer"]["contributionsCollection"]["totalCommitContributions"]
                else:
                    logger.error(f"Unexpected GitHub API response: {data}")
                    return None
            elif response.status_code == 401:
                # Token expired or invalid - log specific error
                logger.error(f"GitHub API authentication failed (401): {response.text}")
                # Check if it's specifically a token expiry issue
                try:
                    error_data = response.json()
                    if "message" in error_data and ("expired" in error_data["message"].lower() or "bad credentials" in error_data["message"].lower()):
                        logger.error("GitHub access token has expired or is invalid. User needs to reconnect GitHub.")
                        # TODO: Implement token refresh or trigger re-authentication
                        # For now, we return None to indicate the error
                        return None
                except:
                    pass
                return None
            elif response.status_code == 403:
                # Rate limiting or permission issues
                logger.error(f"GitHub API rate limited or insufficient permissions (403): {response.text}")
                return None
            else:
                logger.error(f"GitHub API error {response.status_code}: {response.text}")
                return None
                
    except Exception as e:
        logger.error(f"Error fetching GitHub commit count: {e}")
        return None

async def check_github_token_validity(access_token: str) -> dict:
    """
    Check if a GitHub access token is still valid.
    
    Args:
        access_token: GitHub access token to validate
        
    Returns:
        Dict with status and error information
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://api.github.com/user",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github.v3+json"
                },
                timeout=10.0
            )
            
            if response.status_code == 200:
                return {"valid": True, "user": response.json()}
            elif response.status_code == 401:
                error_data = response.json() if response.headers.get("content-type", "").startswith("application/json") else {}
                return {
                    "valid": False, 
                    "error": "token_expired", 
                    "message": error_data.get("message", "Token expired or invalid")
                }
            else:
                return {
                    "valid": False, 
                    "error": "api_error", 
                    "message": f"GitHub API returned {response.status_code}"
                }
                
    except Exception as e:
        return {
            "valid": False, 
            "error": "network_error", 
            "message": str(e)
        }

async def handle_github_token_error(supabase: AsyncClient, user_id: str, error_type: str) -> None:
    """
    Handle GitHub token errors by updating user status and potentially notifying them.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        error_type: Type of error (token_expired, rate_limited, etc.)
    """
    try:
        # Clear the invalid token from the database
        if error_type == "token_expired":
            await supabase.table("user_tokens").update({
                "github_access_token": None,
                "github_token_error": error_type,
                "github_token_error_at": datetime.utcnow().isoformat()
            }).eq("user_id", user_id).execute()
            
            logger.info(f"Cleared expired GitHub token for user {user_id}")
            
            # TODO: Send push notification to user about GitHub reconnection needed
            # await send_github_reconnect_notification(user_id)
        else:
            # For other errors, just log them
            await supabase.table("user_tokens").update({
                "github_token_error": error_type,
                "github_token_error_at": datetime.utcnow().isoformat()
            }).eq("user_id", user_id).execute()
            
    except Exception as e:
        logger.error(f"Error handling GitHub token error for user {user_id}: {e}")

async def get_commit_count_with_error_handling(supabase: AsyncClient, user_id: str, start_date: datetime, end_date: datetime) -> Optional[int]:
    """
    Get commit count with proper error handling and automatic token refresh.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        start_date: Start date (UTC, timezone-naive)
        end_date: End date (UTC, timezone-naive)
        
    Returns:
        Number of commits or None if there was an error
    """
    try:
        # Get user's GitHub token info
        github_result = await supabase.table("user_tokens") \
            .select("github_access_token, github_refresh_token, github_token_expires_at") \
            .eq("user_id", user_id) \
            .execute()
        
        if not github_result.data or not github_result.data[0].get("github_access_token"):
            logger.warning(f"No GitHub access token found for user {user_id}")
            return None
        
        token_data = github_result.data[0]
        access_token = token_data["github_access_token"]
        refresh_token = token_data.get("github_refresh_token")
        expires_at = token_data.get("github_token_expires_at")
        
        # Check if token is expired and refresh if possible
        if expires_at and refresh_token:
            expires_datetime = datetime.fromisoformat(expires_at)
            # Refresh if token expires within 5 minutes (buffer time)
            if datetime.utcnow() >= expires_datetime - timedelta(minutes=5):
                logger.info(f"GitHub token expiring soon for user {user_id}, refreshing...")
                try:
                    access_token = await refresh_user_github_token(supabase, user_id, refresh_token)
                    if not access_token:
                        logger.error(f"Failed to refresh GitHub token for user {user_id}")
                        return None
                except Exception as refresh_error:
                    logger.error(f"Token refresh failed for user {user_id}: {refresh_error}")
                    # Continue with existing token, might still work
        
        # First, validate the token
        token_status = await check_github_token_validity(access_token)
        
        if not token_status["valid"]:
            # If token is invalid and we have a refresh token, try refreshing
            if refresh_token and token_status.get("error") == "token_expired":
                logger.info(f"GitHub token invalid for user {user_id}, attempting refresh...")
                try:
                    access_token = await refresh_user_github_token(supabase, user_id, refresh_token)
                    if access_token:
                        # Retry with new token
                        return await get_commit_count(access_token, start_date, end_date)
                except Exception as refresh_error:
                    logger.error(f"Token refresh failed for user {user_id}: {refresh_error}")
            
            # Refresh failed or no refresh token available
            logger.error(f"GitHub token invalid for user {user_id}: {token_status.get('message')}")
            await handle_github_token_error(supabase, user_id, token_status.get("error", "unknown"))
            return None
        
        # Token is valid, proceed with commit count
        return await get_commit_count(access_token, start_date, end_date)
        
    except Exception as e:
        logger.error(f"Error getting commit count with error handling for user {user_id}: {e}")
        return None

async def refresh_user_github_token(supabase: AsyncClient, user_id: str, refresh_token: str) -> Optional[str]:
    """
    Refresh a user's GitHub access token using their refresh token.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        refresh_token: GitHub refresh token
        
    Returns:
        New access token or None if refresh failed
    """
    try:
        # Import here to avoid circular import
        import httpx
        import os
        
        GITHUB_CLIENT_ID = os.getenv("GITHUB_CLIENT_ID")
        GITHUB_CLIENT_SECRET = os.getenv("GITHUB_CLIENT_SECRET")
        
        if not GITHUB_CLIENT_ID or not GITHUB_CLIENT_SECRET:
            logger.error("GitHub OAuth credentials not configured")
            return None
        
        # Call GitHub token refresh endpoint
        token_url = "https://github.com/login/oauth/access_token"
        async with httpx.AsyncClient() as client:
            headers = {"Accept": "application/json"}
            data = {
                "client_id": GITHUB_CLIENT_ID,
                "client_secret": GITHUB_CLIENT_SECRET,
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
            }
            resp = await client.post(token_url, headers=headers, data=data, timeout=15)
            
            if resp.status_code != 200:
                logger.error(f"GitHub token refresh failed: {resp.status_code} {resp.text}")
                return None
            
            token_json = resp.json()
            
        new_access_token = token_json.get("access_token")
        new_refresh_token = token_json.get("refresh_token", refresh_token)  # Use old refresh token if new one not provided
        expires_in = token_json.get("expires_in")
        
        if not new_access_token:
            logger.error(f"No access token in refresh response for user {user_id}")
            return None
        
        # Calculate new expiration time
        expires_at = None
        if expires_in:
            expires_at = (datetime.utcnow() + timedelta(seconds=expires_in)).isoformat()
        
        # Update database with new token info
        update_payload = {
            "github_access_token": new_access_token,
            "github_refresh_token": new_refresh_token,
            "github_token_expires_at": expires_at,
            "github_token_error": None,  # Clear any previous errors
            "github_token_error_at": None,
        }
        
        await supabase.table("user_tokens").update(update_payload).eq("user_id", user_id).execute()
        
        logger.info(f"Successfully refreshed GitHub token for user {user_id}")
        return new_access_token
        
    except Exception as e:
        logger.error(f"Error refreshing GitHub token for user {user_id}: {e}")
        return None

async def update_github_weekly_progress_async(supabase: AsyncClient, user_id: str, habit_id: str, week_start_date: date, weekly_target: int, week_start_day: int = 0):
    """
    Update weekly progress for a GitHub weekly habit based on actual commit counts (ASYNC version).
    For weekly GitHub habits, the commit_target field contains the weekly commit goal.
    """
    try:
        # Get user's GitHub access token from user_tokens table
        github_result = await supabase.table("user_tokens") \
            .select("github_access_token") \
            .eq("user_id", user_id) \
            .execute()
        
        if not github_result.data or not github_result.data[0].get("github_access_token"):
            logger.warning(f"No GitHub access token found for user {user_id}")
            return
        
        access_token = github_result.data[0]["github_access_token"]
        
        # Calculate week end date
        week_end_date = week_start_date + timedelta(days=6)
        
        # Get commit count for the week
        start_datetime = datetime.combine(week_start_date, time.min).replace(tzinfo=timezone.utc)
        end_datetime = datetime.combine(week_end_date, time.max).replace(tzinfo=timezone.utc)
        
        commit_count = await get_commit_count_with_error_handling(supabase, user_id, start_datetime, end_datetime)
        
        if commit_count is None:
            logger.error(f"Failed to get commit count for user {user_id}")
            return
        
        # For weekly GitHub habits, use the commit_target as the weekly goal
        # weekly_target should be 1 (we check once per week), but commit_target has the actual goal
        
        # Get the habit to find the actual weekly commit goal (stored in commit_target)
        habit_result = await supabase.table("habits") \
            .select("commit_target") \
            .eq("id", habit_id) \
            .execute()
        
        if not habit_result.data:
            logger.error(f"Habit {habit_id} not found")
            return
        
        actual_weekly_goal = habit_result.data[0].get("commit_target", weekly_target)
        if actual_weekly_goal is None:
            actual_weekly_goal = weekly_target  # Fallback to passed parameter
        
        logger.info(f"GitHub weekly progress for habit {habit_id}: {commit_count} commits, goal: {actual_weekly_goal}")
        
        # Update or create weekly progress record
        week_start_str = week_start_date.isoformat()
        is_complete = commit_count >= actual_weekly_goal
        
        # Check if progress record exists
        progress_result = await supabase.table("weekly_habit_progress") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .eq("week_start_date", week_start_str) \
            .execute()
        
        progress_data = {
            "current_completions": commit_count,
            "target_completions": actual_weekly_goal,  # Use commit_target as the goal
            "is_week_complete": is_complete
        }
        
        if progress_result.data:
            # Update existing record
            await supabase.table("weekly_habit_progress") \
                .update(progress_data) \
                .eq("habit_id", habit_id) \
                .eq("week_start_date", week_start_str) \
                .execute()
            
            logger.info(f"Updated GitHub weekly progress for habit {habit_id}: {commit_count}/{actual_weekly_goal}")
        else:
            # Create new record
            progress_data.update({
                "habit_id": habit_id,
                "user_id": user_id,
                "week_start_date": week_start_str
            })
            
            await supabase.table("weekly_habit_progress").insert(progress_data).execute()
            logger.info(f"Created GitHub weekly progress for habit {habit_id}: {commit_count}/{actual_weekly_goal}")
            
    except Exception as e:
        logger.error(f"Error updating GitHub weekly progress for habit {habit_id}: {e}")

def update_github_weekly_progress_sync(supabase: Client, user_id: str, habit_id: str, week_start_date: date, weekly_target: int, week_start_day: int = 0):
    """
    Update weekly progress for a GitHub weekly habit based on actual commit counts (SYNC version).
    This is a simplified sync version that doesn't actually fetch commits - used for scheduler.
    """
    try:
        logger.warning(f"Sync GitHub progress update called for habit {habit_id} - using fallback method")
        
        # For sync calls, we can't fetch from GitHub API, so we skip the update
        # This prevents the scheduler from crashing while maintaining the interface
        logger.info(f"Skipping GitHub API call for habit {habit_id} in sync context")
        
    except Exception as e:
        logger.error(f"Error in sync GitHub weekly progress update for habit {habit_id}: {e}")

# Keep the old function name for backward compatibility but determine client type
async def update_github_weekly_progress(supabase, user_id: str, habit_id: str, week_start_date: date, weekly_target: int, week_start_day: int = 0):
    """
    Update weekly progress for a GitHub weekly habit based on actual commit counts.
    Automatically detects client type and routes to appropriate implementation.
    """
    # Determine if we are using the async or sync client
    if isinstance(supabase, AsyncClient):
        await update_github_weekly_progress_async(supabase, user_id, habit_id, week_start_date, weekly_target, week_start_day)
    else:
        # For sync clients, use the sync version (which just logs and skips)
        update_github_weekly_progress_sync(supabase, user_id, habit_id, week_start_date, weekly_target, week_start_day)

async def update_all_github_weekly_progress(supabase, user_id: str = None):
    """
    Update weekly progress for all GitHub weekly habits.
    
    Args:
        supabase: Supabase client (async or sync)
        user_id: Optional user ID to limit updates to specific user
    """
    try:
        # Determine if we are using the async or sync client
        is_async_client = isinstance(supabase, AsyncClient)
        
        # Get all active weekly GitHub habits
        query = supabase.table("habits") \
            .select("*") \
            .eq("habit_schedule_type", "weekly") \
            .eq("habit_type", "github_commits") \
            .eq("is_active", True)
        
        if user_id:
            query = query.eq("user_id", user_id)
        
        if is_async_client:
            habits_result = await query.execute()
        else:
            habits_result = query.execute()
        
        if not habits_result.data:
            logger.info("No active GitHub weekly habits found")
            return
        
        logger.info(f"Updating weekly progress for {len(habits_result.data)} GitHub habits")
        
        for habit in habits_result.data:
            try:
                habit_id = habit['id']
                habit_user_id = habit['user_id']
                weekly_target = habit.get('weekly_target', 7)
                week_start_day = habit.get('week_start_day', 0)
                
                # Get current week dates for this habit using USER'S timezone
                if is_async_client:
                    user_timezone = await get_user_timezone(supabase, habit_user_id)
                    user_tz = pytz.timezone(user_timezone)
                    user_now = datetime.now(user_tz)
                    today = user_now.date()
                else:
                    # For sync clients, fall back to UTC (scheduler context)
                    today = date.today()
                
                week_start, week_end = get_week_dates(today, week_start_day)
                
                # Update progress for current week
                await update_github_weekly_progress(
                    supabase=supabase,
                    user_id=habit_user_id,
                    habit_id=habit_id,
                    week_start_date=week_start,
                    weekly_target=weekly_target,
                    week_start_day=week_start_day
                )
                
            except Exception as e:
                logger.error(f"Error updating GitHub habit {habit.get('id')}: {e}")
                continue
        
        logger.info("Completed updating GitHub weekly progress")
        
    except Exception as e:
        logger.error(f"Error updating all GitHub weekly progress: {e}")

async def get_current_week_github_commits(supabase: AsyncClient, user_id: str, week_start_day: int = 0):
    """
    Get current week's GitHub commit count for weekly GitHub habits.
    For weekly GitHub habits, the commit goal is stored in commit_target field.
    
    Args:
        supabase: Supabase client
        user_id: User ID
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
        
    Returns:
        Dict with current_commits, weekly_goal, week_start_date, week_end_date, and habits info
        Returns None if no GitHub integration or no weekly GitHub habits found
    """
    try:
        # Get user's GitHub access token from user_tokens table
        github_result = await supabase.table("user_tokens") \
            .select("github_access_token") \
            .eq("user_id", user_id) \
            .execute()
        
        if not github_result.data or not github_result.data[0].get("github_access_token"):
            logger.warning(f"No GitHub access token found for user {user_id}")
            return None
        
        access_token = github_result.data[0]["github_access_token"]
        
        # Get user's weekly GitHub habits to find the weekly commit goal
        habits_result = await supabase.table("habits") \
            .select("id, commit_target, weekly_target, name") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("habit_type", "github_commits") \
            .eq("is_active", True) \
            .execute()
        
        if not habits_result.data:
            logger.info(f"No weekly GitHub habits found for user {user_id}")
            return None
        
        # For weekly GitHub habits, use commit_target as the weekly goal
        # If multiple habits exist, use the maximum goal
        weekly_goals = []
        habit_info = []
        
        for habit in habits_result.data:
            commit_goal = habit.get("commit_target", 7)  # Default to 7 if not set
            weekly_goals.append(commit_goal)
            habit_info.append({
                "id": habit["id"],
                "name": habit["name"],
                "weekly_goal": commit_goal
            })
        
        max_weekly_goal = max(weekly_goals) if weekly_goals else 7
        
        # Get current week dates using USER'S timezone (not server UTC)
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        user_now = datetime.now(user_tz)
        today = user_now.date()
        
        week_start, week_end = get_week_dates(today, week_start_day)
        
        logger.info(f"GitHub weekly commits for user {user_id} in timezone {user_timezone}: "
                   f"today={today}, week_start={week_start}, week_end={week_end}")
        
        # Get commit count for current week
        start_datetime = datetime.combine(week_start, time.min).replace(tzinfo=timezone.utc)
        end_datetime = datetime.combine(week_end, time.max).replace(tzinfo=timezone.utc)
        
        commit_count = await get_commit_count_with_error_handling(supabase, user_id, start_datetime, end_datetime)
        
        if commit_count is None:
            logger.error(f"Failed to get commit count for user {user_id}")
            return {
                "current_commits": 0,
                "weekly_goal": max_weekly_goal,
                "week_start_date": week_start.isoformat(),
                "week_end_date": week_end.isoformat(),
                "habits": habit_info,
                "error": "Failed to fetch commits from GitHub"
            }
        
        logger.info(f"Current week GitHub commits for user {user_id}: {commit_count}/{max_weekly_goal}")
        
        return {
            "current_commits": commit_count,
            "weekly_goal": max_weekly_goal,
            "week_start_date": week_start.isoformat(),
            "week_end_date": week_end.isoformat(),
            "habits": habit_info,
            "progress_percentage": min(100, (commit_count / max_weekly_goal) * 100) if max_weekly_goal > 0 else 0
        }
        
    except Exception as e:
        logger.error(f"Error getting current week GitHub commits for user {user_id}: {e}")
        return None 