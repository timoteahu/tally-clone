"""
Utility functions for updating recipient analytics data.
These functions should be called whenever penalties are created or habits are verified.
"""

from supabase._async.client import AsyncClient
from datetime import date, datetime
import logging

logger = logging.getLogger(__name__)

async def update_analytics_on_penalty_created(
    supabase: AsyncClient,
    habit_id: str,
    recipient_id: str,
    penalty_amount: float,
    penalty_date: date
):
    """
    Update recipient analytics when a penalty is created.
    
    Args:
        supabase: Database client
        habit_id: ID of the habit that had a penalty
        recipient_id: ID of the recipient who will receive the penalty payment
        penalty_amount: Amount of the penalty
        penalty_date: Date the penalty was incurred
    """
    try:
        if not recipient_id:
            return  # No recipient to update analytics for
        
        # Get current analytics for this recipient/habit combination
        analytics_result = await supabase.table("recipient_analytics") \
            .select("*") \
            .eq("recipient_id", recipient_id) \
            .eq("habit_id", habit_id) \
            .execute()
        
        if analytics_result.data:
            # Update existing analytics
            current_analytics = analytics_result.data[0]
            
            update_data = {
                "total_failures": current_analytics["total_failures"] + 1,
                "total_required_days": current_analytics["total_required_days"] + 1,
                "pending_earnings": float(current_analytics["pending_earnings"]) + penalty_amount,
                "last_penalty_date": penalty_date.isoformat(),
                "updated_at": datetime.utcnow().isoformat()
            }
            
            # Recalculate success rate
            new_total_required = update_data["total_required_days"]
            if new_total_required > 0:
                success_rate = (current_analytics["total_completions"] / new_total_required) * 100
                update_data["success_rate"] = round(success_rate, 2)
            
            await supabase.table("recipient_analytics") \
                .update(update_data) \
                .eq("id", current_analytics["id"]) \
                .execute()
                
            logger.info(f"Updated analytics for penalty: recipient={recipient_id}, habit={habit_id}, amount={penalty_amount}")
        else:
            logger.warning(f"No analytics record found for recipient={recipient_id}, habit={habit_id} when creating penalty - creating new record")
            
            # Get habit data to find owner
            habit_result = await supabase.table("habits") \
                .select("user_id") \
                .eq("id", habit_id) \
                .execute()
            
            if habit_result.data:
                habit_owner_id = habit_result.data[0]["user_id"]
                
                # Create new analytics record with this penalty
                new_analytics = {
                    "recipient_id": recipient_id,
                    "habit_id": habit_id,
                    "habit_owner_id": habit_owner_id,
                    "total_completions": 0,
                    "total_failures": 1,
                    "total_required_days": 1,
                    "success_rate": 0.0,
                    "first_recipient_date": penalty_date.isoformat(),
                    "last_penalty_date": penalty_date.isoformat(),
                    "total_earned": 0,
                    "pending_earnings": penalty_amount
                }
                
                await supabase.table("recipient_analytics") \
                    .insert(new_analytics) \
                    .execute()
                    
                logger.info(f"Created new analytics record for penalty: recipient={recipient_id}, habit={habit_id}, amount={penalty_amount}")
            else:
                logger.error(f"Could not find habit {habit_id} to create analytics record")
            
    except Exception as e:
        logger.error(f"Error updating analytics on penalty creation: {e}")

