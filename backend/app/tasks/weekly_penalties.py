from datetime import datetime, timedelta, date
import pytz
import logging
from supabase import Client
from config.database import get_supabase_client, get_async_supabase_client
from utils.weekly_habits import get_week_dates
from .scheduler_utils import get_user_timezone, decrement_habit_streak_local, check_and_create_penalty_for_habit

# Set up logging
logger = logging.getLogger(__name__)

async def check_weekly_penalties():
    """
    Check weekly habits for missed completions and create penalties.
    This runs with timing restrictions to handle different week start days and timezones.
    
    Note: Payment processing for unpaid penalties is now handled separately by 
    check_and_charge_unpaid_penalties() which runs every hour.
    """
    supabase = get_supabase_client()
    async_supabase = await get_async_supabase_client()
    utc_now = datetime.now(pytz.UTC)
    
    logger.info(f"🔄 Starting weekly habit penalty check at {utc_now} UTC")
    
    try:
        # Check weekly habits for missed completions and create penalties
        weekly_habits = supabase.table("habits") \
            .select("*, users!habits_user_id_fkey!inner(timezone)") \
            .eq("habit_schedule_type", "weekly") \
            .eq("is_active", True) \
            .not_.in_("habit_type", ["league_of_legends", "valorant", "github_commits"]) \
            .execute()
        
        if not weekly_habits.data:
            logger.info("📭 No weekly habits found")
            return
        
        logger.info(f"📋 Found {len(weekly_habits.data)} weekly habits to check")
        
        users_processed_weekly = set()
        weekly_penalty_count = 0
        
        for habit in weekly_habits.data:
            user_id = habit['user_id']
            
            # Skip if we already processed this user for weekly habits
            if user_id in users_processed_weekly:
                continue
            users_processed_weekly.add(user_id)
            
            # Get user timezone - USE SAME METHOD AS ENDPOINTS
            user_timezone = get_user_timezone(supabase, user_id)
            user_tz = pytz.timezone(user_timezone)
            user_now = datetime.now(user_tz)  # Changed from utc_now.astimezone(user_tz)
            today_user = user_now.date()
            
            logger.info(f"👤 User {user_id}: {user_timezone}, local time: {user_now.strftime('%a %H:%M')}")
            
            # Get all weekly habits for this user
            user_weekly_habits = [h for h in weekly_habits.data if h['user_id'] == user_id]
            
            # Pre-fetch all weekly_habit_progress for all user habits to avoid N+1
            if user_weekly_habits:
                # Calculate all potential week start dates we need to check
                progress_queries = []
                for habit in user_weekly_habits:
                    habit_week_start_day = habit.get('week_start_day', 0)
                    week_start, week_end = get_week_dates(today_user, habit_week_start_day)
                    # Only need progress for habits where today is the day after week_end
                    if today_user == week_end + timedelta(days=1):
                        yesterday = today_user - timedelta(days=1)
                        completed_week_start, _ = get_week_dates(yesterday, habit_week_start_day)
                        progress_queries.append({
                            'habit_id': habit['id'],
                            'week_start_date': completed_week_start.isoformat()
                        })
                
                # Batch fetch all progress records
                progress_by_habit = {}
                if progress_queries:
                    # Extract unique week start dates and habit IDs
                    habit_ids = list(set(q['habit_id'] for q in progress_queries))
                    week_start_dates = list(set(q['week_start_date'] for q in progress_queries))
                    
                    progress_result = supabase.table("weekly_habit_progress") \
                        .select("*") \
                        .in_("habit_id", habit_ids) \
                        .in_("week_start_date", week_start_dates) \
                        .execute()
                    
                    # Create map for quick lookup: (habit_id, week_start_date) -> progress
                    if progress_result.data:
                        for progress in progress_result.data:
                            key = (progress['habit_id'], progress['week_start_date'])
                            progress_by_habit[key] = progress
            
            for weekly_habit in user_weekly_habits:
                try:
                    habit_week_start_day = weekly_habit.get('week_start_day', 0)
                    
                    # Only process at the end of the week (when week transitions)
                    # Check if today is the last day of the week for this habit
                    week_start, week_end = get_week_dates(today_user, habit_week_start_day)
                    
                    # Only process if today is the day after week_end (start of new week)
                    if today_user != week_end + timedelta(days=1):
                        continue
                    
                    # Only process once per day at the right hour (early morning)
                    if user_now.hour != 1:  # 1 AM
                        continue
                    
                    # Get the week that just ended
                    yesterday = today_user - timedelta(days=1)
                    completed_week_start, completed_week_end = get_week_dates(yesterday, habit_week_start_day)
                    
                    # First week grace period - no penalties during the first week after habit creation
                    habit_created_at = datetime.fromisoformat(weekly_habit['created_at'].replace('Z', '+00:00'))
                    habit_creation_date = habit_created_at.date()
                    first_week_start, first_week_end = get_week_dates(habit_creation_date, habit_week_start_day)
                    
                    # If the completed week is the first week, skip penalties (grace period)
                    if completed_week_start == first_week_start:
                        logger.info(f"Weekly habit {weekly_habit['id']}: First week grace period (created {habit_creation_date})")
                        continue
                    
                    logger.info(f"   ✅ Processing weekly habit {weekly_habit['id']} at week end")
                    logger.info(f"     📅 Completed week: {completed_week_start} to {completed_week_end}")
                    
                    # Check progress for the completed week using pre-fetched data
                    progress_key = (weekly_habit['id'], completed_week_start.isoformat())
                    current_progress = progress_by_habit.get(progress_key) if 'progress_by_habit' in locals() else None
                    
                    if current_progress:
                        missed_count = max(0, current_progress['target_completions'] - current_progress['current_completions'])
                        logger.info(f"     📊 Progress: {current_progress['current_completions']}/{current_progress['target_completions']}")
                    else:
                        # No progress record found, all completions were missed
                        missed_count = weekly_habit['weekly_target']
                        logger.info(f"     📊 No progress found, missed all {missed_count} completions")
                    
                    if missed_count > 0:
                        # Create penalty for missed completions
                        penalty_amount = weekly_habit['penalty_amount'] * missed_count
                        
                        # Create penalty
                        penalty_data = {
                            "habit_id": weekly_habit['id'],
                            "user_id": user_id,
                            "recipient_id": weekly_habit.get('recipient_id'),
                            "amount": penalty_amount,
                            "penalty_date": completed_week_end.isoformat(),
                            "is_paid": False,
                            "reason": f"Weekly habit: missed {missed_count} completions for week {completed_week_start} to {completed_week_end}"
                        }
                        
                        supabase.table("penalties").insert(penalty_data).execute()
                        weekly_penalty_count += 1
                        
                        # Update recipient analytics with proper weekly tracking
                        recipient_id = weekly_habit.get('recipient_id')
                        if recipient_id:
                            try:
                                from utils.recipient_analytics import update_analytics_on_weekly_penalty_created
                                
                                # Get actual completions from progress or default to 0
                                actual_completions = 0
                                if current_progress:
                                    actual_completions = current_progress['current_completions']
                                
                                await update_analytics_on_weekly_penalty_created(
                                    supabase=async_supabase,
                                    habit_id=weekly_habit['id'],
                                    recipient_id=recipient_id,
                                    penalty_amount=penalty_amount,
                                    penalty_date=completed_week_end,
                                    completions=actual_completions,
                                    target=weekly_habit['weekly_target'],
                                    missed_count=missed_count
                                )
                                logger.info(f"     📊 Updated analytics: {actual_completions}/{weekly_habit['weekly_target']} completions")
                            except Exception as e:
                                logger.error(f"     ❌ Error updating recipient analytics: {e}")
                        
                        # Decrement the streak when a weekly penalty is created
                        await decrement_habit_streak_local(async_supabase, weekly_habit["id"])
                        
                        logger.info(f"     💸 Created weekly penalty with proper analytics: ${penalty_amount} for {missed_count} missed completions")
                    else:
                        logger.info(f"     ✅ Weekly habit completed successfully")
                
                except Exception as e:
                    logger.error(f"Error processing weekly habit {weekly_habit.get('id')}: {e}")
                    continue
            
            # After processing regular weekly habits, check weekly gaming habits
            logger.info(f"\n🎮 Checking weekly gaming habits for user {user_id}...")
            yesterday = today_user - timedelta(days=1)
            
            # Get all possible week ranges for yesterday (different habits may have different week_start_days)
            for week_start_day in range(7):  # Check all possible week start days
                week_start, week_end = get_week_dates(yesterday, week_start_day)
                
                # Only check if yesterday was the last day of a week
                if yesterday == week_end:
                    from .gaming_habits import check_weekly_gaming_habits_for_penalties
                    gaming_penalties = await check_weekly_gaming_habits_for_penalties(
                        supabase, async_supabase, user_id, week_start, week_end
                    )
                    if gaming_penalties > 0:
                        logger.info(f"🎮 Created {gaming_penalties} weekly gaming penalties")
                        weekly_penalty_count += gaming_penalties
                    
                    # Also check weekly GitHub habits for this completed week
                    from .github_habits import check_weekly_github_habits_for_penalties
                    github_penalties = await check_weekly_github_habits_for_penalties(
                        supabase, async_supabase, user_id, week_start, week_end
                    )
                    if github_penalties > 0:
                        logger.info(f"📝 Created {github_penalties} weekly GitHub penalties")
                        weekly_penalty_count += github_penalties
                    
                    # Check weekly LeetCode habits for this completed week
                    from .leetcode_habits import check_weekly_leetcode_habits_for_penalties
                    leetcode_penalties = await check_weekly_leetcode_habits_for_penalties(
                        supabase, async_supabase, user_id, week_start, week_end
                    )
                    if leetcode_penalties > 0:
                        logger.info(f"🧩 Created {leetcode_penalties} weekly LeetCode penalties")
                        weekly_penalty_count += leetcode_penalties
        
        logger.info(f"📊 Weekly habit penalty summary:")
        logger.info(f"   • Users processed: {len(users_processed_weekly)}")
        logger.info(f"   • Weekly penalties created: {weekly_penalty_count}")
        logger.info("💡 Note: Payment processing for these penalties will be handled by the hourly payment task")
        
    except Exception as e:
        logger.error(f"Error in check_weekly_penalties: {e}")
        raise 