from datetime import datetime, timedelta, date, time
import pytz
import logging
from supabase import Client
from supabase._async.client import AsyncClient
from services.gaming_habit_service import GamingHabitService
from utils.weekly_habits import get_week_dates
from .scheduler_utils import get_user_timezone, decrement_habit_streak_local, check_and_create_penalty_for_habit
from utils.recipient_analytics import update_analytics_on_habit_verified

# Set up logging
logger = logging.getLogger(__name__)

async def check_gaming_habits_for_penalties(supabase: Client, async_supabase: AsyncClient, user_id: str, yesterday_user: date):
    """
    Check gaming habits for a user and create penalties if they exceeded their limits.
    """
    try:
        gaming_service = GamingHabitService()
        
        # Get user's gaming habits
        gaming_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "daily") \
            .eq("is_active", True) \
            .in_("habit_type", ["league_of_legends", "valorant"]) \
            .execute()
        
        if not gaming_habits_result.data:
            return 0  # No gaming habits
        
        penalties_created = 0
        
        # Get user's timezone - USE SAME METHOD AS ENDPOINTS
        user_timezone = get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        for habit in gaming_habits_result.data:
            try:
                habit_id = habit['id']
                habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                habit_creation_date = habit_created_at.date()
                
                # First-day grace period
                if habit_creation_date >= yesterday_user:
                    logger.info(f"      ⏭️ Gaming habit {habit_id}: First day grace period")
                    continue
                
                # Check if yesterday was a required day for daily habits
                postgres_weekday = (yesterday_user.weekday() + 1) % 7
                if postgres_weekday not in habit.get("weekdays", []):
                    logger.info(f"      ⏭️ Gaming habit {habit_id}: Not required on {yesterday_user.strftime('%A')}")
                    continue
                
                # Convert yesterday to datetime in user's timezone, then to UTC - USE SAME METHOD AS ENDPOINTS
                # Create datetime at midnight in user's timezone
                yesterday_start_local = user_tz.localize(datetime.combine(yesterday_user, time.min))
                # Convert to UTC for the API
                yesterday_datetime = yesterday_start_local.astimezone(pytz.UTC)
                
                # Verify gaming time for yesterday
                verification_result = await gaming_service.verify_gaming_habit(
                    habit_id=habit_id,
                    user_id=user_id,
                    target_date=yesterday_datetime
                )
                
                logger.info(f"      🎮 Gaming habit {habit_id}: {verification_result.total_minutes_yesterday} minutes played")
                logger.info(f"         Limit: {verification_result.daily_limit_hours} hours")
                logger.info(f"         Overage: {verification_result.overage_hours} hours")
                
                # If there's overage, create a penalty
                if verification_result.overage_hours > 0 and verification_result.penalty_amount > 0:
                    # Create penalty using the function that updates analytics
                    habit['penalty_amount'] = verification_result.penalty_amount  # Ensure penalty amount is set
                    await check_and_create_penalty_for_habit(
                        supabase=async_supabase,
                        habit_id=habit_id,
                        user_id=user_id,
                        habit_data=habit,
                        penalty_date=yesterday_user,
                        reason=f"Gaming overage: {verification_result.overage_hours:.1f} hours over {verification_result.daily_limit_hours} hour limit"
                    )
                    penalties_created += 1
                    logger.info(f"      💸 Created gaming penalty with analytics update: ${verification_result.penalty_amount:.2f}")
                    
                    # Send overage notification
                    from services.notification_service import notification_service
                    habit_name = habit.get('name') or (
                        "League of Legends" if habit.get('habit_type') == "league_of_legends" else "Valorant"
                    )
                    await notification_service.send_gaming_overage_notification(
                        user_id=user_id,
                        habit_name=habit_name,
                        overage_hours=verification_result.overage_hours,
                        penalty_amount=verification_result.penalty_amount,
                        period="day",
                        supabase_client=supabase
                    )
                    logger.info(f"      📬 Sent gaming overage notification")
                else:
                    # User stayed under limit - mark as success
                    logger.info(f"      ✅ Gaming habit {habit_id}: Stayed under limit - marking as success")
                    
                    # Update recipient analytics for successful day
                    recipient_id = habit.get('recipient_id')
                    if recipient_id:
                        try:
                            await update_analytics_on_habit_verified(
                                supabase=async_supabase,
                                habit_id=habit_id,
                                recipient_id=recipient_id,
                                verification_date=yesterday_user
                            )
                            logger.info(f"      📊 Updated analytics for gaming success")
                        except Exception as analytics_error:
                            logger.error(f"      ❌ Error updating analytics for gaming success: {analytics_error}")
                
            except Exception as e:
                logger.error(f"❌ Error checking gaming habit {habit.get('id')}: {e}")
                continue
        
        return penalties_created
        
    except Exception as e:
        logger.error(f"❌ Error checking gaming habits for user {user_id}: {e}")
        return 0