async def update_analytics_on_habit_verified(
    supabase: AsyncClient,
    habit_id: str,
    recipient_id: str,
    verification_date: date
):
    """
    Update recipient analytics when a habit is successfully verified.
    
    Args:
        supabase: Database client
        habit_id: ID of the habit that was verified
        recipient_id: ID of the recipient monitoring this habit
        verification_date: Date the habit was verified
    """
    try:
        if not recipient_id:
            return  # No recipient to update analytics for
        
        # Get current analytics for this recipient/habit combination
        analytics_result = await supabase.table("recipient_analytics") \
            .select("*") \
            .eq("recipient_id", recipient_id) \
            .eq("habit_id", habit_id) \
            .execute()
        
        if analytics_result.data:
            # Update existing analytics
            current_analytics = analytics_result.data[0]
            
            update_data = {
                "total_completions": current_analytics["total_completions"] + 1,
                "total_required_days": current_analytics["total_required_days"] + 1,
                "last_verification_date": verification_date.isoformat(),
                "updated_at": datetime.utcnow().isoformat()
            }
            
            # Recalculate success rate
            new_total_required = update_data["total_required_days"]
            if new_total_required > 0:
                success_rate = (update_data["total_completions"] / new_total_required) * 100
                update_data["success_rate"] = round(success_rate, 2)
            
            await supabase.table("recipient_analytics") \
                .update(update_data) \
                .eq("id", current_analytics["id"]) \
                .execute()
                
            logger.info(f"Updated analytics for verification: recipient={recipient_id}, habit={habit_id}")
        else:
            logger.warning(f"No analytics record found for recipient={recipient_id}, habit={habit_id} when verifying habit - creating new record")
            
            # Get habit data to find owner
            habit_result = await supabase.table("habits") \
                .select("user_id") \
                .eq("id", habit_id) \
                .execute()
            
            if habit_result.data:
                habit_owner_id = habit_result.data[0]["user_id"]
                
                # Create new analytics record with this verification
                new_analytics = {
                    "recipient_id": recipient_id,
                    "habit_id": habit_id,
                    "habit_owner_id": habit_owner_id,
                    "total_completions": 1,
                    "total_failures": 0,
                    "total_required_days": 1,
                    "success_rate": 100.0,
                    "first_recipient_date": verification_date.isoformat(),
                    "last_verification_date": verification_date.isoformat(),
                    "total_earned": 0,
                    "pending_earnings": 0
                }
                
                await supabase.table("recipient_analytics") \
                    .insert(new_analytics) \
                    .execute()
                    
                logger.info(f"Created new analytics record for verification: recipient={recipient_id}, habit={habit_id}")
            else:
                logger.error(f"Could not find habit {habit_id} to create analytics record")
            
    except Exception as e:
        logger.error(f"Error updating analytics on habit verification: {e}")

async def update_analytics_on_weekly_penalty_created(
    supabase: AsyncClient,
    habit_id: str,
    recipient_id: str,
    penalty_amount: float,
    penalty_date: date,
    completions: int,
    target: int,
    missed_count: int
):
    """
    Update recipient analytics when a weekly habit penalty is created.
    This handles partial completions properly.
    
    Args:
        supabase: Database client
        habit_id: ID of the habit that had a penalty
        recipient_id: ID of the recipient who will receive the penalty payment
        penalty_amount: Total amount of the penalty
        penalty_date: Date the penalty was incurred (week end date)
        completions: Number of completions achieved
        target: Target number of completions for the week
        missed_count: Number of missed completions
    """
    try:
        if not recipient_id:
            return  # No recipient to update analytics for
        
        # Get current analytics for this recipient/habit combination
        analytics_result = await supabase.table("recipient_analytics") \
            .select("*") \
            .eq("recipient_id", recipient_id) \
            .eq("habit_id", habit_id) \
            .execute()
        
        if analytics_result.data:
            # Update existing analytics
            current_analytics = analytics_result.data[0]
            
            update_data = {
                "total_completions": current_analytics["total_completions"] + completions,
                "total_failures": current_analytics["total_failures"] + missed_count,
                "total_required_days": current_analytics["total_required_days"] + target,
                "pending_earnings": float(current_analytics["pending_earnings"]) + penalty_amount,
                "last_penalty_date": penalty_date.isoformat(),
                "updated_at": datetime.utcnow().isoformat()
            }
            
            # Recalculate success rate
            new_total_required = update_data["total_required_days"]
            if new_total_required > 0:
                success_rate = (update_data["total_completions"] / new_total_required) * 100
                update_data["success_rate"] = round(success_rate, 2)
            
            await supabase.table("recipient_analytics") \
                .update(update_data) \
                .eq("id", current_analytics["id"]) \
                .execute()
                
            logger.info(f"Updated analytics for weekly penalty: recipient={recipient_id}, habit={habit_id}, "
                       f"completions={completions}/{target}, missed={missed_count}, amount={penalty_amount}")
        else:
            logger.warning(f"No analytics record found for recipient={recipient_id}, habit={habit_id} when creating weekly penalty - creating new record")
            
            # Get habit data to find owner
            habit_result = await supabase.table("habits") \
                .select("user_id") \
                .eq("id", habit_id) \
                .execute()
            
            if habit_result.data:
                habit_owner_id = habit_result.data[0]["user_id"]
                
                # Create new analytics record with this weekly penalty
                success_rate = 0.0
                if target > 0:
                    success_rate = (completions / target) * 100
                
                new_analytics = {
                    "recipient_id": recipient_id,
                    "habit_id": habit_id,
                    "habit_owner_id": habit_owner_id,
                    "total_completions": completions,
                    "total_failures": missed_count,
                    "total_required_days": target,
                    "success_rate": round(success_rate, 2),
                    "first_recipient_date": penalty_date.isoformat(),
                    "last_penalty_date": penalty_date.isoformat(),
                    "total_earned": 0,
                    "pending_earnings": penalty_amount
                }
                
                await supabase.table("recipient_analytics") \
                    .insert(new_analytics) \
                    .execute()
                    
                logger.info(f"Created new analytics record for weekly penalty: recipient={recipient_id}, "
                           f"habit={habit_id}, completions={completions}/{target}")
            else:
                logger.error(f"Could not find habit {habit_id} to create analytics record")
            
    except Exception as e:
        logger.error(f"Error updating analytics on weekly penalty creation: {e}")

