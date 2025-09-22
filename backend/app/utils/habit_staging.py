from datetime import datetime, date, timedelta, timezone
from supabase import Client
from config.database import get_supabase_client
import json
import pytz
import logging

logger = logging.getLogger(__name__)

def get_user_timezone(supabase: Client, user_id: str) -> str:
    """Get user's timezone from the database"""
    user = supabase.table("users").select("timezone").eq("id", user_id).execute()
    if not user.data:
        return "UTC"
    
    timezone = user.data[0]["timezone"]
    
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
    if timezone in timezone_mapping:
        timezone = timezone_mapping[timezone]
    
    # Validate the timezone exists in pytz
    try:
        pytz.timezone(timezone)
        return timezone
    except pytz.exceptions.UnknownTimeZoneError:
        print(f"Unknown timezone: {timezone}, falling back to UTC")
        return "UTC"

def get_localized_datetime(supabase: Client, user_id: str) -> datetime:
    """Get current datetime in user's timezone"""
    timezone = get_user_timezone(supabase, user_id)
    return datetime.now(pytz.timezone(timezone))

async def process_staged_habit_changes():
    """
    Process all staged habit changes that should take effect today in users' timezones.
    This should be run daily to apply scheduled habit changes.
    """
    supabase = get_supabase_client()
    
    try:
        # Get all unprocessed staged changes
        pending_changes = supabase.table("habit_change_staging") \
            .select("*") \
            .eq("applied", False) \
            .execute()
        
        if not pending_changes.data:
            logger.info("No pending habit changes to process")
            return
        
        logger.info(f"Found {len(pending_changes.data)} pending habit changes to process")
        
        processed_count = 0
        error_count = 0
        
        for change in pending_changes.data:
            try:
                user_id = change['user_id']
                user_timezone = change['user_timezone']
                effective_date = datetime.fromisoformat(change['effective_date']).date()
                
                # Get current date in user's timezone
                tz = pytz.timezone(user_timezone)
                user_now = datetime.now(tz)
                user_today = user_now.date()
                
                # Check if it's time to apply this change
                if user_today >= effective_date:
                    success = await apply_staged_change(supabase, change)
                    if success:
                        processed_count += 1
                        logger.info(f"Applied {change['change_type']} for habit {change['habit_id']}")
                    else:
                        error_count += 1
                        logger.error(f"Failed to apply {change['change_type']} for habit {change['habit_id']}")
                
            except Exception as e:
                error_count += 1
                logger.error(f"Error processing staged change {change['id']}: {e}")
        
        logger.info(f"Processed {processed_count} habit changes, {error_count} errors")
        
    except Exception as e:
        logger.error(f"Error in process_staged_habit_changes: {e}")

