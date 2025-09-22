#!/usr/bin/env python3
"""
Standalone test script for the GitHub integration scheduler.

• Runs an AsyncIO event-loop with an APScheduler that executes every minute (development-friendly)
• Each run:
  – Retrieves every user that has a `github_access_token` in the `user_tokens` table
  – Calls `utils.github_commits.get_commit_count` to fetch _today's_ commit total (UTC) for that user
  – Logs the result so you can verify that tokens are valid and the GraphQL query works

Requirements:
  • SUPABASE_URL / SUPABASE_SERVICE_KEY must be set in your environment         (see `config/database.py`)
  • No extra FastAPI server is needed – this is a simple script you run via `python github_scheduler_test.py`
  • APScheduler is already in the dependency tree via the main scheduler module

Usage:
    # Make sure your venv has the project installed / PYTHONPATH includes backend/app
    $ export SUPABASE_URL=... SUPABASE_SERVICE_KEY=...
    $ python backend/scripts/github_scheduler_test.py
    # Press Ctrl-C to stop
"""

import sys, pathlib

# ---------------------------------------------------------
# Ensure the project’s backend/app directory is on PYTHONPATH
# ---------------------------------------------------------
_CURRENT_FILE = pathlib.Path(__file__).resolve()
BACKEND_APP = _CURRENT_FILE.parent.parent / "app"
if BACKEND_APP.exists():
    sys.path.insert(0, str(BACKEND_APP))  # Highest priority

import asyncio
import datetime
import logging
from typing import List

import pytz
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from datetime import timedelta, time
from tasks.scheduler import get_user_timezone, check_weekly_github_habits_for_penalties

# Project imports – make sure script is executed from repository root so these resolve
from config.database import get_supabase_client
from utils.github_commits import get_commit_count
from utils.weekly_habits import get_week_dates

logger = logging.getLogger("github_scheduler_test")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s", force=True)
logger.setLevel(logging.INFO)
# Ensure at least one stream handler is present (root may have different level)
if not logger.handlers:
    _h = logging.StreamHandler()
    _h.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
    logger.addHandler(_h)


async def _fetch_all_tokens() -> List[dict]:
    """Return a list of `{user_id, github_access_token}` dicts for all users who have connected GitHub."""
    supabase = get_supabase_client()
    result = supabase.table("user_tokens").select("user_id, github_access_token").not_.is_("github_access_token", "null").execute()
    if not result.data:
        logger.info("No GitHub tokens found in user_tokens table – nothing to do")
        return []
    return result.data


