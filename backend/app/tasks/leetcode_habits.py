from datetime import datetime, timedelta, date, time
import pytz
import logging
from supabase import Client
from supabase._async.client import AsyncClient
from utils.weekly_habits import get_week_dates
from .scheduler_utils import decrement_habit_streak_local, check_and_create_penalty_for_habit
from utils.timezone_utils import get_user_timezone
from utils.recipient_analytics import update_analytics_on_habit_verified, update_analytics_on_weekly_penalty_created
from utils.leetcode_habits import get_leetcode_problems_for_date, get_weekly_problems_solved

# Set up logging
logger = logging.getLogger(__name__)

async def check_leetcode_habits_for_penalties(supabase: Client, async_supabase: AsyncClient, user_id: str, yesterday_user: date):
    """
    Check LeetCode habits for a user and create penalties if they didn't meet their problem-solving targets.
    """
    try:
        # Get user's LeetCode habits
        leetcode_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "daily") \
            .eq("habit_type", "leetcode") \
            .eq("is_active", True) \
            .execute()
        
        if not leetcode_habits_result.data:
            return 0  # No LeetCode habits
        
        # Get user's LeetCode username
        token_result = supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .single() \
            .execute()
        
        if not token_result.data or not token_result.data.get("leetcode_username"):
            logger.warning(f"      ⚠️ User {user_id} has LeetCode habits but no connected account")
            return 0
        
        leetcode_username = token_result.data["leetcode_username"]
        penalties_created = 0
        
        for habit in leetcode_habits_result.data:
            try:
                habit_id = habit['id']
                habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                habit_creation_date = habit_created_at.date()
                
                # First-day grace period
                if habit_creation_date >= yesterday_user:
                    logger.info(f"      ⏭️ LeetCode habit {habit_id}: First day grace period")
                    continue
                
                # Check if yesterday was a required day for daily habits
                postgres_weekday = (yesterday_user.weekday() + 1) % 7
                if postgres_weekday not in habit.get("weekdays", []):
                    logger.info(f"      ⏭️ LeetCode habit {habit_id}: Not required on {yesterday_user.strftime('%A')}")
                    continue
                
                # Get problems solved yesterday
                problems_solved = await get_leetcode_problems_for_date(async_supabase, user_id, yesterday_user)
                if problems_solved is None:
                    logger.error(f"      ❌ Failed to get LeetCode problems for habit {habit_id}")
                    problems_solved = 0
                
                problems_target = habit['commit_target']  # LeetCode daily targets are stored in commit_target
                
                logger.info(f"      📝 LeetCode habit {habit_id}: {problems_solved} problems on {yesterday_user} (target: {problems_target})")
                
                # If problems solved are below target, create a penalty
                if problems_solved < problems_target:
                    # Create penalty using the function that updates analytics
                    await check_and_create_penalty_for_habit(
                        supabase=async_supabase,
                        habit_id=habit_id,
                        user_id=user_id,
                        habit_data=habit,
                        penalty_date=yesterday_user,
                        reason=f"LeetCode problems: {problems_solved}/{problems_target} on {yesterday_user}"
                    )
                    penalties_created += 1
                    logger.info(f"      💸 Created LeetCode penalty with analytics update: ${habit.get('penalty_amount', 0):.2f}")
                else:
                    logger.info(f"      ✅ LeetCode habit {habit_id}: Target met!")
                    
                    # Update recipient analytics for successful day
                    recipient_id = habit.get('recipient_id')
                    if recipient_id:
                        try:
                            await update_analytics_on_habit_verified(
                                supabase=async_supabase,
                                habit_id=habit_id,
                                recipient_id=recipient_id,
                                verification_date=yesterday_user
                            )
                            logger.info(f"      📊 Updated analytics for LeetCode success")
                        except Exception as analytics_error:
                            logger.error(f"      ❌ Error updating analytics for LeetCode success: {analytics_error}")
                
            except Exception as e:
                logger.error(f"❌ Error checking LeetCode habit {habit.get('id')}: {e}")
                continue
        
        return penalties_created
        
    except Exception as e:
        logger.error(f"❌ Error checking LeetCode habits for user {user_id}: {e}")
        return 0

