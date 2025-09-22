import asyncio
import logging
from datetime import datetime, timedelta, time, timezone, date
from typing import List, Dict, Optional, Any
import pytz
from supabase._async.client import AsyncClient
from services.notification_service import notification_service
from services.gaming_habit_service import GamingHabitService

logger = logging.getLogger(__name__)

class HabitNotificationScheduler:
    """Enhanced notification scheduler for habit reminders and missed habit notifications"""
    
    def __init__(self):
        self.notification_service = notification_service
        self.gaming_service = GamingHabitService()
        
    async def schedule_notifications_for_habit(
        self,
        habit_data: Dict[str, Any],
        supabase_client: AsyncClient
    ):
        """Schedule all notifications for a specific habit based on its type and schedule"""
        try:
            habit_type = habit_data.get('habit_type', '')
            habit_id = habit_data.get('id')
            user_id = habit_data.get('user_id')
            habit_schedule_type = habit_data.get('habit_schedule_type', 'daily')
            
            # Get user timezone
            user_timezone = await self._get_user_timezone(supabase_client, user_id)
            user_tz = pytz.timezone(user_timezone)
            now = datetime.now(user_tz)
            
            if habit_type == 'alarm':
                await self._schedule_alarm_notifications(habit_data, user_tz, now, supabase_client)
            elif habit_type in ['league_of_legends', 'valorant']:
                await self._schedule_gaming_notifications(habit_data, user_tz, now, supabase_client)
            elif habit_schedule_type == 'weekly':
                await self._schedule_weekly_habit_notifications(habit_data, user_tz, now, supabase_client)
            else:
                await self._schedule_regular_habit_notifications(habit_data, user_tz, now, supabase_client)
                
        except Exception as e:
            logger.error(f"Error scheduling notifications for habit {habit_id}: {e}")
    
    async def reschedule_all_notifications_for_user(
        self,
        user_id: str,
        supabase_client: AsyncClient
    ):
        """Reschedule all notifications for a user (useful when timezone changes)"""
        try:
            # Delete all existing unsent notifications for this user
            await supabase_client.table('scheduled_notifications').delete().eq(
                'user_id', user_id
            ).eq('sent', False).execute()
            
            # Get all active habits for this user
            habits_result = await supabase_client.table('habits').select(
                '*'
            ).eq('user_id', user_id).eq('is_active', True).execute()
            
            if not habits_result.data:
                logger.info(f"No active habits found for user {user_id}")
                return
            
            # Reschedule notifications for each habit
            for habit_data in habits_result.data:
                await self.schedule_notifications_for_habit(habit_data, supabase_client)
            
            logger.info(f"Rescheduled notifications for {len(habits_result.data)} habits for user {user_id}")
            
        except Exception as e:
            logger.error(f"Error rescheduling all notifications for user {user_id}: {e}")
    
    def _get_personalized_habit_title(self, habit_type: str) -> str:
        """Get personalized short title for habit type"""
        # Map specific habit types to readable names
        habit_type_mapping = {
            'alarm': 'alarm',
            'gym': 'gym',
            'study': 'study',
            'meditation': 'meditation',
            'reading': 'reading',
            'exercise': 'exercise',
            'water': 'water',
            'sleep': 'sleep',
            'work': 'work',
            'diet': 'diet',
            'github_commits': 'coding',
            'league_of_legends': 'gaming',
            'valorant': 'gaming',
            'custom': 'custom'
        }
        
        readable_type = habit_type_mapping.get(habit_type, habit_type)
        return f"{readable_type} habit"
    
    def _calculate_hours_until(self, due_datetime: datetime, current_time: datetime) -> int:
        """Calculate hours remaining until due time"""
        time_diff = due_datetime - current_time
        hours = int(time_diff.total_seconds() / 3600)
        return max(hours, 0)  # Don't return negative hours
    
    async def _schedule_gaming_notifications(
        self,
        habit_data: Dict[str, Any],
        user_tz: pytz.timezone,
        now: datetime,
        supabase_client: AsyncClient
    ):
        """Schedule gaming-specific notifications for limit warnings"""
        habit_id = habit_data.get('id')
        user_id = habit_data.get('user_id')
        habit_name = habit_data.get('name', '')
        habit_type = habit_data.get('habit_type', '')
        schedule_type = habit_data.get('habit_schedule_type', 'daily')
        
        if not habit_name:
            habit_name = "League of Legends" if habit_type == "league_of_legends" else "Valorant"
        
        # For gaming habits, we schedule periodic checks throughout the day
        # These checks will evaluate current usage and send warnings if needed
        
        if schedule_type == 'daily':
            # Schedule checks every 2 hours throughout the day
            check_hours = [10, 12, 14, 16, 18, 20, 22]  # Check at these hours
            
            for day_offset in range(7):  # Schedule for next 7 days
                target_date = now.date() + timedelta(days=day_offset)
                
                for hour in check_hours:
                    check_time = user_tz.localize(datetime.combine(target_date, time(hour, 0)))
                    
                    # Skip if time has already passed
                    if check_time <= now:
                        continue
                    
                    # Create a gaming check notification
                    await self._create_scheduled_notification(
                        user_id=user_id,
                        habit_id=habit_id,
                        notification_type='gaming_limit_check',
                        scheduled_time=check_time,
                        title='Gaming Check',  # This won't be sent to user
                        message='Check gaming usage and send warning if needed',
                        supabase_client=supabase_client
                    )
        
        else:  # weekly
            # For weekly habits, check twice daily
            check_hours = [14, 20]  # Check at 2 PM and 8 PM
            
            for day_offset in range(7):
                target_date = now.date() + timedelta(days=day_offset)
                
                for hour in check_hours:
                    check_time = user_tz.localize(datetime.combine(target_date, time(hour, 0)))
                    
                    if check_time <= now:
                        continue
                    
                    await self._create_scheduled_notification(
                        user_id=user_id,
                        habit_id=habit_id,
                        notification_type='gaming_limit_check',
                        scheduled_time=check_time,
                        title='Gaming Check',
                        message='Check weekly gaming usage and send warning if needed',
                        supabase_client=supabase_client
                    )
    
    async def _schedule_alarm_notifications(
        self,
        habit_data: Dict[str, Any],
        user_tz: pytz.timezone,
        now: datetime,
        supabase_client: AsyncClient
    ):
        """Schedule alarm-specific notifications"""
        habit_id = habit_data.get('id')
        user_id = habit_data.get('user_id')
        alarm_time_str = habit_data.get('alarm_time')  # Format: "07:30"
        weekdays = habit_data.get('weekdays', [])
        habit_type = habit_data.get('habit_type', 'alarm')
        
        if not alarm_time_str:
            logger.warning(f"Alarm habit {habit_id} has no alarm_time set")
            return
        
        # Handle None weekdays (default to empty list)
        if weekdays is None:
            weekdays = []
        
        try:
            # Parse alarm time
            alarm_time = datetime.strptime(alarm_time_str, '%H:%M').time()
            
            # Schedule notifications for the next 7 days
            for day_offset in range(7):
                target_date = now.date() + timedelta(days=day_offset)
                
                # Check if this day is required for the habit
                postgres_weekday = (target_date.weekday() + 1) % 7
                if postgres_weekday not in weekdays:
                    continue
                
                # Create target datetime for alarm
                alarm_datetime = user_tz.localize(datetime.combine(target_date, alarm_time))
                
                # Skip if alarm time has already passed today
                if alarm_datetime <= now:
                    continue
                
                # Schedule the 3 alarm notifications
                await self._schedule_single_alarm_notifications(
                    habit_data, alarm_datetime, user_tz, supabase_client
                )
                
        except Exception as e:
            logger.error(f"Error scheduling alarm notifications for habit {habit_id}: {e}")
    
    async def _schedule_single_alarm_notifications(
        self,
        habit_data: Dict[str, Any],
        alarm_datetime: datetime,
        user_tz: pytz.timezone,
        supabase_client: AsyncClient
    ):
        """Schedule the 3 notifications for a single alarm occurrence"""
        habit_id = habit_data.get('id')
        user_id = habit_data.get('user_id')
        habit_type = habit_data.get('habit_type', 'alarm')
        
        # Calculate time strings for messaging
        alarm_time_str = alarm_datetime.strftime('%I:%M %p')
        
        # Get current time for comparison
        now = datetime.now(user_tz)
        
        # Get personalized title
        habit_title = self._get_personalized_habit_title(habit_type)
        
        # 1. One hour before: "Check-in window started"
        one_hour_before = alarm_datetime - timedelta(hours=1)
        if one_hour_before > now + timedelta(minutes=5):  # Only schedule if at least 5 minutes away
            hours_until = self._calculate_hours_until(alarm_datetime, one_hour_before)
            await self._create_scheduled_notification(
                user_id=user_id,
                habit_id=habit_id,
                notification_type='alarm_checkin_window',
                scheduled_time=one_hour_before,
                title=habit_title,
                message=f'1 hour left until your {habit_title} is due at {alarm_time_str}. Get ready!',
                supabase_client=supabase_client
            )
        else:
            logger.debug(f"Skipped 1h alarm checkin for habit {habit_id} - too close to current time")
        
        # 2. At alarm time: "Wake up!" (always schedule this one)
        await self._create_scheduled_notification(
            user_id=user_id,
            habit_id=habit_id,
            notification_type='alarm_wake_up',
            scheduled_time=alarm_datetime,
            title=habit_title,
            message=f'⏰ Your {habit_title} is due now! Time to wake up.',
            supabase_client=supabase_client
        )
        
        # 3. Ten minutes after: "You missed the alarm habit" (always schedule this one)
        ten_minutes_after = alarm_datetime + timedelta(minutes=10)
        await self._create_scheduled_notification(
            user_id=user_id,
            habit_id=habit_id,
            notification_type='alarm_missed',
            scheduled_time=ten_minutes_after,
            title=habit_title,
            message=f'You missed your {habit_title}. Better luck tomorrow!',
            supabase_client=supabase_client
        )
    
    async def _schedule_regular_habit_notifications(
        self,
        habit_data: Dict[str, Any],
        user_tz: pytz.timezone,
        now: datetime,
        supabase_client: AsyncClient
    ):
        """Schedule notifications for regular (non-alarm) habits"""
        habit_id = habit_data.get('id')
        user_id = habit_data.get('user_id')
        habit_type = habit_data.get('habit_type', '')
        weekdays = habit_data.get('weekdays', [])
        penalty_amount = habit_data.get('penalty_amount', 0)
        
        # Handle None weekdays (default to empty list)
        if weekdays is None:
            weekdays = []
        
        # Schedule notifications for the next 7 days
        for day_offset in range(7):
            target_date = now.date() + timedelta(days=day_offset)
            
            # Check if this day is required for the habit
            postgres_weekday = (target_date.weekday() + 1) % 7
            if postgres_weekday not in weekdays:
                continue
            
            # Set due time at end of day (11:59 PM)
            due_datetime = user_tz.localize(datetime.combine(target_date, time(23, 59)))
            
            # Skip if due time has already passed
            if due_datetime <= now:
                continue
            
            # Schedule the 4 regular habit notifications
            await self._schedule_single_habit_notifications(
                habit_data, due_datetime, user_tz, supabase_client
            )
    
    async def _schedule_single_habit_notifications(
        self,
        habit_data: Dict[str, Any],
        due_datetime: datetime,
        user_tz: pytz.timezone,
        supabase_client: AsyncClient
    ):
        """Schedule the 4 notifications for a single habit occurrence"""
        habit_id = habit_data.get('id')
        user_id = habit_data.get('user_id')
        habit_type = habit_data.get('habit_type', '')
        penalty_amount = habit_data.get('penalty_amount', 0)
        
        # Get current time for comparison
        now = datetime.now(user_tz)
        
        # Get personalized title
        habit_title = self._get_personalized_habit_title(habit_type)
        
        # Determine if this is today or tomorrow
        today = now.date()
        due_date = due_datetime.date()
        day_text = "today" if due_date == today else "tomorrow" if due_date == today + timedelta(days=1) else f"on {due_date.strftime('%A')}"
        
        # 1. Twelve hours before: Early reminder
        twelve_hours_before = due_datetime - timedelta(hours=12)
        if twelve_hours_before > now + timedelta(minutes=5):  # Only schedule if at least 5 minutes away
            hours_until = self._calculate_hours_until(due_datetime, twelve_hours_before)
            await self._create_scheduled_notification(
                user_id=user_id,
                habit_id=habit_id,
                notification_type='habit_reminder_12h',
                scheduled_time=twelve_hours_before,
                title=habit_title,
                message=f'12 hours left until your {habit_title} is due {day_text}.',
                supabase_client=supabase_client
            )
        else:
            logger.debug(f"Skipped 12h reminder for habit {habit_id} - too close to current time")
        
        # 2. Six hours before: Mid-day reminder
        six_hours_before = due_datetime - timedelta(hours=6)
        if six_hours_before > now + timedelta(minutes=5):  # Only schedule if at least 5 minutes away
            hours_until = self._calculate_hours_until(due_datetime, six_hours_before)
            await self._create_scheduled_notification(
                user_id=user_id,
                habit_id=habit_id,
                notification_type='habit_reminder_6h',
                scheduled_time=six_hours_before,
                title=habit_title,
                message=f'6 hours left until your {habit_title} is due {day_text}.',
                supabase_client=supabase_client
            )
        else:
            logger.debug(f"Skipped 6h reminder for habit {habit_id} - too close to current time")
        
        # 3. One hour before: Final reminder
        one_hour_before = due_datetime - timedelta(hours=1)
        if one_hour_before > now + timedelta(minutes=5):  # Only schedule if at least 5 minutes away
            hours_until = self._calculate_hours_until(due_datetime, one_hour_before)
            await self._create_scheduled_notification(
                user_id=user_id,
                habit_id=habit_id,
                notification_type='habit_reminder_1h',
                scheduled_time=one_hour_before,
                title=habit_title,
                message=f'1 hour left until your {habit_title} is due {day_text}. Don\'t forget!',
                supabase_client=supabase_client
            )
        else:
            logger.debug(f"Skipped 1h reminder for habit {habit_id} - too close to current time")
        
        # 4. At due time: Missed notification (always schedule this one)
        await self._create_scheduled_notification(
            user_id=user_id,
            habit_id=habit_id,
            notification_type='habit_missed',
            scheduled_time=due_datetime,
            title=habit_title,
            message=f'You missed your {habit_title}. ${penalty_amount:.2f} penalty charged.',
            supabase_client=supabase_client
        )
    
    async def _schedule_weekly_habit_notifications(
        self,
        habit_data: Dict[str, Any],
        user_tz: pytz.timezone,
        now: datetime,
        supabase_client: AsyncClient
    ):
        """Schedule notifications for weekly habits (progress reminders)"""
        habit_id = habit_data.get('id')
        user_id = habit_data.get('user_id')
        habit_type = habit_data.get('habit_type', '')
        weekly_target = habit_data.get('weekly_target', 1)
        week_start_day = habit_data.get('week_start_day', 0)  # 0 = Sunday
        
        # Get personalized title
        habit_title = self._get_personalized_habit_title(habit_type)
        
        # Get current week dates
        from utils.weekly_habits import get_week_dates
        today = now.date()
        current_week_start, current_week_end = get_week_dates(today, week_start_day)
        
        # Get current progress for this week
        try:
            progress_result = await supabase_client.table('weekly_habit_progress').select(
                '*'
            ).eq('habit_id', habit_id).eq('week_start_date', current_week_start.isoformat()).execute()
            
            current_completions = 0
            if progress_result.data:
                current_completions = progress_result.data[0].get('current_completions', 0)
        except Exception as e:
            logger.debug(f"Could not get current progress for habit {habit_id}: {e}")
            current_completions = 0
        
        # Schedule weekly progress notifications
        await self._schedule_weekly_progress_notifications(
            habit_data, user_tz, now, current_week_start, current_week_end, 
            current_completions, weekly_target, supabase_client
        )
        
        # Schedule next week notifications 
        next_week_start = current_week_end + timedelta(days=1)
        next_week_end = next_week_start + timedelta(days=6)
        await self._schedule_weekly_progress_notifications(
            habit_data, user_tz, now, next_week_start, next_week_end, 
            0, weekly_target, supabase_client  # Next week starts with 0 completions
        )
    
    async def _schedule_weekly_progress_notifications(
        self,
        habit_data: Dict[str, Any],
        user_tz: pytz.timezone,
        now: datetime,
        week_start: date,
        week_end: date,
        current_completions: int,
        weekly_target: int,
        supabase_client: AsyncClient
    ):
        """Schedule progress reminder notifications for a specific week"""
        habit_id = habit_data.get('id')
        user_id = habit_data.get('user_id')
        habit_type = habit_data.get('habit_type', '')
        habit_title = self._get_personalized_habit_title(habit_type)
        
        # Days remaining in the week
        days_left = (week_end - now.date()).days + 1
        if days_left <= 0:
            return  # Week is over
        
        completions_needed = max(0, weekly_target - current_completions)
        
        # Skip if already completed
        if completions_needed == 0:
            return
        
        # Schedule notifications at strategic times during the week
        notification_days = []
        
        # Mid-week check (Wednesday)
        wednesday = week_start + timedelta(days=3)  # 3 days after week start
        if wednesday >= now.date() and wednesday <= week_end:
            notification_days.append((wednesday, "mid-week"))
        
        # Weekend reminder (Friday)
        friday = week_start + timedelta(days=5)  # 5 days after week start  
        if friday >= now.date() and friday <= week_end:
            notification_days.append((friday, "weekend"))
        
        # Final day reminder (day before week ends)
        final_day = week_end
        if final_day >= now.date():
            notification_days.append((final_day, "final"))
        
        for notification_date, notification_stage in notification_days:
            # Calculate updated progress for this notification date
            days_passed = (notification_date - week_start).days
            notification_datetime = user_tz.localize(datetime.combine(notification_date, time(18, 0)))  # 6 PM
            
            # Skip if time has already passed
            if notification_datetime <= now:
                continue
            
            # Create contextual messages based on progress and stage
            if notification_stage == "mid-week":
                if current_completions == 0:
                    message = f"You have {completions_needed} {habit_title} completions left this week. Great time to start!"
                else:
                    message = f"{current_completions}/{weekly_target} completed! {completions_needed} more {habit_title} completions needed this week."
            elif notification_stage == "weekend":
                if current_completions == 0:
                    message = f"Weekend reminder: {completions_needed} {habit_title} completions still needed this week!"
                else:
                    message = f"Weekend progress: {current_completions}/{weekly_target} done! {completions_needed} more to go."
            else:  # final
                if current_completions == 0:
                    message = f"Last chance! {completions_needed} {habit_title} completions needed to avoid penalty."
                else:
                    message = f"Final day: {current_completions}/{weekly_target} done. Complete {completions_needed} more today!"
            
            await self._create_scheduled_notification(
                user_id=user_id,
                habit_id=habit_id,
                notification_type=f'weekly_reminder_{notification_stage}',
                scheduled_time=notification_datetime,
                title=habit_title,
                message=message,
                supabase_client=supabase_client
            )
    
    async def _create_scheduled_notification(
        self,
        user_id: str,
        habit_id: str,
        notification_type: str,
        scheduled_time: datetime,
        title: str,
        message: str,
        supabase_client: AsyncClient
    ):
        """Create a scheduled notification record in the database"""
        try:
            notification_data = {
                'user_id': user_id,
                'habit_id': habit_id,
                'notification_type': notification_type,
                'scheduled_time': scheduled_time.isoformat(),
                'title': title,
                'message': message,
                'sent': False,
                'created_at': datetime.utcnow().isoformat()
            }
            
            # Check if notification already exists to avoid duplicates
            existing = await supabase_client.table('scheduled_notifications').select('*').eq(
                'user_id', user_id
            ).eq('habit_id', habit_id).eq('notification_type', notification_type).eq(
                'scheduled_time', scheduled_time.isoformat()
            ).execute()
            
            if not existing.data:
                await supabase_client.table('scheduled_notifications').insert(notification_data).execute()
                logger.info(f"Scheduled {notification_type} notification for habit {habit_id} at {scheduled_time}")
            
        except Exception as e:
            logger.error(f"Error creating scheduled notification: {e}")
    
    async def process_due_notifications(self, supabase_client: AsyncClient):
        """Process all notifications that are due to be sent"""
        try:
            now_utc = datetime.now(pytz.UTC)
            
            # Get all unsent notifications that are due (limit to prevent overwhelming)
            # Add retry logic for network timeouts
            max_retries = 3
            for attempt in range(max_retries):
                try:
                    due_notifications = await supabase_client.table('scheduled_notifications').select(
                        '*'
                    ).eq('sent', False).lte('scheduled_time', now_utc.isoformat()).order(
                        'scheduled_time', desc=False
                    ).limit(50).execute()  # Process max 50 notifications per run
                    break  # Success, exit retry loop
                except asyncio.CancelledError:
                    if attempt == max_retries - 1:
                        logger.error(f"Failed to fetch due notifications after {max_retries} attempts due to network timeout")
                        return
                    else:
                        logger.warning(f"Network timeout fetching due notifications, retrying ({attempt + 1}/{max_retries})...")
                        await asyncio.sleep(2 ** attempt)  # Exponential backoff: 1s, 2s, 4s
                        continue
                except Exception as e:
                    logger.error(f"Database error fetching due notifications: {e}")
                    return

            if not due_notifications.data:
                logger.debug("No due notifications to process")
                return
                
            logger.info(f"Processing {len(due_notifications.data)} due notifications")
            
            for notification in due_notifications.data:
                await self._process_single_notification(notification, supabase_client)
                
        except Exception as e:
            logger.error(f"Error processing due notifications: {e}")
    
    async def _process_single_notification(
        self,
        notification: Dict[str, Any],
        supabase_client: AsyncClient
    ):
        """Process a single notification"""
        try:
            notification_id = notification['id']
            notification_type = notification['notification_type']
            user_id = notification['user_id']
            habit_id = notification['habit_id']
            title = notification['title']
            message = notification['message']
            scheduled_time = notification['scheduled_time']
            
            logger.debug(f"Processing {notification_type} notification for user {user_id[:8]}... scheduled at {scheduled_time}")
            
            # Handle gaming limit check notifications
            if notification_type == 'gaming_limit_check':
                await self._process_gaming_limit_check(
                    user_id=user_id,
                    habit_id=habit_id,
                    supabase_client=supabase_client
                )
                
                # Mark as sent
                await supabase_client.table('scheduled_notifications').update({
                    'sent': True,
                    'sent_at': datetime.utcnow().isoformat()
                }).eq('id', notification_id).execute()
                return
            
            # Check if habit was verified for reminder notifications and missed notifications
            # Skip verification check for alarm_wake_up as it should always fire regardless
            if notification_type in ['habit_missed', 'alarm_missed', 'habit_reminder_12h', 'habit_reminder_6h', 'habit_reminder_1h', 'alarm_checkin_window']:
                # Check if habit was verified for this day
                scheduled_time_dt = datetime.fromisoformat(scheduled_time)
                user_timezone = await self._get_user_timezone(supabase_client, user_id)
                user_tz = pytz.timezone(user_timezone)
                local_time = scheduled_time_dt.astimezone(user_tz)
                check_date = local_time.date()
                
                # Check for verifications on this date
                start_of_day = user_tz.localize(datetime.combine(check_date, datetime.min.time()))
                end_of_day = user_tz.localize(datetime.combine(check_date, datetime.max.time()))
                
                verifications = await supabase_client.table('habit_verifications').select(
                    '*'
                ).eq('habit_id', habit_id).gte(
                    'verified_at', start_of_day.isoformat()
                ).lte('verified_at', end_of_day.isoformat()).execute()
                
                if verifications.data:
                    # Habit was verified, don't send notification
                    skip_reason = 'habit_was_verified'
                    if notification_type.startswith('habit_reminder') or notification_type == 'alarm_checkin_window':
                        skip_reason = 'habit_already_completed'
                    
                    await supabase_client.table('scheduled_notifications').update({
                        'sent': True,
                        'sent_at': datetime.utcnow().isoformat(),
                        'skipped': True,
                        'skip_reason': skip_reason
                    }).eq('id', notification_id).execute()
                    logger.info(f"Skipped {notification_type} notification for user {user_id[:8]}... - habit already completed")
                    return
            
            # Send the notification
            await self._send_notification_to_user(
                user_id=user_id,
                title=title,
                message=message,
                notification_type=notification_type,
                habit_id=habit_id,
                supabase_client=supabase_client
            )
            
            # Mark as sent
            await supabase_client.table('scheduled_notifications').update({
                'sent': True,
                'sent_at': datetime.utcnow().isoformat()
            }).eq('id', notification_id).execute()
            
            logger.info(f"Successfully sent {notification_type} notification to user {user_id[:8]}...")
            
        except Exception as e:
            logger.error(f"Error processing notification {notification.get('id')}: {e}")
    
    async def _process_gaming_limit_check(
        self,
        user_id: str,
        habit_id: str,
        supabase_client: AsyncClient
    ):
        """Check gaming usage and send warning notification if approaching limit"""
        try:
            # Get habit details
            habit_result = await supabase_client.table("habits").select("*").eq("id", habit_id).single().execute()
            if not habit_result.data:
                logger.error(f"Gaming habit {habit_id} not found")
                return
            
            habit = habit_result.data
            habit_name = habit.get("name", "")
            habit_type = habit.get("habit_type", "")
            schedule_type = habit.get("habit_schedule_type", "daily")
            
            if not habit_name:
                habit_name = "League of Legends" if habit_type == "league_of_legends" else "Valorant"
            
            # Get current usage based on habit schedule type
            if schedule_type == 'daily':
                # Calculate today's usage
                today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
                today_end = today_start + timedelta(days=1)
                
                sessions = await self.gaming_service.get_gaming_sessions(
                    habit_id=habit_id,
                    start_date=today_start,
                    end_date=today_end
                )
                
                total_minutes = sum(s.duration_minutes for s in sessions)
                current_hours = total_minutes / 60.0
                limit_hours = habit.get("daily_limit_hours", 0)
                period = "day"
                notification_key = f"gaming_warning_{habit_id}_daily_{datetime.now(timezone.utc).date()}"
                
            else:  # weekly
                # Calculate this week's usage using USER'S timezone, not UTC
                from utils.timezone_utils import get_user_timezone
                user_timezone = await get_user_timezone(supabase_client, user_id)
                user_tz = pytz.timezone(user_timezone)
                user_now = datetime.now(user_tz)
                today_user_tz = user_now.date()
                
                from utils.weekly_habits import get_week_dates
                week_start_day = habit.get("week_start_day", 0)
                week_start, week_end = get_week_dates(today_user_tz, week_start_day)
                
                logger.info(f"Gaming notification check for user {user_id} in timezone {user_timezone}: "
                           f"today={today_user_tz}, week_start={week_start}, week_end={week_end}")
                
                week_start_dt = datetime.combine(week_start, datetime.min.time()).replace(tzinfo=timezone.utc)
                week_end_dt = datetime.combine(week_end, datetime.max.time()).replace(tzinfo=timezone.utc)
                
                sessions = await self.gaming_service.get_gaming_sessions(
                    habit_id=habit_id,
                    start_date=week_start_dt,
                    end_date=week_end_dt
                )
                
                total_minutes = sum(s.duration_minutes for s in sessions)
                current_hours = total_minutes / 60.0
                limit_hours = habit.get("daily_limit_hours", 0)  # For weekly habits, this is actually the weekly limit
                period = "week"
                notification_key = f"gaming_warning_{habit_id}_weekly_{week_start}"
            
            # Calculate hours remaining
            hours_remaining = limit_hours - current_hours
            
            # Check if we've already sent a notification today/this week
            existing_notification = await supabase_client.table("notifications").select("id").eq("user_id", user_id).eq("notification_key", notification_key).execute()
            
            if not existing_notification.data:
                # Send warning if within 1 hour of limit or already over
                if hours_remaining <= 1.0:
                    # Send the warning notification
                    await self.notification_service.send_gaming_limit_warning_notification(
                        user_id=user_id,
                        habit_name=habit_name,
                        hours_remaining=max(0, hours_remaining),
                        current_hours=current_hours,
                        limit_hours=limit_hours,
                        supabase_client=supabase_client
                    )
                    
                    # Record that we sent this notification
                    await supabase_client.table("notifications").insert({
                        "user_id": user_id,
                        "notification_key": notification_key,
                        "notification_type": "gaming_limit_warning",
                        "sent_at": datetime.now(timezone.utc).isoformat()
                    }).execute()
                    
                    logger.info(f"Sent gaming limit warning for habit {habit_id} - {hours_remaining:.1f} hours remaining")
            
        except Exception as e:
            logger.error(f"Error processing gaming limit check: {e}")
    
    async def _get_user_device_tokens(self, user_id: str, supabase_client: AsyncClient) -> List[str]:
        """Get all device tokens for a user with both sync/async client support"""
        try:
            # Query device_tokens table for user's active tokens
            result = await supabase_client.table("device_tokens").select("token").eq("user_id", user_id).eq("is_active", True).execute()
            
            if result.data:
                return [row["token"] for row in result.data]
            return []
            
        except Exception as e:
            logger.error(f"Failed to get device tokens for user {user_id}: {e}")
            return []

    async def _send_notification_to_user(
        self,
        user_id: str,
        title: str,
        message: str,
        notification_type: str,
        habit_id: str,
        supabase_client: AsyncClient
    ):
        """Send push notification to user"""
        try:
            # Get user's device tokens using our wrapper method
            device_tokens = await self._get_user_device_tokens(user_id, supabase_client)
            
            if not device_tokens:
                logger.info(f"No device tokens found for user {user_id}")
                return
            
            # Create notification payload
            notification_data = {
                'type': 'habit_notification',
                'notification_type': notification_type,
                'habit_id': habit_id,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            # Send push notification
            await self.notification_service.send_apns_notification(
                device_tokens=device_tokens,
                title=title,
                body=message,
                data=notification_data,
                supabase_client=supabase_client
            )
            
            logger.info(f"Sent {notification_type} notification to user {user_id}")
            
        except Exception as e:
            logger.error(f"Error sending notification to user {user_id}: {e}")
    
    async def _get_user_timezone(self, supabase_client: AsyncClient, user_id: str) -> str:
        """Get user's timezone from database"""
        try:
            user_result = await supabase_client.table('users').select('timezone').eq('id', user_id).execute()
            
            if user_result.data:
                timezone = user_result.data[0]['timezone']
                
                # Handle timezone abbreviations
                timezone_mapping = {
                    'PDT': 'America/Los_Angeles',
                    'PST': 'America/Los_Angeles',
                    'EDT': 'America/New_York',
                    'EST': 'America/New_York',
                    'CDT': 'America/Chicago',
                    'CST': 'America/Chicago',
                    'MDT': 'America/Denver',
                    'MST': 'America/Denver',
                }
                
                if timezone in timezone_mapping:
                    timezone = timezone_mapping[timezone]
                
                # Validate timezone
                try:
                    pytz.timezone(timezone)
                    return timezone
                except pytz.exceptions.UnknownTimeZoneError:
                    logger.warning(f"Unknown timezone: {timezone}, falling back to UTC")
                    return 'UTC'
            
            return 'UTC'
            
        except Exception as e:
            logger.error(f"Error getting user timezone: {e}")
            return 'UTC'
    
    async def cleanup_old_notifications(self, supabase_client: AsyncClient, days_old: int = 7):
        """Clean up old sent notifications"""
        try:
            cutoff_date = datetime.utcnow() - timedelta(days=days_old)
            
            await supabase_client.table('scheduled_notifications').delete().eq(
                'sent', True
            ).lt('sent_at', cutoff_date.isoformat()).execute()
            
            logger.info(f"Cleaned up notifications older than {days_old} days")
            
        except Exception as e:
            logger.error(f"Error cleaning up old notifications: {e}")

# Global instance
habit_notification_scheduler = HabitNotificationScheduler() 