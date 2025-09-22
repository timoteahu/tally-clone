from datetime import datetime, timedelta, date, time
import pytz
import logging
from config.database import get_supabase_client, get_async_supabase_client
from supabase import Client
from .scheduler_utils import get_user_timezone, decrement_habit_streak_local, check_and_create_penalty_for_habit

# Set up logging
logger = logging.getLogger(__name__)

async def check_and_charge_penalties():
    """
    Check for missed habits from yesterday and create penalties
    Then attempt to charge penalties for habits with auto-pay enabled
    Includes first-day grace period - no charging on the first day after habit creation
    Runs hourly but only processes users at 1 AM in their timezone (when day has truly ended)
    """
    supabase = get_supabase_client()
    async_supabase = await get_async_supabase_client()
    utc_now = datetime.now(pytz.UTC)
    logger.info(f"\n{'='*50}")
    logger.info(f"🔄 Starting penalty check at {utc_now} UTC")
    logger.info(f"{'='*50}")
    
    try:
        # Process habits that were deleted/edited today and charge penalties if missed
        try:
            logger.info("📋 Checking for deleted/edited habits...")
            from .habit_management import check_deleted_edited_habits_penalties
            await check_deleted_edited_habits_penalties(supabase)
        except Exception as e:
            logger.error(f"❌ Error checking deleted/edited habits penalties: {e}")
        
        # Get all DAILY habits with their created_at timestamps and user timezones (excluding gaming habits)
        logger.info("\n📥 Fetching active daily habits...")
        habits_result = supabase.table("habits") \
            .select("*, users!habits_user_id_fkey!inner(timezone)") \
            .eq("habit_schedule_type", "daily") \
            .eq("is_active", True) \
            .not_.in_("habit_type", ["league_of_legends", "valorant"]) \
            .execute()
        habits = habits_result.data
        logger.info(f"📋 Found {len(habits)} active daily habits (excluding gaming)")

        if not habits:
            logger.warning("⚠️ No active daily habits found - exiting early")
            return

        # Group habits by user to avoid duplicate timezone processing
        users_processed = set()
        users_at_check_time = 0
        penalties_created = 0

        # Group habits by user for better logging
        habits_by_user = {}
        for habit in habits:
            user_id = habit['user_id']
            if user_id not in habits_by_user:
                habits_by_user[user_id] = []
            habits_by_user[user_id].append(habit)
        
        logger.info(f"\n👥 Processing {len(habits_by_user)} users with daily habits...")

        for user_id, user_habits in habits_by_user.items():
            # Skip if we already processed this user in this run
            if user_id in users_processed:
                logger.info(f"⏭️ User {user_id}: Already processed in this run")
                continue
            users_processed.add(user_id)
            
            # Get user's timezone and current time - USE SAME METHOD AS ENDPOINTS
            user_timezone = get_user_timezone(supabase, user_id)
            user_tz = pytz.timezone(user_timezone)
            user_now = datetime.now(user_tz)  # Changed from utc_now.astimezone(user_tz)
            
            logger.info(f"\n👤 User {user_id}:")
            logger.info(f"   🌍 Timezone: {user_timezone}")
            logger.info(f"   🕒 Local time: {user_now.strftime('%Y-%m-%d %H:%M %Z')}")
            logger.info(f"   📝 Active habits: {len(user_habits)}")
            
            # Only process penalties if it's 1 AM in the user's timezone
            if user_now.hour != 1:  # 1 AM
                logger.info(f"   ⏭️ Wrong hour: {user_now.hour}:00 (waiting for 01:00)")
                continue
            
            users_at_check_time += 1
            logger.info(f"   ✅ Processing at correct hour (01:00)")
            
            # Get yesterday in user's timezone - USE SAME METHOD AS ENDPOINTS
            yesterday_user = (user_now.date() - timedelta(days=1))  # Changed from user_now.date() - timedelta(days=1)
            logger.info(f"   📅 Checking for: {yesterday_user} (yesterday in user's timezone)")
            
            # Pre-fetch all verifications for all user habits in a single query to avoid N+1
            start_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.min.time()))
            end_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.max.time()))
            
            habit_ids = [habit["id"] for habit in user_habits]
            verifications_result = supabase.table("habit_verifications") \
                .select("*") \
                .in_("habit_id", habit_ids) \
                .gte("verified_at", start_of_yesterday.isoformat()) \
                .lte("verified_at", end_of_yesterday.isoformat()) \
                .execute()
            
            # Group verifications by habit_id for quick lookup
            verifications_by_habit = {}
            if verifications_result.data:
                for verification in verifications_result.data:
                    habit_id = verification["habit_id"]
                    if habit_id not in verifications_by_habit:
                        verifications_by_habit[habit_id] = []
                    verifications_by_habit[habit_id].append(verification)
            
            for habit in user_habits:
                logger.info(f"\n      🔍 Habit {habit['id']}:")
                
                # First-day grace period - no charging on the first day after habit creation
                habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                habit_creation_date = habit_created_at.date()
                if habit_creation_date >= yesterday_user:
                    logger.info(f"      ⏭️ First day grace period (created {habit_creation_date})")
                    continue
                
                # Check if yesterday was a required day
                postgres_weekday = (yesterday_user.weekday() + 1) % 7  # Convert to Postgres weekday format
                weekday_name = yesterday_user.strftime('%A')
                
                logger.info(f"      📅 Yesterday ({weekday_name}) weekday value: {postgres_weekday}")
                logger.info(f"      📅 Required days: {habit['weekdays']}")
                
                if postgres_weekday not in habit["weekdays"]:
                    logger.info(f"      ⏭️ Not required on {weekday_name}")
                    continue

                # Check for verifications using pre-fetched data
                logger.info(f"      🔍 Checking verifications between:")
                logger.info(f"         {start_of_yesterday.isoformat()}")
                logger.info(f"         {end_of_yesterday.isoformat()}")
                
                # Get verifications from pre-fetched map
                habit_verifications = verifications_by_habit.get(habit["id"], [])

                if not habit_verifications:
                    logger.info(f"      ❌ No verifications found")
                    
                    # Create penalty using the function that updates analytics
                    try:
                        await check_and_create_penalty_for_habit(
                            supabase=async_supabase,
                            habit_id=habit["id"],
                            user_id=habit["user_id"],
                            habit_data=habit,
                            penalty_date=yesterday_user,
                            reason=f"Missed {habit.get('name', 'habit')} on {yesterday_user}"
                        )
                        penalties_created += 1
                        logger.info(f"      💸 Created penalty with analytics update: ${habit['penalty_amount']}")
                    except Exception as e:
                        logger.error(f"      ❌ Error creating penalty: {e}")
                else:
                    logger.info(f"      ✅ Found {len(habit_verifications)} verifications")
            
            # After processing regular habits, check gaming habits for this user
            logger.info(f"\n   🎮 Checking gaming habits for user {user_id}...")
            from .gaming_habits import check_gaming_habits_for_penalties
            gaming_penalties = await check_gaming_habits_for_penalties(supabase, async_supabase, user_id, yesterday_user)
            penalties_created += gaming_penalties
            if gaming_penalties > 0:
                logger.info(f"   🎮 Created {gaming_penalties} gaming penalties")

            # After processing gaming habits, check GitHub commit habits for this user
            logger.info(f"\n   📝 Checking GitHub commit habits for user {user_id}...")
            from .github_habits import check_github_habits_for_penalties
            github_penalties = await check_github_habits_for_penalties(supabase, async_supabase, user_id, yesterday_user, user_timezone)
            penalties_created += github_penalties
            if github_penalties > 0:
                logger.info(f"   📝 Created {github_penalties} GitHub commit penalties")
            
            # Check LeetCode habits for this user
            logger.info(f"\n   🧩 Checking LeetCode habits for user {user_id}...")
            from .leetcode_habits import check_leetcode_habits_for_penalties
            leetcode_penalties = await check_leetcode_habits_for_penalties(supabase, async_supabase, user_id, yesterday_user)
            penalties_created += leetcode_penalties
            if leetcode_penalties > 0:
                logger.info(f"   🧩 Created {leetcode_penalties} LeetCode penalties")

        logger.info(f"\n{'='*50}")
        logger.info(f"📊 Penalty Check Summary:")
        logger.info(f"   • Total users with habits: {len(habits_by_user)}")
        logger.info(f"   • Users at check time (1 AM): {users_at_check_time}")
        logger.info(f"   • Penalties created: {penalties_created}")
        logger.info(f"{'='*50}\n")

    except Exception as e:
        logger.error(f"❌ Error in check_and_charge_penalties: {str(e)}")
        logger.error(f"{'='*50}")
        raise 