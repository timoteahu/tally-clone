from fastapi import HTTPException
from models.schemas import User, HabitWithAnalytics
from supabase._async.client import AsyncClient
from typing import List
from utils.encoders import UUIDEncoder
import json
from datetime import datetime, timedelta
from uuid import UUID
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from services.notification_service import NotificationService
from utils.recipient_analytics import get_recipient_summary_stats
import pytz
import logging

logger = logging.getLogger(__name__)
notification_service = NotificationService()

@memory_optimized(cleanup_args=False)
@memory_profile("get_habits_as_recipient_service")
async def get_habits_as_recipient_service(
    include_inactive: bool = False,
    current_user: User = None,
    supabase: AsyncClient = None
) -> List[HabitWithAnalytics]:
    """
    OPTIMIZED: Get all habits where the current user is the recipient with analytics data.
    
    Fixed N+1 query problem by using joins and batch queries.
    
    Returns:
        List of habits with analytics where current user is the recipient
    """
    try:
        user_id = str(current_user.id)
        
        # OPTIMIZATION 1: Get habits with owner info in one query using joins
        # Use PostgREST foreign table syntax for efficient joining
        habits_query = supabase.table("habits").select(
            "*, users!habits_user_id_fkey(name, phone_number, last_active, timezone)"
        ).eq("recipient_id", user_id).not_.is_("recipient_id", None)
        
        if not include_inactive:
            habits_query = habits_query.eq("is_active", True)
            
        habits_result = await habits_query.execute()
        
        if not habits_result.data:
            return []
        
        # OPTIMIZATION 2: Batch fetch analytics for all habits in one query
        habit_ids = [habit['id'] for habit in habits_result.data]
        analytics_result = await supabase.table("recipient_analytics").select("*").eq("recipient_id", user_id).in_("habit_id", habit_ids).execute()
        
        # Create analytics lookup dictionary for O(1) access
        analytics_lookup = {item['habit_id']: item for item in analytics_result.data}
        
        # OPTIMIZATION 3: Batch fetch weekly progress for weekly habits only
        weekly_habit_ids = [h['id'] for h in habits_result.data if h.get('habit_schedule_type') == 'weekly']
        weekly_progress_lookup = {}
        
        if weekly_habit_ids:
            # Calculate current week start dates for each habit
            today = datetime.now().date()
            
            # For now, use a simplified approach - could be further optimized by grouping by week_start_day
            progress_queries = []
            for habit in habits_result.data:
                if habit.get('habit_schedule_type') == 'weekly':
                    week_start_day = habit.get('week_start_day', 0)
                    days_since_week_start = (today.weekday() + 1 - week_start_day) % 7
                    week_start = today - timedelta(days=days_since_week_start)
                    progress_queries.append((habit['id'], week_start.isoformat()))
            
            # Batch fetch all weekly progress in one query
            if progress_queries:
                # Create a list of (habit_id, week_start_date) pairs
                habit_week_pairs = [(hid, wstart) for hid, wstart in progress_queries]
                
                # Use OR conditions to fetch all at once (PostgREST supports this)
                progress_result = await supabase.table("weekly_habit_progress").select("*").in_("habit_id", weekly_habit_ids).execute()
                
                # Filter and create lookup
                for item in progress_result.data:
                    # Match with the correct week for each habit
                    for habit_id, week_start_date in habit_week_pairs:
                        if item['habit_id'] == habit_id and item['week_start_date'] == week_start_date:
                            weekly_progress_lookup[habit_id] = item
                            break
        
        # OPTIMIZATION 4: Build response with O(1) lookups instead of N queries
        habits_with_analytics = []
        
        for habit_data in habits_result.data:
            habit_id = habit_data['id']
            
            # Convert habit data to proper format (remove joined user data to avoid conflicts)
            user_data = habit_data.pop('users', None)  # Extract user data before JSON conversion
            habit_json = json.loads(json.dumps(habit_data, cls=UUIDEncoder))
            
            # OPTIMIZATION 5: Get analytics data from lookup (O(1) instead of query per habit)
            analytics_data = None
            if habit_id in analytics_lookup:
                analytics_raw = analytics_lookup[habit_id]
                
                # Check for today's verification in real-time (this is the only per-habit query we keep)
                today_verification_date = None
                last_verification_date = None
                
                if user_data:
                    owner_timezone = user_data.get('timezone', 'UTC')
                    try:
                        owner_tz = pytz.timezone(owner_timezone)
                        today_in_owner_tz = datetime.now(owner_tz).date()
                        
                        start_of_today = datetime.combine(today_in_owner_tz, datetime.min.time())
                        end_of_today = datetime.combine(today_in_owner_tz, datetime.max.time())
                        
                        start_of_today_utc = owner_tz.localize(start_of_today).astimezone(pytz.UTC)
                        end_of_today_utc = owner_tz.localize(end_of_today).astimezone(pytz.UTC)
                        
                        today_verification = await supabase.table("habit_verifications") \
                            .select("verified_at") \
                            .eq("habit_id", habit_id) \
                            .eq("verification_result", True) \
                            .gte("verified_at", start_of_today_utc.isoformat()) \
                            .lte("verified_at", end_of_today_utc.isoformat()) \
                            .execute()
                        
                        if today_verification.data:
                            today_verification_date = today_in_owner_tz
                    except Exception as e:
                        logger.warning(f"Error checking today's verification for habit {habit_id}: {e}")
                
                # Use today's verification date if available, otherwise use the one from analytics
                last_verification_date = today_verification_date or (
                    datetime.fromisoformat(analytics_raw['last_verification_date']).date() 
                    if analytics_raw['last_verification_date'] else None
                )
                
                analytics_data = {
                    "id": UUID(analytics_raw['id']),
                    "recipient_id": UUID(analytics_raw['recipient_id']),
                    "habit_id": UUID(analytics_raw['habit_id']),
                    "habit_owner_id": UUID(analytics_raw['habit_owner_id']),
                    "total_earned": float(analytics_raw['total_earned']),
                    "pending_earnings": float(analytics_raw['pending_earnings']),
                    "total_completions": analytics_raw['total_completions'],
                    "total_failures": analytics_raw['total_failures'],
                    "total_required_days": analytics_raw['total_required_days'],
                    "success_rate": float(analytics_raw['success_rate']),
                    "first_recipient_date": datetime.fromisoformat(analytics_raw['first_recipient_date']).date(),
                    "last_verification_date": last_verification_date,
                    "last_penalty_date": datetime.fromisoformat(analytics_raw['last_penalty_date']).date() if analytics_raw['last_penalty_date'] else None,
                    "created_at": datetime.fromisoformat(analytics_raw['created_at'].replace('Z', '+00:00')),
                    "updated_at": datetime.fromisoformat(analytics_raw['updated_at'].replace('Z', '+00:00'))
                }
            
            # OPTIMIZATION 6: Get owner info from join (no additional query)
            owner_name = None
            owner_phone = None
            owner_last_active = None
            owner_timezone = None
            if user_data:
                owner_name = user_data.get('name')
                owner_phone = user_data.get('phone_number')
                owner_timezone = user_data.get('timezone')
                owner_last_active_str = user_data.get('last_active')
                if owner_last_active_str:
                    owner_last_active = datetime.fromisoformat(owner_last_active_str.replace('Z', '+00:00'))
            
            # OPTIMIZATION 7: Get weekly progress from lookup (O(1) instead of query per habit)
            weekly_progress_data = None
            if habit_id in weekly_progress_lookup:
                progress_raw = weekly_progress_lookup[habit_id]
                weekly_progress_data = {
                    "current_completions": progress_raw['current_completions'],
                    "target_completions": progress_raw['target_completions'],
                    "week_start_date": datetime.fromisoformat(progress_raw['week_start_date']).date()
                }
            
            # Create HabitWithAnalytics object
            habit_with_analytics = {
                **habit_json,
                "analytics": analytics_data,
                "owner_name": owner_name,
                "owner_phone": owner_phone,
                "owner_last_active": owner_last_active,
                "owner_timezone": owner_timezone,
                "weekly_progress": weekly_progress_data
            }
            
            # Reduced logging for better performance
            if logger.isEnabledFor(logging.DEBUG):
                logger.debug(f"[RecipientHabits] Processed habit: {habit_json.get('name')}")
            
            habits_with_analytics.append(habit_with_analytics)
        
        return habits_with_analytics
        
    except Exception as e:
        logger.error(f"Error getting habits where user {current_user.id} is recipient: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("get_recipient_summary_service")
async def get_recipient_summary_service(
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """
    Get summary statistics for the current user as a recipient across all habits.
    
    Returns aggregate data like total earnings, success rates, and habit counts
    for all habits where the current user is the accountability partner.
    
    Returns:
        Dict with summary statistics for the recipient
    """
    try:
        user_id = str(current_user.id)
        
        # Get summary statistics using the utility function
        summary_stats = await get_recipient_summary_stats(supabase, user_id)
        
        return {
            "recipient_id": user_id,
            "summary": summary_stats
        }
        
    except Exception as e:
        logger.error(f"Error getting recipient summary for user {current_user.id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("send_tickle_notification_service")
async def send_tickle_notification_service(
    habit_id: str,
    custom_message: str,
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """
    Send a tickle notification to a habit owner when they haven't completed their habit.
    Only the habit's recipient can send tickles.
    """
    try:
        # Normalize the habit_id to handle case sensitivity
        habit_id = habit_id.lower()
        user_id = str(current_user.id)
        
        logger.info(f"Tickle request for habit {habit_id} by user {user_id}")
        
        # OPTIMIZATION: Use specific column selection instead of SELECT *
        try:
            habit_check_result = await supabase.table("habits").select(
                "id, name, user_id, is_active"
            ).eq("recipient_id", user_id).eq("id", habit_id).execute()
        except Exception as e:
            logger.error(f"Error querying habit {habit_id} for recipient check: {str(e)}")
            raise HTTPException(status_code=404, detail=f"Unable to verify habit access: {str(e)}")
        
        if not habit_check_result.data:
            logger.warning(f"Habit {habit_id} not found or user {user_id} is not the recipient")
            raise HTTPException(status_code=404, detail="Habit not found or you are not the recipient")
        
        habit = habit_check_result.data[0]
        
        # OPTIMIZATION: Get only needed owner info
        owner_result = await supabase.table("users").select("name").eq("id", habit['user_id']).execute()
        owner_info = owner_result.data[0] if owner_result.data else {}
        
        # Check if habit is active
        if not habit.get("is_active", True):
            raise HTTPException(status_code=400, detail="Cannot tickle inactive habits")
        
        # Get recipient (tickler) name
        tickler_name = current_user.name or "Your accountability partner"
        
        # Send tickle notification immediately using notification service
        try:
            await notification_service.send_tickle_notification(
                recipient_user_id=habit["user_id"],
                tickler_name=tickler_name,
                habit_name=habit['name'],
                supabase_client=supabase,
                custom_message=custom_message if custom_message else None
            )
            logger.info(f"Tickle notification sent for habit {habit_id} by user {current_user.id} ({tickler_name})")
            
        except Exception as e:
            logger.error(f"Failed to send tickle notification: {str(e)}")
            # Don't fail the entire request if notification fails
        
        # Get owner name from the query
        owner_name = owner_info.get('name', 'the habit owner')
        
        return {
            "success": True,
            "message": f"Tickle sent to {owner_name}",
            "habit_id": habit_id,
            "habit_name": habit["name"]
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error sending tickle: {e}")
        raise HTTPException(status_code=500, detail=str(e)) 