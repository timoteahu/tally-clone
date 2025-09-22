#!/usr/bin/env python3
import asyncio
from datetime import datetime, timedelta
import pytz
import logging
import sys
import os

# Set up logging with more detailed configuration
logging.basicConfig(
    level=logging.DEBUG,  # Set to DEBUG to show all messages
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    force=True  # Force reconfiguration of the root logger
)

# Add the current directory to Python path
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

from tasks.scheduler import (
    check_and_charge_penalties,
    check_weekly_penalties,
    update_processing_payment_statuses,
    process_staged_habit_changes,
    archive_old_feed_cards_task,
    get_user_timezone,
    decrement_habit_streak_local
)

from config.database import get_supabase_client
import stripe

# Create a specific logger for this script
logger = logging.getLogger('test_scheduler')
logger.setLevel(logging.DEBUG)

# Create console handler with formatting
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
console_handler.setFormatter(formatter)

# Add handler to logger
logger.addHandler(console_handler)

async def debug_check_penalties(bypass_time_check=False, dry_run=False):
    """Debug version of check_and_charge_penalties with detailed logging
    
    Args:
        bypass_time_check: If True, ignores the time-of-day check
        dry_run: If True, only logs what would happen without creating penalties
    """
    supabase = get_supabase_client()
    utc_now = datetime.now(pytz.UTC)
    logger.info(f"Starting penalty check at {utc_now} UTC")
    logger.info(f"Time check bypass: {bypass_time_check}")
    logger.info(f"Dry run: {dry_run}")

    try:
        # Get all DAILY habits
        habits_result = supabase.table("habits") \
            .select("*, users!habits_user_id_fkey!inner(timezone)") \
            .eq("habit_schedule_type", "daily") \
            .eq("is_active", True) \
            .execute()
        
        habits = habits_result.data
        logger.info(f"Found {len(habits)} active daily habits")

        # Group habits by user
        users_processed = set()
        penalties_created = 0
        
        for habit in habits:
            user_id = habit['user_id']
            
            if user_id in users_processed:
                logger.info(f"Skipping already processed user {user_id}")
                continue
            
            # Get user's timezone and current time
            user_timezone = get_user_timezone(supabase, user_id)
            user_tz = pytz.timezone(user_timezone)
            user_now = utc_now.astimezone(user_tz)
            yesterday_user = (user_now.date() - timedelta(days=1))
            
            logger.info(f"\nProcessing user {user_id}:")
            logger.info(f"  Timezone: {user_timezone}")
            logger.info(f"  Local time: {user_now.strftime('%Y-%m-%d %H:%M:%S %Z')}")
            logger.info(f"  Hour: {user_now.hour}")
            logger.info(f"  Checking habits for: {yesterday_user}")
            
            # Skip time check if bypass is enabled
            if not bypass_time_check and user_now.hour != 1:  # Using 1 AM as in the original scheduler
                logger.info(f"  Skipping - not 1 AM in user's timezone (current hour: {user_now.hour})")
                continue
                
            users_processed.add(user_id)
            logger.info("  Processing penalties for this user...")

            # Get all daily habits for this user
            user_habits = [h for h in habits if h['user_id'] == user_id]
            logger.info(f"  Found {len(user_habits)} habits for user")

            for habit in user_habits:
                logger.info(f"\n  Checking habit {habit['id']}:")
                logger.info(f"    Penalty amount: ${habit.get('penalty_amount', 0)}")
                logger.info(f"    Required days: {habit.get('weekdays', [])}")
                
                # Check if yesterday was a required day
                postgres_weekday = (yesterday_user.weekday() + 1) % 7
                if postgres_weekday not in habit["weekdays"]:
                    logger.info(f"    Skipping - {yesterday_user.strftime('%A')} not required")
                    continue

                # Check for verifications
                start_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.min.time()))
                end_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.max.time()))
                
                logs = supabase.table("habit_verifications") \
                    .select("*") \
                    .eq("habit_id", habit["id"]) \
                    .gte("verified_at", start_of_yesterday.isoformat()) \
                    .lte("verified_at", end_of_yesterday.isoformat()) \
                    .execute()

                if not logs.data:
                    if dry_run:
                        logger.info(f"    Would create penalty: ${habit['penalty_amount']} for {yesterday_user}")
                    else:
                        # Create actual penalty using the real logic
                        penalty_data = {
                            "user_id": habit["user_id"],
                            "recipient_id": habit["recipient_id"],
                            "amount": habit["penalty_amount"],
                            "penalty_date": yesterday_user.isoformat(),
                            "is_paid": False
                        }
                        
                        penalty_result = supabase.table("penalties").insert(penalty_data).execute()
                        penalty = penalty_result.data[0]
                        penalties_created += 1

                        # Decrement the streak when a penalty is created
                        await decrement_habit_streak_local(supabase, habit["id"])
                        
                        logger.info(f"    ✅ Created penalty: ${habit['penalty_amount']} for {yesterday_user}")
                        logger.info(f"    📉 Decremented streak for habit {habit['id']}")
                else:
                    logger.info(f"    Found verification - no penalty needed")

        logger.info(f"\n=== Summary ===")
        logger.info(f"Users processed: {len(users_processed)}")
        if dry_run:
            logger.info(f"This was a dry run - no penalties were actually created")
        else:
            logger.info(f"Penalties created: {penalties_created}")

    except Exception as e:
        logger.error(f"Error in debug_check_penalties: {str(e)}")
        raise

