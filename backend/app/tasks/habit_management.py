from datetime import datetime, timedelta, date, time
import pytz
import logging
import json
from supabase import Client
from config.database import get_supabase_client, get_async_supabase_client
from utils.weekly_habits import get_week_dates
from .scheduler_utils import get_user_timezone, check_and_create_penalty_for_habit

# Set up logging
logger = logging.getLogger(__name__)

async def check_deleted_edited_habits_penalties(supabase: Client):
    """
    Check for habits that were deleted or edited today and charge penalties if they were missed.
    This runs at the end of the day to catch any habits that were removed from today's schedule.
    For weekly habits, this runs at the end of the week (Sunday).
    Only processes users at 1 AM in their timezone (when day has truly ended).
    """
    try:
        async_supabase = await get_async_supabase_client()
        utc_now = datetime.now(pytz.UTC)
        # Get all staging records that haven't been applied yet
        staging_result = supabase.table("habit_change_staging") \
            .select("*") \
            .eq("applied", False) \
            .execute()
        
        if not staging_result.data:
            return
        
        # Group by user to avoid duplicate processing
        users_processed = set()
        
        for staging_record in staging_result.data:
            try:
                user_id = staging_record['user_id']
                change_type = staging_record['change_type']
                
                # Skip if we already processed this user in this run
                if user_id in users_processed:
                    continue
                
                # Get user timezone and current time
                user_timezone = get_user_timezone(supabase, user_id)
                user_tz = pytz.timezone(user_timezone)
                user_now = utc_now.astimezone(user_tz)
                today_user = user_now.date()
                
                # Check if this staging record is ready to be processed
                effective_date = datetime.fromisoformat(staging_record['effective_date']).date()
                
                # Only process if the effective date has arrived or passed
                if today_user < effective_date:
                    continue  # Not time yet to process this change
                
                # Only process penalties if it's 1 AM in the user's timezone
                # This ensures the day has truly ended (past midnight) before charging penalties
                if user_now.hour != 1:  # 1 = 1 AM
                    continue
                
                users_processed.add(user_id)
                
                # Get all staging records for this user that are ready to be processed
                user_staging_records = [r for r in staging_result.data 
                                      if r['user_id'] == user_id 
                                      and datetime.fromisoformat(r['effective_date']).date() <= today_user
                                      and not r['applied']]
                
                for record in user_staging_records:
                    # Parse old habit data
                    old_habit_data = json.loads(record['old_habit_data']) if record['old_habit_data'] else None
                    
                    if not old_habit_data:
                        continue
                    
                    habit_id = old_habit_data['id']
                    habit_schedule_type = old_habit_data.get('habit_schedule_type', 'daily')
                    
                    if habit_schedule_type == 'daily':
                        # For daily habits, check if yesterday (the last day before deletion) was a required day
                        yesterday_user = today_user - timedelta(days=1)
                        postgres_weekday = (yesterday_user.weekday() + 1) % 7
                        
                        if record['change_type'] == 'delete':
                            # For deletions, check if yesterday was a required day
                            if postgres_weekday in old_habit_data.get('weekdays', []):
                                await check_and_create_penalty_for_habit(
                                    async_supabase, habit_id, user_id, old_habit_data, yesterday_user, 
                                    f"Habit deleted on required day {yesterday_user}"
                                )
                        elif record['change_type'] == 'update':
                            # For updates, check if yesterday was removed from the schedule
                            new_habit_data = json.loads(record['new_habit_data']) if record['new_habit_data'] else {}
                            old_weekdays = old_habit_data.get('weekdays', [])
                            new_weekdays = new_habit_data.get('weekdays', old_weekdays)
                            
                            # If yesterday was in old schedule but not in new schedule
                            if postgres_weekday in old_weekdays and postgres_weekday not in new_weekdays:
                                await check_and_create_penalty_for_habit(
                                    async_supabase, habit_id, user_id, old_habit_data, yesterday_user,
                                    f"Habit schedule changed, removing {yesterday_user} requirement"
                                )
                    
                    elif habit_schedule_type == 'weekly':
                        # For weekly habits, check if the week is incomplete when deleted
                        if record['change_type'] == 'delete':
                            week_start_day = old_habit_data.get('week_start_day', 0)
                            weekly_target = old_habit_data.get('weekly_target', 1)
                            
                            # Calculate the week that just ended
                            # Since we delete on Sunday (end of week), yesterday would be Saturday (last day of week)
                            yesterday_user = today_user - timedelta(days=1)
                            
                            # Get the week dates for the week that just ended
                            week_start, week_end = get_week_dates(yesterday_user, week_start_day)
                            
                            # Check weekly progress for the completed week
                            progress_result = supabase.table("weekly_habit_progress") \
                                .select("*") \
                                .eq("habit_id", habit_id) \
                                .eq("week_start_date", week_start.isoformat()) \
                                .execute()
                            
                            if progress_result.data:
                                current_progress = progress_result.data[0]
                                current_completions = current_progress['current_completions']
                                target_completions = current_progress['target_completions']
                                
                                # If the week was incomplete, charge penalty for missed completions
                                if current_completions < target_completions:
                                    missed_completions = target_completions - current_completions
                                    
                                    # Create penalty for each missed completion
                                    for i in range(missed_completions):
                                        penalty_data = {
                                            "habit_id": habit_id,
                                            "user_id": user_id,
                                            "recipient_id": old_habit_data.get("recipient_id"),
                                            "amount": old_habit_data.get("penalty_amount", 0),
                                            "penalty_date": week_end.isoformat(),
                                            "is_paid": False,
                                            "reason": f"Weekly habit deleted with incomplete week: {current_completions}/{target_completions} completions"
                                        }
                                        
                                        penalty_result = supabase.table("penalties").insert(penalty_data).execute()
                                        if penalty_result.data:
                                            logger.info(f"Created penalty for weekly habit {habit_id}: missed completion {i+1}/{missed_completions}")
                                
                            else:
                                # No progress record found, charge penalty for full target
                                for i in range(weekly_target):
                                    penalty_data = {
                                        "habit_id": habit_id,
                                        "user_id": user_id,
                                        "recipient_id": old_habit_data.get("recipient_id"),
                                        "amount": old_habit_data.get("penalty_amount", 0),
                                        "penalty_date": week_end.isoformat(),
                                        "is_paid": False,
                                        "reason": f"Weekly habit deleted with no completions: 0/{weekly_target} completions"
                                    }
                                    
                                    penalty_result = supabase.table("penalties").insert(penalty_data).execute()
                                    if penalty_result.data:
                                        logger.info(f"Created penalty for weekly habit {habit_id}: no progress, missed completion {i+1}/{weekly_target}")
                    
                
            except Exception as e:
                logger.error(f"Error processing staging record {staging_record.get('id')}: {e}")
                continue
        
        
    except Exception as e:
        logger.error(f"Error in check_deleted_edited_habits_penalties: {e}")

async def process_habit_notifications():
    """Process due habit notifications and send push notifications"""
    try:
        from config.database import get_async_supabase_client
        from services.habit_notification_scheduler import habit_notification_scheduler
        
        # Properly await the async client
        async_supabase = await get_async_supabase_client()
        
        logger.info("🔔 Starting habit notification processing")
        
        # Process all due notifications
        await habit_notification_scheduler.process_due_notifications(async_supabase)
        
        logger.info("✅ Habit notification processing completed")
        
    except Exception as e:
        logger.error(f"❌ Error processing habit notifications: {e}")

async def cleanup_old_habit_notifications():
    """Clean up old sent habit notifications"""
    try:
        from config.database import get_async_supabase_client
        from services.habit_notification_scheduler import habit_notification_scheduler
        
        # Properly await the async client
        async_supabase = await get_async_supabase_client()
        
        logger.info("🧹 Starting habit notification cleanup")
        
        # Clean up notifications older than 7 days
        await habit_notification_scheduler.cleanup_old_notifications(async_supabase, days_old=7)
        
        logger.info("✅ Habit notification cleanup completed")
        
    except Exception as e:
        logger.error(f"❌ Error cleaning up habit notifications: {e}") 