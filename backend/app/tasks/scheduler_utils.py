import pytz
import logging
from datetime import datetime, timedelta, date
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized, cleanup_memory
from utils.memory_monitoring import memory_profile

# Set up logging
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    force=True
)
logger = logging.getLogger(__name__)
logger.setLevel(logging.WARNING)

@memory_optimized(cleanup_args=False)
async def get_user_timezone_async(supabase: AsyncClient, user_id: str) -> str:
    """Get user's timezone from the database (async version)"""
    user = await supabase.table("users").select("timezone").eq("id", user_id).execute()
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
        cleanup_memory(user)
        return timezone
    except pytz.exceptions.UnknownTimeZoneError:
        logger.error(f"Unknown timezone: {timezone}, falling back to UTC")
        cleanup_memory(user)
        return "UTC"

# Legacy sync version for backward compatibility
def get_user_timezone(supabase, user_id: str) -> str:
    """Get user's timezone from the database (sync version for legacy code)"""
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

@memory_optimized(cleanup_args=False)
@memory_profile("decrement_habit_streak")
async def decrement_habit_streak_local(supabase: AsyncClient, habit_id: str) -> int:
    """Decrement the streak for a habit (minimum 0) and return the new streak value - OPTIMIZED"""
    try:
        # OPTIMIZATION: Use selective columns for streak operations
        habit_result = await supabase.table("habits").select("streak").eq("id", habit_id).execute()
        if not habit_result.data:
            return 0
        
        current_streak = habit_result.data[0].get("streak", 0)
        new_streak = max(0, current_streak - 1)  # Ensure streak doesn't go below 0
        
        # OPTIMIZATION: Single optimized update query
        await supabase.table("habits").update({"streak": new_streak}).eq("id", habit_id).execute()
        
        cleanup_memory(habit_result)
        return new_streak
    except Exception as e:
        logger.error(f"❌ [Streak] Failed to decrement streak for habit {habit_id}: {e}")
        return 0

