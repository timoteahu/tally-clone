#!/usr/bin/env python3
"""
Test script to force run the actual scheduler functions.

This script allows you to test the actual scheduler functions without waiting for 
the scheduled times. It runs the same functions that the production scheduler uses.

Usage:
    # Make sure your venv has the project installed / PYTHONPATH includes backend/app
    $ export SUPABASE_URL=... SUPABASE_SERVICE_KEY=...
    $ python backend/scripts/run_scheduler_test.py
"""

import sys, pathlib

# ---------------------------------------------------------
# Ensure the project's backend/app directory is on PYTHONPATH
# ---------------------------------------------------------
_CURRENT_FILE = pathlib.Path(__file__).resolve()
BACKEND_APP = _CURRENT_FILE.parent.parent / "app"
if BACKEND_APP.exists():
    sys.path.insert(0, str(BACKEND_APP))  # Highest priority

import asyncio
import logging
from datetime import datetime, timedelta, time
import pytz

# Import actual scheduler functions
from tasks.scheduler import (
    check_and_charge_penalties,
    check_weekly_penalties,
    update_processing_payment_statuses,
    process_all_eligible_transfers,
    check_github_habits_for_penalties,
    check_weekly_github_habits_for_penalties,
    get_user_timezone
)
from config.database import get_supabase_client
from utils.weekly_habits import get_week_dates

logger = logging.getLogger("scheduler_test")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", force=True)
logger.setLevel(logging.INFO)

async def test_github_habits_only():
    """Test GitHub habits checking for all users with tokens."""
    logger.info("🚀 Testing GitHub habits checking...")
    
    supabase = get_supabase_client()
    
    # Get all users with GitHub tokens
    tokens_result = supabase.table("user_tokens") \
        .select("user_id, github_access_token") \
        .not_.is_("github_access_token", "null") \
        .execute()
    
    if not tokens_result.data:
        logger.info("No users with GitHub tokens found")
        return
    
    logger.info(f"Found {len(tokens_result.data)} users with GitHub tokens")
    
    for token_row in tokens_result.data:
        user_id = token_row["user_id"]
        
        # Get user's timezone and calculate yesterday
        user_timezone = get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        user_now = datetime.now(user_tz)
        yesterday_user = user_now.date() - timedelta(days=1)
        
        logger.info(f"\n👤 Testing user {user_id}:")
        logger.info(f"   🌍 Timezone: {user_timezone}")
        logger.info(f"   📅 Yesterday: {yesterday_user}")
        
        # Check if user has GitHub habits
        github_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "daily") \
            .eq("habit_type", "github_commits") \
            .eq("is_active", True) \
            .execute()
        
        if not github_habits_result.data:
            logger.info(f"   ❌ No GitHub commit habits found for user {user_id}")
            continue
        
        logger.info(f"   📝 Found {len(github_habits_result.data)} GitHub commit habits")
        
        # Check each habit
        for habit in github_habits_result.data:
            habit_id = habit['id']
            habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
            habit_creation_date = habit_created_at.date()
            
            logger.info(f"   🔍 Checking habit {habit_id}:")
            
            # Use UTC logic like the actual scheduler
            utc_tz = pytz.timezone('UTC')
            utc_now = datetime.now(utc_tz)
            yesterday_date_utc = utc_now.date() - timedelta(days=1)
            
            # First-day grace period
            if habit_creation_date >= yesterday_date_utc:
                logger.info(f"      ⏭️ First day grace period (created {habit_creation_date})")
                continue
            
            # Check if yesterday was a required day
            postgres_weekday = (yesterday_date_utc.weekday() + 1) % 7
            weekday_name = yesterday_date_utc.strftime('%A')
            
            logger.info(f"      📅 Yesterday ({weekday_name}) weekday value: {postgres_weekday}")
            logger.info(f"      📅 Required days: {habit.get('weekdays', [])}")
            
            if postgres_weekday not in habit.get("weekdays", []):
                logger.info(f"      ⏭️ Not required on {weekday_name} (UTC)")
                continue
            
            # Get commit count using the same logic as scheduler
            access_token = token_row["github_access_token"]
            
            # Create timezone-aware datetime objects for start and end of yesterday in UTC
            start_local = utc_tz.localize(datetime.combine(yesterday_date_utc, time.min))
            end_local = utc_tz.localize(datetime.combine(yesterday_date_utc, time.max))
            
            # Convert to UTC for GitHub API
            start_utc = start_local.astimezone(pytz.UTC).replace(tzinfo=None)
            end_utc = end_local.astimezone(pytz.UTC).replace(tzinfo=None)
            
            # Get commit count
            from utils.github_commits import get_commit_count
            commit_count = await get_commit_count(access_token, start_utc, end_utc) or 0
            commit_target = habit.get('commit_target', 1)
            
            logger.info(f"      📝 GitHub habit {habit_id}: {commit_count} commits on {yesterday_date_utc} (UTC) (target: {commit_target})")
            
            # Check if goal was met
            if commit_count >= commit_target:
                logger.info(f"      ✅ GitHub habit {habit_id}: Target met!")
            else:
                logger.info(f"      ❌ GitHub habit {habit_id}: Target missed - would create penalty")
        
        # Run the actual scheduler function for comparison
        penalties_created = await check_github_habits_for_penalties(
            supabase, user_id, yesterday_user, user_timezone
        )
        
        logger.info(f"   📊 Scheduler result: {penalties_created} penalties created")

