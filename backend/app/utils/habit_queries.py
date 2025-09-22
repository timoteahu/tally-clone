"""
Shared habit query utilities to optimize database access patterns.
Replaces 60+ direct habit table queries with optimized, reusable functions.
"""

from typing import List, Dict, Any, Optional, Set
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from fastapi import HTTPException
from uuid import UUID
import logging

logger = logging.getLogger(__name__)

# Common column sets for different use cases
HABIT_BASIC_COLUMNS = "id, name, habit_type, user_id, is_active"
HABIT_VERIFICATION_COLUMNS = "id, name, habit_type, user_id, recipient_id, penalty_amount, is_active, private, streak, custom_habit_type_id"
HABIT_GAMING_COLUMNS = "id, name, habit_type, user_id, daily_limit_hours, hourly_penalty_rate, games_tracked, is_active, habit_schedule_type"
HABIT_HEALTH_COLUMNS = "id, name, habit_type, user_id, health_target_value, health_target_unit, health_data_type, is_active"
HABIT_FULL_COLUMNS = "id, name, recipient_id, habit_type, weekdays, penalty_amount, user_id, created_at, updated_at, study_duration_minutes, screen_time_limit_minutes, restricted_apps, alarm_time, private, custom_habit_type_id, habit_schedule_type, weekly_target, week_start_day, commit_target, daily_limit_hours, hourly_penalty_rate, games_tracked, health_target_value, health_target_unit, health_data_type, is_active, streak"

@memory_optimized(cleanup_args=False)
@memory_profile("get_habit_by_id")
async def get_habit_by_id(
    supabase: AsyncClient, 
    habit_id: str, 
    user_id: Optional[str] = None,
    columns: str = HABIT_BASIC_COLUMNS,
    require_active: bool = True
) -> Optional[Dict[str, Any]]:
    """
    Get a single habit by ID with ownership validation and selective columns.
    
    Args:
        supabase: Database client
        habit_id: The habit ID to fetch
        user_id: Optional user ID for ownership validation
        columns: Specific columns to fetch (default: basic columns)
        require_active: Whether to require is_active=True
        
    Returns:
        Habit data dict or None if not found
        
    Raises:
        HTTPException: If user_id provided and user doesn't own the habit
    """
    try:
        query = supabase.table("habits").select(columns).eq("id", habit_id)
        
        if require_active:
            query = query.eq("is_active", True)
            
        result = await query.execute()
        
        if not result.data:
            return None
            
        habit = result.data[0]
        
        # Validate ownership if user_id provided
        if user_id and str(habit.get('user_id')).lower() != str(user_id).lower():
            raise HTTPException(status_code=403, detail="Cannot access another user's habit")
            
        return habit
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching habit {habit_id}: {e}")
        return None

@memory_optimized(cleanup_args=False)
@memory_profile("get_habits_by_user")
async def get_habits_by_user(
    supabase: AsyncClient,
    user_id: str,
    habit_types: Optional[List[str]] = None,
    columns: str = HABIT_BASIC_COLUMNS,
    require_active: bool = True,
    limit: int = 100
) -> List[Dict[str, Any]]:
    """
    Get all habits for a user with optional filtering.
    
    Args:
        supabase: Database client
        user_id: User ID to fetch habits for
        habit_types: Optional list of habit types to filter by
        columns: Specific columns to fetch
        require_active: Whether to require is_active=True
        limit: Maximum number of habits to return
        
    Returns:
        List of habit data dicts
    """
    try:
        query = supabase.table("habits").select(columns).eq("user_id", user_id)
        
        if require_active:
            query = query.eq("is_active", True)
            
        if habit_types:
            query = query.in_("habit_type", habit_types)
            
        query = query.limit(limit)
        result = await query.execute()
        
        return result.data or []
        
    except Exception as e:
        logger.error(f"Error fetching habits for user {user_id}: {e}")
        return []

@memory_optimized(cleanup_args=False) 
@memory_profile("batch_get_habits")
async def batch_get_habits(
    supabase: AsyncClient,
    habit_ids: List[str],
    columns: str = HABIT_BASIC_COLUMNS,
    require_active: bool = True
) -> Dict[str, Dict[str, Any]]:
    """
    Batch fetch multiple habits by IDs.
    
    Args:
        supabase: Database client
        habit_ids: List of habit IDs to fetch
        columns: Specific columns to fetch
        require_active: Whether to require is_active=True
        
    Returns:
        Dict mapping habit_id -> habit_data
    """
    try:
        if not habit_ids:
            return {}
            
        query = supabase.table("habits").select(columns).in_("id", habit_ids)
        
        if require_active:
            query = query.eq("is_active", True)
            
        result = await query.execute()
        
        # Create lookup dictionary
        return {habit['id']: habit for habit in result.data or []}
        
    except Exception as e:
        logger.error(f"Error batch fetching habits {habit_ids}: {e}")
        return {}

