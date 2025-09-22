#!/usr/bin/env python3
"""
Comprehensive test file for all task functions in the scheduler system.
This allows direct calling of any task function with full control over parameters.
"""

import asyncio
from datetime import datetime, timedelta, date
import pytz
import logging
import sys
import os

# Set up logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    force=True
)

# Configure root logger
root_logger = logging.getLogger()
root_logger.setLevel(logging.DEBUG)

# Add the parent directory to Python path
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

# Initialize Stripe before importing task modules
import stripe
from dotenv import load_dotenv

# Load .env file from the backend directory (parent of app)
app_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
backend_dir = os.path.dirname(app_dir)
env_path = os.path.join(backend_dir, '.env')
load_dotenv(env_path)

stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
if not stripe.api_key:
    print(f"⚠️  STRIPE_SECRET_KEY not found in environment variables!")
    print(f"Looking for .env file at: {env_path}")
    print(f"Environment variables loaded: {list(os.environ.keys())[:10]}...")
else:
    print(f"✅ Stripe initialized with API key: {stripe.api_key[:20]}...")

# Import all task functions
from tasks.daily_penalties import check_and_charge_penalties
from tasks.weekly_penalties import check_weekly_penalties
from tasks.payment_processing import (
    update_processing_payment_statuses, 
    process_all_eligible_transfers, 
    check_and_charge_unpaid_penalties
)
from tasks.habit_management import (
    process_habit_notifications, 
    cleanup_old_habit_notifications,
    check_deleted_edited_habits_penalties
)
from tasks.github_habits import (
    update_github_weekly_progress_task,
    check_github_habits_for_penalties,
    check_weekly_github_habits_for_penalties
)
from tasks.leetcode_habits import (
    update_leetcode_weekly_progress_task,
    check_leetcode_habits_for_penalties,
    check_weekly_leetcode_habits_for_penalties
)
from tasks.gaming_habits import (
    check_gaming_habits_for_penalties,
    check_weekly_gaming_habits_for_penalties
)
from tasks.maintenance import archive_old_feed_cards_task
from tasks.github_token_refresh import (
    refresh_expiring_github_tokens,
    cleanup_expired_github_tokens
)

# Import utility functions
from utils.habit_staging import (
    process_staged_habit_changes, 
    cleanup_old_staged_changes
)
from tasks.scheduler_utils import (
    get_user_timezone,
    get_user_timezone_async,
    decrement_habit_streak_local,
    check_and_create_penalty_for_habit
)

# Import database clients
from config.database import get_supabase_client, get_async_supabase_client

logger = logging.getLogger(__name__)

# Configure all task module loggers to ensure they output
def configure_all_loggers():
    """Configure all task module loggers to INFO level"""
    loggers_to_configure = [
        'tasks.daily_penalties',
        'tasks.weekly_penalties',
        'tasks.payment_processing',
        'tasks.habit_management',
        'tasks.github_habits',
        'tasks.leetcode_habits',
        'tasks.gaming_habits',
        'tasks.maintenance',
        'tasks.github_token_refresh',
        'tasks.scheduler_utils',
        'utils.habit_staging',
        'utils.memory_optimization',
        'utils.memory_monitoring',
        'utils.recipient_analytics',
        'utils.weekly_habits'
    ]
    
    for logger_name in loggers_to_configure:
        task_logger = logging.getLogger(logger_name)
        task_logger.setLevel(logging.INFO)
        
    # Also ensure the main logger is configured
    logger.setLevel(logging.INFO)
    
    print("✅ All loggers configured to INFO level")

# Configure loggers on import
configure_all_loggers()


