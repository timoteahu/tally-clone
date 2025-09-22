from fastapi import APIRouter, Depends, HTTPException, Query
from models.schemas import User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user, get_current_user_lightweight
from services.gaming_habit_service import GamingHabitService
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta
from uuid import UUID
import logging
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
# OPTIMIZATION: Use optimized habit queries
from utils.habit_queries import (
    get_gaming_habit_for_verification, 
    verify_habit_ownership,
    HABIT_GAMING_COLUMNS
)

logger = logging.getLogger(__name__)

router = APIRouter()

# Global gaming service instance
gaming_service = GamingHabitService()

@router.post("/habits/{habit_id}/start-session")
@memory_optimized(cleanup_args=False)
@memory_profile("start_gaming_session")
async def start_gaming_session(
    habit_id: UUID,
    current_user = Depends(get_current_user)
):
    """Start a new gaming session for a habit - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    try:
        # OPTIMIZATION: Use optimized habit verification
        if not await verify_habit_ownership(supabase, str(habit_id), str(current_user.id)):
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # Start the session using the gaming service
        session = await gaming_service.start_session(
            habit_id=str(habit_id),
            user_id=str(current_user.id)
        )
        
        return {"message": "Gaming session started", "session": session}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error starting gaming session: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to start gaming session")

@router.post("/habits/{habit_id}/end-session")
@memory_optimized(cleanup_args=False)
@memory_profile("end_gaming_session")
async def end_gaming_session(
    habit_id: UUID,
    current_user = Depends(get_current_user)
):
    """End the current gaming session for a habit - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    try:
        # OPTIMIZATION: Use optimized habit verification
        if not await verify_habit_ownership(supabase, str(habit_id), str(current_user.id)):
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # End the session using the gaming service
        session = await gaming_service.end_session(
            habit_id=str(habit_id),
            user_id=str(current_user.id)
        )
        
        return {"message": "Gaming session ended", "session": session}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error ending gaming session: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to end gaming session")

@router.get("/habits/{habit_id}/current-session")
async def get_current_session(
    habit_id: UUID,
    current_user = Depends(get_current_user)
):
    """Get the current active gaming session for a habit - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    try:
        # OPTIMIZATION: Use optimized habit verification
        if not await verify_habit_ownership(supabase, str(habit_id), str(current_user.id)):
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # Get current session
        session = await gaming_service.get_current_session(
            habit_id=str(habit_id),
            user_id=str(current_user.id)
        )
        
        return {"session": session}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting current session: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get current session")

@router.get("/habits/{habit_id}/sessions")
async def get_gaming_sessions(
    habit_id: UUID,
    start_date: Optional[datetime] = Query(None),
    end_date: Optional[datetime] = Query(None),
    current_user = Depends(get_current_user)
):
    """Get gaming sessions for a habit within a date range - OPTIMIZED"""
    # OPTIMIZATION: Use efficient ownership verification with minimal columns
    supabase = await get_async_supabase_client()
    
    if not await verify_habit_ownership(supabase, str(habit_id), str(current_user.id)):
        raise HTTPException(status_code=404, detail="Habit not found")
    
    sessions = await gaming_service.get_gaming_sessions(
        habit_id=str(habit_id),
        start_date=start_date,
        end_date=end_date
    )
    return sessions

@router.get("/habits/{habit_id}/weekly-summary")
async def get_weekly_gaming_summary(
    habit_id: UUID,
    week_start: datetime,
    current_user = Depends(get_current_user)
):
    """Get weekly gaming summary for a habit - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    # OPTIMIZATION: Get habit with selective columns for verification
    habit = await get_gaming_habit_for_verification(
        supabase=supabase,
        habit_id=str(habit_id),
        user_id=str(current_user.id)
    )
    
    if not habit:
        raise HTTPException(status_code=404, detail="Habit not found")
    
    if habit["habit_schedule_type"] != "weekly":
        raise HTTPException(status_code=400, detail="This endpoint is only for weekly habits")
    
    try:
        summary = await gaming_service.calculate_weekly_gaming_total(
            habit_id=str(habit_id),
            week_start=week_start
        )
        return summary
    except Exception as e:
        logger.error(f"Error getting weekly summary: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get weekly summary")

