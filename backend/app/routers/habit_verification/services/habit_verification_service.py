from typing import Optional, Dict, Any
from datetime import datetime
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory, disable_print, memory_optimized
from utils.memory_monitoring import memory_profile
from utils.timezone_utils import get_user_timezone
# OPTIMIZATION: Use optimized habit queries
from utils.habit_queries import get_habit_by_id
import pytz

# Disable verbose printing for performance
print = disable_print()

@memory_optimized(cleanup_args=False)
@memory_profile("check_existing_verification")
async def check_existing_verification(habit_id: str, user_id: str, supabase: AsyncClient) -> Optional[Dict[str, Any]]:
    """Check if habit is already verified today in user's timezone - OPTIMIZED"""
    try:
        # Get user timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        # Get current date in user's timezone
        now_user_tz = datetime.now(user_tz)
        today = now_user_tz.date()
        
        # OPTIMIZATION: Use selective columns instead of SELECT *
        existing_verification = await supabase.table("habit_verifications").select(
            "id, verified_at, status, verification_result"
        ).eq("habit_id", habit_id).eq("user_id", user_id).execute()
        
        for verification in existing_verification.data:
            # Convert verification time to user's timezone
            verification_date = datetime.fromisoformat(verification["verified_at"]).astimezone(user_tz).date()
            if verification_date == today and verification["status"] in ("verified", "completed"):
                return verification
        
        return None
        
    except Exception as e:
        print(f"Error checking existing verification: {e}")
        return None

@memory_optimized(cleanup_args=False)
@memory_profile("increment_habit_streak")
async def increment_habit_streak(habit_id: str, supabase: AsyncClient) -> int:
    """Increment the streak for a habit and return the new streak value - OPTIMIZED"""
    try:
        # OPTIMIZATION: Use selective columns and optimize for the update
        habit_result = await supabase.table("habits").select("streak").eq("id", habit_id).execute()
        if not habit_result.data:
            return 0
        
        current_streak = habit_result.data[0].get("streak", 0)
        new_streak = current_streak + 1
        
        # OPTIMIZATION: Single optimized update query
        await supabase.table("habits").update({"streak": new_streak}).eq("id", habit_id).execute()
        
        cleanup_memory(habit_result)
        return new_streak
    except Exception as e:
        print(f"❌ [Streak] Failed to increment streak for habit {habit_id}: {e}")
        return 0

@memory_optimized(cleanup_args=False)
@memory_profile("decrement_habit_streak")
async def decrement_habit_streak(habit_id: str, supabase: AsyncClient) -> int:
    """Decrement the streak for a habit (minimum 0) and return the new streak value - OPTIMIZED"""
    try:
        # OPTIMIZATION: Use selective columns
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
        print(f"❌ [Streak] Failed to decrement streak for habit {habit_id}: {e}")
        return 0

@memory_optimized(cleanup_args=False)
@memory_profile("reset_habit_streak")
async def reset_habit_streak(habit_id: str, supabase: AsyncClient) -> int:
    """Reset the streak for a habit to 0 and return the new streak value - OPTIMIZED"""
    try:
        # OPTIMIZATION: Use selective columns for logging
        habit_result = await supabase.table("habits").select("streak").eq("id", habit_id).execute()
        current_streak = 0
        if habit_result.data:
            current_streak = habit_result.data[0].get("streak", 0)
        
        # OPTIMIZATION: Single optimized update query
        await supabase.table("habits").update({"streak": 0}).eq("id", habit_id).execute()
        
        cleanup_memory(habit_result)
        return 0
    except Exception as e:
        print(f"❌ [Streak] Failed to reset streak for habit {habit_id}: {e}")
        return 0

# OPTIMIZATION: Add caching for custom habit types (frequently accessed)
_custom_habit_type_cache = {}

@memory_optimized(cleanup_args=False)
@memory_profile("get_custom_habit_type_cached")
async def get_custom_habit_type_cached(supabase: AsyncClient, custom_habit_type_id: str) -> Optional[Dict[str, Any]]:
    """Get custom habit type with caching for performance"""
    try:
        # Check cache first
        if custom_habit_type_id in _custom_habit_type_cache:
            return _custom_habit_type_cache[custom_habit_type_id]
        
        # OPTIMIZATION: Use selective columns instead of SELECT *
        custom_type = await supabase.table("custom_habit_types").select(
            "id, type_identifier, keywords, description"
        ).eq("id", custom_habit_type_id).execute()
        
        if custom_type.data:
            custom_type_data = custom_type.data[0]
            
            # Cache for future use (limit cache size)
            if len(_custom_habit_type_cache) < 100:  # Limit cache size
                _custom_habit_type_cache[custom_habit_type_id] = custom_type_data
            
            cleanup_memory(custom_type)
            return custom_type_data
        
        return None
        
    except Exception as e:
        print(f"Error fetching custom habit type {custom_habit_type_id}: {e}")
        return None

@memory_optimized(cleanup_args=False)
@memory_profile("batch_update_streaks")
async def batch_update_streaks(supabase: AsyncClient, streak_updates: Dict[str, int]) -> Dict[str, int]:
    """Batch update multiple habit streaks for better performance"""
    try:
        results = {}
        
        if not streak_updates:
            return results
        
        # OPTIMIZATION: Process in batches to avoid overwhelming the database
        batch_size = 10
        habit_ids = list(streak_updates.keys())
        
        for i in range(0, len(habit_ids), batch_size):
            batch_habit_ids = habit_ids[i:i + batch_size]
            
            # Update all habits in this batch
            for habit_id in batch_habit_ids:
                new_streak = streak_updates[habit_id]
                await supabase.table("habits").update({"streak": new_streak}).eq("id", habit_id).execute()
                results[habit_id] = new_streak
        
        return results
        
    except Exception as e:
        print(f"❌ [Batch Streaks] Failed to batch update streaks: {e}")
        return {}

def clear_custom_habit_type_cache():
    """Clear the custom habit type cache (useful for testing or when types are updated)"""
    global _custom_habit_type_cache
    _custom_habit_type_cache.clear() 