@memory_optimized(cleanup_args=False)
@memory_profile("get_habits_by_type_batch")
async def get_habits_by_type_batch(
    supabase: AsyncClient,
    user_ids: List[str],
    habit_types: List[str],
    columns: str = HABIT_BASIC_COLUMNS
) -> Dict[str, List[Dict[str, Any]]]:
    """
    Batch fetch habits by type for multiple users (for bulk operations).
    
    Args:
        supabase: Database client
        user_ids: List of user IDs
        habit_types: List of habit types to fetch
        columns: Specific columns to fetch
        
    Returns:
        Dict mapping user_id -> list of habits
    """
    try:
        if not user_ids or not habit_types:
            return {}
            
        query = supabase.table("habits").select(columns + ", user_id").in_("user_id", user_ids).in_("habit_type", habit_types).eq("is_active", True)
        result = await query.execute()
        
        # Group by user_id
        user_habits = {}
        for habit in result.data or []:
            user_id = habit['user_id']
            if user_id not in user_habits:
                user_habits[user_id] = []
            user_habits[user_id].append(habit)
            
        return user_habits
        
    except Exception as e:
        logger.error(f"Error batch fetching habits by type: {e}")
        return {}

@memory_optimized(cleanup_args=False)
@memory_profile("verify_habit_ownership")
async def verify_habit_ownership(
    supabase: AsyncClient,
    habit_id: str,
    user_id: str,
    require_active: bool = True
) -> bool:
    """
    Efficiently verify that a user owns a habit.
    
    Args:
        supabase: Database client
        habit_id: Habit ID to check
        user_id: User ID to verify ownership
        require_active: Whether to require is_active=True
        
    Returns:
        True if user owns the habit, False otherwise
    """
    try:
        query = supabase.table("habits").select("id").eq("id", habit_id).eq("user_id", user_id)
        
        if require_active:
            query = query.eq("is_active", True)
            
        result = await query.execute()
        return len(result.data or []) > 0
        
    except Exception as e:
        logger.error(f"Error verifying habit ownership {habit_id} for user {user_id}: {e}")
        return False

@memory_optimized(cleanup_args=False)
@memory_profile("get_recipient_habits")
async def get_recipient_habits(
    supabase: AsyncClient,
    recipient_id: str,
    columns: str = HABIT_VERIFICATION_COLUMNS,
    include_inactive: bool = False
) -> List[Dict[str, Any]]:
    """
    Get all habits where user is the recipient (accountability partner).
    
    Args:
        supabase: Database client
        recipient_id: ID of the recipient user
        columns: Specific columns to fetch
        include_inactive: Whether to include inactive habits
        
    Returns:
        List of habits where user is recipient
    """
    try:
        query = supabase.table("habits").select(columns).eq("recipient_id", recipient_id).not_.is_("recipient_id", None)
        
        if not include_inactive:
            query = query.eq("is_active", True)
            
        result = await query.execute()
        return result.data or []
        
    except Exception as e:
        logger.error(f"Error fetching recipient habits for {recipient_id}: {e}")
        return []

# Specialized query functions for specific use cases

async def get_health_habits_for_sync(
    supabase: AsyncClient,
    user_id: str,
    health_data_types: List[str]
) -> List[Dict[str, Any]]:
    """Get health habits that need data sync updates."""
    return await get_habits_by_user(
        supabase=supabase,
        user_id=user_id,
        habit_types=health_data_types,
        columns=HABIT_HEALTH_COLUMNS
    )

async def get_gaming_habit_for_verification(
    supabase: AsyncClient,
    habit_id: str,
    user_id: str
) -> Optional[Dict[str, Any]]:
    """Get gaming habit with all needed fields for verification."""
    return await get_habit_by_id(
        supabase=supabase,
        habit_id=habit_id,
        user_id=user_id,
        columns=HABIT_GAMING_COLUMNS
    )

async def get_habits_for_penalty_check(
    supabase: AsyncClient,
    user_ids: Optional[List[str]] = None
) -> List[Dict[str, Any]]:
    """Get habits that need penalty checking."""
    try:
        columns = "id, user_id, habit_type, weekdays, penalty_amount, recipient_id, habit_schedule_type, weekly_target, week_start_day"
        query = supabase.table("habits").select(columns).eq("is_active", True)
        
        if user_ids:
            query = query.in_("user_id", user_ids)
            
        result = await query.execute()
        return result.data or []
        
    except Exception as e:
        logger.error(f"Error fetching habits for penalty check: {e}")
        return [] 