async def fetch_and_log_commit_counts():
    """Scheduled job: iterate over every connected user and log yesterday's commit count relative to their timezone."""
    logger.info("🏃‍♂️ Running GitHub commit count job…")
    try:
        # Get all rows with tokens first (sync call – cheap)
        token_rows = await asyncio.to_thread(asyncio.run, _fetch_all_tokens()) if False else await _fetch_all_tokens()
        if not token_rows:
            return  # Already logged inside helper

        supabase = get_supabase_client()

        async def _process_row(row: dict):
            token = row["github_access_token"]
            user_id = row["user_id"]

            # 1️⃣  Determine the user's timezone - USE SAME METHOD AS ENDPOINTS
            user_timezone = get_user_timezone(supabase, user_id)  # falls back to 'UTC' if missing/invalid
            user_tz = pytz.timezone(user_timezone)
            user_now = datetime.datetime.now(user_tz)  # Changed from utc_now.astimezone(user_tz)

            # 2️⃣  Calculate yesterday's date in the user's local tz
            yesterday_date = user_now.date() - timedelta(days=1)
            today_date = user_now.date()
            
            logger.info(f"🕒 User {user_id} time calculations:")
            logger.info(f"   Current time: {user_now} ({user_timezone})")
            logger.info(f"   Today: {today_date}")
            logger.info(f"   Yesterday: {yesterday_date}")

            # 3️⃣  Check if any active github_commits habit was scheduled for yesterday
            try:
                habits_res = supabase.table("habits") \
                    .select("id, weekdays") \
                    .eq("user_id", user_id) \
                    .eq("habit_type", "github_commits") \
                    .eq("is_active", True) \
                    .execute()
            except Exception as db_exc:
                logger.error(f"User {user_id} – DB error fetching GitHub habits: {db_exc}")
                return

            if not habits_res.data:
                logger.debug(f"User {user_id} – no active github_commits habits; skipping")
                return

            postgres_weekday = (yesterday_date.weekday() + 1) % 7  # Sunday=0 in postgres convention
            if not any(postgres_weekday in (h.get("weekdays") or []) for h in habits_res.data):
                logger.debug(f"User {user_id} – yesterday ({yesterday_date}) not scheduled for any GitHub habit; skipping")
                return

            # 4️⃣  Use the EXACT same logic as test_github_commits.py (which works correctly)
            # Force UTC timezone since that's what works correctly
            
            # Get yesterday's date in UTC timezone (this is what works)
            utc_tz = pytz.timezone('UTC')
            utc_now = datetime.datetime.now(utc_tz)
            yesterday_date_utc = utc_now.date() - timedelta(days=1)
            
            # Create timezone-aware datetime objects for start and end of yesterday in UTC
            start_local = utc_tz.localize(datetime.datetime.combine(yesterday_date_utc, time.min))
            end_local = utc_tz.localize(datetime.datetime.combine(yesterday_date_utc, time.max))
            
            # Convert to UTC for GitHub API (GitHub expects UTC timestamps)
            start_utc = start_local.astimezone(pytz.UTC).replace(tzinfo=None)
            end_utc = end_local.astimezone(pytz.UTC).replace(tzinfo=None)
            
            logger.info(f"📅 Using EXACT test_github_commits.py logic (UTC timezone):")
            logger.info(f"   UTC now: {utc_now}")
            logger.info(f"   Yesterday date (UTC): {yesterday_date_utc}")
            logger.info(f"   Start (UTC): {start_utc}")
            logger.info(f"   End (UTC): {end_utc}")
            logger.info(f"   User's local yesterday was: {yesterday_date} (in {user_timezone})")
            
            # 5️⃣  Fetch and log commit count for yesterday using exact test_github_commits.py logic
            try:
                count_utc = await get_commit_count(token, start_utc, end_utc) or 0
                
                logger.info(f"📊 COMMIT COUNT RESULT:")
                logger.info(f"   Expected (GitHub profile): 1 commit on {yesterday_date_utc} (UTC)")
                logger.info(f"   ✅ Result: {count_utc} commits")
                
                if count_utc == 1:
                    logger.info(f"   🎉 SUCCESS! Exact test_github_commits.py logic works!")
                else:
                    logger.warning(f"   ⚠️ Expected 1 commit, got {count_utc}")
                
            except Exception as exc:
                logger.error(f"Failed to fetch commits for user {user_id}: {exc}")

        # Run all GitHub API calls concurrently – GitHub allows a decent rate-limit for authenticated requests
        await asyncio.gather(*(_process_row(r) for r in token_rows))

    except Exception as e:
        logger.exception(f"Unexpected error in scheduled job: {e}")


