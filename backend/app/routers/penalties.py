from fastapi import APIRouter, Depends, HTTPException
from models.schemas import Penalty, PenaltyCreate, User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from typing import List
from datetime import date, datetime
from utils.encoders import UUIDEncoder
from utils.memory_optimization import memory_optimized, cleanup_memory
from utils.memory_monitoring import memory_profile
from utils.habit_queries import get_habit_by_id, HABIT_BASIC_COLUMNS
from tasks.scheduler import check_and_charge_penalties
from routers.auth import get_current_user_lightweight
import json

router = APIRouter()

# OPTIMIZATION: Define selective columns for penalties
PENALTY_COLUMNS = "id, habit_id, user_id, recipient_id, amount, penalty_date, is_paid, payment_status, payment_intent_id, transfer_id, platform_fee_rate, reason, created_at"

@router.post("/", response_model=Penalty)
@memory_optimized(cleanup_args=True)
@memory_profile("create_penalty")
async def create_penalty(
    penalty: PenaltyCreate, 
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        # OPTIMIZATION: Use optimized habit query with selective columns
        habit_data = await get_habit_by_id(
            supabase=supabase,
            habit_id=str(penalty.habit_id),
            columns=HABIT_BASIC_COLUMNS + ", user_id, recipient_id, penalty_amount"
        )
        
        if not habit_data:
            raise HTTPException(status_code=404, detail="Habit not found")

        # Convert date to string for Supabase
        penalty_dict = penalty.model_dump()
        penalty_dict['penalty_date'] = penalty_dict['penalty_date'].isoformat()
        penalty_dict['habit_id'] = str(penalty_dict['habit_id'])  # Convert UUID to string
        penalty_dict['user_id'] = habit_data['user_id']  # Set user_id from habit
        penalty_dict['recipient_id'] = habit_data['recipient_id']  # Set recipient_id from habit

        result = await supabase.table("penalties").insert(penalty_dict).execute()
        cleanup_memory(penalty_dict, habit_data)
        return result.data[0]
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/user/{user_id}", response_model=List[Penalty])
@memory_optimized(cleanup_args=True)
@memory_profile("get_user_penalties")
async def get_user_penalties(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        # Users can only access their own penalty data
        if str(current_user.id) != user_id:
            raise HTTPException(status_code=403, detail="Not authorized to access this user's penalties")
        
        # OPTIMIZATION: Use selective columns and add pagination
        result = await supabase.table("penalties").select(
            PENALTY_COLUMNS
        ).eq("user_id", user_id).order("created_at", desc=True).limit(100).execute()
        
        return result.data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/habit/{habit_id}", response_model=List[Penalty])
@memory_optimized(cleanup_args=True)
@memory_profile("get_habit_penalties")
async def get_habit_penalties(
    habit_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        # First verify that the user owns this habit
        habit_data = await get_habit_by_id(
            supabase=supabase,
            habit_id=habit_id,
            columns="user_id"
        )
        
        if not habit_data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        if habit_data["user_id"] != str(current_user.id):
            raise HTTPException(status_code=403, detail="Not authorized to access this habit's penalties")
        
        # OPTIMIZATION: Use selective columns and add pagination
        result = await supabase.table("penalties").select(
            PENALTY_COLUMNS
        ).eq("habit_id", habit_id).order("created_at", desc=True).limit(50).execute()
        
        return result.data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/{penalty_id}", response_model=Penalty)
@memory_optimized(cleanup_args=True)
@memory_profile("get_penalty")
async def get_penalty(
    penalty_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        # OPTIMIZATION: Use selective columns
        result = await supabase.table("penalties").select(
            PENALTY_COLUMNS
        ).eq("id", penalty_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=404, detail="Penalty not found")
        
        # Verify user owns this penalty
        if result.data[0]["user_id"] != str(current_user.id):
            raise HTTPException(status_code=403, detail="Not authorized to access this penalty")
        
        return result.data[0]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.put("/{penalty_id}/pay")
@memory_optimized(cleanup_args=True)
@memory_profile("mark_penalty_paid")
async def mark_penalty_paid(
    penalty_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        # First get the penalty to verify ownership
        penalty_result = await supabase.table("penalties").select(
            "user_id"
        ).eq("id", penalty_id).execute()
        
        if not penalty_result.data:
            raise HTTPException(status_code=404, detail="Penalty not found")
        
        if penalty_result.data[0]["user_id"] != str(current_user.id):
            raise HTTPException(status_code=403, detail="Not authorized to modify this penalty")
        
        # Now update the penalty
        result = await supabase.table("penalties").update({
            "is_paid": True
        }).eq("id", penalty_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=404, detail="Penalty not found")
        return {"message": "Penalty marked as paid"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/check", response_model=dict)
@memory_optimized(cleanup_args=False)
@memory_profile("trigger_penalty_check")
async def trigger_penalty_check():
    """Test endpoint to manually trigger the penalty check"""
    try:
        await check_and_charge_penalties()
        return {"message": "Penalty check completed successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# OPTIMIZATION: Add batch penalty processing endpoint
@router.post("/batch/mark-paid")
@memory_optimized(cleanup_args=True)
@memory_profile("batch_mark_penalties_paid")
async def batch_mark_penalties_paid(
    penalty_ids: List[str],
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Mark multiple penalties as paid in a single batch operation"""
    try:
        if not penalty_ids:
            raise HTTPException(status_code=400, detail="No penalty IDs provided")
        
        if len(penalty_ids) > 100:  # Limit batch size
            raise HTTPException(status_code=400, detail="Too many penalty IDs (max 100)")
        
        # OPTIMIZATION: Batch update instead of individual updates
        result = await supabase.table("penalties").update({
            "is_paid": True
        }).in_("id", penalty_ids).execute()
        
        updated_count = len(result.data) if result.data else 0
        cleanup_memory(penalty_ids, result)
        
        return {
            "message": f"Marked {updated_count} penalties as paid",
            "updated_count": updated_count
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# OPTIMIZATION: Add unpaid penalties summary endpoint
@router.get("/user/{user_id}/unpaid-summary")
@memory_optimized(cleanup_args=True)
@memory_profile("get_unpaid_penalties_summary")
async def get_unpaid_penalties_summary(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get summary of unpaid penalties for a user"""
    try:
        # Users can only access their own penalty summary
        if str(current_user.id) != user_id:
            raise HTTPException(status_code=403, detail="Not authorized to access this user's penalty summary")
        # OPTIMIZATION: Use aggregation to get summary without fetching all records
        unpaid_result = await supabase.table("penalties").select(
            "amount, penalty_date, habit_id"
        ).eq("user_id", user_id).eq("is_paid", False).execute()
        
        if not unpaid_result.data:
            return {
                "total_amount": 0.0,
                "penalty_count": 0,
                "oldest_penalty_date": None,
                "habits_with_penalties": 0
            }
        
        penalties = unpaid_result.data
        total_amount = sum(float(p["amount"]) for p in penalties)
        penalty_count = len(penalties)
        unique_habits = len(set(p["habit_id"] for p in penalties))
        oldest_date = min(p["penalty_date"] for p in penalties)
        
        cleanup_memory(unpaid_result, penalties)
        
        return {
            "total_amount": total_amount,
            "penalty_count": penalty_count,
            "oldest_penalty_date": oldest_date,
            "habits_with_penalties": unique_habits
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e)) 