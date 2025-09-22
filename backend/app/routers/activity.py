from fastapi import APIRouter, Depends, HTTPException
from models.schemas import User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user_lightweight
from utils.activity_tracking import track_user_activity
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, date
import logging

logger = logging.getLogger(__name__)
router = APIRouter()

class ActivityResponse(BaseModel):
    success: bool
    last_active: str
    message: str

class DailyActiveUsersResponse(BaseModel):
    date: str
    total_users: int
    user_ids: Optional[list[str]] = None

@router.post("/track", response_model=ActivityResponse)
async def track_activity(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Track user activity - call this endpoint when the app becomes active/foreground.
    This updates last_active and records daily active user.
    """
    try:
        user_id = str(current_user.id)
        await track_user_activity(supabase, user_id)
        
        return ActivityResponse(
            success=True,
            last_active=datetime.utcnow().isoformat(),
            message="Activity tracked successfully"
        )
    except Exception as e:
        logger.error(f"Failed to track activity for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to track activity")

@router.get("/daily-active-users/{date}", response_model=DailyActiveUsersResponse)
async def get_daily_active_users(
    date: str,  # Format: YYYY-MM-DD
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get count of daily active users for a specific date (admin only).
    """
    try:
        # Parse and validate date
        try:
            parsed_date = datetime.strptime(date, "%Y-%m-%d").date()
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
        
        # Query daily active users for the date
        result = await supabase.table("daily_active_users").select(
            "user_id"
        ).eq("date", parsed_date.isoformat()).execute()
        
        user_ids = [row["user_id"] for row in result.data] if result.data else []
        
        return DailyActiveUsersResponse(
            date=parsed_date.isoformat(),
            total_users=len(user_ids),
            user_ids=user_ids if len(user_ids) < 100 else None  # Don't return huge lists
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get daily active users: {e}")
        raise HTTPException(status_code=500, detail="Failed to get daily active users")

@router.get("/daily-active-users-summary")
async def get_daily_active_users_summary(
    days: int = 7,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get daily active users summary for the last N days.
    """
    try:
        # Calculate date range
        end_date = date.today()
        start_date = end_date - timedelta(days=days-1)
        
        # Query daily active users grouped by date
        result = await supabase.table("daily_active_users").select(
            "date"
        ).gte("date", start_date.isoformat()).lte("date", end_date.isoformat()).execute()
        
        # Count users per day
        daily_counts = {}
        for row in result.data:
            row_date = row["date"]
            if row_date not in daily_counts:
                daily_counts[row_date] = 0
            daily_counts[row_date] += 1
        
        # Fill in missing days with 0
        summary = []
        current = start_date
        while current <= end_date:
            date_str = current.isoformat()
            summary.append({
                "date": date_str,
                "active_users": daily_counts.get(date_str, 0)
            })
            current += timedelta(days=1)
        
        return {
            "days": days,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "daily_summary": summary,
            "total_unique_users": len(set(row["user_id"] for row in result.data)) if result.data else 0
        }
    except Exception as e:
        logger.error(f"Failed to get daily active users summary: {e}")
        raise HTTPException(status_code=500, detail="Failed to get summary")

# Import timedelta
from datetime import timedelta