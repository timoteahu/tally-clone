from fastapi import HTTPException
from models.schemas import User
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from tasks.scheduler import check_and_charge_penalties
from ..utils.habit_helpers import get_user_timezone
import pytz
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)

@memory_optimized(cleanup_args=False)
@memory_profile("test_penalty_check_service")
async def test_penalty_check_service(
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """Test endpoint to manually trigger penalty checking for current user"""
    try:
        # Temporarily override the 1 AM check for testing
        from tasks.scheduler import check_deleted_edited_habits_penalties, check_and_create_penalty_for_habit
        import pytz
        from datetime import datetime, timedelta
        
        user_id = str(current_user.id)
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        utc_now = datetime.now(pytz.UTC)
        user_now = utc_now.astimezone(user_tz)
        yesterday_user = (user_now.date() - timedelta(days=1))
        
        
        # Check deleted/edited habits penalties
        await check_deleted_edited_habits_penalties(supabase)
        
        # Check regular daily habits for this user only
        habits_result = await supabase.table("habits") \
            .select("*") \
            .eq("habit_schedule_type", "daily") \
            .eq("is_active", True) \
            .eq("user_id", user_id)
        
        processed_habits = []
        
        for habit in habits_result.data:
            # Check if yesterday was a required day
            postgres_weekday = (yesterday_user.weekday() + 1) % 7
            
            if postgres_weekday not in habit["weekdays"]:
                continue
            
            # Check for verification
            start_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.min.time()))
            end_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.max.time()))
            
            logs = await supabase.table("habit_verifications") \
                .select("*") \
                .eq("habit_id", habit["id"]) \
                .gte("verified_at", start_of_yesterday.isoformat()) \
                .lte("verified_at", end_of_yesterday.isoformat())
            
            habit_status = {
                "habit_id": habit["id"],
                "habit_name": habit["name"],
                "yesterday_required": True,
                "verified": len(logs.data) > 0,
                "penalty_needed": len(logs.data) == 0
            }
            
            if len(logs.data) == 0:
                # Check if penalty already exists
                existing_penalty = await supabase.table("penalties") \
                    .select("*") \
                    .eq("habit_id", habit["id"]) \
                    .eq("penalty_date", yesterday_user.isoformat())
                
                if not existing_penalty.data:
                    # Create penalty
                    penalty_data = {
                        "habit_id": habit["id"],
                        "user_id": user_id,
                        "recipient_id": habit["recipient_id"],
                        "amount": habit["penalty_amount"],
                        "penalty_date": yesterday_user.isoformat(),
                        "is_paid": False,
                        "reason": f"Test penalty check - missed habit on {yesterday_user}"
                    }
                    
                    penalty_result = await supabase.table("penalties").insert(penalty_data).execute()
                    habit_status["penalty_created"] = penalty_result.data[0]["id"]
                else:
                    habit_status["penalty_exists"] = existing_penalty.data[0]["id"]
            
            processed_habits.append(habit_status)
        
        return {
            "message": "Test penalty check completed",
            "user_timezone": user_timezone,
            "current_time": user_now.isoformat(),
            "checked_date": yesterday_user.isoformat(),
            "processed_habits": processed_habits
        }
        
    except Exception as e:
        logger.error(f"Error in test penalty check: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("trigger_habit_check_service")
async def trigger_habit_check_service(habit_id: str) -> dict:
    """Test endpoint to manually trigger the penalty check for a specific habit"""
    try:
        await check_and_charge_penalties()
        return {"message": f"Penalty check completed for habit {habit_id}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) 