async def debug_weekly_aggregation(bypass_time_check=False, dry_run=False, actually_charge=False):
    """Debug version of weekly penalty aggregation with detailed logging
    
    Args:
        bypass_time_check: If True, ignores the Sunday midnight requirement
        dry_run: If True, only logs what would happen without creating charges
        actually_charge: If True, creates real Stripe charges (use with caution!)
    """
    supabase = get_supabase_client()
    utc_now = datetime.now(pytz.UTC)
    logger.info(f"Starting weekly penalty aggregation at {utc_now} UTC")
    logger.info(f"Time check bypass: {bypass_time_check}")
    logger.info(f"Dry run: {dry_run}")
    logger.info(f"Actually charge: {actually_charge}")

    try:
        # Get all users who have unpaid penalties
        users_with_penalties = supabase.table("penalties") \
            .select("user_id") \
            .eq("is_paid", False) \
            .execute()
        
        if not users_with_penalties.data:
            logger.info("No users with unpaid penalties found")
            return
        
        # Get unique user IDs
        user_ids = list(set([p["user_id"] for p in users_with_penalties.data]))
        logger.info(f"Found {len(user_ids)} users with unpaid penalties")
        
        for user_id in user_ids:
            try:
                # Get user timezone
                user_timezone = get_user_timezone(supabase, user_id)
                user_tz = pytz.timezone(user_timezone)
                user_now = utc_now.astimezone(user_tz)
                
                logger.info(f"\nProcessing user {user_id}:")
                logger.info(f"  Timezone: {user_timezone}")
                logger.info(f"  Local time: {user_now.strftime('%Y-%m-%d %H:%M:%S %Z')}")
                logger.info(f"  Weekday: {user_now.strftime('%A')}")
                logger.info(f"  Hour: {user_now.hour}")
                
                # Only process at beginning of Sunday (00:00-01:00) in user's timezone
                if not bypass_time_check and (user_now.weekday() != 6 or user_now.hour != 0):
                    logger.info(f"  Skipping - not Sunday midnight (current: {user_now.strftime('%A %H:%M')})")
                    continue
                
                # Get all unpaid penalties for this user
                unpaid_penalties = supabase.table("penalties") \
                    .select("*") \
                    .eq("user_id", user_id) \
                    .eq("is_paid", False) \
                    .execute()
                
                if not unpaid_penalties.data:
                    logger.info("  No unpaid penalties found")
                    continue
                
                # Calculate total amount
                total_amount = sum(float(p["amount"]) for p in unpaid_penalties.data)
                logger.info(f"  Found {len(unpaid_penalties.data)} unpaid penalties totaling ${total_amount:.2f}")
                
                if total_amount <= 0:
                    logger.info("  Skipping - total amount is $0")
                    continue
                
                # Get user's Stripe info
                user = supabase.table("users") \
                    .select("*") \
                    .eq("id", user_id) \
                    .single() \
                    .execute()
                
                if not user.data or not user.data.get("stripe_customer_id") or not user.data.get("default_payment_method_id"):
                    logger.warning(f"  User {user_id} has unpaid penalties but no payment method configured")
                    continue
                
                # Group penalties by recipient
                penalties_with_recipients = [p for p in unpaid_penalties.data if p.get("recipient_id")]
                penalties_without_recipients = [p for p in unpaid_penalties.data if not p.get("recipient_id")]
                
                if penalties_with_recipients:
                    recipient_groups = {}
                    for penalty in penalties_with_recipients:
                        recipient_id = penalty.get("recipient_id")
                        if recipient_id not in recipient_groups:
                            recipient_groups[recipient_id] = []
                        recipient_groups[recipient_id].append(penalty)
                    
                    logger.info(f"  Found penalties for {len(recipient_groups)} recipients")
                    
                    for recipient_id, recipient_penalties in recipient_groups.items():
                        recipient_amount = sum(float(p["amount"]) for p in recipient_penalties)
                        platform_fee = recipient_amount * 0.15  # 15% fee
                        recipient_gets = recipient_amount - platform_fee
                        
                        logger.info(f"\n  Recipient {recipient_id}:")
                        logger.info(f"    Penalties: {len(recipient_penalties)}")
                        logger.info(f"    Total amount: ${recipient_amount:.2f}")
                        logger.info(f"    Platform fee (15%): ${platform_fee:.2f}")
                        logger.info(f"    Recipient gets: ${recipient_gets:.2f}")
                        
                        # Check $5 minimum before proceeding
                        if recipient_amount < 5.0:
                            logger.info(f"    ⏭️ Skipping - below $5.00 minimum (${recipient_amount:.2f})")
                            continue
                        
                        if not dry_run and actually_charge:
                            # Get recipient's Connect account
                            recipient = supabase.table("users") \
                                .select("*") \
                                .eq("id", recipient_id) \
                                .single() \
                                .execute()
                            
                            if not recipient.data or not recipient.data.get("stripe_connect_account_id"):
                                logger.warning(f"    Recipient missing Connect account")
                                continue
                            
                            # Create destination charge
                            payment_intent = stripe.PaymentIntent.create(
                                amount=int(round(recipient_amount * 100)),
                                currency="usd",
                                customer=user.data["stripe_customer_id"],
                                payment_method=user.data["default_payment_method_id"],
                                off_session=True,
                                confirm=True,
                                application_fee_amount=int(round(platform_fee * 100)),
                                transfer_data={
                                    "destination": recipient.data["stripe_connect_account_id"],
                                },
                                metadata={
                                    "user_id": user_id,
                                    "recipient_id": recipient_id,
                                    "type": "weekly_aggregate_with_recipient",
                                    "penalty_count": str(len(recipient_penalties))
                                }
                            )
                            logger.info(f"    Created charge: {payment_intent.id}")
                
                if penalties_without_recipients:
                    platform_amount = sum(float(p["amount"]) for p in penalties_without_recipients)
                    logger.info(f"\n  Platform-only penalties:")
                    logger.info(f"    Count: {len(penalties_without_recipients)}")
                    logger.info(f"    Amount: ${platform_amount:.2f}")
                    
                    # Check $5 minimum before proceeding
                    if platform_amount < 5.0:
                        logger.info(f"    ⏭️ Skipping - below $5.00 minimum (${platform_amount:.2f})")
                        continue
                    
                    if not dry_run and actually_charge:
                        payment_intent = stripe.PaymentIntent.create(
                            amount=int(platform_amount * 100),
                            currency="usd",
                            customer=user.data["stripe_customer_id"],
                            payment_method=user.data["default_payment_method_id"],
                            off_session=True,
                            confirm=True,
                            metadata={
                                "user_id": user_id,
                                "type": "weekly_aggregate_platform_only",
                                "penalty_count": str(len(penalties_without_recipients))
                            }
                        )
                        logger.info(f"    Created charge: {payment_intent.id}")
            
            except Exception as e:
                logger.error(f"Error processing user {user_id}: {str(e)}")
                continue

    except Exception as e:
        logger.error(f"Error in debug_weekly_aggregation: {str(e)}")
        raise

