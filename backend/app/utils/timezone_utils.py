import pytz
from datetime import datetime, timezone, timedelta
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory

async def get_user_timezone(supabase: AsyncClient, user_id: str) -> str:
    """Get user's timezone from the database"""
    user_result = None
    try:
        user_result = await supabase.table("users").select("timezone").eq("id", user_id).execute()
        if not user_result.data:
            return "UTC"
        
        timezone = user_result.data[0]["timezone"]
        
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
            
    except Exception as e:
        print(f"Error fetching user timezone: {e}")
        return "UTC"
    finally:
        cleanup_memory(user_result)

def get_user_date_range_in_timezone(user_timezone: str, target_date=None):
    """Get start and end of day in user's timezone, converted to UTC"""
    tz = pytz.timezone(user_timezone)
    
    if target_date is None:
        user_now = datetime.now(tz)
        target_date = user_now.date()
    
    start_of_day_local = tz.localize(datetime.combine(target_date, datetime.min.time()))
    end_of_day_local = tz.localize(datetime.combine(target_date, datetime.max.time()))
    
    start_of_day_utc = start_of_day_local.astimezone(pytz.utc)
    end_of_day_utc = end_of_day_local.astimezone(pytz.utc)
    
    return start_of_day_utc, end_of_day_utc

def get_week_boundaries_in_timezone(user_timezone: str, target_date=None):
    """Get week start (Sunday) and end (Saturday) in user's timezone"""
    tz = pytz.timezone(user_timezone)
    
    if target_date is None:
        user_now = datetime.now(tz)
        target_date = user_now.date()
    
    # Calculate current week boundaries (Sunday to Saturday)
    days_since_sunday = (target_date.weekday() + 1) % 7
    week_start = target_date - timedelta(days=days_since_sunday)
    week_end = week_start + timedelta(days=6)
    
    return week_start, week_end

def get_month_boundaries_in_timezone(user_timezone: str, target_date=None):
    """Get month start and end in user's timezone"""
    tz = pytz.timezone(user_timezone)
    
    if target_date is None:
        user_now = datetime.now(tz)
        target_date = user_now.date()
    
    # Calculate current month boundaries
    month_start = target_date.replace(day=1)
    if target_date.month == 12:
        month_end = target_date.replace(year=target_date.year + 1, month=1, day=1) - timedelta(days=1)
    else:
        month_end = target_date.replace(month=target_date.month + 1, day=1) - timedelta(days=1)
    
    return month_start, month_end 