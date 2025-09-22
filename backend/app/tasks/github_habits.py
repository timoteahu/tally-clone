from datetime import datetime, timedelta, date, time
import pytz
import logging
from supabase import Client
from supabase._async.client import AsyncClient
from utils.weekly_habits import get_week_dates
from .scheduler_utils import get_user_timezone, decrement_habit_streak_local, check_and_create_penalty_for_habit
from utils.recipient_analytics import update_analytics_on_habit_verified

# Set up logging
logger = logging.getLogger(__name__)

async def check_github_habits_for_penalties(supabase: Client, async_supabase: AsyncClient, user_id: str, yesterday_user: date, user_timezone: str):
    """
    Check GitHub commit habits for a user and create penalties if they didn't meet their commit targets.
    """
    try:
        # Get user's GitHub commit habits
        github_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "daily") \
            .eq("habit_type", "github_commits") \
            .eq("is_active", True) \
            .execute()
        
        if not github_habits_result.data:
            return 0  # No GitHub commit habits
        
        # Get user's GitHub token
        token_result = supabase.table("user_tokens") \
            .select("github_access_token") \
            .eq("user_id", user_id) \
            .single() \
            .execute()
        
        if not token_result.data or not token_result.data.get("github_access_token"):
            logger.warning(f"      ⚠️ User {user_id} has GitHub habits but no access token")
            return 0
        
        access_token = token_result.data["github_access_token"]
        penalties_created = 0
        
        for habit in github_habits_result.data:
            try:
                habit_id = habit['id']
                habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                habit_creation_date = habit_created_at.date()
                
                # Use the EXACT same logic as test_github_commits.py UTC version (which works correctly)
                # Force UTC timezone since that's what works correctly
                
                # Get UTC timezone (like timezone_str='UTC' in test script)
                utc_tz = pytz.timezone('UTC')
                
                # Get yesterday's date in UTC timezone (like the test script)
                utc_now = datetime.now(utc_tz)
                yesterday_date = utc_now.date() - timedelta(days=1)
                
                # First-day grace period (using UTC date)
                if habit_creation_date >= yesterday_date:
                    logger.info(f"      ⏭️ GitHub habit {habit_id}: First day grace period")
                    continue
                
                # Check if yesterday was a required day for daily habits (use UTC date)
                postgres_weekday = (yesterday_date.weekday() + 1) % 7
                if postgres_weekday not in habit.get("weekdays", []):
                    logger.info(f"      ⏭️ GitHub habit {habit_id}: Not required on {yesterday_date.strftime('%A')} (UTC)")
                    continue
                
                # Create timezone-aware datetime objects for start and end of yesterday (EXACT test script logic)
                start_local = utc_tz.localize(datetime.combine(yesterday_date, time.min))
                end_local = utc_tz.localize(datetime.combine(yesterday_date, time.max))
                
                # Convert to UTC for GitHub API (GitHub expects UTC timestamps)
                start_utc = start_local.astimezone(pytz.UTC).replace(tzinfo=None)
                end_utc = end_local.astimezone(pytz.UTC).replace(tzinfo=None)
                
                # Get commit count for yesterday
                from utils.github_commits import get_commit_count
                commit_count = await get_commit_count(access_token, start_utc, end_utc) or 0
                commit_target = habit.get('commit_target', 1)
                
                logger.info(f"      📝 GitHub habit {habit_id}: {commit_count} commits on {yesterday_date} (UTC) (target: {commit_target})")
                
                # If commits are below target, create a penalty
                if commit_count < commit_target:
                    # Create penalty using the function that updates analytics
                    await check_and_create_penalty_for_habit(
                        supabase=async_supabase,
                        habit_id=habit_id,
                        user_id=user_id,
                        habit_data=habit,
                        penalty_date=yesterday_date,
                        reason=f"GitHub commits: {commit_count}/{commit_target} (UTC date: {yesterday_date})"
                    )
                    penalties_created += 1
                    logger.info(f"      💸 Created GitHub penalty with analytics update: ${habit.get('penalty_amount', 0):.2f}")
                else:
                    logger.info(f"      ✅ GitHub habit {habit_id}: Target met!")
                    
                    # Update recipient analytics for successful day
                    recipient_id = habit.get('recipient_id')
                    if recipient_id:
                        try:
                            await update_analytics_on_habit_verified(
                                supabase=async_supabase,
                                habit_id=habit_id,
                                recipient_id=recipient_id,
                                verification_date=yesterday_date
                            )
                            logger.info(f"      📊 Updated analytics for GitHub success")
                        except Exception as analytics_error:
                            logger.error(f"      ❌ Error updating analytics for GitHub success: {analytics_error}")
                
            except Exception as e:
                logger.error(f"❌ Error checking GitHub habit {habit.get('id')}: {e}")
                continue
        
        return penalties_created
        
    except Exception as e:
        logger.error(f"❌ Error checking GitHub habits for user {user_id}: {e}")
        return 0

