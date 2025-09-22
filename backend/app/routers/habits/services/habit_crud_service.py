from fastapi import HTTPException
from models.schemas import Habit, HabitCreate, HabitUpdate, User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from typing import List, Optional, Dict, Any
from utils.encoders import UUIDEncoder
from utils.weekly_habits import initialize_weekly_progress
import json
from datetime import datetime, timedelta, timezone, date
import pytz
from uuid import UUID
import uuid
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from services.habit_notification_scheduler import habit_notification_scheduler
from utils.activity_tracking import track_user_activity
from utils.friends_filter import get_eligible_friends_with_stripe
from pydantic import BaseModel
import logging
from ..utils.habit_validation import (
    validate_custom_habit_type, 
    validate_recipient_stripe_connect, 
    validate_unique_recipients,
    is_custom_habit_type
)
from ..utils.habit_helpers import get_user_timezone, get_localized_datetime

logger = logging.getLogger(__name__)

class HabitCreateResponse(BaseModel):
    """Enhanced response for habit creation that includes updated friends data"""
    habit: Habit
    updated_friends_with_stripe: Optional[List[Dict[str, Any]]] = None
    friends_data_changed: bool = False

def _convert_uuids_to_strings(data: dict) -> dict:
    """Utility function to convert UUID fields to strings efficiently"""
    uuid_fields = ['user_id', 'custom_habit_type_id', 'recipient_id']
    for field in uuid_fields:
        if field in data and data[field]:
            data[field] = str(data[field])
    return data

def _convert_uuids_for_response(habit_data: dict) -> dict:
    """Convert string UUIDs back to UUID objects for response"""
    uuid_fields = ['id', 'user_id', 'custom_habit_type_id', 'recipient_id']
    for field in uuid_fields:
        if field in habit_data and habit_data[field]:
            habit_data[field] = UUID(habit_data[field])
    return habit_data