async def apply_staged_change(supabase: Client, change: dict) -> bool:
    """
    Apply a single staged habit change (update or delete).
    
    Args:
        supabase: Database client
        change: The staged change record
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        change_type = change['change_type']
        habit_id = change['habit_id']
        user_id = change['user_id']
        
        if change_type == 'delete':
            # Get the habit data before deletion to check for recipient
            habit_result = supabase.table("habits") \
                .select("recipient_id, user_id") \
                .eq("id", habit_id) \
                .execute()
            
            recipient_id = None
            if habit_result.data:
                recipient_id = habit_result.data[0].get('recipient_id')
            
            # SOFT DELETE: Set is_active = false and completed_at timestamp
            # This preserves referential integrity with penalties, analytics, etc.
            result = supabase.table("habits") \
                .update({
                    "is_active": False,
                    "completed_at": datetime.now(timezone.utc).isoformat()
                }) \
                .eq("id", habit_id) \
                .execute()
            
            if result.data:  # UPDATE returns the updated records
                logger.info(f"Soft deleted habit {habit_id} (set is_active = false)")
                success = True
            else:
                logger.error(f"Failed to soft delete habit {habit_id}")
                success = False
                
        elif change_type == 'update':
            # Apply the staged updates
            new_habit_data = json.loads(change['new_habit_data'])
            
            # Remove fields that shouldn't be updated directly
            update_data = new_habit_data.copy()
            fields_to_exclude = ['id', 'user_id', 'created_at']
            for field in fields_to_exclude:
                update_data.pop(field, None)
            
            # VALIDATE AND CLEAN DATA to prevent constraint violations
            habit_schedule_type = update_data.get('habit_schedule_type', 'daily')
            
            logger.info(f"Applying habit update for {habit_id}: schedule_type={habit_schedule_type}")
            logger.info(f"Update data before validation: weekdays={update_data.get('weekdays')}, weekly_target={update_data.get('weekly_target')}")
            
            # Apply constraint validation logic
            if habit_schedule_type == 'daily':
                # Daily habits: weekdays must be non-empty array, weekly_target must be null
                weekdays = update_data.get('weekdays')
                if not weekdays or (isinstance(weekdays, list) and len(weekdays) == 0):
                    # Set default weekdays if empty or null
                    update_data['weekdays'] = [0, 1, 2, 3, 4, 5, 6]  # All days
                    logger.info(f"Fixed empty weekdays for daily habit: set to all days")
                
                # Remove ALL weekly-specific fields for daily habits
                weekly_fields_to_remove = ['weekly_target', 'week_start_day']
                for field in weekly_fields_to_remove:
                    if field in update_data:
                        del update_data[field]
                        logger.info(f"Removed {field} from daily habit update")
                
                # Set weekly fields explicitly to NULL to ensure constraint compliance
                update_data['weekly_target'] = None
                update_data['week_start_day'] = None
                    
            elif habit_schedule_type == 'weekly':
                # Weekly habits: weekdays must be null, weekly_target must be > 0
                update_data['weekdays'] = None
                
                weekly_target = update_data.get('weekly_target')
                if not weekly_target or weekly_target <= 0:
                    update_data['weekly_target'] = 1  # Default to 1
                    logger.info(f"Fixed invalid weekly_target for weekly habit: set to 1")
                
                # Set week_start_day to 0 if not provided
                if 'week_start_day' not in update_data or update_data['week_start_day'] is None:
                    update_data['week_start_day'] = 0
                    logger.info(f"Set week_start_day to 0 for weekly habit")
                    
            elif habit_schedule_type == 'one_time':
                # One-time habits: both weekdays and weekly_target must be null
                update_data['weekdays'] = None
                update_data['weekly_target'] = None
                update_data['week_start_day'] = None
                logger.info(f"Cleaned one_time habit data")
            
            logger.info(f"Update data after validation: weekdays={update_data.get('weekdays')}, weekly_target={update_data.get('weekly_target')}")
            
            # Check if recipient changed (affects friends filtering)
            old_habit_data = json.loads(change.get('old_habit_data', '{}'))
            old_recipient = old_habit_data.get('recipient_id')
            new_recipient = update_data.get('recipient_id')
            recipient_changed = old_recipient != new_recipient
            
            # Update the habit
            try:
                result = supabase.table("habits") \
                    .update(update_data) \
                    .eq("id", habit_id) \
                    .eq("is_active", True) \
                    .execute()
            except Exception as db_error:
                error_str = str(db_error)
                if "valid_habit_schedule_data" in error_str:
                    logger.error(f"Database constraint violation for habit {habit_id}: {error_str}")
                    logger.error(f"Update data that failed: {update_data}")
                    logger.error(f"This indicates the data validation logic needs to be improved")
                    
                    # Try to fix the data and retry once
                    logger.info(f"Attempting to fix constraint violation data for habit {habit_id}")
                    
                    # Apply more aggressive data cleaning
                    if update_data.get('habit_schedule_type') == 'daily':
                        # For daily habits, ensure ALL weekly fields are NULL
                        update_data['weekly_target'] = None
                        update_data['week_start_day'] = None
                        update_data['commit_target'] = None if update_data.get('habit_type') != 'github_commits' else update_data.get('commit_target')
                        
                        # Ensure weekdays is not null/empty
                        if not update_data.get('weekdays'):
                            update_data['weekdays'] = [0, 1, 2, 3, 4, 5, 6]
                    
                    elif update_data.get('habit_schedule_type') == 'weekly':
                        # For weekly habits, ensure weekdays is NULL and weekly_target is valid
                        update_data['weekdays'] = None
                        if not update_data.get('weekly_target') or update_data.get('weekly_target') <= 0:
                            update_data['weekly_target'] = 1
                        if update_data.get('week_start_day') is None:
                            update_data['week_start_day'] = 0
                    
                    elif update_data.get('habit_schedule_type') == 'one_time':
                        # For one_time habits, ensure both fields are NULL
                        update_data['weekdays'] = None
                        update_data['weekly_target'] = None
                        update_data['week_start_day'] = None
                    
                    logger.info(f"Retrying with fixed data: {update_data}")
                    
                    try:
                        result = supabase.table("habits") \
                            .update(update_data) \
                            .eq("id", habit_id) \
                            .eq("is_active", True) \
                            .execute()
                        logger.info(f"Successfully applied fix for constraint violation on habit {habit_id}")
                    except Exception as retry_error:
                        logger.error(f"Retry also failed for habit {habit_id}: {retry_error}")
                        raise retry_error
                else:
                    logger.error(f"Database error updating habit {habit_id}: {error_str}")
                    raise db_error
            
            if result.data:
                logger.info(f"Updated habit {habit_id}")
                
                # If recipient changed, this might affect friends filtering
                if recipient_changed:
                    try:
                        # Check if user is not premium and might be affected by the unique recipients rule
                        user_result = supabase.table("users").select("ispremium").eq("id", user_id).execute()
                        is_premium = user_result.data and user_result.data[0].get("ispremium", False)
                        
                        if not is_premium:
                            logger.info(f"User {user_id} changed recipient from {old_recipient} to {new_recipient} - friends filtering may be affected")
                        
                    except Exception as e:
                        logger.warning(f"Error checking recipient availability after habit update: {e}")
                        # Don't fail the update if we can't update friends filtering
                
                success = True
            else:
                logger.error(f"Failed to update habit {habit_id}")
                success = False
        else:
            logger.error(f"Unknown change type: {change_type}")
            success = False
        
        if success:
            # Mark the staged change as applied
            supabase.table("habit_change_staging") \
                .update({"applied": True}) \
                .eq("id", change['id']) \
                .execute()
        
        return success
        
    except Exception as e:
        logger.error(f"Error applying staged change {change['id']}: {e}")
        return False

async def cleanup_old_staged_changes(days_old: int = 30):
    """
    Clean up old staged changes that have been applied or are very old.
    
    Args:
        days_old: Remove changes older than this many days
    """
    supabase = get_supabase_client()
    
    try:
        cutoff_date = datetime.now() - timedelta(days=days_old)
        
        # Delete old applied changes or very old unprocessed changes
        supabase.table("habit_change_staging") \
            .delete() \
            .or_(f"applied.eq.true,created_at.lt.{cutoff_date.isoformat()}") \
            .execute()
        
        logger.info(f"Cleaned up old staged changes older than {days_old} days")
        
    except Exception as e:
        logger.error(f"Error cleaning up old staged changes: {e}") 