async def test_daily_penalties():
    """Test the daily penalty checking function."""
    logger.info("🚀 Testing daily penalty checking...")
    await check_and_charge_penalties()

async def test_weekly_penalties():
    """Test the weekly penalty checking function."""
    logger.info("🚀 Testing weekly penalty checking...")
    await check_weekly_penalties()

async def test_payment_statuses():
    """Test the payment status updating function."""
    logger.info("🚀 Testing payment status updates...")
    await update_processing_payment_statuses()

async def test_eligible_transfers():
    """Test the eligible transfers processing function."""
    logger.info("🚀 Testing eligible transfers processing...")
    await process_all_eligible_transfers()

async def test_weekly_github_habits():
    """Test weekly GitHub habits checking for all users with tokens."""
    logger.info("🚀 Testing weekly GitHub habits checking...")
    
    supabase = get_supabase_client()
    
    # Get all users with GitHub tokens
    tokens_result = supabase.table("user_tokens") \
        .select("user_id, github_access_token") \
        .not_.is_("github_access_token", "null") \
        .execute()
    
    if not tokens_result.data:
        logger.info("No users with GitHub tokens found")
        return
    
    logger.info(f"Found {len(tokens_result.data)} users with GitHub tokens")
    
    for token_row in tokens_result.data:
        user_id = token_row["user_id"]
        
        # Get user's timezone and calculate current week
        user_timezone = get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        user_now = datetime.now(user_tz)
        today_user = user_now.date()
        
        # Check for weekly GitHub habits
        github_habits_result = supabase.table("habits") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("habit_schedule_type", "weekly") \
            .eq("habit_type", "github_commits") \
            .eq("is_active", True) \
            .execute()
        
        if not github_habits_result.data:
            logger.info(f"   ❌ User {user_id}: No weekly GitHub habits found")
            continue
        
        logger.info(f"\n👤 Testing user {user_id}:")
        logger.info(f"   🌍 Timezone: {user_timezone}")
        logger.info(f"   📅 Today: {today_user}")
        logger.info(f"   📝 Found {len(github_habits_result.data)} weekly GitHub habits")
        
        # Check each habit
        for habit in github_habits_result.data:
            habit_id = habit['id']
            habit_week_start_day = habit.get('week_start_day', 0)
            # For GitHub weekly habits, use commit_target as the actual weekly commit goal
            weekly_commit_goal = habit.get('commit_target', 7)  # commit_target is the actual goal
            weekly_target = habit.get('weekly_target', 1)  # should be 1 for database constraint
            
            logger.info(f"\n   🔍 Checking habit {habit_id}:")
            logger.info(f"      📅 Week starts on: {['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][habit_week_start_day]}")
            logger.info(f"      🎯 Weekly commit goal: {weekly_commit_goal} commits (from commit_target)")
            logger.info(f"      📊 Weekly target (DB): {weekly_target} (should be 1)")
            
            # Get current week dates
            week_start, week_end = get_week_dates(today_user, habit_week_start_day)
            logger.info(f"      📅 Current week: {week_start} to {week_end}")
            
            # Get commit count for current week so far
            access_token = token_row["github_access_token"]
            
            # Use UTC timezone for consistency
            utc_tz = pytz.timezone('UTC')
            week_start_utc = utc_tz.localize(datetime.combine(week_start, time.min))
            week_end_utc = utc_tz.localize(datetime.combine(week_end, time.max))
            
            start_utc = week_start_utc.astimezone(pytz.UTC).replace(tzinfo=None)
            end_utc = week_end_utc.astimezone(pytz.UTC).replace(tzinfo=None)
            
            # Get commit count for the week
            from utils.github_commits import get_commit_count
            commit_count = await get_commit_count(access_token, start_utc, end_utc) or 0
            
            logger.info(f"      📝 Commits this week: {commit_count}/{weekly_commit_goal}")
            
            penalty_amount = habit.get('penalty_amount', 0)
            logger.info(f"      💰 Penalty per missed commit: ${penalty_amount:.2f}")
            
            if commit_count >= weekly_commit_goal:
                logger.info(f"      ✅ Weekly target met!")
            else:
                missed_commits = weekly_commit_goal - commit_count
                total_penalty = missed_commits * penalty_amount
                logger.info(f"      ⚠️ Weekly target not yet met ({commit_count}/{weekly_commit_goal})")
                logger.info(f"      💸 If week ended today: {missed_commits} missed commits × ${penalty_amount:.2f} = ${total_penalty:.2f}")
                
                # Show what would happen if week ended today
                if today_user == week_end:
                    logger.info(f"      🚨 Week ending today - would create {missed_commits} penalties!")
                else:
                    days_left = (week_end - today_user).days
                    logger.info(f"      📅 {days_left} days left to reach target")
        
        # Test the actual scheduler function for last week
        yesterday = today_user - timedelta(days=1)
        
        # Find all weeks that ended yesterday
        for week_start_day in range(7):
            week_start, week_end = get_week_dates(yesterday, week_start_day)
            
            if yesterday == week_end:
                logger.info(f"\n   🔄 Testing completed week: {week_start} to {week_end}")
                penalties_created = await check_weekly_github_habits_for_penalties(
                    supabase, user_id, week_start, week_end
                )
                
                if penalties_created > 0:
                    logger.info(f"   📊 Scheduler result: {penalties_created} penalties created")
                    
                    # Show penalty breakdown for each habit
                    for habit in github_habits_result.data:
                        habit_week_start_day = habit.get('week_start_day', 0)
                        if get_week_dates(week_end, habit_week_start_day)[0] == week_start:
                            penalty_amount = habit.get('penalty_amount', 0)
                            total_penalty = penalties_created * penalty_amount
                            logger.info(f"      💸 Total penalty: {penalties_created} × ${penalty_amount:.2f} = ${total_penalty:.2f}")
                else:
                    logger.info(f"   📊 Scheduler result: No penalties created")