@memory_optimized(cleanup_args=False)
@memory_profile("check_and_create_penalty_for_habit")
async def check_and_create_penalty_for_habit(
    supabase: AsyncClient, 
    habit_id: str, 
    user_id: str, 
    habit_data: dict, 
    penalty_date: date, 
    reason: str
):
    """
    Check if a penalty should be created for a specific habit and date, and create it if needed.
    OPTIMIZED: Uses async client and selective queries for better performance.
    """
    try:
        # OPTIMIZATION: Use async timezone helper
        user_timezone = await get_user_timezone_async(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        start_of_day = user_tz.localize(datetime.combine(penalty_date, datetime.min.time()))
        end_of_day = user_tz.localize(datetime.combine(penalty_date, datetime.max.time()))
        
        # OPTIMIZATION: Use selective columns for verification check
        verification_result = await supabase.table("habit_verifications").select(
            "id, verified_at, status"
        ).eq("habit_id", habit_id).gte("verified_at", start_of_day.isoformat()).lte(
            "verified_at", end_of_day.isoformat()
        ).execute()
        
        if verification_result.data:
            cleanup_memory(verification_result)
            return  # Already verified, no penalty needed
        
        # OPTIMIZATION: Use selective columns for existing penalty check
        existing_penalty = await supabase.table("penalties").select(
            "id"
        ).eq("habit_id", habit_id).eq("penalty_date", penalty_date.isoformat()).execute()
        
        if existing_penalty.data:
            cleanup_memory(verification_result, existing_penalty)
            return  # Penalty already exists
        
        # Create penalty
        penalty_data = {
            "habit_id": habit_id,
            "user_id": user_id,
            "recipient_id": habit_data.get('recipient_id'),
            "amount": habit_data['penalty_amount'],
            "penalty_date": penalty_date.isoformat(),
            "is_paid": False,
            "reason": reason
        }
        
        await supabase.table("penalties").insert(penalty_data).execute()
        
        # Update recipient analytics if there's a recipient
        recipient_id = habit_data.get('recipient_id')
        if recipient_id:
            try:
                from utils.recipient_analytics import update_analytics_on_penalty_created
                await update_analytics_on_penalty_created(
                    supabase=supabase,
                    habit_id=habit_id,
                    recipient_id=recipient_id,
                    penalty_amount=float(habit_data['penalty_amount']),
                    penalty_date=penalty_date
                )
                logger.info(f"Updated recipient analytics for penalty: habit={habit_id}, recipient={recipient_id}")
            except Exception as analytics_error:
                logger.error(f"Error updating recipient analytics for penalty: {analytics_error}")
                # Don't fail penalty creation if analytics update fails
        
        # Decrement the streak when a penalty is created
        await decrement_habit_streak_local(supabase, habit_id)
        
        cleanup_memory(verification_result, existing_penalty, penalty_data)
        
    except Exception as e:
        logger.error(f"Error creating penalty for habit {habit_id} on {penalty_date}: {e}")

# OPTIMIZATION: Add batch penalty creation for better performance
@memory_optimized(cleanup_args=False)
@memory_profile("batch_create_penalties")
async def batch_create_penalties(
    supabase: AsyncClient,
    penalty_batch: list,
    habit_data_map: dict
):
    """
    Create multiple penalties in batch for better performance.
    penalty_batch: List of penalty data dicts
    habit_data_map: Map of habit_id -> habit_data for analytics updates
    """
    try:
        if not penalty_batch:
            return
        
        # OPTIMIZATION: Batch insert penalties
        await supabase.table("penalties").insert(penalty_batch).execute()
        
        # OPTIMIZATION: Batch update recipient analytics
        analytics_updates = []
        streak_decrements = []
        
        for penalty in penalty_batch:
            habit_id = penalty["habit_id"]
            recipient_id = penalty.get("recipient_id")
            
            # Collect analytics updates
            if recipient_id and habit_id in habit_data_map:
                analytics_updates.append({
                    "habit_id": habit_id,
                    "recipient_id": recipient_id,
                    "penalty_amount": float(penalty["amount"]),
                    "penalty_date": penalty["penalty_date"]
                })
            
            # Collect streak decrements
            streak_decrements.append(habit_id)
        
        # OPTIMIZATION: Batch process analytics updates
        if analytics_updates:
            try:
                from utils.recipient_analytics import batch_update_analytics_on_penalty_created
                await batch_update_analytics_on_penalty_created(supabase, analytics_updates)
                logger.info(f"Batch updated analytics for {len(analytics_updates)} penalties")
            except Exception as analytics_error:
                logger.error(f"Error in batch analytics update: {analytics_error}")
        
        # OPTIMIZATION: Batch process streak decrements
        if streak_decrements:
            try:
                from routers.habit_verification.services.habit_verification_service import batch_update_streaks
                
                # Get current streaks
                habits_result = await supabase.table("habits").select(
                    "id, streak"
                ).in_("id", streak_decrements).execute()
                
                streak_updates = {}
                for habit in habits_result.data:
                    current_streak = habit.get("streak", 0)
                    new_streak = max(0, current_streak - 1)
                    streak_updates[habit["id"]] = new_streak
                
                # Batch update streaks
                await batch_update_streaks(supabase, streak_updates)
                logger.info(f"Batch decremented streaks for {len(streak_updates)} habits")
                
                cleanup_memory(habits_result)
                
            except Exception as streak_error:
                logger.error(f"Error in batch streak decrement: {streak_error}")
        
        cleanup_memory(penalty_batch, analytics_updates, streak_decrements)
        
    except Exception as e:
        logger.error(f"Error in batch penalty creation: {e}")
        raise

# OPTIMIZATION: Add habit data caching for penalty processing
_habit_data_cache = {}

@memory_optimized(cleanup_args=False)
async def get_habit_data_cached(supabase: AsyncClient, habit_id: str) -> dict:
    """Get habit data with caching for penalty processing"""
    if habit_id in _habit_data_cache:
        return _habit_data_cache[habit_id]
    
    try:
        # OPTIMIZATION: Use selective columns for habit data
        habit_result = await supabase.table("habits").select(
            "id, user_id, recipient_id, penalty_amount, name, habit_type"
        ).eq("id", habit_id).execute()
        
        if habit_result.data:
            habit_data = habit_result.data[0]
            
            # Cache with size limit
            if len(_habit_data_cache) < 1000:
                _habit_data_cache[habit_id] = habit_data
            
            cleanup_memory(habit_result)
            return habit_data
        
        return None
        
    except Exception as e:
        logger.error(f"Error fetching habit data for {habit_id}: {e}")
        return None

def clear_habit_data_cache():
    """Clear the habit data cache"""
    global _habit_data_cache
    _habit_data_cache.clear() 