async def check_weekly_github_habits_for_penalties(supabase: Client, async_supabase: AsyncClient, user_id: str, completed_week_start: date, completed_week_end: date):
    """
    Check weekly GitHub habits for a user and create penalties if they didn't meet their weekly commit goals.
    Calls GitHub API directly at penalty time to get accurate commit counts.
    For weekly GitHub habits, commit_target contains the actual weekly commit goal.
    Creates one penalty per missed commit (penalty_amount * missed_commits).
    
    Returns:
        int: Number of penalties created
    """
    try:
        penalties_created = 0
        
        # Get user's weekly GitHub commit habits
        github_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("habit_type", "github_commits") \
            .eq("is_active", True) \
            .execute()
        
        if not github_habits_result.data:
            return 0
        
        # Get user's GitHub access token once for all habits
        token_result = supabase.table("user_tokens") \
            .select("github_access_token") \
            .eq("user_id", user_id) \
            .single() \
            .execute()
        
        if not token_result.data or not token_result.data.get("github_access_token"):
            logger.warning(f"User {user_id} has GitHub habits but no access token")
            # Create penalties for all habits since we can't verify
            for habit in github_habits_result.data:
                habit_id = habit["id"]
                weekly_commit_goal = habit.get("commit_target", 7)
                penalty_amount = habit["penalty_amount"]
                recipient_id = habit.get("recipient_id")
                
                # First week grace period
                habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                habit_creation_date = habit_created_at.date()
                first_week_start, first_week_end = get_week_dates(habit_creation_date, habit.get('week_start_day', 0))
                if completed_week_start == first_week_start:
                    continue  # Skip first week
                
                for i in range(weekly_commit_goal):
                    reason = f"Weekly GitHub habit: missed commit {i+1}/{weekly_commit_goal} for week {completed_week_start} (no GitHub token)"
                    
                    # Check if penalty already exists
                    existing_penalty = supabase.table("penalties") \
                        .select("*") \
                        .eq("habit_id", habit_id) \
                        .eq("penalty_date", completed_week_end.isoformat()) \
                        .eq("reason", reason) \
                        .execute()
                    
                    if not existing_penalty.data:
                        # Create penalty using the function that updates analytics
                        await check_and_create_penalty_for_habit(
                            supabase=async_supabase,
                            habit_id=habit_id,
                            user_id=user_id,
                            habit_data=habit,
                            penalty_date=completed_week_end,
                            reason=reason
                        )
                        penalties_created += 1
                        logger.info(f"✅ Created penalty {i+1}/{weekly_commit_goal} for GitHub habit {habit_id} (no token) with analytics update: ${penalty_amount}")
            return penalties_created
        
        access_token = token_result.data["github_access_token"]
        
        for habit in github_habits_result.data:
            habit_id = habit["id"]
            weekly_commit_goal = habit.get("commit_target", 7)  # Default to 7 if not set
            penalty_amount = habit["penalty_amount"]
            recipient_id = habit.get("recipient_id")
            
            # First week grace period - no penalties during the first week after habit creation
            habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
            habit_creation_date = habit_created_at.date()
            
            # Check if this completed week is the first week
            habit_week_start_day = habit.get('week_start_day', 0)
            first_week_start, first_week_end = get_week_dates(habit_creation_date, habit_week_start_day)
            
            # If the completed week is the first week, skip penalties (grace period)
            if completed_week_start == first_week_start:
                logger.info(f"GitHub weekly habit {habit_id}: First week grace period (created {habit_creation_date})")
                continue
            
            logger.info(f"Checking GitHub weekly habit {habit_id} for week {completed_week_start} to {completed_week_end}, goal: {weekly_commit_goal} commits")
            
            try:
                # Call GitHub API directly for the completed week
                # Follow the EXACT UTC pattern from test_github_commits.py
                
                # Use UTC timezone (like timezone_str='UTC' in test script)
                utc_tz = pytz.timezone('UTC')
                
                # completed_week_start and completed_week_end are dates, treat them as UTC dates
                # Create timezone-aware datetime objects (EXACT test script logic)
                start_local = utc_tz.localize(datetime.combine(completed_week_start, time.min))
                end_local = utc_tz.localize(datetime.combine(completed_week_end, time.max))
                
                # Convert to UTC for GitHub API (GitHub expects UTC timestamps)
                start_utc = start_local.astimezone(pytz.UTC).replace(tzinfo=None)
                end_utc = end_local.astimezone(pytz.UTC).replace(tzinfo=None)
                
                from utils.github_commits import get_commit_count
                actual_commits = await get_commit_count(access_token, start_utc, end_utc)
                
                if actual_commits is None:
                    logger.error(f"GitHub habit {habit_id}: Failed to fetch commits from GitHub API")
                    # Create penalties for all commits since we can't verify
                    actual_commits = 0  # Assume 0 commits on API failure
                
                logger.info(f"GitHub habit {habit_id}: {actual_commits}/{weekly_commit_goal} commits for week {completed_week_start}")
                
                # Calculate missed commits and create penalties
                if actual_commits >= weekly_commit_goal:
                    logger.info(f"GitHub habit {habit_id}: Goal met! ({actual_commits}/{weekly_commit_goal} commits)")
                    
                    # Update recipient analytics for successful week
                    recipient_id = habit.get('recipient_id')
                    if recipient_id:
                        try:
                            from utils.recipient_analytics import update_analytics_on_weekly_penalty_created
                            
                            # For weekly GitHub success, track based on commit target
                            await update_analytics_on_weekly_penalty_created(
                                supabase=async_supabase,
                                habit_id=habit_id,
                                recipient_id=recipient_id,
                                penalty_amount=0,  # No penalty for success
                                penalty_date=completed_week_end,
                                completions=weekly_commit_goal,  # Met the target
                                target=weekly_commit_goal,  # Target commits
                                missed_count=0  # No failures
                            )
                            logger.info(f"📊 Updated analytics for weekly GitHub success")
                        except Exception as analytics_error:
                            logger.error(f"❌ Error updating analytics for weekly GitHub success: {analytics_error}")
                else:
                    missed_commits = weekly_commit_goal - actual_commits
                    logger.info(f"GitHub habit {habit_id}: {missed_commits} commits missed, creating penalties")
                    
                    # Create one penalty per missed commit
                    for i in range(missed_commits):
                        reason = f"Weekly GitHub habit: missed commit {i+1}/{missed_commits} for week {completed_week_start} ({actual_commits}/{weekly_commit_goal} commits)"
                        
                        # Check if penalty already exists
                        existing_penalty = supabase.table("penalties") \
                            .select("*") \
                            .eq("habit_id", habit_id) \
                            .eq("penalty_date", completed_week_end.isoformat()) \
                            .eq("reason", reason) \
                            .execute()
                        
                        if not existing_penalty.data:
                            # Create penalty using the function that updates analytics
                            await check_and_create_penalty_for_habit(
                                supabase=async_supabase,
                                habit_id=habit_id,
                                user_id=user_id,
                                habit_data=habit,
                                penalty_date=completed_week_end,
                                reason=reason
                            )
                            penalties_created += 1
                            logger.info(f"✅ Created penalty {i+1}/{missed_commits} for GitHub habit {habit_id} with analytics update: ${penalty_amount}")
                        else:
                            logger.info(f"Penalty {i+1}/{missed_commits} already exists for GitHub habit {habit_id}")
                    
                    if missed_commits > 0:
                        total_penalty = missed_commits * penalty_amount
                        logger.info(f"📊 Total penalty for GitHub habit {habit_id}: {missed_commits} × ${penalty_amount} = ${total_penalty}")
                
            except Exception as e:
                logger.error(f"Error checking GitHub habit {habit_id}: {e}")
                # Create penalties for all commits since we couldn't verify
                for i in range(weekly_commit_goal):
                    reason = f"Weekly GitHub habit: missed commit {i+1}/{weekly_commit_goal} for week {completed_week_start} (error)"
                    
                    # Check if penalty already exists
                    existing_penalty = supabase.table("penalties") \
                        .select("*") \
                        .eq("habit_id", habit_id) \
                        .eq("penalty_date", completed_week_end.isoformat()) \
                        .eq("reason", reason) \
                        .execute()
                    
                    if not existing_penalty.data:
                        # Create penalty using the function that updates analytics
                        await check_and_create_penalty_for_habit(
                            supabase=async_supabase,
                            habit_id=habit_id,
                            user_id=user_id,
                            habit_data=habit,
                            penalty_date=completed_week_end,
                            reason=reason
                        )
                        penalties_created += 1
                        logger.info(f"✅ Created penalty {i+1}/{weekly_commit_goal} for GitHub habit {habit_id} (error) with analytics update: ${penalty_amount}")
                        
    except Exception as e:
        logger.error(f"❌ Error checking weekly GitHub habits for penalties: {e}")
        return 0
    
    return penalties_created

async def update_github_weekly_progress_task():
    """Update GitHub weekly progress for all users with active GitHub weekly habits"""
    try:
        from config.database import get_async_supabase_client
        from utils.github_commits import update_all_github_weekly_progress
        
        # Get the async client properly
        async_supabase = await get_async_supabase_client()
        
        logger.info("🔄 Starting GitHub weekly progress update")
        
        # Update all GitHub weekly habits progress
        await update_all_github_weekly_progress(async_supabase)
        
        logger.info("✅ GitHub weekly progress update completed")
        
    except Exception as e:
        logger.error(f"❌ Error updating GitHub weekly progress: {e}") 