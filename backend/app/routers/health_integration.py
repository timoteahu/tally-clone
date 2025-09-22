from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from models.schemas import User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user_lightweight
# OPTIMIZATION: Use actual functions from health_processing
from utils.health_processing import (
    HEALTH_DATA_TYPE_MAPPINGS as HEALTH_DATA_TYPES,
    sync_health_data_batch,
    verify_health_habit
)
from utils.timezone_utils import get_user_timezone
from datetime import datetime, date, timedelta
import pytz
from typing import List, Dict, Any
import logging
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
# OPTIMIZATION: Use optimized habit queries
from utils.habit_queries import get_health_habits_for_sync, batch_get_habits

logger = logging.getLogger(__name__)

router = APIRouter()

@router.post("/upload")
async def upload_health_data(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Upload and process health data from Apple Health export"""
    try:
        user_id = str(current_user.id)
        
        # Read the uploaded file content
        content = await file.read()
        
        # For now, return a placeholder response since the full parser doesn't exist
        # This can be implemented to parse Apple Health XML exports
        return {
            "message": f"Health data file uploaded ({len(content)} bytes)",
            "status": "received",
            "note": "File processing will be implemented based on Apple Health XML format"
        }
        
    except Exception as e:
        logger.error(f"Error uploading health data: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload health data")

@router.get("/today-status")
@memory_optimized(cleanup_args=False)
@memory_profile("get_today_health_status")
async def get_today_health_status(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get today's status for all health habits - OPTIMIZED"""
    try:
        user_id = str(current_user.id)
        
        # Get user's timezone and today's date
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        today = datetime.now(user_tz).date()
        
        # OPTIMIZATION: Get all health habit types and use optimized query
        health_habit_types = list(HEALTH_DATA_TYPES.keys())
        habits = await get_health_habits_for_sync(
            supabase=supabase,
            user_id=user_id,
            health_data_types=health_habit_types
        )
        
        habit_statuses = []
        
        # OPTIMIZATION: Batch fetch all progress records at once if we have habits
        if habits:
            habit_ids = [habit['id'] for habit in habits]
            
            # FIXED: Use correct column names from actual schema
            progress_result = await supabase.table("health_habit_progress").select(
                "habit_id, actual_value, target_value, is_target_met"
            ).in_("habit_id", habit_ids).eq("date", today.isoformat()).execute()
            
            # Create lookup for O(1) access
            progress_lookup = {p['habit_id']: p for p in progress_result.data or []}
            
            # Build response with O(1) lookups instead of N queries
            for habit in habits:
                habit_id = habit['id']
                progress = progress_lookup.get(habit_id)
                
                status = {
                    "habit_id": habit_id,
                    "habit_name": habit['name'],
                    "habit_type": habit['habit_type'],
                    "target_value": habit.get('health_target_value', 0),
                    "target_unit": habit.get('health_target_unit', ''),
                    "current_value": progress['actual_value'] if progress else 0,
                    "is_completed": progress['is_target_met'] if progress else False,
                    "progress_percentage": 0
                }
                
                # Calculate progress percentage
                if progress and habit.get('health_target_value', 0) > 0:
                    status["progress_percentage"] = min(
                        100, 
                        round((progress['actual_value'] / habit['health_target_value']) * 100, 1)
                    )
                
                habit_statuses.append(status)
        
        return {
            "date": today.isoformat(),
            "timezone": user_timezone,
            "health_habits": habit_statuses
        }
        
    except Exception as e:
        logger.error(f"Error getting today's health status: {e}")
        raise HTTPException(status_code=500, detail="Failed to get health status")

@router.get("/weekly-summary")
@memory_optimized(cleanup_args=False)
@memory_profile("get_weekly_health_summary")
async def get_weekly_health_summary(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get weekly summary for all health habits - OPTIMIZED"""
    try:
        user_id = str(current_user.id)
        
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        today = datetime.now(user_tz).date()
        
        # Calculate current week (Monday to Sunday)
        days_since_monday = today.weekday()
        week_start = today - timedelta(days=days_since_monday)
        week_end = week_start + timedelta(days=6)
        
        # OPTIMIZATION: Get all health habits at once
        health_habit_types = list(HEALTH_DATA_TYPES.keys())
        habits = await get_health_habits_for_sync(
            supabase=supabase,
            user_id=user_id,
            health_data_types=health_habit_types
        )
        
        if not habits:
            return {
                "week_start": week_start.isoformat(),
                "week_end": week_end.isoformat(),
                "health_habits": []
            }
        
        # OPTIMIZATION: Batch fetch all weekly progress at once
        habit_ids = [habit['id'] for habit in habits]
        # FIXED: Use correct column names from actual schema
        weekly_progress_result = await supabase.table("health_habit_progress").select(
            "habit_id, date, actual_value, target_value, is_target_met"
        ).in_("habit_id", habit_ids).gte(
            "date", week_start.isoformat()
        ).lte("date", week_end.isoformat()).execute()
        
        # Group progress by habit_id for O(1) access
        habit_progress = {}
        for progress in weekly_progress_result.data or []:
            habit_id = progress['habit_id']
            if habit_id not in habit_progress:
                habit_progress[habit_id] = []
            habit_progress[habit_id].append(progress)
        
        habit_summaries = []
        
        # Build weekly summaries with efficient lookups
        for habit in habits:
            habit_id = habit['id']
            progress_records = habit_progress.get(habit_id, [])
            
            # Calculate weekly statistics
            total_days = len(progress_records)
            completed_days = sum(1 for p in progress_records if p['is_target_met'])
            total_value = sum(p['actual_value'] for p in progress_records)
            
            avg_value = total_value / total_days if total_days > 0 else 0
            completion_rate = (completed_days / 7) * 100  # 7 days in a week
            
            summary = {
                "habit_id": habit_id,
                "habit_name": habit['name'],
                "habit_type": habit['habit_type'],
                "target_value": habit.get('health_target_value', 0),
                "target_unit": habit.get('health_target_unit', ''),
                "total_days_tracked": total_days,
                "completed_days": completed_days,
                "completion_rate": round(completion_rate, 1),
                "average_value": round(avg_value, 2),
                "total_value": round(total_value, 2)
            }
            
            habit_summaries.append(summary)
        
        return {
            "week_start": week_start.isoformat(),
            "week_end": week_end.isoformat(),
            "timezone": user_timezone,
            "health_habits": habit_summaries
        }
        
    except Exception as e:
        logger.error(f"Error getting weekly health summary: {e}")
        raise HTTPException(status_code=500, detail="Failed to get weekly summary")

@router.get("/habit/{habit_id}/progress")
async def get_habit_health_progress(
    habit_id: str,
    start_date: str = None,
    end_date: str = None,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get health progress for a specific habit - OPTIMIZED"""
    try:
        user_id = str(current_user.id)
        
        # OPTIMIZATION: Use optimized habit query with selective columns
        from utils.habit_queries import get_habit_by_id, HABIT_HEALTH_COLUMNS
        
        habit = await get_habit_by_id(
            supabase=supabase,
            habit_id=habit_id,
            user_id=user_id,  # This validates ownership
            columns=HABIT_HEALTH_COLUMNS
        )
        
        if not habit:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # Validate this is a health habit
        if not habit['habit_type'].startswith('health_'):
            raise HTTPException(status_code=400, detail="This endpoint is only for health habits")
        
        # Parse date range
        if start_date:
            start_date = datetime.strptime(start_date, "%Y-%m-%d").date()
        else:
            start_date = datetime.now().date() - timedelta(days=30)  # Default to last 30 days
            
        if end_date:
            end_date = datetime.strptime(end_date, "%Y-%m-%d").date()
        else:
            end_date = datetime.now().date()
        
        # FIXED: Use correct column names from actual schema
        progress_result = await supabase.table("health_habit_progress").select(
            "date, actual_value, target_value, is_target_met, created_at"
        ).eq("habit_id", habit_id).gte(
            "date", start_date.isoformat()
        ).lte("date", end_date.isoformat()).order("date").execute()
        
        return {
            "habit_id": habit_id,
            "habit_name": habit['name'],
            "habit_type": habit['habit_type'],
            "target_value": habit.get('health_target_value'),
            "target_unit": habit.get('health_target_unit'),
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "progress_records": progress_result.data or []
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting habit health progress: {e}")
        raise HTTPException(status_code=500, detail="Failed to get habit progress")

@router.get("/data-types")
async def get_health_data_types():
    """Get all supported health data types and their configurations"""
    return {"data_types": HEALTH_DATA_TYPES} 