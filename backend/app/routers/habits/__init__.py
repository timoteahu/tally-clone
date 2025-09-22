from fastapi import APIRouter, Depends, HTTPException, Body
from models.schemas import Habit, HabitCreate, HabitUpdate, User, WeeklyHabitProgress, HabitWithAnalytics
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from typing import List, Optional, Dict, Any
from routers.auth import get_current_user_lightweight

# Import service functions
from .services.habit_crud_service import (
    create_habit_service,
    get_user_habits_service,
    get_habit_service,
    delete_habit_service,
    update_habit_service,
    get_completed_one_time_habits_service,
    HabitCreateResponse
)
from .services.habit_recipient_service import (
    get_habits_as_recipient_service,
    get_recipient_summary_service,
    send_tickle_notification_service
)
from .services.habit_progress_service import (
    get_user_weekly_progress_service,
    get_habit_weekly_progress_service,
    fix_weekly_habit_targets_service
)
from .services.habit_staging_service import (
    get_staged_deletion_service,
    restore_habit_service
)
from .services.habit_stats_service import (
    get_user_habit_stats_service
)
# NOTE: LeetCode services are used internally by habit_crud_service
# and are not imported directly into the router

router = APIRouter()

@router.post("/", response_model=HabitCreateResponse)
async def create_habit(
    habit: HabitCreate, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Create a new habit"""
    return await create_habit_service(habit, current_user, supabase)

@router.get("/user/{user_id}", response_model=List[Habit])
async def get_user_habits(
    user_id: str, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client),
    include_completed: bool = False
):
    """Get all habits for a user"""
    return await get_user_habits_service(user_id, current_user, supabase, include_completed)

@router.get("/recipient", response_model=List[HabitWithAnalytics])
async def get_habits_as_recipient(
    include_inactive: bool = False,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all habits where the current user is the recipient"""
    return await get_habits_as_recipient_service(include_inactive, current_user, supabase)

@router.get("/recipient/summary")
async def get_recipient_summary(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get summary statistics for the current user as a recipient"""
    return await get_recipient_summary_service(current_user, supabase)

@router.get("/{habit_id}", response_model=Habit)
async def get_habit(
    habit_id: str, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get a specific habit by ID"""
    return await get_habit_service(habit_id, current_user, supabase)

@router.delete("/{habit_id}")
async def delete_habit(
    habit_id: str, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Delete a habit (soft delete)"""
    return await delete_habit_service(habit_id, current_user, supabase)


@router.post("/{habit_id}/tickle", response_model=dict)
async def send_tickle_notification(
    habit_id: str,
    request: Optional[Dict[str, Any]] = Body(default={}),
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Send a tickle notification to a habit owner"""
    custom_message = request.get("message", "").strip() if request else ""
    return await send_tickle_notification_service(habit_id, custom_message, current_user, supabase)

@router.put("/{habit_id}", response_model=dict)
async def update_habit(
    habit_id: str, 
    habit: HabitUpdate, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Update a habit"""
    return await update_habit_service(habit_id, habit, current_user, supabase)

@router.get("/weekly-progress/{user_id}", response_model=List[WeeklyHabitProgress])
async def get_user_weekly_progress(
    user_id: str,
    week_start_date: Optional[str] = None,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get weekly progress for all weekly habits for a user"""
    return await get_user_weekly_progress_service(user_id, week_start_date, current_user, supabase)

@router.get("/weekly-progress/habit/{habit_id}", response_model=List[WeeklyHabitProgress])
async def get_habit_weekly_progress(
    habit_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all weekly progress records for a specific habit"""
    return await get_habit_weekly_progress_service(habit_id, current_user, supabase)


@router.post("/fix-weekly-targets", deprecated=True)
async def fix_weekly_habit_targets(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    DEPRECATED: Fix weekly habit progress records that have incorrect target_completions.
    This is a one-time data migration endpoint and should be removed after data is fixed.
    """
    return await fix_weekly_habit_targets_service(current_user, supabase)

@router.get("/{habit_id}/staged-deletion")
async def get_staged_deletion(
    habit_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Check if a habit has a pending deletion scheduled"""
    return await get_staged_deletion_service(habit_id, current_user, supabase)

@router.post("/{habit_id}/restore")
async def restore_habit(
    habit_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Restore a habit that is scheduled for deletion"""
    return await restore_habit_service(habit_id, current_user, supabase)

@router.get("/user/{user_id}/completed-one-time", response_model=List[Habit])
async def get_completed_one_time_habits(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all completed one-time habits for a user"""
    return await get_completed_one_time_habits_service(user_id, current_user, supabase)

@router.get("/user/{user_id}/stats")
async def get_user_habit_stats(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get basic habit statistics for any user (consider consolidating with other user endpoints)"""
    return await get_user_habit_stats_service(user_id, current_user, supabase) 