async def update_analytics_on_penalty_paid(
    supabase: AsyncClient,
    habit_id: str,
    recipient_id: str,
    penalty_amount: float
):
    """
    Update recipient analytics when a penalty is paid (move from pending to earned).
    
    Args:
        supabase: Database client
        habit_id: ID of the habit that had the penalty
        recipient_id: ID of the recipient who received the payment
        penalty_amount: Amount that was paid
    """
    try:
        if not recipient_id:
            return  # No recipient to update analytics for
        
        # Get current analytics for this recipient/habit combination
        analytics_result = await supabase.table("recipient_analytics") \
            .select("*") \
            .eq("recipient_id", recipient_id) \
            .eq("habit_id", habit_id) \
            .execute()
        
        if analytics_result.data:
            # Update existing analytics
            current_analytics = analytics_result.data[0]
            
            update_data = {
                "total_earned": float(current_analytics["total_earned"]) + penalty_amount,
                "pending_earnings": float(current_analytics["pending_earnings"]) - penalty_amount,
                "updated_at": datetime.utcnow().isoformat()
            }
            
            # Ensure pending_earnings doesn't go negative
            if update_data["pending_earnings"] < 0:
                update_data["pending_earnings"] = 0
            
            await supabase.table("recipient_analytics") \
                .update(update_data) \
                .eq("id", current_analytics["id"]) \
                .execute()
                
            logger.info(f"Updated analytics for penalty payment: recipient={recipient_id}, habit={habit_id}, amount={penalty_amount}")
        else:
            logger.warning(f"No analytics record found for recipient={recipient_id}, habit={habit_id} when processing penalty payment")
            
    except Exception as e:
        logger.error(f"Error updating analytics on penalty payment: {e}")