async def fetch_and_log_weekly_commit_counts():
    """Test weekly GitHub commit habits for all users with tokens."""
    logger.info("🏃‍♂️ Running weekly GitHub commit habits test...")
    try:
        # Get all rows with tokens first
        token_rows = await _fetch_all_tokens()
        if not token_rows:
            return  # Already logged inside helper

        supabase = get_supabase_client()

        async def _process_weekly_row(row: dict):
            token = row["github_access_token"]
            user_id = row["user_id"]

            # Get user's timezone and current date
            user_timezone = get_user_timezone(supabase, user_id)
            user_tz = pytz.timezone(user_timezone)
            user_now = datetime.datetime.now(user_tz)
            today_user = user_now.date()
            
            logger.info(f"🕒 User {user_id} weekly time calculations:")
            logger.info(f"   Current time: {user_now} ({user_timezone})")
            logger.info(f"   Today: {today_user}")

            # Check for weekly GitHub habits
            try:
                habits_res = supabase.table("habits") \
                    .select("id, commit_target, weekly_target, penalty_amount, week_start_day") \
                    .eq("user_id", user_id) \
                    .eq("habit_type", "github_commits") \
                    .eq("habit_schedule_type", "weekly") \
                    .eq("is_active", True) \
                    .execute()
            except Exception as db_exc:
                logger.error(f"User {user_id} – DB error fetching weekly GitHub habits: {db_exc}")
                return

            if not habits_res.data:
                logger.debug(f"User {user_id} – no active weekly github_commits habits; skipping")
                return

            logger.info(f"📝 Found {len(habits_res.data)} weekly GitHub habits")

            # Check each habit
            for habit in habits_res.data:
                habit_id = habit['id']
                habit_week_start_day = habit.get('week_start_day', 0)
                # For GitHub weekly habits, use commit_target as the actual weekly commit goal
                weekly_commit_goal = habit.get('commit_target', 7)  # commit_target is the actual goal
                weekly_target = habit.get('weekly_target', 1)  # should be 1 for database constraint
                penalty_amount = habit.get('penalty_amount', 0)
                
                logger.info(f"\n   🔍 Checking habit {habit_id}:")
                logger.info(f"      📅 Week starts on: {['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][habit_week_start_day]}")
                logger.info(f"      🎯 Weekly commit goal: {weekly_commit_goal} commits (from commit_target)")
                logger.info(f"      📊 Weekly target (DB): {weekly_target} (should be 1)")
                logger.info(f"      💰 Penalty amount: ${penalty_amount:.2f}")
                
                # Get current week dates
                week_start, week_end = get_week_dates(today_user, habit_week_start_day)
                logger.info(f"      📅 Current week: {week_start} to {week_end}")
                
                # Use UTC timezone for consistency with GitHub API
                utc_tz = pytz.timezone('UTC')
                week_start_utc = utc_tz.localize(datetime.datetime.combine(week_start, time.min))
                week_end_utc = utc_tz.localize(datetime.datetime.combine(week_end, time.max))
                
                start_utc = week_start_utc.astimezone(pytz.UTC).replace(tzinfo=None)
                end_utc = week_end_utc.astimezone(pytz.UTC).replace(tzinfo=None)
                
                logger.info(f"      📅 UTC time range:")
                logger.info(f"         Start: {start_utc}")
                logger.info(f"         End: {end_utc}")
                
                # Get commit count for the current week
                try:
                    commit_count = await get_commit_count(token, start_utc, end_utc) or 0
                    
                    logger.info(f"      📊 WEEKLY COMMIT COUNT RESULT:")
                    logger.info(f"         Current progress: {commit_count}/{weekly_commit_goal} commits")
                    
                    if commit_count >= weekly_commit_goal:
                        logger.info(f"         ✅ Weekly target met!")
                    else:
                        missed_commits = weekly_commit_goal - commit_count
                        total_penalty = missed_commits * penalty_amount  # One penalty per missed commit
                        logger.info(f"         ⚠️ Weekly target not yet met")
                        logger.info(f"         💸 If week ended today: {missed_commits} missed commits × ${penalty_amount:.2f} = ${total_penalty:.2f}")
                        
                        # Show what would happen if week ended today
                        if today_user == week_end:
                            logger.info(f"         🚨 Week ending today - would create {missed_commits} penalties!")
                        else:
                            days_left = (week_end - today_user).days
                            logger.info(f"         📅 {days_left} days left to reach target")
                            
                except Exception as exc:
                    logger.error(f"Failed to fetch weekly commits for user {user_id}: {exc}")
            
            # Test the actual scheduler function for last week
            yesterday = today_user - timedelta(days=1)
            
            # Find all weeks that ended yesterday
            for week_start_day in range(7):
                week_start, week_end = get_week_dates(yesterday, week_start_day)
                
                if yesterday == week_end:
                    logger.info(f"\n   🔄 Testing completed week: {week_start} to {week_end}")
                    
                    # Check if there are any GitHub weekly habits for this user and week
                    weekly_habits_for_week = [h for h in habits_res.data 
                                            if h.get('habit_schedule_type') == 'weekly' 
                                            and h.get('week_start_day') == week_start_day]
                    
                    if weekly_habits_for_week:
                        # First, update the weekly progress for this completed week
                        logger.info(f"   📊 Updating weekly progress for completed week...")
                        
                        for habit in weekly_habits_for_week:
                            from utils.github_commits import update_github_weekly_progress
                            
                            # For GitHub weekly habits, commit_target is the actual weekly commit goal
                            actual_weekly_goal = habit.get('commit_target', 7)
                            
                            await update_github_weekly_progress(
                                supabase=supabase,
                                user_id=user_id,
                                habit_id=habit['id'],
                                week_start_date=week_start,
                                weekly_target=actual_weekly_goal,  # Use commit_target as the goal
                                week_start_day=week_start_day
                            )
                            
                            logger.info(f"   ✅ Updated weekly progress for habit {habit['id']}")
                        
                        # Now test the penalty scheduler
                        penalties_created = await check_weekly_github_habits_for_penalties(
                            supabase, user_id, week_start, week_end
                        )
                        
                        if penalties_created > 0:
                            logger.info(f"   📊 Scheduler result: {penalties_created} penalties created")
                            
                            # Show penalty details
                            for habit in weekly_habits_for_week:
                                # Get the weekly progress record
                                progress_result = supabase.table("weekly_habit_progress") \
                                    .select("*") \
                                    .eq("habit_id", habit['id']) \
                                    .eq("week_start_date", week_start.isoformat()) \
                                    .execute()
                                
                                if progress_result.data:
                                    progress = progress_result.data[0]
                                    current_commits = progress['current_completions']
                                    target_commits = progress['target_completions']
                                    is_complete = progress['is_week_complete']
                                    
                                    if not is_complete:
                                        missed_commits = target_commits - current_commits
                                        total_penalty = missed_commits * habit.get('penalty_amount', 0)
                                        logger.info(f"      💸 Habit {habit['id']}: {current_commits}/{target_commits} commits - {missed_commits} missed × ${habit.get('penalty_amount', 0):.2f} = ${total_penalty:.2f}")
                        else:
                            logger.info(f"   📊 Scheduler result: No penalties created")
                    else:
                        logger.info(f"   ⏭️ No weekly GitHub habits with week_start_day={week_start_day}")
            
            # Also test the new weekly progress update function
            logger.info(f"\n   🔄 Testing weekly progress update function...")
            from utils.github_commits import update_all_github_weekly_progress
            
            await update_all_github_weekly_progress(supabase, user_id)
            
            logger.info(f"   ✅ Weekly progress update completed")
            
            # Show current weekly progress for all GitHub habits
            for habit in habits_res.data:
                if habit.get('habit_schedule_type') == 'weekly':
                    progress_result = supabase.table("weekly_habit_progress") \
                        .select("*") \
                        .eq("habit_id", habit['id']) \
                        .order("week_start_date", desc=True) \
                        .limit(1) \
                        .execute()
                    
                    if progress_result.data:
                        progress = progress_result.data[0]
                        logger.info(f"   📊 Habit {habit['id']} current week: {progress['current_completions']}/{progress['target_completions']} (complete: {progress['is_week_complete']})")
                    else:
                        logger.info(f"   ⚠️ No weekly progress record found for habit {habit['id']}")

        # Run all GitHub API calls concurrently
        await asyncio.gather(*(_process_weekly_row(r) for r in token_rows))

    except Exception as e:
        logger.exception(f"Unexpected error in weekly scheduled job: {e}")