async def run_scheduler_task(task_name: str):
    """
    Run a specific scheduler task on demand
    """
    if task_name == "check_penalties":
        bypass = input("Bypass time check? (y/n): ").lower() == 'y'
        dry_run = input("Dry run (no actual penalties created)? (y/n): ").lower() == 'y'
        await debug_check_penalties(bypass_time_check=bypass, dry_run=dry_run)
        return
    
    if task_name == "check_weekly":
        bypass = input("Bypass time check? (y/n): ").lower() == 'y'
        dry_run = input("Dry run (no actual charges created)? (y/n): ").lower() == 'y'
        if not dry_run:
            charge = input("Actually create Stripe charges? (y/n): ").lower() == 'y'
        else:
            charge = False
        await debug_weekly_aggregation(bypass_time_check=bypass, dry_run=dry_run, actually_charge=charge)
        return

    task_mapping = {
        "update_payments": update_processing_payment_statuses,
        "process_staged": process_staged_habit_changes,
        "archive_feed": archive_old_feed_cards_task
    }
    
    if task_name not in task_mapping:
        logger.error(f"Unknown task: {task_name}")
        logger.info(f"Available tasks: {list(task_mapping.keys())}")
        return
    
    logger.info(f"Running task: {task_name} at {datetime.now(pytz.UTC)}")
    try:
        await task_mapping[task_name]()
        logger.info(f"Task {task_name} completed successfully")
    except Exception as e:
        logger.error(f"Task {task_name} failed: {e}")
        logger.error(f"Error details: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python tasks/test_scheduler.py <task_name>")
        print("Run from the backend/app directory")
        print("\nAvailable tasks:")
        print("  - check_penalties: Run daily penalty checks")
        print("  - check_weekly: Run weekly penalty aggregation")
        print("  - update_payments: Update processing payment statuses")
        print("  - process_staged: Process staged habit changes")
        print("  - archive_feed: Archive old feed cards")
        sys.exit(1)
    
    task_name = sys.argv[1]
    asyncio.run(run_scheduler_task(task_name)) 