async def check_weekly_gaming_habits_for_penalties(supabase: Client, async_supabase: AsyncClient, user_id: str, completed_week_start: date, completed_week_end: date):
    """
    Check weekly gaming habits for a user and create penalties if they exceeded their weekly limits.
    """
    try:
        gaming_service = GamingHabitService()
        
        # Get user's weekly gaming habits
        gaming_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("is_active", True) \
            .in_("habit_type", ["league_of_legends", "valorant"]) \
            .execute()
        
        if not gaming_habits_result.data:
            return 0  # No weekly gaming habits
        
        penalties_created = 0
        
        for habit in gaming_habits_result.data:
            try:
                habit_id = habit['id']
                habit_week_start_day = habit.get('week_start_day', 0)
                
                # Check if this habit's week matches the completed week
                habit_week_start, habit_week_end = get_week_dates(completed_week_end, habit_week_start_day)
                if habit_week_start != completed_week_start:
                    continue  # Different week schedule
                
                # First week grace period - no penalties during the first week after habit creation
                habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                habit_creation_date = habit_created_at.date()
                first_week_start, first_week_end = get_week_dates(habit_creation_date, habit_week_start_day)
                
                # If the completed week is the first week, skip penalties (grace period)
                if completed_week_start == first_week_start:
                    logger.info(f"Weekly gaming habit {habit_id}: First week grace period (created {habit_creation_date})")
                    continue
                
                # Calculate weekly gaming total
                summary = await gaming_service.calculate_weekly_gaming_total(
                    habit_id=habit_id,
                    week_start=completed_week_start
                )
                
                logger.info(f"📊 Weekly gaming habit {habit_id}:")
                logger.info(f"   Total: {summary['total_hours']:.1f} hours")
                logger.info(f"   Limit: {summary['weekly_limit_hours']} hours")
                logger.info(f"   Overage: {summary['overage_hours']:.1f} hours")
                
                # If there's overage, create a penalty
                if summary['overage_hours'] > 0 and summary['penalty_amount'] > 0:
                    # Create penalty using the function that updates analytics
                    habit['penalty_amount'] = summary['penalty_amount']  # Ensure penalty amount is set
                    await check_and_create_penalty_for_habit(
                        supabase=async_supabase,
                        habit_id=habit_id,
                        user_id=user_id,
                        habit_data=habit,
                        penalty_date=completed_week_end,
                        reason=f"Weekly gaming overage: {summary['overage_hours']:.1f} hours over {summary['weekly_limit_hours']} hour weekly limit"
                    )
                    penalties_created += 1
                    logger.info(f"💸 Created weekly gaming penalty with analytics update: ${summary['penalty_amount']:.2f}")
                    
                    # Send overage notification
                    from services.notification_service import notification_service
                    habit_name = habit.get('name') or (
                        "League of Legends" if habit.get('habit_type') == "league_of_legends" else "Valorant"
                    )
                    await notification_service.send_gaming_overage_notification(
                        user_id=user_id,
                        habit_name=habit_name,
                        overage_hours=summary['overage_hours'],
                        penalty_amount=summary['penalty_amount'],
                        period="week",
                        supabase_client=supabase
                    )
                    logger.info(f"📬 Sent weekly gaming overage notification")
                else:
                    # User stayed under weekly limit - mark as success
                    logger.info(f"✅ Weekly gaming habit {habit_id}: Stayed under limit - marking as success")
                    
                    # Update recipient analytics for successful week
                    recipient_id = habit.get('recipient_id')
                    if recipient_id:
                        try:
                            from utils.recipient_analytics import update_analytics_on_weekly_penalty_created
                            
                            # For weekly success, we track the whole week as completed
                            # Total days in week that habit was active
                            days_in_week = 7  # Weekly habits track full weeks
                            
                            await update_analytics_on_weekly_penalty_created(
                                supabase=async_supabase,
                                habit_id=habit_id,
                                recipient_id=recipient_id,
                                penalty_amount=0,  # No penalty for success
                                penalty_date=completed_week_end,
                                completions=days_in_week,  # All days successful
                                target=days_in_week,  # Target was all days
                                missed_count=0  # No failures
                            )
                            logger.info(f"📊 Updated analytics for weekly gaming success")
                        except Exception as analytics_error:
                            logger.error(f"❌ Error updating analytics for weekly gaming success: {analytics_error}")
                
            except Exception as e:
                logger.error(f"Error checking weekly gaming habit {habit.get('id')}: {e}")
                continue
        
        return penalties_created
        
    except Exception as e:
        logger.error(f"Error checking weekly gaming habits for user {user_id}: {e}")
        return 0 