async def main():
    """Entry-point – set up scheduler and keep the loop alive."""
    
    print("🛠️  GitHub Scheduler Test Runner")
    print("=" * 50)
    print("1. Test daily GitHub habits (scheduled every minute)")
    print("2. Test weekly GitHub habits (scheduled every 2 minutes)")
    print("3. Run both tests once")
    print("4. Run both tests once, then start scheduled testing")
    print("0. Exit")
    print("=" * 50)
    
    while True:
        try:
            choice = input("\nEnter your choice (0-4): ").strip()
            
            if choice == "0":
                print("👋 Goodbye!")
                break
            elif choice == "1":
                print("🚀 Starting daily GitHub habits scheduler...")
                scheduler = AsyncIOScheduler()
                
                # Schedule daily GitHub habits every minute
                scheduler.add_job(fetch_and_log_commit_counts, "interval", minutes=1, id="github_daily_commit_count")
                
                # Run once immediately
                await fetch_and_log_commit_counts()
                
                scheduler.start()
                logger.info("Daily scheduler started – press Ctrl-C to exit")
                
                # Block forever
                try:
                    while True:
                        await asyncio.sleep(3600)
                except (KeyboardInterrupt, asyncio.CancelledError):
                    logger.info("Shutting down daily scheduler…")
                    scheduler.shutdown()
                    break
                    
            elif choice == "2":
                print("🚀 Starting weekly GitHub habits scheduler...")
                scheduler = AsyncIOScheduler()
                
                # Schedule weekly GitHub habits every 2 minutes
                scheduler.add_job(fetch_and_log_weekly_commit_counts, "interval", minutes=2, id="github_weekly_commit_count")
                
                # Run once immediately
                await fetch_and_log_weekly_commit_counts()
                
                scheduler.start()
                logger.info("Weekly scheduler started – press Ctrl-C to exit")
                
                # Block forever
                try:
                    while True:
                        await asyncio.sleep(3600)
                except (KeyboardInterrupt, asyncio.CancelledError):
                    logger.info("Shutting down weekly scheduler…")
                    scheduler.shutdown()
                    break
                    
            elif choice == "3":
                print("🚀 Running both tests once...")
                logger.info("📅 Testing daily GitHub habits...")
                await fetch_and_log_commit_counts()
                logger.info("\n📅 Testing weekly GitHub habits...")
                await fetch_and_log_weekly_commit_counts()
                logger.info("✅ Both tests completed!")
                
            elif choice == "4":
                print("🚀 Running both tests once, then starting scheduled testing...")
                
                # Run both tests once immediately
                logger.info("📅 Initial test - daily GitHub habits...")
                await fetch_and_log_commit_counts()
                logger.info("\n📅 Initial test - weekly GitHub habits...")
                await fetch_and_log_weekly_commit_counts()
                
                # Set up scheduler for both
                scheduler = AsyncIOScheduler()
                
                # Schedule both jobs
                scheduler.add_job(fetch_and_log_commit_counts, "interval", minutes=1, id="github_daily_commit_count")
                scheduler.add_job(fetch_and_log_weekly_commit_counts, "interval", minutes=2, id="github_weekly_commit_count")
                
                scheduler.start()
                logger.info("Both schedulers started – press Ctrl-C to exit")
                
                # Block forever
                try:
                    while True:
                        await asyncio.sleep(3600)
                except (KeyboardInterrupt, asyncio.CancelledError):
                    logger.info("Shutting down both schedulers…")
                    scheduler.shutdown()
                    break
                    
            else:
                print("❌ Invalid choice. Please enter 0-4.")
                continue
                
        except KeyboardInterrupt:
            print("\n👋 Goodbye!")
            break
        except Exception as e:
            logger.error(f"❌ Error: {e}")
            continue


if __name__ == "__main__":
    asyncio.run(main()) 