async def main():
    """Main function with menu options."""
    print("🛠️  Scheduler Test Runner")
    print("=" * 50)
    print("1. Test daily GitHub habits")
    print("2. Test daily penalties (full)")
    print("3. Test weekly penalties")
    print("4. Test payment status updates")
    print("5. Test eligible transfers")
    print("6. Test weekly GitHub habits")
    print("7. Run all tests")
    print("0. Exit")
    print("=" * 50)
    
    while True:
        try:
            choice = input("\nEnter your choice (0-7): ").strip()
            
            if choice == "0":
                print("👋 Goodbye!")
                break
            elif choice == "1":
                await test_github_habits_only()
            elif choice == "2":
                await test_daily_penalties()
            elif choice == "3":
                await test_weekly_penalties()
            elif choice == "4":
                await test_payment_statuses()
            elif choice == "5":
                await test_eligible_transfers()
            elif choice == "6":
                await test_weekly_github_habits()
            elif choice == "7":
                logger.info("🚀 Running all tests...")
                await test_github_habits_only()
                await test_daily_penalties()
                await test_weekly_penalties()
                await test_payment_statuses()
                await test_eligible_transfers()
                await test_weekly_github_habits()
                logger.info("✅ All tests completed!")
            else:
                print("❌ Invalid choice. Please enter 0-7.")
                continue
                
        except KeyboardInterrupt:
            print("\n👋 Goodbye!")
            break
        except Exception as e:
            logger.error(f"❌ Error: {e}")
            continue

if __name__ == "__main__":
    asyncio.run(main()) 