async def recalculate_recipient_analytics(
    supabase: AsyncClient,
    recipient_id: str,
    habit_id: str
):
    """
    Recalculate all analytics for a specific recipient/habit combination from scratch.
    This can be used to fix inconsistencies or initialize analytics for existing habits.
    
    Args:
        supabase: Database client
        recipient_id: ID of the recipient
        habit_id: ID of the habit
    """
    try:
        # Get habit information
        habit_result = await supabase.table("habits") \
            .select("*") \
            .eq("id", habit_id) \
            .eq("recipient_id", recipient_id) \
            .execute()
        
        if not habit_result.data:
            logger.warning(f"No habit found with id={habit_id} and recipient_id={recipient_id}")
            return
        
        habit = habit_result.data[0]
        
        # Get all penalties for this habit
        penalties_result = await supabase.table("penalties") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .eq("recipient_id", recipient_id) \
            .execute()
        
        # Get all verifications for this habit
        verifications_result = await supabase.table("habit_verifications") \
            .select("*") \
            .eq("habit_id", habit_id) \
            .execute()
        
        # Calculate metrics
        penalties = penalties_result.data or []
        verifications = verifications_result.data or []
        
        total_earned = sum(float(p["amount"]) for p in penalties if p["is_paid"])
        pending_earnings = sum(float(p["amount"]) for p in penalties if not p["is_paid"])
        total_failures = len(penalties)
        total_completions = len(verifications)
        total_required_days = total_completions + total_failures
        
        success_rate = 0.0
        if total_required_days > 0:
            success_rate = (total_completions / total_required_days) * 100
        
        # Get dates
        first_recipient_date = datetime.fromisoformat(habit["created_at"].replace('Z', '+00:00')).date()
        last_verification_date = None
        last_penalty_date = None
        
        if verifications:
            latest_verification = max(verifications, key=lambda v: v["verified_at"])
            last_verification_date = datetime.fromisoformat(latest_verification["verified_at"]).date()
        
        if penalties:
            latest_penalty = max(penalties, key=lambda p: p["penalty_date"])
            last_penalty_date = datetime.fromisoformat(latest_penalty["penalty_date"]).date()
        
        # Update or create analytics record
        analytics_data = {
            "recipient_id": recipient_id,
            "habit_id": habit_id,
            "habit_owner_id": habit["user_id"],
            "total_earned": total_earned,
            "pending_earnings": pending_earnings,
            "total_completions": total_completions,
            "total_failures": total_failures,
            "total_required_days": total_required_days,
            "success_rate": round(success_rate, 2),
            "first_recipient_date": first_recipient_date.isoformat(),
            "last_verification_date": last_verification_date.isoformat() if last_verification_date else None,
            "last_penalty_date": last_penalty_date.isoformat() if last_penalty_date else None
        }
        
        # Try to update existing record, or insert new one
        await supabase.table("recipient_analytics") \
            .upsert(analytics_data, on_conflict="recipient_id,habit_id") \
            .execute()
        
        logger.info(f"Recalculated analytics for recipient={recipient_id}, habit={habit_id}")
        
    except Exception as e:
        logger.error(f"Error recalculating recipient analytics: {e}")

async def get_recipient_summary_stats(supabase: AsyncClient, recipient_id: str) -> dict:
    """
    Get summary statistics across all habits where the user is a recipient.
    
    Args:
        supabase: Database client
        recipient_id: ID of the recipient
        
    Returns:
        Dict with summary statistics
    """
    try:
        # Get all analytics for this recipient
        analytics_result = await supabase.table("recipient_analytics") \
            .select("*") \
            .eq("recipient_id", recipient_id) \
            .execute()
        
        if not analytics_result.data:
            return {
                "total_habits_monitored": 0,
                "total_earned_all_time": 0.0,
                "total_pending_all_habits": 0.0,
                "overall_success_rate": 0.0,
                "total_completions_all_habits": 0,
                "total_failures_all_habits": 0
            }
        
        analytics_records = analytics_result.data
        
        total_earned = sum(float(record["total_earned"]) for record in analytics_records)
        pending_earnings = sum(float(record["pending_earnings"]) for record in analytics_records)
        total_completions = sum(record["total_completions"] for record in analytics_records)
        total_failures = sum(record["total_failures"] for record in analytics_records)
        total_required_days = sum(record["total_required_days"] for record in analytics_records)
        
        overall_success_rate = 0.0
        if total_required_days > 0:
            overall_success_rate = (total_completions / total_required_days) * 100
        
        return {
            "total_habits_monitored": len(analytics_records),
            "total_earned_all_time": total_earned,
            "total_pending_all_habits": pending_earnings,
            "overall_success_rate": round(overall_success_rate, 2),
            "total_completions_all_habits": total_completions,
            "total_failures_all_habits": total_failures
        }
        
    except Exception as e:
        logger.error(f"Error getting recipient summary stats: {e}")
        return {} 