class TaskTester:
    """Main class for testing all scheduler tasks"""
    
    def __init__(self):
        self.supabase = get_supabase_client()
        self.tasks = {
            # Daily tasks
            "1": {
                "name": "Check and Charge Daily Penalties",
                "func": check_and_charge_penalties,
                "description": "Check for missed daily habits and create penalties",
                "async": True
            },
            "1b": {
                "name": "Check Daily Penalties (BYPASS TIME CHECK)",
                "func": self.check_daily_penalties_bypass_time,
                "description": "Check daily penalties ignoring timezone hour restrictions",
                "async": True
            },
            
            # Weekly tasks
            "2": {
                "name": "Check Weekly Penalties",
                "func": check_weekly_penalties,
                "description": "Check weekly habits for missed completions",
                "async": True
            },
            "2b": {
                "name": "Check Weekly Penalties (BYPASS TIME CHECK)",
                "func": self.check_weekly_penalties_bypass_time,
                "description": "Check weekly penalties ignoring timezone hour restrictions",
                "async": True
            },
            
            # Payment processing
            "3": {
                "name": "Update Processing Payment Statuses",
                "func": update_processing_payment_statuses,
                "description": "Check PaymentIntent statuses and update accordingly",
                "async": True
            },
            "4": {
                "name": "Process All Eligible Transfers",
                "func": process_all_eligible_transfers,
                "description": "Process transfers to recipients",
                "async": True
            },
            "5": {
                "name": "Check and Charge Unpaid Penalties",
                "func": check_and_charge_unpaid_penalties,
                "description": "Charge users with ≥$5 unpaid penalties",
                "async": True
            },
            
            # Habit management
            "6": {
                "name": "Process Habit Notifications",
                "func": process_habit_notifications,
                "description": "Send scheduled habit notifications",
                "async": True
            },
            "7": {
                "name": "Cleanup Old Habit Notifications",
                "func": cleanup_old_habit_notifications,
                "description": "Remove old notification records",
                "async": True
            },
            "8": {
                "name": "Process Staged Habit Changes",
                "func": process_staged_habit_changes,
                "description": "Apply staged habit modifications",
                "async": True
            },
            "9": {
                "name": "Cleanup Old Staged Changes",
                "func": cleanup_old_staged_changes,
                "description": "Remove old staged change records",
                "async": True
            },
            
            # GitHub tasks
            "10": {
                "name": "Update GitHub Weekly Progress",
                "func": update_github_weekly_progress_task,
                "description": "Update GitHub commit progress for all users",
                "async": True
            },
            "11": {
                "name": "Refresh Expiring GitHub Tokens",
                "func": refresh_expiring_github_tokens,
                "description": "Refresh GitHub tokens expiring soon",
                "async": True
            },
            "12": {
                "name": "Cleanup Expired GitHub Tokens",
                "func": cleanup_expired_github_tokens,
                "description": "Remove expired GitHub tokens",
                "async": True
            },
            
            # LeetCode tasks
            "13": {
                "name": "Update LeetCode Weekly Progress",
                "func": update_leetcode_weekly_progress_task,
                "description": "Update LeetCode problem progress for all users",
                "async": True
            },
            
            # Maintenance tasks
            "14": {
                "name": "Archive Old Feed Cards",
                "func": archive_old_feed_cards_task,
                "description": "Archive feed cards older than 30 days",
                "async": True
            },
            
            # Custom test functions
            "15": {
                "name": "Test Daily Penalties for Specific User",
                "func": self.test_daily_penalties_for_user,
                "description": "Test daily penalty check for a specific user",
                "async": True
            },
            "16": {
                "name": "Test Weekly Penalties for Specific User",
                "func": self.test_weekly_penalties_for_user,
                "description": "Test weekly penalty check for a specific user",
                "async": True
            },
            "17": {
                "name": "Test Gaming Habits for Specific User",
                "func": self.test_gaming_habits_for_user,
                "description": "Test gaming habit penalties for a specific user",
                "async": True
            },
            "18": {
                "name": "Test GitHub Habits for Specific User",
                "func": self.test_github_habits_for_user,
                "description": "Test GitHub habit penalties for a specific user",
                "async": True
            },
            "19": {
                "name": "Test LeetCode Habits for Specific User",
                "func": self.test_leetcode_habits_for_user,
                "description": "Test LeetCode habit penalties for a specific user",
                "async": True
            },
            "20": {
                "name": "Debug User Timezone and Current Time",
                "func": self.debug_user_timezone,
                "description": "Show timezone info for a specific user",
                "async": True
            },
            "21": {
                "name": "List All Active Habits",
                "func": self.list_all_active_habits,
                "description": "Display all active habits in the system",
                "async": True
            },
            "22": {
                "name": "Check Deleted/Edited Habits Penalties",
                "func": self.check_deleted_edited_habits_wrapper,
                "description": "Check for penalties on deleted/edited habits",
                "async": True
            }
        }
    
    async def check_daily_penalties_bypass_time(self):
        """Run daily penalty check with timezone hour check bypassed"""
        logger.info("Running daily penalty check with TIME CHECK BYPASSED")
        logger.info("This will process ALL users regardless of their local hour")
        
        confirm = input("\n⚠️  WARNING: This will process penalties for ALL users. Continue? (y/n): ").lower()
        if confirm != 'y':
            logger.info("Cancelled.")
            return
        
        # We need to create a modified version that bypasses the time check
        # Since we can't modify the original function, we'll create our own version
        await self._run_daily_penalties_bypass_time()
    
    async def _run_daily_penalties_bypass_time(self):
        """Modified version of check_and_charge_penalties that bypasses time check"""
        from datetime import datetime, timedelta, date, time
        import pytz
        from config.database import get_supabase_client, get_async_supabase_client
        from tasks.scheduler_utils import get_user_timezone, decrement_habit_streak_local, check_and_create_penalty_for_habit
        
        supabase = get_supabase_client()
        async_supabase = await get_async_supabase_client()
        utc_now = datetime.now(pytz.UTC)
        logger.info(f"\n{'='*50}")
        logger.info(f"🔄 Starting penalty check at {utc_now} UTC (TIME CHECK BYPASSED)")
        logger.info(f"{'='*50}")
        
        try:
            # Process habits that were deleted/edited today
            try:
                logger.info("📋 Checking for deleted/edited habits...")
                from tasks.habit_management import check_deleted_edited_habits_penalties
                await check_deleted_edited_habits_penalties(supabase)
            except Exception as e:
                logger.error(f"❌ Error checking deleted/edited habits penalties: {e}")
            
            # Get all DAILY habits
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

            # Group habits by user
            users_processed = set()
            penalties_created = 0
            habits_by_user = {}
            
            for habit in habits:
                user_id = habit['user_id']
                if user_id not in habits_by_user:
                    habits_by_user[user_id] = []
                habits_by_user[user_id].append(habit)
            
            logger.info(f"\n👥 Processing {len(habits_by_user)} users with daily habits...")
            logger.info("⚡ TIME CHECK BYPASSED - Processing ALL users regardless of hour")

            for user_id, user_habits in habits_by_user.items():
                if user_id in users_processed:
                    logger.info(f"⏭️ User {user_id}: Already processed in this run")
                    continue
                users_processed.add(user_id)
                
                # Get user's timezone and current time
                user_timezone = get_user_timezone(supabase, user_id)
                user_tz = pytz.timezone(user_timezone)
                user_now = datetime.now(user_tz)
                
                logger.info(f"\n👤 User {user_id}:")
                logger.info(f"   🌍 Timezone: {user_timezone}")
                logger.info(f"   🕒 Local time: {user_now.strftime('%Y-%m-%d %H:%M %Z')}")
                logger.info(f"   📝 Active habits: {len(user_habits)}")
                logger.info(f"   ⚡ BYPASSED: Processing even though hour is {user_now.hour}:00")
                
                # Get yesterday in user's timezone
                yesterday_user = (user_now.date() - timedelta(days=1))
                logger.info(f"   📅 Checking for: {yesterday_user} (yesterday in user's timezone)")
                
                # Pre-fetch all verifications for this user
                start_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.min.time()))
                end_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.max.time()))
                
                habit_ids = [habit["id"] for habit in user_habits]
                verifications_result = supabase.table("habit_verifications") \
                    .select("*") \
                    .in_("habit_id", habit_ids) \
                    .gte("verified_at", start_of_yesterday.isoformat()) \
                    .lte("verified_at", end_of_yesterday.isoformat()) \
                    .execute()
                
                # Group verifications by habit_id
                verifications_by_habit = {}
                if verifications_result.data:
                    for verification in verifications_result.data:
                        habit_id = verification["habit_id"]
                        if habit_id not in verifications_by_habit:
                            verifications_by_habit[habit_id] = []
                        verifications_by_habit[habit_id].append(verification)
                
                for habit in user_habits:
                    logger.info(f"\n      🔍 Habit {habit['id']}:")
                    
                    # First-day grace period check
                    habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
                    habit_creation_date = habit_created_at.date()
                    if habit_creation_date >= yesterday_user:
                        logger.info(f"      ⏭️ First day grace period (created {habit_creation_date})")
                        continue
                    
                    # Check if yesterday was a required day
                    postgres_weekday = (yesterday_user.weekday() + 1) % 7
                    weekday_name = yesterday_user.strftime('%A')
                    
                    logger.info(f"      📅 Yesterday ({weekday_name}) weekday value: {postgres_weekday}")
                    logger.info(f"      📅 Required days: {habit['weekdays']}")
                    
                    if postgres_weekday not in habit["weekdays"]:
                        logger.info(f"      ⏭️ Not required on {weekday_name}")
                        continue

                    # Check for verifications
                    habit_verifications = verifications_by_habit.get(habit["id"], [])

                    if not habit_verifications:
                        logger.info(f"      ❌ No verifications found")
                        
                        # Create penalty
                        try:
                            await check_and_create_penalty_for_habit(
                                supabase=async_supabase,  # Use async client
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
                
                # Check gaming habits
                logger.info(f"\n   🎮 Checking gaming habits for user {user_id}...")
                from tasks.gaming_habits import check_gaming_habits_for_penalties
                gaming_penalties = await check_gaming_habits_for_penalties(supabase, async_supabase, user_id, yesterday_user)
                penalties_created += gaming_penalties
                if gaming_penalties > 0:
                    logger.info(f"   🎮 Created {gaming_penalties} gaming penalties")

                # Check GitHub habits
                logger.info(f"\n   📝 Checking GitHub commit habits for user {user_id}...")
                from tasks.github_habits import check_github_habits_for_penalties
                github_penalties = await check_github_habits_for_penalties(supabase, async_supabase, user_id, yesterday_user, user_timezone)
                penalties_created += github_penalties
                if github_penalties > 0:
                    logger.info(f"   📝 Created {github_penalties} GitHub commit penalties")
                
                # Check LeetCode habits
                logger.info(f"\n   🧩 Checking LeetCode habits for user {user_id}...")
                from tasks.leetcode_habits import check_leetcode_habits_for_penalties
                leetcode_penalties = await check_leetcode_habits_for_penalties(supabase, async_supabase, user_id, yesterday_user)
                penalties_created += leetcode_penalties
                if leetcode_penalties > 0:
                    logger.info(f"   🧩 Created {leetcode_penalties} LeetCode penalties")

            logger.info(f"\n{'='*50}")
            logger.info(f"📊 Penalty Check Summary (TIME CHECK BYPASSED):")
            logger.info(f"   • Total users processed: {len(users_processed)}")
            logger.info(f"   • Penalties created: {penalties_created}")
            logger.info(f"{'='*50}\n")

        except Exception as e:
            logger.error(f"❌ Error in check_and_charge_penalties: {str(e)}")
            raise

    async def check_weekly_penalties_bypass_time(self):
        """Run weekly penalty check with timezone hour check bypassed"""
        logger.info("Running weekly penalty check with TIME CHECK BYPASSED")
        logger.info("This will process ALL users regardless of their local hour or day")
        
        confirm = input("\n⚠️  WARNING: This will process weekly penalties for ALL users. Continue? (y/n): ").lower()
        if confirm != 'y':
            logger.info("Cancelled.")
            return
        
        # For weekly penalties, we'll call the original function since it's more complex
        # But we'll provide instructions
        logger.info("\n📝 NOTE: The weekly penalty function has complex week-end detection.")
        logger.info("It normally only runs at 1 AM on the day after a habit's week ends.")
        logger.info("To test weekly penalties, consider using option 16 instead to test specific users.")
        
        proceed = input("\nStill proceed with full weekly check? (y/n): ").lower()
        if proceed == 'y':
            await check_weekly_penalties()

    async def check_deleted_edited_habits_wrapper(self):
        """Wrapper for check_deleted_edited_habits_penalties that provides supabase client"""
        logger.info("Checking for deleted/edited habits penalties...")
        await check_deleted_edited_habits_penalties(self.supabase)
        logger.info("Deleted/edited habits check completed")

    async def test_daily_penalties_for_user(self):
        """Test daily penalties for a specific user"""
        user_id = input("Enter user ID: ").strip()
        bypass_time = input("Bypass time check? (y/n): ").lower() == 'y'
        dry_run = input("Dry run mode? (y/n): ").lower() == 'y'
        
        logger.info(f"Testing daily penalties for user {user_id}")
        logger.info(f"Bypass time check: {bypass_time}")
        logger.info(f"Dry run: {dry_run}")
        
        # Get user info
        user_timezone = get_user_timezone(self.supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        user_now = datetime.now(user_tz)
        
        logger.info(f"User timezone: {user_timezone}")
        logger.info(f"User current time: {user_now}")
        
        # Get user's daily habits
        habits = self.supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "daily") \
            .eq("is_active", True) \
            .execute()
        
        logger.info(f"Found {len(habits.data)} daily habits for user")
        
        if not dry_run:
            # Actually run the penalty check
            await check_and_charge_penalties()
        else:
            logger.info("Dry run - no penalties will be created")
            for habit in habits.data:
                logger.info(f"Habit {habit['id']}: {habit.get('name', 'Unnamed')}")
                logger.info(f"  Penalty amount: ${habit['penalty_amount']}")
                logger.info(f"  Required days: {habit['weekdays']}")
    
    async def test_weekly_penalties_for_user(self):
        """Test weekly penalties for a specific user"""
        user_id = input("Enter user ID: ").strip()
        
        logger.info(f"Testing weekly penalties for user {user_id}")
        
        # Get user's weekly habits
        habits = self.supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("is_active", True) \
            .execute()
        
        logger.info(f"Found {len(habits.data)} weekly habits for user")
        
        for habit in habits.data:
            logger.info(f"Habit {habit['id']}: {habit.get('name', 'Unnamed')}")
            logger.info(f"  Weekly target: {habit['weekly_target']}")
            logger.info(f"  Penalty amount: ${habit['penalty_amount']}")
            logger.info(f"  Week start day: {habit.get('week_start_day', 0)}")
        
        # Run the check
        await check_weekly_penalties()
    
    async def test_gaming_habits_for_user(self):
        """Test gaming habit penalties for a specific user"""
        user_id = input("Enter user ID: ").strip()
        check_date = input("Enter date to check (YYYY-MM-DD) or press Enter for yesterday: ").strip()
        
        if not check_date:
            check_date = date.today() - timedelta(days=1)
        else:
            check_date = date.fromisoformat(check_date)
        
        logger.info(f"Testing gaming habits for user {user_id} on {check_date}")
        
        async_supabase = await get_async_supabase_client()
        penalties_created = await check_gaming_habits_for_penalties(
            self.supabase, async_supabase, user_id, check_date
        )
        
        logger.info(f"Gaming penalties created: {penalties_created}")
    
    async def test_github_habits_for_user(self):
        """Test GitHub habit penalties for a specific user"""
        user_id = input("Enter user ID: ").strip()
        check_date = input("Enter date to check (YYYY-MM-DD) or press Enter for yesterday: ").strip()
        
        if not check_date:
            check_date = date.today() - timedelta(days=1)
        else:
            check_date = date.fromisoformat(check_date)
        
        logger.info(f"Testing GitHub habits for user {user_id} on {check_date}")
        
        user_timezone = get_user_timezone(self.supabase, user_id)
        async_supabase = await get_async_supabase_client()
        
        penalties_created = await check_github_habits_for_penalties(
            self.supabase, async_supabase, user_id, check_date, user_timezone
        )
        
        logger.info(f"GitHub penalties created: {penalties_created}")
    
    async def test_leetcode_habits_for_user(self):
        """Test LeetCode habit penalties for a specific user"""
        user_id = input("Enter user ID: ").strip()
        check_date = input("Enter date to check (YYYY-MM-DD) or press Enter for yesterday: ").strip()
        
        if not check_date:
            check_date = date.today() - timedelta(days=1)
        else:
            check_date = date.fromisoformat(check_date)
        
        logger.info(f"Testing LeetCode habits for user {user_id} on {check_date}")
        
        async_supabase = await get_async_supabase_client()
        penalties_created = await check_leetcode_habits_for_penalties(
            self.supabase, async_supabase, user_id, check_date
        )
        
        logger.info(f"LeetCode penalties created: {penalties_created}")
    
    async def debug_user_timezone(self):
        """Debug timezone information for a user"""
        user_id = input("Enter user ID: ").strip()
        
        user_timezone = get_user_timezone(self.supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        user_now = datetime.now(user_tz)
        utc_now = datetime.now(pytz.UTC)
        
        logger.info(f"User {user_id} timezone info:")
        logger.info(f"  Timezone: {user_timezone}")
        logger.info(f"  Current local time: {user_now}")
        logger.info(f"  Current UTC time: {utc_now}")
        logger.info(f"  Local date: {user_now.date()}")
        logger.info(f"  Local hour: {user_now.hour}")
        logger.info(f"  Weekday: {user_now.strftime('%A')} (postgres: {(user_now.weekday() + 1) % 7})")
    
    async def list_all_active_habits(self):
        """List all active habits in the system"""
        habits = self.supabase.table("habits") \
            .select("*, users!habits_user_id_fkey!inner(email, timezone)") \
            .eq("is_active", True) \
            .execute()
        
        logger.info(f"Total active habits: {len(habits.data)}")
        
        # Group by type
        daily_habits = [h for h in habits.data if h['habit_schedule_type'] == 'daily']
        weekly_habits = [h for h in habits.data if h['habit_schedule_type'] == 'weekly']
        
        logger.info(f"Daily habits: {len(daily_habits)}")
        logger.info(f"Weekly habits: {len(weekly_habits)}")
        
        show_details = input("Show detailed list? (y/n): ").lower() == 'y'
        
        if show_details:
            for habit in habits.data:
                user = habit['users']
                logger.info(f"\nHabit {habit['id']}:")
                logger.info(f"  User: {user['email']} (TZ: {user['timezone']})")
                logger.info(f"  Name: {habit.get('name', 'Unnamed')}")
                logger.info(f"  Type: {habit['habit_type']}")
                logger.info(f"  Schedule: {habit['habit_schedule_type']}")
                logger.info(f"  Penalty: ${habit['penalty_amount']}")
                if habit['habit_schedule_type'] == 'weekly':
                    logger.info(f"  Weekly target: {habit['weekly_target']}")
                else:
                    logger.info(f"  Required days: {habit['weekdays']}")
    
    def display_menu(self):
        """Display the interactive menu"""
        print("\n" + "="*60)
        print("Task Scheduler Test Menu")
        print("="*60)
        
        # Custom sort function that handles both numbers and alphanumeric keys
        def sort_key(item):
            key = item[0]
            # Try to extract the numeric part for sorting
            if key.isdigit():
                return (int(key), '')
            else:
                # Extract number and letter parts (e.g., "1b" -> (1, 'b'))
                num_part = ''
                alpha_part = ''
                for char in key:
                    if char.isdigit():
                        num_part += char
                    else:
                        alpha_part += char
                return (int(num_part) if num_part else 999, alpha_part)
        
        for key, task in sorted(self.tasks.items(), key=sort_key):
            print(f"{key:4}. {task['name']}")
            print(f"      {task['description']}")
        
        print("\n0. Exit")
        print("="*60)
    
    async def run_task(self, task_num):
        """Run a specific task by number"""
        if task_num not in self.tasks:
            logger.error(f"Invalid task number: {task_num}")
            return
        
        task = self.tasks[task_num]
        logger.info(f"\nRunning: {task['name']}")
        logger.info(f"Description: {task['description']}")
        logger.info("="*60)
        
        try:
            start_time = datetime.now()
            
            if task['async']:
                await task['func']()
            else:
                task['func']()
            
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            logger.info("="*60)
            logger.info(f"Task completed successfully in {duration:.2f} seconds")
        except Exception as e:
            logger.error(f"Task failed with error: {e}")
            logger.exception("Full traceback:")
    
    async def run_interactive(self):
        """Run the interactive menu"""
        while True:
            self.display_menu()
            choice = input("\nEnter task number (or 0 to exit): ").strip()
            
            if choice == "0":
                logger.info("Exiting...")
                break
            
            if choice in self.tasks:
                await self.run_task(choice)
                input("\nPress Enter to continue...")
            else:
                logger.error("Invalid choice. Please try again.")


async def main():
    """Main entry point"""
    tester = TaskTester()
    
    if len(sys.argv) > 1:
        # Run specific task from command line
        task_num = sys.argv[1]
        await tester.run_task(task_num)
    else:
        # Run interactive menu
        await tester.run_interactive()


if __name__ == "__main__":
    asyncio.run(main())