from datetime import datetime
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
import pytz
import logging
from functools import lru_cache
from typing import Dict

logger = logging.getLogger(__name__)

# In-memory cache for timezone lookups (TTL would be better but this is simpler)
_timezone_cache: Dict[str, str] = {}
_cache_max_size = 1000

@memory_optimized(cleanup_args=False)
@memory_profile("get_user_timezone")
async def get_user_timezone(supabase: AsyncClient, user_id: str) -> str:
    """Get user's timezone from the database with caching"""
    
    # OPTIMIZATION: Check cache first
    if user_id in _timezone_cache:
        return _timezone_cache[user_id]
    
    # Cache miss - query database
    user = await supabase.table("users").select("timezone").eq("id", user_id).execute()
    if not user.data:
        timezone = "UTC"
    else:
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
    except pytz.exceptions.UnknownTimeZoneError:
        logger.warning(f"Unknown timezone: {timezone}, falling back to UTC")
        timezone = "UTC"
    
    # OPTIMIZATION: Cache the result with size limit
    if len(_timezone_cache) >= _cache_max_size:
        # Simple cache eviction - remove oldest entries (FIFO)
        # In production, consider using a TTL cache like cachetools
        oldest_keys = list(_timezone_cache.keys())[:100]  # Remove 100 oldest
        for key in oldest_keys:
            del _timezone_cache[key]
    
    _timezone_cache[user_id] = timezone
    return timezone

@memory_optimized(cleanup_args=False)
@memory_profile("get_localized_datetime")
async def get_localized_datetime(supabase: AsyncClient, user_id: str) -> datetime:
    """Get current datetime in user's timezone"""
    timezone = await get_user_timezone(supabase, user_id)
    return datetime.now(pytz.timezone(timezone))

def clear_timezone_cache(user_id: str = None):
    """Clear timezone cache for a specific user or all users"""
    if user_id:
        _timezone_cache.pop(user_id, None)
    else:
        _timezone_cache.clear()

@lru_cache(maxsize=100)
def get_timezone_object(timezone_str: str) -> pytz.BaseTzInfo:
    """Cached timezone object creation"""
    try:
        return pytz.timezone(timezone_str)
    except pytz.exceptions.UnknownTimeZoneError:
        return pytz.UTC 