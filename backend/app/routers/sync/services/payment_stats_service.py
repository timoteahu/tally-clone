from typing import Dict, Any, List
from datetime import datetime, timezone, timedelta
from supabase._async.client import AsyncClient
from models.schemas import User
from utils.memory_optimization import cleanup_memory, disable_print, memory_optimized
from utils.timezone_utils import get_user_timezone, get_week_boundaries_in_timezone, get_month_boundaries_in_timezone
import pytz

# Disable verbose printing to reduce response latency
print = disable_print()

@memory_optimized(cleanup_args=False)
async def get_payment_stats_service(
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, Any]:
    """
    Get payment statistics for the current user including:
    - Weekly payments (current week)
    - Daily payments breakdown (current week)
    - Monthly payments
    - Total payments
    """
    try:
        user_id = str(current_user.id)
        
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        # Get current date in user's timezone
        now_user_tz = datetime.now(user_tz)
        today_user = now_user_tz.date()
        
        # Calculate current week boundaries (Sunday to Saturday)
        week_start, week_end = get_week_boundaries_in_timezone(user_timezone, today_user)
        
        # Calculate current month boundaries
        month_start, month_end = get_month_boundaries_in_timezone(user_timezone, today_user)
        
        # Get all penalties for this user
        penalties_result = await supabase.table("penalties").select("*").eq("user_id", user_id).execute()
        
        if not penalties_result.data:
            return {
                "weekly_payments": 0.0,
                "monthly_payments": 0.0,
                "total_payments": 0.0,
                "daily_payments": [0.0] * 7,
                "week_days": ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
                "unpaid_penalties": 0.0,
                "processing_payments": 0.0,
                "payment_history": []
            }
        
        # Process penalties
        weekly_payments = 0.0
        monthly_payments = 0.0
        total_payments = 0.0
        unpaid_penalties = 0.0
        processing_payments = 0.0
        daily_payments = [0.0] * 7  # Sunday to Saturday
        payment_history = []
        
        for penalty in penalties_result.data:
            penalty_date = datetime.fromisoformat(penalty["penalty_date"]).date()
            amount = float(penalty["amount"])
            is_paid = penalty["is_paid"]
            payment_status = penalty.get("payment_status", "unpaid")
            
            # Add to payment history
            payment_history.append({
                "id": penalty["id"],
                "amount": amount,
                "date": penalty_date.isoformat(),
                "is_paid": is_paid,
                "payment_status": payment_status,
                "reason": penalty.get("reason") or "Missed habit"
            })
            
            # Calculate totals based on payment status
            if is_paid:
                total_payments += amount
                
                # Check if payment is in current week
                if week_start <= penalty_date <= week_end:
                    weekly_payments += amount
                    
                    # Add to daily breakdown
                    day_of_week = (penalty_date.weekday() + 1) % 7  # Convert to Sunday=0 format
                    daily_payments[day_of_week] += amount
                
                # Check if payment is in current month
                if month_start <= penalty_date <= month_end:
                    monthly_payments += amount
            else:
                # Track unpaid penalties
                unpaid_penalties += amount
                
                # Check if it's currently being processed
                if payment_status == "processing":
                    processing_payments += amount
        
        # Sort payment history by date (newest first)
        payment_history.sort(key=lambda x: x["date"], reverse=True)
        
        # Generate week days labels
        week_days = []
        for i in range(7):
            day = week_start + timedelta(days=i)
            week_days.append(day.strftime("%a"))
        
        return {
            "weekly_payments": weekly_payments,
            "monthly_payments": monthly_payments,
            "total_payments": total_payments,
            "daily_payments": daily_payments,
            "week_days": week_days,
            "unpaid_penalties": unpaid_penalties,
            "processing_payments": processing_payments,
            "payment_history": payment_history[:20]  # Return last 20 payments
        }
        
    except Exception as e:
        print(f"Error fetching payment stats: {e}")
        raise Exception("Failed to fetch payment statistics") 