async def check_weekly_leetcode_habits_for_penalties(supabase: Client, async_supabase: AsyncClient, user_id: str, completed_week_start: date, completed_week_end: date):
    """
    Check weekly LeetCode habits for a user and create penalties if they didn't meet their weekly problem-solving goals.
    For weekly LeetCode habits, commit_target contains the weekly problems goal.
    Creates one penalty for the entire week if target not met.
    
    Returns:
        int: Number of penalties created
    """
    try:
        penalties_created = 0
        
        # Get user's weekly LeetCode habits
        leetcode_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("habit_type", "leetcode") \
            .eq("is_active", True) \
            .execute()
        
        if not leetcode_habits_result.data:
            return 0
        
        # Get user's LeetCode username
        token_result = supabase.table("user_tokens") \
            .select("leetcode_username") \
            .eq("user_id", user_id) \
            .single() \
            .execute()
        
        if not token_result.data or not token_result.data.get("leetcode_username"):
            logger.warning(f"User {user_id} has LeetCode habits but no connected account")
            # Create penalties for all habits since we can't verify
            for habit in leetcode_habits_result.data:
                habit_id = habit["id"]
                weekly_problems_goal = habit["commit_target"]  # LeetCode weekly targets are stored in commit_target
                penalty_amount = habit["penalty_amount"]
                
                # First week grace period
                habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                habit_creation_date = habit_created_at.date()
                first_week_start, first_week_end = get_week_dates(habit_creation_date, habit.get('week_start_day', 0))
                if completed_week_start == first_week_start:
                    continue  # Skip first week
                
                reason = f"Weekly LeetCode habit: 0/{weekly_problems_goal} problems for week {completed_week_start} (no account connected)"
                
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
                    logger.info(f"✅ Created penalty for LeetCode habit {habit_id} (no account) with analytics update: ${penalty_amount}")
            return penalties_created
        
        leetcode_username = token_result.data["leetcode_username"]
        
        # Get user's timezone
        user_tz_str = await get_user_timezone(async_supabase, user_id)
        
        for habit in leetcode_habits_result.data:
            habit_id = habit["id"]
            weekly_problems_goal = habit.get("commit_target") or 3  # Default to 3 problems/week if None or missing
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
                logger.info(f"LeetCode weekly habit {habit_id}: First week grace period (created {habit_creation_date})")
                continue
            
            logger.info(f"Checking LeetCode weekly habit {habit_id} for week {completed_week_start} to {completed_week_end}, goal: {weekly_problems_goal} problems")
            
            try:
                # Get problems solved for the completed week
                actual_problems = await get_weekly_problems_solved(
                    leetcode_username, 
                    completed_week_start, 
                    completed_week_end, 
                    user_tz_str
                )
                
                logger.info(f"LeetCode habit {habit_id}: {actual_problems}/{weekly_problems_goal} problems for week {completed_week_start}")
                
                # Check if goal was met
                if actual_problems >= weekly_problems_goal:
                    logger.info(f"LeetCode habit {habit_id}: Goal met! ({actual_problems}/{weekly_problems_goal} problems)")
                    
                    # Update recipient analytics for successful week
                    if recipient_id:
                        try:
                            await update_analytics_on_weekly_penalty_created(
                                supabase=async_supabase,
                                habit_id=habit_id,
                                recipient_id=recipient_id,
                                penalty_amount=0,  # No penalty for success
                                penalty_date=completed_week_end,
                                completions=actual_problems,  # Actual problems solved
                                target=weekly_problems_goal,  # Target problems
                                missed_count=0  # No failures
                            )
                            logger.info(f"📊 Updated analytics for weekly LeetCode success")
                        except Exception as analytics_error:
                            logger.error(f"❌ Error updating analytics for weekly LeetCode success: {analytics_error}")
                else:
                    missed_problems = weekly_problems_goal - actual_problems
                    logger.info(f"LeetCode habit {habit_id}: {missed_problems} problems short of goal")
                    
                    reason = f"Weekly LeetCode habit: {actual_problems}/{weekly_problems_goal} problems for week {completed_week_start}"
                    
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
                        logger.info(f"✅ Created penalty for LeetCode habit {habit_id} with analytics update: ${penalty_amount}")
                    else:
                        logger.info(f"Penalty already exists for LeetCode habit {habit_id}")
                
            except Exception as e:
                logger.error(f"Error checking LeetCode habit {habit_id}: {e}")
                # Create penalty since we couldn't verify
                reason = f"Weekly LeetCode habit: unable to verify for week {completed_week_start} (error)"
                
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
                    logger.info(f"✅ Created penalty for LeetCode habit {habit_id} (error) with analytics update: ${penalty_amount}")
                        
    except Exception as e:
        logger.error(f"❌ Error checking weekly LeetCode habits for penalties: {e}")
        return 0
    
    return penalties_created

async def update_leetcode_weekly_progress_task():
    """Update LeetCode weekly progress for all users with active LeetCode weekly habits"""
    try:
        from config.database import get_async_supabase_client
        from utils.leetcode_habits import update_all_leetcode_weekly_progress
        
        # Get the async client properly
        async_supabase = await get_async_supabase_client()
        
        logger.info("🔄 Starting LeetCode weekly progress update")
        
        # Update all LeetCode weekly habits progress
        await update_all_leetcode_weekly_progress(async_supabase)
        
        logger.info("✅ LeetCode weekly progress update completed")
        
    except Exception as e:
        logger.error(f"❌ Error updating LeetCode weekly progress: {e}")