@memory_optimized(cleanup_args=False)
@memory_profile("create_habit_service")
async def create_habit_service(
    habit: HabitCreate, 
    current_user: User,
    supabase: AsyncClient
) -> HabitCreateResponse:
    """
    Create a new habit with optimized memory usage and integrated services.
    Handles all habit types including LeetCode habits with automatic progress initialization.
    
    Args:
        habit: Habit creation data
        current_user: Current authenticated user
        supabase: Database client
        
    Returns:
        HabitCreateResponse with created habit and optional friends data
    """
    try:
        # Track user activity when creating a habit
        await track_user_activity(supabase, str(current_user.id))
        
        habit_dict = habit.model_dump()
        habit_dict = _convert_uuids_to_strings(habit_dict)
        
        # Validate that the user_id matches the current user
        if str(current_user.id).lower() != habit_dict['user_id'].lower():
            raise HTTPException(status_code=403, detail="Cannot create habit for another user")
        
        # Check if this habit creation will affect friends filtering
        user_id = str(current_user.id)
        recipient_id = habit_dict.get('recipient_id')
        will_affect_friends_filter = False
        
        if recipient_id:
            # OPTIMIZATION: Batch query to get user data and unique recipients count in one go
            # Get user premium status and unique recipient count using a single RPC call
            user_stats_result = await supabase.rpc("get_user_habit_stats_optimized", {
                "p_user_id": user_id
            }).execute()
            
            if user_stats_result.data and len(user_stats_result.data) > 0:
                stats = user_stats_result.data[0]
                is_premium = stats.get("is_premium", False)
                unique_recipients_count = stats.get("unique_recipients_count", 0)
                
                # If currently < 3 unique recipients and not premium, this creation might affect the filter
                if not is_premium and unique_recipients_count < 3:
                    will_affect_friends_filter = True
        
        # Validate recipient has Stripe Connect
        await validate_recipient_stripe_connect(
            recipient_id=recipient_id,
            supabase=supabase
        )
        
        # Validate unique recipients rule
        await validate_unique_recipients(
            user_id=user_id,
            new_recipient_id=recipient_id,
            current_habit_id=None,  # This is a new habit
            supabase=supabase
        )
        
        # Validate alarm_time format if provided
        if habit_dict.get('alarm_time'):
            try:
                # Validate HH:mm format
                datetime.strptime(habit_dict['alarm_time'], '%H:%M')
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid alarm_time format. Must be in HH:mm format")
        
        # Validate custom habit type if provided
        if habit_dict.get('custom_habit_type_id'):
            custom_habit_type_id = str(habit_dict['custom_habit_type_id'])
            is_valid = await validate_custom_habit_type(custom_habit_type_id, user_id, supabase)
            if not is_valid:
                raise HTTPException(
                    status_code=400, 
                    detail="Invalid custom habit type. The custom habit type does not exist or does not belong to you."
                )
            
            # Ensure the habit_type is properly formatted for custom types
            if is_custom_habit_type(habit_dict['habit_type']):
                # Get the custom habit type details to validate the habit_type format
                custom_type_result = await supabase.table("active_custom_habit_types").select("type_identifier").eq(
                    "id", custom_habit_type_id
                ).execute()
                
                if custom_type_result.data:
                    expected_habit_type = f"custom_{custom_type_result.data[0]['type_identifier']}"
                    if habit_dict['habit_type'] != expected_habit_type:
                        habit_dict['habit_type'] = expected_habit_type
        
        # Validate built-in habit types
        elif habit_dict['habit_type'] not in [
            'gym', 'studying', 'screenTime', 'alarm', 'yoga', 'outdoors', 'cycling', 'cooking', 
            'github_commits', 'leetcode', 'league_of_legends', 'valorant',
            # Apple Health habit types
            'health_steps', 'health_walking_running_distance', 'health_flights_climbed',
            'health_exercise_minutes', 'health_cycling_distance', 'health_sleep_hours',
            'health_calories_burned', 'health_mindful_minutes'
        ] and not is_custom_habit_type(habit_dict['habit_type']):
            raise HTTPException(status_code=400, detail="Invalid habit type")
        
        # Handle one_time habit schedule type specifics
        if habit_dict.get('habit_schedule_type') == 'one_time':
            # Clear weekdays and weekly_target fields for one_time habits
            habit_dict['weekdays'] = None
            habit_dict['weekly_target'] = None
            # Target count is implicitly 1 for one_time habits (handled by database constraint)
        
        # Handle weekly habit schedule type specifics
        elif habit_dict.get('habit_schedule_type') == 'weekly':
            logger.info(f"Creating weekly habit. Input: habit_type={habit_dict.get('habit_type')}, weekly_target={habit_dict.get('weekly_target')}, weekdays={habit_dict.get('weekdays')}")
            
            # For weekly habits, weekdays should be NULL (database constraint requirement)
            habit_dict['weekdays'] = None
            
            logger.info(f"Final weekly habit data: weekdays={habit_dict.get('weekdays')}, weekly_target={habit_dict.get('weekly_target')}, commit_target={habit_dict.get('commit_target')}")
        
        # Handle daily habit specific fields
        elif habit_dict.get('habit_schedule_type') == 'daily':
            # Ensure LeetCode daily habits have commit_target set
            if habit_dict.get('habit_type') == 'leetcode':
                if 'commit_target' not in habit_dict or habit_dict['commit_target'] is None:
                    logger.warning(f"LeetCode daily habit missing commit_target, setting default to 1")
                    habit_dict['commit_target'] = 1  # Default to 1 problem per day
        
        # Create the habit
        result = await supabase.table("habits").insert(habit_dict).execute()
        new_habit = result.data[0]
        
        # OPTIMIZATION: Use efficient UUID conversion for response
        new_habit = _convert_uuids_for_response(new_habit)

        # Initialize weekly progress if this is a weekly habit
        if habit_dict.get('habit_schedule_type') == 'weekly':
            try:
                await initialize_weekly_progress(supabase, new_habit)
                
                # For GitHub weekly habits, also update the progress with current commit count
                if habit_dict.get('habit_type') == 'github_commits':
                    from utils.github_commits import update_github_weekly_progress
                    from utils.weekly_habits import get_week_dates
                    from datetime import date
                    
                    # Get current week dates for this habit
                    today = date.today()
                    week_start_day = new_habit.get('week_start_day', 0)
                    week_start, week_end = get_week_dates(today, week_start_day)
                    
                    # Update with current commit count
                    await update_github_weekly_progress(
                        supabase=supabase,
                        user_id=str(new_habit['user_id']),
                        habit_id=str(new_habit['id']),
                        week_start_date=week_start,
                        weekly_target=new_habit.get('weekly_target', 7),
                        week_start_day=week_start_day
                    )
                    
                    logger.info(f"Initialized GitHub weekly progress for habit {new_habit['id']}")
                
                # For LeetCode weekly habits, also update the progress with current problem count
                elif habit_dict.get('habit_type') == 'leetcode':
                    from .habit_leetcode_service import update_leetcode_weekly_progress_service
                    from utils.weekly_habits import get_week_dates
                    from datetime import date
                    
                    # Get current week dates for this habit
                    today = date.today()
                    week_start_day = new_habit.get('week_start_day', 0)
                    week_start, week_end = get_week_dates(today, week_start_day)
                    
                    # Update with current problem count using internal service
                    await update_leetcode_weekly_progress_service(
                        habit_id=str(new_habit['id']),
                        week_start_date=week_start,
                        weekly_target=new_habit.get('commit_target', 3),  # LeetCode uses commit_target
                        week_start_day=week_start_day,
                        current_user=current_user,
                        supabase=supabase
                    )
                    
                    logger.info(f"Initialized LeetCode weekly progress for habit {new_habit['id']}")
                    
            except Exception as e:
                logger.error(f"Failed to initialize weekly progress for habit {new_habit['id']}: {e}")
                # Don't fail the entire habit creation if weekly progress initialization fails
        
        # For daily GitHub/LeetCode habits, update today's count
        elif habit_dict.get('habit_schedule_type') == 'daily':
            try:
                if habit_dict.get('habit_type') == 'github_commits':
                    from utils.github_commits import get_github_commits_for_date
                    from datetime import date
                    import pytz
                    
                    # Get user's timezone
                    user_result = await supabase.table("users").select("timezone").eq("id", str(new_habit['user_id'])).execute()
                    user_timezone = user_result.data[0]['timezone'] if user_result.data else 'UTC'
                    user_tz = pytz.timezone(user_timezone)
                    today = datetime.now(user_tz).date()
                    
                    # Get today's commits
                    commits_today = await get_github_commits_for_date(supabase, str(new_habit['user_id']), today)
                    logger.info(f"GitHub habit {new_habit['id']} - commits today: {commits_today}")
                    
                elif habit_dict.get('habit_type') == 'leetcode':
                    from utils.leetcode_api import LeetCodeAPI
                    from datetime import date
                    import pytz
                    
                    # Get user's timezone
                    user_result = await supabase.table("users").select("timezone").eq("id", str(new_habit['user_id'])).execute()
                    user_timezone = user_result.data[0]['timezone'] if user_result.data else 'UTC'
                    user_tz = pytz.timezone(user_timezone)
                    today = datetime.now(user_tz).date()
                    
                    # Get LeetCode username
                    from ..utils.leetcode_helpers import get_leetcode_username_for_user
                    username = await get_leetcode_username_for_user(supabase, str(new_habit['user_id']))
                    
                    if username:
                        # Get today's problems using LeetCode API directly
                        problems_today = await LeetCodeAPI.get_daily_problems_solved(username, today)
                        logger.info(f"LeetCode habit {new_habit['id']} - problems solved today: {problems_today}")
                    else:
                        logger.warning(f"No LeetCode username found for user {new_habit['user_id']}")
                    
            except Exception as e:
                logger.error(f"Failed to fetch initial daily count for habit {new_habit['id']}: {e}")
                # Don't fail habit creation if initial count fetch fails
        
        # Schedule notifications for the new habit
        try:
            # OPTIMIZATION: Use efficient UUID conversion for scheduler
            habit_data_for_scheduler = {**new_habit}
            for uuid_field in ['id', 'user_id', 'custom_habit_type_id', 'recipient_id']:
                if uuid_field in habit_data_for_scheduler and isinstance(habit_data_for_scheduler[uuid_field], UUID):
                    habit_data_for_scheduler[uuid_field] = str(habit_data_for_scheduler[uuid_field])
                
            await habit_notification_scheduler.schedule_notifications_for_habit(
                habit_data_for_scheduler, supabase
            )
            logger.info(f"Scheduled notifications for new habit {new_habit['id']}")
        except Exception as e:
            logger.error(f"Failed to schedule notifications for habit {new_habit['id']}: {e}")
            # Don't fail habit creation if notification scheduling fails
        
        # If this habit creation affects friends filtering, get updated friends with Stripe data
        updated_friends_with_stripe = None
        if will_affect_friends_filter:
            try:
                # OPTIMIZATION: Get all friends with their Stripe info in a single optimized RPC call
                friends_result = await supabase.rpc("get_user_friends_with_stripe_optimized", {
                    "p_user_id": user_id
                }).execute()
                
                if friends_result.data:
                    # Friends are already filtered for active Stripe Connect by the RPC
                    friends_with_stripe = friends_result.data
                    
                    # Apply the unique recipients restriction filter
                    updated_friends_with_stripe = await get_eligible_friends_with_stripe(
                        supabase, user_id, friends_with_stripe
                    )
                    
                    logger.info(f"✅ [Habit Creation] Updated friends_with_stripe: {len(updated_friends_with_stripe)}/{len(friends_with_stripe)} eligible")
                
            except Exception as e:
                logger.error(f"❌ [Habit Creation] Error fetching updated friends data: {e}")
                # Don't fail habit creation if friends update fails
                pass
        
        return HabitCreateResponse(
            habit=new_habit,
            updated_friends_with_stripe=updated_friends_with_stripe,
            friends_data_changed=will_affect_friends_filter and updated_friends_with_stripe is not None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating habit: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("get_user_habits_service")
async def get_user_habits_service(
    user_id: str, 
    current_user: User,
    supabase: AsyncClient,
    include_completed: bool = False
) -> List[Habit]:
    """
    Get all habits for a user.
    
    Args:
        user_id: ID of the user to get habits for
        include_completed: Whether to include completed one-time habits (default: False)
        
    Returns:
        List of habits
    """
    try:
        # Verify user permissions
        if str(current_user.id) != user_id:
            raise HTTPException(status_code=403, detail="Can only access your own habits")
        
        # OPTIMIZATION: Use selective column fetching instead of SELECT *
        columns = "id, name, recipient_id, habit_type, weekdays, penalty_amount, user_id, created_at, updated_at, study_duration_minutes, screen_time_limit_minutes, restricted_apps, alarm_time, custom_habit_type_id, habit_schedule_type, weekly_target, week_start_day, streak, commit_target, health_target_value, health_target_unit, health_data_type, is_active, completed_at"
        
        # Build the query - start with only active habits by default
        query = supabase.table("habits").select(columns)
        
        # Apply filters based on parameters
        if include_completed:
            # If include_completed is True, get all habits for the user (active and completed)
            query = query.eq("user_id", user_id)
        else:
            # Otherwise only get active habits (is_active = true)
            # This will filter out completed one-time habits
            query = query.eq("user_id", user_id).eq("is_active", True)
        
        # Execute the query
        result = await query.execute()
        
        # If no habits found, return empty list
        if not result.data:
            return []
        
        # Parse habits data and return
        habits = []
        for habit_data in result.data:
            # Convert to JSON string then parse to handle UUID fields
            habit_json = json.loads(json.dumps(habit_data, cls=UUIDEncoder))
            habit = Habit(**habit_json)
            habits.append(habit)
        
        return habits
    except Exception as e:
        logger.error(f"Error getting habits for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("get_habit_service")
async def get_habit_service(
    habit_id: str, 
    current_user: User,
    supabase: AsyncClient
) -> Habit:
    try:
        # OPTIMIZATION: Use selective column fetching instead of long column list
        columns = "id, name, recipient_id, habit_type, weekdays, penalty_amount, user_id, created_at, updated_at, study_duration_minutes, screen_time_limit_minutes, restricted_apps, alarm_time, custom_habit_type_id, habit_schedule_type, weekly_target, week_start_day, streak, commit_target, health_target_value, health_target_unit, health_data_type"
        result = await supabase.table("habits").select(columns).eq("id", habit_id).eq("is_active", True).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        habit_data = result.data[0]
        
        # Validate that the user can only access their own habits
        if str(current_user.id).lower() != habit_data['user_id'].lower():
            raise HTTPException(status_code=403, detail="Cannot access another user's habit")
        
        # OPTIMIZATION: Use efficient UUID conversion
        habit_data = _convert_uuids_for_response(habit_data)
        return habit_data
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching habit: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("delete_habit_service")
async def delete_habit_service(
    habit_id: str, 
    current_user: User,
    supabase: AsyncClient
) -> dict:
    """
    Soft delete a habit by marking it as inactive (is_active = false).
    
    IMPORTANT: Habits are NEVER hard deleted from the database to maintain:
    - Referential integrity with penalties, analytics, and verifications
    - Payment obligations that were incurred while the habit was active
    - Historical data for recipients and analytics
    
    Deletion timing:
    - Daily habits: Effective at end of current day (after penalty check)
    - Weekly habits: Effective at end of current week
    - Exception: Immediate soft delete if created today and never verified
    """
    try:
        # SAFETY CHECK: Never use .delete() on habits table - always soft delete
        # This is enforced by database trigger, but we check here too
        if not habit_id:
            raise HTTPException(status_code=400, detail="Invalid habit ID")
            
        # First check if the habit exists and belongs to the user
        habit_result = await supabase.table("habits").select("*").eq("id", habit_id).eq("is_active", True).execute()
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        habit_data = habit_result.data[0]
        
        if str(current_user.id).lower() != habit_data['user_id'].lower():
            raise HTTPException(status_code=403, detail="Cannot delete another user's habit")
        
        user_id = str(current_user.id)
        user_timezone = await get_user_timezone(supabase, user_id)
        now = await get_localized_datetime(supabase, user_id)
        
        # Get habit schedule type
        habit_schedule_type = habit_data.get('habit_schedule_type', 'daily')
        
        # Check if habit was created today and has never been verified
        created_at_str = habit_data.get('created_at')
        last_verified_date = habit_data.get('last_verified_date')
        
        if created_at_str and last_verified_date is None:
            # Parse created_at timestamp and convert to user's timezone
            created_at = datetime.fromisoformat(created_at_str.replace('Z', '+00:00'))
            created_at_local = created_at.astimezone(pytz.timezone(user_timezone))
            
            # Check if habit was created today in user's timezone
            if created_at_local.date() == now.date():
                # SOFT DELETE immediately without staging since no penalty will be charged
                # IMPORTANT: Using .update() not .delete() to preserve referential integrity
                await supabase.table("habits").update({
                    "is_active": False,
                    "completed_at": datetime.now(timezone.utc).isoformat()
                }).eq("id", habit_id).execute()
                
                # Clean up any scheduled notifications for this habit
                await supabase.table("scheduled_notifications").delete().eq("habit_id", habit_id).eq("sent", False).execute()
                logger.info(f"Cleaned up unsent notifications for soft-deleted habit {habit_id}")
                
                return {
                    "message": f"Habit deleted immediately. No penalties will be charged since the habit was created today and never verified.",
                    "effective_date": now.date().isoformat(),
                    "timezone": user_timezone,
                    "habit_type": habit_schedule_type,
                    "deletion_timing": "immediate"
                }
        
        # Calculate effective date based on habit type
        if habit_schedule_type == 'weekly':
            # For weekly habits, delete at the end of the current week (Sunday)
            week_start_day = habit_data.get('week_start_day', 0)  # 0 = Sunday
            
            # Calculate the end of the current week based on the habit's week start day
            current_weekday = now.weekday()  # Monday = 0, Sunday = 6
            
            # Convert to match our week start day (0 = Sunday, 1 = Monday, etc.)
            days_since_week_start = (current_weekday + 1 - week_start_day) % 7
            days_until_week_end = 6 - days_since_week_start
            
            effective_date = (now + timedelta(days=days_until_week_end)).date()
            effective_description = f"end of the week (Sunday)"
        else:
            # For daily habits, delete tomorrow (existing behavior)
            effective_date = (now + timedelta(days=1)).date()
            effective_description = f"tomorrow"
        
        # Stage the deletion to take effect at the calculated time
        # The scheduler will check for missed penalties at end of day/week
        staging_data = {
            "habit_id": habit_id,
            "user_id": user_id,
            "change_type": "delete",
            "old_habit_data": json.dumps(habit_data, cls=UUIDEncoder),
            "new_habit_data": None,  # null for delete
            "effective_date": effective_date.isoformat(),
            "user_timezone": user_timezone,
            "applied": False
        }
        
        await supabase.table("habit_change_staging").insert(staging_data).execute()
        
        return {
            "message": f"Habit will be permanently deleted at {effective_description} ({effective_date}) in your timezone ({user_timezone}). If you miss today's requirement, you will be charged at the end of the day.",
            "effective_date": effective_date.isoformat(),
            "timezone": user_timezone,
            "habit_type": habit_schedule_type,
            "deletion_timing": effective_description
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting habit: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("update_habit_service")
async def update_habit_service(
    habit_id: str, 
    habit: HabitUpdate, 
    current_user: User,
    supabase: AsyncClient
) -> dict:
    try:
        # First check if the habit exists and belongs to the user
        habit_result = await supabase.table("habits").select("*").eq("id", habit_id).eq("is_active", True).execute()
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        old_habit_data = habit_result.data[0]
        
        if str(current_user.id).lower() != old_habit_data['user_id'].lower():
            raise HTTPException(status_code=403, detail="Cannot update another user's habit")
        
        habit_dict = habit.model_dump(exclude_unset=True)
        
        # OPTIMIZATION: Use efficient UUID conversion
        habit_dict = _convert_uuids_to_strings(habit_dict)
        
        # Validate alarm_time format if provided
        if habit_dict.get('alarm_time'):
            try:
                # Validate HH:mm format
                datetime.strptime(habit_dict['alarm_time'], '%H:%M')
            except ValueError:
                raise HTTPException(status_code=400, detail="Invalid alarm_time format. Must be in HH:mm format")
        
        # Validate custom habit type if provided
        if habit_dict.get('custom_habit_type_id'):
            custom_habit_type_id = str(habit_dict['custom_habit_type_id'])
            is_valid = await validate_custom_habit_type(custom_habit_type_id, str(current_user.id), supabase)
            if not is_valid:
                raise HTTPException(
                    status_code=400, 
                    detail="Invalid custom habit type. The custom habit type does not exist or does not belong to you."
                )
        
        # Validate habit type if provided
        if habit_dict.get('habit_type'):
            if habit_dict['habit_type'] not in [
                'gym', 'studying', 'screenTime', 'alarm', 'yoga', 'outdoors', 'cycling', 'cooking', 
                'github_commits', 'leetcode', 'league_of_legends', 'valorant',
                # Apple Health habit types
                'health_steps', 'health_walking_running_distance', 'health_flights_climbed',
                'health_exercise_minutes', 'health_cycling_distance', 'health_sleep_hours',
                'health_calories_burned', 'health_mindful_minutes'
            ] and not is_custom_habit_type(habit_dict['habit_type']):
                raise HTTPException(status_code=400, detail="Invalid habit type")
        
        # Validate recipient has Stripe Connect (if recipient is being changed)
        new_recipient_id = habit_dict.get('recipient_id')
        if 'recipient_id' in habit_dict:  # Only validate if recipient_id is in the update
            await validate_recipient_stripe_connect(
                recipient_id=new_recipient_id,
                supabase=supabase
            )
        
        # Validate unique recipients rule
        await validate_unique_recipients(
            user_id=str(current_user.id),
            new_recipient_id=new_recipient_id,
            current_habit_id=habit_id,  # This is an update
            supabase=supabase
        )
        
        user_id = str(current_user.id)
        user_timezone = await get_user_timezone(supabase, user_id)
        now = await get_localized_datetime(supabase, user_id)
        tomorrow = (now + timedelta(days=1)).date()
        
        # Create new habit data by merging old data with updates
        new_habit_data = old_habit_data.copy()
        new_habit_data.update(habit_dict)
        
        # Handle habit-specific parameters (same as create_habit)
        # Add GitHub habit fields
        if new_habit_data.get('habit_type') == 'github_commits':
            # Only set commit_target for daily habits
            if new_habit_data.get('habit_schedule_type') == 'daily':
                if 'commit_target' in habit_dict:
                    new_habit_data['commit_target'] = habit_dict['commit_target']
            # For weekly habits, the target is in weekly_target field, not commit_target
        
        # Add LeetCode habit fields
        if new_habit_data.get('habit_type') == 'leetcode':
            # Set commit_target for daily habits
            if new_habit_data.get('habit_schedule_type') == 'daily':
                if 'commit_target' in habit_dict:
                    new_habit_data['commit_target'] = habit_dict['commit_target']
            # For weekly habits, the target is already handled by schema validation
        
        # Add gaming habit fields
        if new_habit_data.get('habit_type') in ['league_of_legends', 'valorant']:
            if 'daily_limit_hours' in habit_dict:
                new_habit_data['daily_limit_hours'] = habit_dict['daily_limit_hours']
            if 'hourly_penalty_rate' in habit_dict:
                new_habit_data['hourly_penalty_rate'] = habit_dict['hourly_penalty_rate']
            if 'games_tracked' in habit_dict:
                new_habit_data['games_tracked'] = habit_dict['games_tracked']
        
        # Add health habit fields
        if new_habit_data.get('habit_type', '').startswith('health_'):
            if 'health_target_value' in habit_dict:
                new_habit_data['health_target_value'] = habit_dict['health_target_value']
            if 'health_target_unit' in habit_dict:
                new_habit_data['health_target_unit'] = habit_dict['health_target_unit']
            if 'health_data_type' in habit_dict:
                new_habit_data['health_data_type'] = habit_dict['health_data_type']
        
        # Check if changes affect notification scheduling (alarm_time, weekdays, habit_type, etc.)
        notification_affecting_fields = ['alarm_time', 'weekdays', 'habit_type', 'name', 'penalty_amount']
        should_reschedule_notifications = any(
            field in habit_dict for field in notification_affecting_fields
        )
        
        # Stage the update to take effect tomorrow in user's timezone
        # The scheduler will check for missed penalties at end of day
        staging_data = {
            "habit_id": habit_id,
            "user_id": user_id,
            "change_type": "update",
            "old_habit_data": json.dumps(old_habit_data, cls=UUIDEncoder),
            "new_habit_data": json.dumps(new_habit_data, cls=UUIDEncoder),
            "effective_date": tomorrow.isoformat(),
            "user_timezone": user_timezone,
            "applied": False
        }
        
        await supabase.table("habit_change_staging").insert(staging_data).execute()
        
        # If changes affect notifications, reschedule them
        if should_reschedule_notifications:
            try:
                # Delete existing unsent notifications for this habit
                await supabase.table('scheduled_notifications').delete().eq(
                    'habit_id', habit_id
                ).eq('sent', False).execute()
                
                # Schedule new notifications with updated habit data
                await habit_notification_scheduler.schedule_notifications_for_habit(
                    new_habit_data, supabase
                )
                
                logger.info(f"Rescheduled notifications for updated habit {habit_id}")
                
            except Exception as e:
                logger.error(f"Failed to reschedule notifications for habit {habit_id}: {e}")
                # Don't fail the habit update if notification rescheduling fails
        
        return {
            "message": f"Habit changes will take effect tomorrow ({tomorrow}) in your timezone ({user_timezone}). If you miss today's requirement, you will be charged at the end of the day.",
            "effective_date": tomorrow.isoformat(),
            "timezone": user_timezone,
            "old_habit": old_habit_data,
            "staged_changes": habit_dict,
            "notifications_rescheduled": should_reschedule_notifications
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating habit: {e}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("get_completed_one_time_habits_service")
async def get_completed_one_time_habits_service(
    user_id: str,
    current_user: User,
    supabase: AsyncClient
) -> List[Habit]:
    """
    Get all completed one-time habits for a user.
    
    This is a specialized endpoint for showing one-time habit history. It returns only
    completed one-time habits (habit_schedule_type = 'one_time' and completed_at is not null).
    
    Args:
        user_id: ID of the user to get completed one-time habits for
        
    Returns:
        List of completed one-time habits
    """
    try:
        # Verify user permissions
        if str(current_user.id) != user_id:
            raise HTTPException(status_code=403, detail="Can only access your own habits")
        
        # OPTIMIZATION: Use selective column fetching
        columns = "id, name, habit_type, penalty_amount, user_id, created_at, completed_at, custom_habit_type_id"
        
        # Build query to get only completed one-time habits
        # A habit is considered completed if completed_at is not null
        query = (supabase.table("habits")
                .select(columns)
                .eq("user_id", user_id)
                .eq("habit_schedule_type", "one_time")
                .not_("completed_at", "is", "null"))
        
        # Execute the query
        result = await query.execute()
        
        # If no habits found, return empty list
        if not result.data:
            return []
        
        # Parse habits data and return
        habits = []
        for habit_data in result.data:
            # Convert to JSON string then parse to handle UUID fields
            habit_json = json.loads(json.dumps(habit_data, cls=UUIDEncoder))
            habit = Habit(**habit_json)
            habits.append(habit)
        
        # Sort by completion date (newest first)
        habits.sort(key=lambda h: h.completed_at if h.completed_at else datetime.min, reverse=True)
        
        return habits
    except Exception as e:
        logger.error(f"Error getting completed one-time habits for user {user_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e)) 