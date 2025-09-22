from fastapi import APIRouter, Depends, HTTPException
from models.schemas import HabitLog, HabitLogCreate, User
from config.database import get_supabase_client
from supabase import Client
from typing import List
from datetime import date
from routers.auth import get_current_user_lightweight

router = APIRouter()

@router.post("/", response_model=HabitLog)
async def create_habit_log(
    log: HabitLogCreate,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    try:
        # Check if habit exists and user owns it
        habit = supabase.table("habits").select("*").eq("id", log.habit_id).execute()
        if not habit.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        # Verify user owns this habit
        if habit.data[0]["user_id"] != str(current_user.id):
            raise HTTPException(status_code=403, detail="Not authorized to create logs for this habit")

        # Check if log already exists for this date
        existing_log = supabase.table("habit_logs").select("*").eq("habit_id", log.habit_id).eq("submission_date", log.submission_date).execute()
        if existing_log.data:
            raise HTTPException(status_code=400, detail="Log already exists for this date")

        result = supabase.table("habit_logs").insert(log.dict()).execute()
        return result.data[0]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/habit/{habit_id}", response_model=List[HabitLog])
async def get_habit_logs(
    habit_id: str, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    try:
        # First verify that the user owns this habit
        habit = supabase.table("habits").select("user_id").eq("id", habit_id).execute()
        if not habit.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        if habit.data[0]["user_id"] != str(current_user.id):
            raise HTTPException(status_code=403, detail="Not authorized to access this habit's logs")
        
        result = supabase.table("habit_logs").select("*").eq("habit_id", habit_id).execute()
        return result.data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/user/{user_id}", response_model=List[HabitLog])
async def get_user_logs(
    user_id: str, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    try:
        # Users can only access their own logs
        if str(current_user.id) != user_id:
            raise HTTPException(status_code=403, detail="Not authorized to access this user's logs")
        
        result = supabase.table("habit_logs").select("*").eq("user_id", user_id).execute()
        return result.data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.put("/{log_id}/verify")
async def verify_log(
    log_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    try:
        # Get the log to find the habit
        log_result = supabase.table("habit_logs").select("habit_id").eq("id", log_id).execute()
        if not log_result.data:
            raise HTTPException(status_code=404, detail="Log not found")
        
        # Verify user owns the habit
        habit_result = supabase.table("habits").select("user_id").eq("id", log_result.data[0]["habit_id"]).execute()
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        if habit_result.data[0]["user_id"] != str(current_user.id):
            raise HTTPException(status_code=403, detail="Not authorized to verify this log")
        
        # Now update the log
        result = supabase.table("habit_logs").update({"is_verified": True}).eq("id", log_id).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="Log not found")
        return {"message": "Log verified successfully"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e)) 