@router.post("/habits/{habit_id}/check-usage")
@memory_optimized(cleanup_args=False)
@memory_profile("check_gaming_usage")
async def check_gaming_usage_and_notify(
    habit_id: UUID,
    current_user = Depends(get_current_user)
):
    """Check current gaming usage and send warning notification if approaching limit - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    try:
        # OPTIMIZATION: Use optimized habit query with gaming-specific columns
        habit = await get_gaming_habit_for_verification(
            supabase=supabase,
            habit_id=str(habit_id),
            user_id=str(current_user.id)
        )
        
        if not habit:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # Ensure this is a gaming habit
        if habit['habit_type'] not in ['league_of_legends', 'valorant']:
            raise HTTPException(status_code=400, detail="This endpoint is only for gaming habits")
        
        # Check usage and send notification if needed
        result = await gaming_service.check_and_notify_usage(
            habit_id=str(habit_id),
            user_id=str(current_user.id),
            habit_data=habit
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error checking gaming usage: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to check usage")

@router.get("/habits/{habit_id}/today-usage")
async def get_today_gaming_usage(
    habit_id: UUID,
    current_user = Depends(get_current_user)
):
    """Get today's gaming usage for a habit - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    # OPTIMIZATION: Use efficient ownership verification
    if not await verify_habit_ownership(supabase, str(habit_id), str(current_user.id)):
        raise HTTPException(status_code=404, detail="Habit not found")
    
    try:
        usage = await gaming_service.get_today_usage(
            habit_id=str(habit_id),
            user_id=str(current_user.id)
        )
        return usage
        
    except Exception as e:
        logger.error(f"Error getting today's usage: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get today's usage")

@router.post("/habits/{habit_id}/manual-session")
@memory_optimized(cleanup_args=False)
@memory_profile("create_manual_gaming_session")
async def create_manual_gaming_session(
    habit_id: UUID,
    start_time: datetime,
    end_time: datetime,
    game_title: str,
    current_user = Depends(get_current_user)
):
    """Create a manual gaming session entry - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    try:
        # OPTIMIZATION: Use optimized habit verification
        habit = await get_gaming_habit_for_verification(
            supabase=supabase,
            habit_id=str(habit_id),
            user_id=str(current_user.id)
        )
        
        if not habit:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # Create manual session
        session = await gaming_service.create_manual_session(
            habit_id=str(habit_id),
            user_id=str(current_user.id),
            start_time=start_time,
            end_time=end_time,
            game_title=game_title
        )
        
        return {"message": "Manual session created", "session": session}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating manual session: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to create manual session")

@router.get("/habits/{habit_id}/statistics")
async def get_gaming_statistics(
    habit_id: UUID,
    days: int = Query(30, ge=1, le=90),
    current_user = Depends(get_current_user)
):
    """Get gaming statistics for a habit over the specified period - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    # OPTIMIZATION: Use efficient ownership verification
    if not await verify_habit_ownership(supabase, str(habit_id), str(current_user.id)):
        raise HTTPException(status_code=404, detail="Habit not found")
    
    try:
        stats = await gaming_service.get_gaming_statistics(
            habit_id=str(habit_id),
            user_id=str(current_user.id),
            days=days
        )
        return stats
        
    except Exception as e:
        logger.error(f"Error getting gaming statistics: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get statistics")

@router.post("/habits/{habit_id}/batch-update")
@memory_optimized(cleanup_args=False)
@memory_profile("batch_update_gaming_data")
async def batch_update_gaming_data(
    habit_id: UUID,
    sessions: List[Dict[str, Any]],
    current_user = Depends(get_current_user_lightweight)
):
    """Batch update gaming data for performance - OPTIMIZED"""
    supabase = await get_async_supabase_client()
    
    try:
        # OPTIMIZATION: Use optimized habit verification  
        if not await verify_habit_ownership(supabase, str(habit_id), str(current_user.id)):
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # Process batch update
        result = await gaming_service.batch_update_sessions(
            habit_id=str(habit_id),
            user_id=str(current_user.id),
            sessions=sessions
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in batch update: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to batch update gaming data")