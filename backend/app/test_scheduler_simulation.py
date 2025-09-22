#!/usr/bin/env python3
"""
Scheduler Simulation Script - Exactly mimics how the auto scheduler works

This script runs the exact same logic as the production scheduler:
1. Daily penalty checks (runs every hour, processes users at 1 AM in their timezone)
2. Weekly penalty aggregation (runs every hour, processes users at Sunday midnight)
3. Weekly habit penalties (checks incomplete weekly habits)

NEW: Added timing bypass options for testing without waiting for specific times!

Usage:
    python test_scheduler_simulation.py
"""

import asyncio
import os
import sys
from datetime import datetime, timedelta
import pytz

# Add the current directory to Python path
sys.path.append(os.path.dirname(__file__))

from config.database import get_supabase_client
from tasks.scheduler import (
    get_user_timezone,
    decrement_habit_streak_local,
    check_and_create_penalty_for_habit,
    check_deleted_edited_habits_penalties,
    process_recipient_transfers
)
from utils.weekly_habits import get_week_dates
import stripe


class SchedulerSimulator:
    def __init__(self, verbose=True, actually_charge=False, bypass_timing=False):
        self.verbose = verbose
        self.actually_charge = actually_charge
        self.bypass_timing = bypass_timing  # NEW: Bypass all timing checks for testing
        self.supabase = get_supabase_client()
        self.utc_now = datetime.now(pytz.UTC)
        
    def log(self, message, level="INFO"):
        if self.verbose:
            timestamp = self.utc_now.strftime("%Y-%m-%d %H:%M:%S UTC")
            bypass_indicator = " [BYPASS]" if self.bypass_timing else ""
            print(f"[{timestamp}]{bypass_indicator} [{level}] {message}")
    
    async def simulate_daily_penalty_check(self):
        """
        Exact replica of check_and_charge_penalties() function
        """
        self.log("🔄 Starting daily penalty check simulation...")
        
        try:
            # Process habits that were deleted/edited today and charge penalties if missed
            try:
                await check_deleted_edited_habits_penalties(self.supabase)
                self.log("✅ Processed deleted/edited habits penalties")
            except Exception as e:
                self.log(f"❌ Error checking deleted/edited habits penalties: {e}", "ERROR")
            
            # Get all DAILY habits with their created_at timestamps and user timezones
            habits_result = self.supabase.table("habits") \
                .select("*, users!habits_user_id_fkey!inner(timezone)") \
                .eq("habit_schedule_type", "daily") \
                .eq("is_active", True) \
                .execute()
            habits = habits_result.data
            
            self.log(f"📋 Found {len(habits)} active daily habits")

            # Group habits by user to avoid duplicate timezone processing
            users_processed = set()
            daily_penalty_count = 0
            users_eligible_count = 0
            users_processed_count = 0

            for habit in habits:
                user_id = habit['user_id']
                
                # Skip if we already processed this user in this run
                if user_id in users_processed:
                    continue
                users_processed.add(user_id)
                users_eligible_count += 1
                
                # Get user's timezone and current time
                user_timezone = get_user_timezone(self.supabase, user_id)
                user_tz = pytz.timezone(user_timezone)
                user_now = self.utc_now.astimezone(user_tz)
                
                self.log(f"👤 User {user_id}: {user_timezone}, local time: {user_now.strftime('%a %H:%M')}")
                
                # TIMING CHECK: Only process penalties if it's 1 AM in the user's timezone (or bypass timing)
                if not self.bypass_timing and user_now.hour != 1:  # 1 = 1 AM
                    self.log(f"   ⏭️ Skipping (waiting for 01:00, currently {user_now.strftime('%H:%M')})")
                    continue
                elif self.bypass_timing:
                    self.log(f"   🧪 BYPASS: Processing user (would normally wait for 01:00)")
                
                users_processed_count += 1
                self.log(f"   ✅ Processing user at 1 AM" if not self.bypass_timing else f"   ✅ Processing user (timing bypassed)")
                
                # Get yesterday in user's timezone
                yesterday_user = (user_now.date() - timedelta(days=1))
                
                # Get all daily habits for this user
                user_habits = [h for h in habits if h['user_id'] == user_id]
                self.log(f"   📝 Checking {len(user_habits)} habits for {yesterday_user}")
                
                for habit in user_habits:
                    # Check if yesterday was a required day (weekday is 0-6 where 0 is Sunday in Postgres)
                    postgres_weekday = (yesterday_user.weekday() + 1) % 7  # Convert to Postgres weekday format
                    
                    if postgres_weekday not in habit["weekdays"]:
                        self.log(f"     ⏭️ Habit {habit['id']}: {yesterday_user.strftime('%A')} not required")
                        continue

                    start_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.min.time()))
                    end_of_yesterday = user_tz.localize(datetime.combine(yesterday_user, datetime.max.time()))
                    
                    logs = self.supabase.table("habit_verifications") \
                        .select("*") \
                        .eq("habit_id", habit["id"]) \
                        .gte("verified_at", start_of_yesterday.isoformat()) \
                        .lte("verified_at", end_of_yesterday.isoformat()) \
                        .execute()

                    if not logs.data:
                        # Create penalty
                        penalty_data = {
                            "user_id": habit["user_id"],
                            "recipient_id": habit["recipient_id"],
                            "amount": habit["penalty_amount"],
                            "penalty_date": yesterday_user.isoformat(),
                            "is_paid": False
                        }
                        
                        penalty_result = self.supabase.table("penalties").insert(penalty_data).execute()
                        penalty = penalty_result.data[0]
                        daily_penalty_count += 1

                        # Decrement the streak when a penalty is created
                        await decrement_habit_streak_local(self.supabase, habit["id"])

                        self.log(f"     💸 Created penalty: ${habit['penalty_amount']} for habit {habit['id']}")
                    else:
                        self.log(f"     ✅ Habit {habit['id']}: verified on {yesterday_user}")

            self.log(f"📊 Daily penalty check summary:")
            self.log(f"   • Total users with daily habits: {users_eligible_count}")
            self.log(f"   • Users processed (at 1 AM): {users_processed_count}")
            self.log(f"   • Penalties created: {daily_penalty_count}")

        except Exception as e:
            self.log(f"❌ Error in daily penalty check: {str(e)}", "ERROR")
            raise
    
    async def simulate_weekly_penalty_aggregation(self):
        """
        NEW: Aggregate and charge all unpaid penalties per user when total reaches $5
        Then transfer funds to recipients separately with 15% platform fee
        """
        self.log("🔄 Starting weekly penalty aggregation simulation...")
        
        all_processed_penalty_ids = []  # Track all penalty IDs for potential recipient payouts
        
        try:
            # --- 1. AGGREGATE AND CHARGE ALL UNPAID PENALTIES PER USER ---
            # Get all users who have unpaid penalties
            users_with_penalties = self.supabase.table("penalties") \
                .select("user_id") \
                .eq("is_paid", False) \
                .execute()
            
            if not users_with_penalties.data:
                self.log("📭 No users with unpaid penalties found")
                return all_processed_penalty_ids
            
            # Get unique user IDs
            user_ids = list(set([p["user_id"] for p in users_with_penalties.data]))
            self.log(f"👥 Found {len(user_ids)} users with unpaid penalties")
            
            charged_users = 0
            total_charged_amount = 0
            
            for user_id in user_ids:
                try:
                    # Get user timezone
                    user_timezone = get_user_timezone(self.supabase, user_id)
                    user_tz = pytz.timezone(user_timezone)
                    user_now = self.utc_now.astimezone(user_tz)
                    
                    self.log(f"👤 User {user_id}: {user_timezone}, local time: {user_now.strftime('%a %H:%M')}")
                    
                    # TIMING CHECK: Only process at beginning of Sunday (00:00-01:00) in user's timezone (or bypass timing)
                    if not self.bypass_timing and (user_now.weekday() != 6 or user_now.hour != 0):  # 6 = Sunday, 0 = midnight hour
                        self.log(f"   ⏭️ Skipping (waiting for Sunday 00:00, currently {user_now.strftime('%a %H:%M')})")
                        continue
                    elif self.bypass_timing:
                        self.log(f"   🧪 BYPASS: Processing user (would normally wait for Sunday 00:00)")
                    
                    self.log(f"   ✅ Processing user at Sunday midnight" if not self.bypass_timing else f"   ✅ Processing user (timing bypassed)")
                    
                    # Get all unpaid penalties for this user
                    unpaid_penalties = self.supabase.table("penalties") \
                        .select("*") \
                        .eq("user_id", user_id) \
                        .eq("is_paid", False) \
                        .execute()
                    
                    if not unpaid_penalties.data:
                        self.log(f"   📭 No unpaid penalties for user")
                        continue
                    
                    # Calculate total amount across ALL penalties
                    total_amount = sum(float(p["amount"]) for p in unpaid_penalties.data)
                    
                    # NEW: Only charge if total amount is $5 or more (across all recipients)
                    if total_amount < 5.0:
                        self.log(f"   💰 {len(unpaid_penalties.data)} penalties totaling ${total_amount:.2f} < $5.00 minimum, waiting for more")
                        continue
                    
                    self.log(f"   💰 {len(unpaid_penalties.data)} penalties totaling ${total_amount}")
                    
                    if total_amount <= 0:
                        self.log(f"   ⏭️ Total amount is $0, skipping")
                        continue
                    
                    # Get user's Stripe info
                    user = self.supabase.table("users") \
                        .select("*") \
                        .eq("id", user_id) \
                        .single() \
                        .execute()
                    
                    if not user.data or not user.data.get("stripe_customer_id") or not user.data.get("default_payment_method_id"):
                        self.log(f"   ❌ Missing Stripe configuration", "WARNING")
                        continue
                    
                    # Create aggregated payment intent
                    penalty_ids = [str(p["id"]) for p in unpaid_penalties.data]
                    
                    self.log(f"   💳 Creating single platform charge for ${total_amount:.2f}...")
                    
                    if self.actually_charge:
                        # NEW: Create single charge to platform (no destination charge)
                        payment_intent = stripe.PaymentIntent.create(
                            amount=int(total_amount * 100),  # Convert to cents
                            currency="usd",
                            customer=user.data["stripe_customer_id"],
                            payment_method=user.data["default_payment_method_id"],
                            off_session=True,
                            confirm=True,
                            metadata={
                                "user_id": user_id,
                                "type": "weekly_aggregate_with_separate_transfers",
                                "penalty_count": str(len(penalty_ids)),
                                "total_amount": str(total_amount)
                            }
                        )
                        
                        # Update all penalties with payment intent ID and mark as processing
                        self.supabase.table("penalties") \
                            .update({
                                "payment_intent_id": payment_intent.id, 
                                "payment_status": "processing"
                            }) \
                            .in_("id", penalty_ids) \
                            .execute()
                        
                        self.log(f"   ✅ Created platform charge: {payment_intent.id}")
                        
                        # Check payment status immediately (since confirm=True should make it succeed instantly)
                        payment_status = payment_intent.status
                        self.log(f"   📊 Payment status: {payment_status}")
                        
                        if payment_status == "succeeded":
                            # Mark penalties as paid and succeeded
                            self.supabase.table("penalties") \
                                .update({
                                    "is_paid": True,
                                    "payment_status": "succeeded"
                                }) \
                                .in_("id", penalty_ids) \
                                .execute()
                            
                            self.log(f"   ✅ Penalties marked as succeeded")
                            
                            # NEW: Process transfers to recipients separately
                            await self.process_recipient_transfers_simulation(unpaid_penalties.data)
                            
                            all_processed_penalty_ids.extend(penalty_ids)
                        else:
                            self.log(f"   ⚠️ Payment not immediately succeeded, status: {payment_status}")
                    else:
                        self.log(f"   🧪 SIMULATION: Would create platform charge for ${total_amount}")
                        self.log(f"       Penalty IDs: {penalty_ids}")
                        penalties_with_recipients = [p for p in unpaid_penalties.data if p.get("recipient_id")]
                        if penalties_with_recipients:
                            self.log(f"       Would then transfer to {len(set([p['recipient_id'] for p in penalties_with_recipients]))} recipients with 15% platform fee")
                        
                        # For simulation, mark as processed
                        all_processed_penalty_ids.extend(penalty_ids)
                    
                    charged_users += 1
                    total_charged_amount += total_amount
                    
                except Exception as e:
                    self.log(f"   ❌ Error processing user {user_id}: {e}", "ERROR")
                    continue
            
            self.log(f"📊 Weekly aggregation summary:")
            self.log(f"   • Users with penalties: {len(user_ids)}")
            self.log(f"   • Users charged: {charged_users}")
            self.log(f"   • Total amount: ${total_charged_amount:.2f}")
            
            return all_processed_penalty_ids
        
        except Exception as e:
            self.log(f"❌ Error in weekly penalty aggregation: {e}", "ERROR")
            raise

    async def process_recipient_transfers_simulation(self, penalties: list):
        """
        NEW: Simulate processing transfers to recipients after successful platform charge
        Uses 15% platform fee and calculates amounts dynamically
        """
        try:
            # Group penalties by recipient
            recipient_groups = {}
            for penalty in penalties:
                recipient_id = penalty.get("recipient_id")
                if recipient_id:
                    if recipient_id not in recipient_groups:
                        recipient_groups[recipient_id] = []
                    recipient_groups[recipient_id].append(penalty)
            
            if not recipient_groups:
                self.log("   📭 No penalties with recipients found for transfers")
                return
            
            self.log(f"   💸 Processing transfers to {len(recipient_groups)} recipients")
            
            for recipient_id, recipient_penalties in recipient_groups.items():
                try:
                    # Get recipient's Connect account
                    recipient = self.supabase.table("users") \
                        .select("*") \
                        .eq("id", recipient_id) \
                        .single() \
                        .execute()
                    
                    if not recipient.data or not recipient.data.get("stripe_connect_account_id"):
                        self.log(f"      ⚠️ Recipient {recipient_id} missing Connect account, skipping transfer")
                        continue
                    
                    recipient_connect_account = recipient.data["stripe_connect_account_id"]
                    
                    # Calculate amounts dynamically from existing penalty amounts
                    recipient_penalty_amount = sum(float(p["amount"]) for p in recipient_penalties)
                    recipient_penalty_ids = [str(p["id"]) for p in recipient_penalties]
                    
                    # Platform fee rate (15% - can be made configurable later)
                    platform_fee_rate = 0.15  # 15% platform fee
                    platform_fee = recipient_penalty_amount * platform_fee_rate
                    transfer_amount = recipient_penalty_amount * (1 - platform_fee_rate)  # 85% to recipient
                    
                    # Skip if transfer amount is less than $5.00 minimum (due to Stripe Connect fees)
                    if transfer_amount < 5.00:
                        self.log(f"      ⏭️ Skipping recipient {recipient.data.get('name', 'Unknown')}: transfer amount ${transfer_amount:.2f} < $5.00 minimum")
                        continue
                    
                    self.log(f"      🎯 Creating transfer for {recipient.data.get('name', 'Unknown')}")
                    self.log(f"         Original penalty amount: ${recipient_penalty_amount:.2f}")
                    self.log(f"         Platform fee (15%): ${platform_fee:.2f}")
                    self.log(f"         Transfer amount: ${transfer_amount:.2f}")
                    
                    if self.actually_charge:
                        # Create transfer to recipient
                        transfer = stripe.Transfer.create(
                            amount=int(round(transfer_amount * 100)),  # Transfer amount after platform fee
                            currency="usd",
                            destination=recipient_connect_account,
                            metadata={
                                "recipient_id": recipient_id,
                                "original_amount": str(recipient_penalty_amount),
                                "platform_fee": str(platform_fee),
                                "platform_fee_rate": str(platform_fee_rate),
                                "type": "recipient_penalty_payout",
                                "penalty_count": str(len(recipient_penalty_ids))
                            }
                        )
                        
                        # Update penalties with transfer info (only store transfer_id and platform_fee_rate)
                        self.supabase.table("penalties") \
                            .update({
                                "transfer_id": transfer.id,
                                "platform_fee_rate": platform_fee_rate
                            }) \
                            .in_("id", recipient_penalty_ids) \
                            .execute()
                        
                        self.log(f"      ✅ Transfer created: {transfer.id}")
                    else:
                        self.log(f"      🧪 SIMULATION: Would create transfer {transfer.id if 'transfer' in locals() else 'N/A'}")
                    
                except Exception as e:
                    self.log(f"      ❌ Error creating transfer for recipient {recipient_id}: {e}")
                    continue
            
            self.log(f"   🎉 Recipient transfers completed!")
            
        except Exception as e:
            self.log(f"   ❌ Error in process_recipient_transfers: {e}")
            raise
    
    async def simulate_weekly_habit_penalties(self):
        """
        Exact replica of the weekly habits part of check_weekly_penalties()
        """
        self.log("🔄 Starting weekly habit penalty check simulation...")
        
        try:
            weekly_habits = self.supabase.table("habits") \
                .select("*, users!habits_user_id_fkey!inner(timezone)") \
                .eq("habit_schedule_type", "weekly") \
                .eq("is_active", True) \
                .execute()
            
            self.log(f"📋 Found {len(weekly_habits.data)} active weekly habits")
            
            users_processed_weekly = set()
            weekly_penalty_count = 0
            
            for habit in weekly_habits.data:
                user_id = habit['user_id']
                
                # Skip if we already processed this user for weekly habits
                if user_id in users_processed_weekly:
                    continue
                users_processed_weekly.add(user_id)
                
                # Get user timezone
                user_timezone = get_user_timezone(self.supabase, user_id)
                user_tz = pytz.timezone(user_timezone)
                user_now = self.utc_now.astimezone(user_tz)
                today_user = user_now.date()
                
                self.log(f"👤 User {user_id}: {user_timezone}, local date: {today_user}")
                
                # Get all weekly habits for this user
                user_weekly_habits = [h for h in weekly_habits.data if h['user_id'] == user_id]
                
                for weekly_habit in user_weekly_habits:
                    try:
                        habit_week_start_day = weekly_habit.get('week_start_day', 0)
                        
                        if self.bypass_timing:
                            # When bypassing timing, assume we're at the end of the week
                            self.log(f"   🧪 BYPASS: Processing weekly habit {weekly_habit['id']} (would normally check week end)")
                            # Use yesterday as the completed week end
                            yesterday = today_user - timedelta(days=1)
                            completed_week_start, completed_week_end = get_week_dates(yesterday, habit_week_start_day)
                        else:
                            # TIMING CHECK: Only process at the end of the week (when week transitions)
                            # Check if today is the last day of the week for this habit
                            week_start, week_end = get_week_dates(today_user, habit_week_start_day)
                            
                            # Only process if today is the day after week_end (start of new week)
                            if today_user != week_end + timedelta(days=1):
                                self.log(f"   ⏭️ Habit {weekly_habit['id']}: not end of week (week ends {week_end})")
                                continue
                            
                            # Only process once per day at the right hour (early morning)
                            if user_now.hour != 1:  # 1 AM
                                self.log(f"   ⏭️ Habit {weekly_habit['id']}: waiting for 1 AM (currently {user_now.hour}:00)")
                                continue
                            
                            # Get the week that just ended
                            yesterday = today_user - timedelta(days=1)
                            completed_week_start, completed_week_end = get_week_dates(yesterday, habit_week_start_day)
                        
                        self.log(f"   ✅ Processing weekly habit {weekly_habit['id']} at week end" if not self.bypass_timing else f"   ✅ Processing weekly habit {weekly_habit['id']} (timing bypassed)")
                        self.log(f"     📅 Completed week: {completed_week_start} to {completed_week_end}")
                        
                        # Check progress for the completed week
                        progress_result = self.supabase.table("weekly_habit_progress") \
                            .select("*") \
                            .eq("habit_id", weekly_habit['id']) \
                            .eq("week_start_date", completed_week_start.isoformat()) \
                            .execute()
                        
                        if progress_result.data:
                            current_progress = progress_result.data[0]
                            missed_count = max(0, current_progress['target_completions'] - current_progress['current_completions'])
                            self.log(f"     📊 Progress: {current_progress['current_completions']}/{current_progress['target_completions']}")
                        else:
                            # No progress record found, all completions were missed
                            missed_count = weekly_habit['weekly_target']
                            self.log(f"     📊 No progress found, missed all {missed_count} completions")
                        
                        if missed_count > 0:
                            # Create penalty for missed completions (will be charged next Sunday)
                            penalty_amount = weekly_habit['penalty_amount'] * missed_count
                            penalty_data = {
                                "user_id": user_id,
                                "recipient_id": weekly_habit["recipient_id"],
                                "amount": penalty_amount,
                                "penalty_date": completed_week_end.isoformat(),
                                "is_paid": False
                            }
                            
                            penalty_result = self.supabase.table("penalties").insert(penalty_data).execute()
                            weekly_penalty_count += 1
                            
                            # Decrement the streak when a weekly penalty is created
                            await decrement_habit_streak_local(self.supabase, weekly_habit["id"])
                            
                            self.log(f"     💸 Created weekly penalty: ${penalty_amount} for {missed_count} missed completions")
                        else:
                            self.log(f"     ✅ Week completed successfully")
                
                    except Exception as e:
                        self.log(f"   ❌ Error processing weekly habit {weekly_habit.get('id')}: {e}", "ERROR")
                        continue
            
            self.log(f"📊 Weekly habit penalty summary:")
            self.log(f"   • Users with weekly habits: {len(users_processed_weekly)}")
            self.log(f"   • Weekly penalties created: {weekly_penalty_count}")
        
        except Exception as e:
            self.log(f"❌ Error in weekly habit penalty check: {e}", "ERROR")
            raise
    
    async def show_user_summary(self):
        """Show summary of all users and their current status"""
        self.log("📊 User Summary:")
        
        try:
            # Get all users with habits
            users_result = self.supabase.table("users") \
                .select("id, timezone") \
                .execute()
            
            for user in users_result.data:
                user_id = user['id']
                user_timezone = user.get('timezone', 'UTC')
                
                try:
                    user_tz = pytz.timezone(get_user_timezone(self.supabase, user_id))
                    user_now = self.utc_now.astimezone(user_tz)
                    
                    # Get habit counts
                    daily_habits = self.supabase.table("habits") \
                        .select("id") \
                        .eq("user_id", user_id) \
                        .eq("habit_schedule_type", "daily") \
                        .eq("is_active", True) \
                        .execute()
                    
                    weekly_habits = self.supabase.table("habits") \
                        .select("id") \
                        .eq("user_id", user_id) \
                        .eq("habit_schedule_type", "weekly") \
                        .eq("is_active", True) \
                        .execute()
                    
                    # Get penalty counts
                    unpaid_penalties = self.supabase.table("penalties") \
                        .select("amount") \
                        .eq("user_id", user_id) \
                        .eq("is_paid", False) \
                        .execute()
                    
                    total_unpaid = sum(float(p["amount"]) for p in unpaid_penalties.data)
                    
                    # Check if user would be processed now
                    daily_ready = user_now.hour == 1
                    weekly_ready = user_now.weekday() == 6 and user_now.hour == 0
                    
                    status_flags = []
                    if self.bypass_timing:
                        status_flags.append("🧪 BYPASS_ENABLED")
                    if daily_ready:
                        status_flags.append("🔴 DAILY_READY")
                    if weekly_ready:
                        status_flags.append("🔵 WEEKLY_READY")
                    
                    self.log(f"👤 {user_id[:8]}... ({user_timezone})")
                    self.log(f"   📅 Local time: {user_now.strftime('%a %Y-%m-%d %H:%M')}")
                    self.log(f"   📝 Habits: {len(daily_habits.data)} daily, {len(weekly_habits.data)} weekly")
                    self.log(f"   💸 Unpaid penalties: {len(unpaid_penalties.data)} (${total_unpaid:.2f})")
                    if status_flags:
                        self.log(f"   🚨 Status: {' '.join(status_flags)}")
                    self.log("")
                    
                except Exception as e:
                    self.log(f"   ❌ Error processing user {user_id}: {e}", "ERROR")
        
        except Exception as e:
            self.log(f"❌ Error in user summary: {e}", "ERROR")

    async def test_recipient_payouts(self, penalty_ids: list = None, user_id: str = None):
        """
        Test function to manually test recipient payout processing
        
        Args:
            penalty_ids: Specific penalty IDs to test (if None, finds recent succeeded penalties)
            user_id: Filter penalties by user ID (optional)
        """
        self.log("🧪 Testing aggregated recipient payout processing...")
        self.log(f"🧪 Penalty IDs: {penalty_ids or 'Auto-detect all eligible penalties'}")
        self.log(f"🧪 User ID filter: {user_id or 'All users'}")
        
        try:
            # Show platform balance first
            try:
                balance = stripe.Balance.retrieve()
                available_usd = 0
                for balance_item in balance.available:
                    if balance_item.currency == "usd":
                        available_usd = balance_item.amount / 100
                        break
                self.log(f"💰 Current platform balance: ${available_usd:.2f}")
            except Exception as e:
                self.log(f"❌ Could not retrieve balance: {e}", "WARNING")
            
            if not penalty_ids:
                # Find ALL eligible penalties with recipients (both 'completed' and 'succeeded' status)
                query = self.supabase.table("penalties") \
                    .select("*") \
                    .in_("payment_status", ["succeeded", "completed"]) \
                    .eq("is_paid", True) \
                    .is_("transfer_id", "null") \
                    .not_.is_("recipient_id", "null")
                
                if user_id:
                    query = query.eq("user_id", user_id)
                
                result = query.execute()
                
                if not result.data:
                    self.log("❌ No eligible penalties found for testing")
                    self.log("Looking for penalties that are:")
                    self.log("  - payment_status = 'succeeded' OR 'completed'")
                    self.log("  - is_paid = true")
                    self.log("  - transfer_id is null")
                    self.log("  - recipient_id is not null")
                    return
                
                penalty_ids = [p["id"] for p in result.data]
                self.log(f"Found {len(penalty_ids)} eligible penalties for aggregation")
            
            # Show aggregated penalty details by recipient before processing
            penalties_result = self.supabase.table("penalties") \
                .select("*") \
                .in_("payment_status", ["succeeded", "completed"]) \
                .eq("is_paid", True) \
                .is_("transfer_id", "null") \
                .not_.is_("recipient_id", "null") \
                .execute()
            
            # Group by recipient to show aggregation
            recipient_groups = {}
            for penalty in penalties_result.data:
                recipient_id = penalty.get("recipient_id")
                if recipient_id:
                    if recipient_id not in recipient_groups:
                        recipient_groups[recipient_id] = {
                            "penalties": [],
                            "total_amount": 0,
                            "count": 0
                        }
                    recipient_groups[recipient_id]["penalties"].append(penalty)
                    recipient_groups[recipient_id]["total_amount"] += float(penalty["amount"])
                    recipient_groups[recipient_id]["count"] += 1
            
            self.log(f"\n📋 Aggregated penalties by recipient ({len(recipient_groups)} recipients):")
            total_needed = 0
            for recipient_id, group in recipient_groups.items():
                payout_amount = group["total_amount"] * 0.85  # 15% platform fee
                platform_fee = group["total_amount"] * 0.15
                total_needed += payout_amount
                
                # Get recipient name
                recipient = self.supabase.table("users").select("name").eq("id", recipient_id).single().execute()
                recipient_name = recipient.data.get("name", "Unknown") if recipient.data else "Unknown"
                
                self.log(f"  👤 {recipient_name} ({recipient_id[:8]}...):")
                self.log(f"    📊 {group['count']} penalties = ${group['total_amount']:.2f}")
                self.log(f"    💰 Payout (85%): ${payout_amount:.2f}")
                self.log(f"    🏦 Platform fee (15%): ${platform_fee:.2f}")
                if payout_amount < 5.00:
                    self.log(f"    ⚠️ Below $5.00 minimum - will wait for more penalties")
                else:
                    self.log(f"    ✅ Ready to transfer ${payout_amount:.2f}")
            
            self.log(f"\n💸 Total payout needed: ${total_needed:.2f}")
            
            # Test the recipient payout processing with the found penalties
            await process_recipient_transfers(self.supabase, penalties_result.data)
            
            # Show results after processing
            self.log("\n📋 Results after processing:")
            processed_count = 0
            total_transferred = 0
            
            for recipient_id, group in recipient_groups.items():
                # Check if any penalties for this recipient got transfer_ids
                updated_penalties = self.supabase.table("penalties") \
                    .select("*") \
                    .eq("recipient_id", recipient_id) \
                    .not_.is_("transfer_id", "null") \
                    .execute()
                
                if updated_penalties.data:
                    transfer_id = updated_penalties.data[0].get("transfer_id")
                    transferred_amount = sum(float(p["amount"]) for p in updated_penalties.data) * 0.85
                    total_transferred += transferred_amount
                    processed_count += 1
                    
                    recipient = self.supabase.table("users").select("name").eq("id", recipient_id).single().execute()
                    recipient_name = recipient.data.get("name", "Unknown") if recipient.data else "Unknown"
                    
                    self.log(f"  ✅ {recipient_name}: ${transferred_amount:.2f} transferred (ID: {transfer_id})")
                else:
                    recipient = self.supabase.table("users").select("name").eq("id", recipient_id).single().execute()
                    recipient_name = recipient.data.get("name", "Unknown") if recipient.data else "Unknown"
                    payout_amount = group["total_amount"] * 0.85
                    
                    if payout_amount < 5.00:
                        self.log(f"  ⏭️ {recipient_name}: Waiting for aggregation (${payout_amount:.2f} < $5.00)")
                    else:
                        self.log(f"  ❌ {recipient_name}: Transfer failed or Connect account issue")
            
            self.log(f"\n🎉 Summary: {processed_count} recipients processed, ${total_transferred:.2f} total transferred")
            self.log("✅ Aggregated recipient payout test completed!")
            
        except Exception as e:
            self.log(f"❌ Error in recipient payout test: {e}", "ERROR")
            raise

    async def simulate_payment_success(self, penalty_ids: list):
        """
        Test function to simulate successful payment for testing recipient payouts
        
        Args:
            penalty_ids: List of penalty IDs to mark as succeeded
        """
        self.log(f"🧪 Simulating payment success for {len(penalty_ids)} penalties...")
        
        try:
            # Update penalties to mark them as succeeded
            result = self.supabase.table("penalties") \
                .update({
                    "is_paid": True,
                    "payment_status": "succeeded",
                    "payment_intent_id": "pi_test_simulation_" + str(int(datetime.now().timestamp()))
                }) \
                .in_("id", penalty_ids) \
                .execute()
            
            self.log(f"✅ Marked {len(penalty_ids)} penalties as succeeded")
            
            # Now test recipient payouts
            await process_recipient_payouts(self.supabase, penalty_ids)
            
            self.log("✅ Payment simulation and recipient payout test completed!")
            
        except Exception as e:
            self.log(f"❌ Error in payment simulation: {e}", "ERROR")
            raise

    async def check_penalty_status(self, user_id: str = None):
        """
        Check penalty status for a user or all users
        
        Args:
            user_id: Specific user ID to check (if None, checks all users)
        """
        self.log(f"📊 Checking penalty status for: {user_id or 'ALL USERS'}")
        
        try:
            query = self.supabase.table("penalties").select("*")
            if user_id:
                query = query.eq("user_id", user_id)
            
            penalties = query.order("created_at", desc=True).execute()
            
            if not penalties.data:
                self.log("📭 No penalties found")
                return
            
            # Group by user and payment status
            by_user = {}
            for penalty in penalties.data:
                uid = penalty["user_id"]
                if uid not in by_user:
                    by_user[uid] = {"paid": [], "unpaid": [], "processing": [], "with_recipients": []}
                
                if penalty["is_paid"]:
                    by_user[uid]["paid"].append(penalty)
                elif penalty.get("payment_status") == "processing":
                    by_user[uid]["processing"].append(penalty)
                else:
                    by_user[uid]["unpaid"].append(penalty)
                    
                if penalty.get("recipient_id"):
                    by_user[uid]["with_recipients"].append(penalty)
            
            for uid, user_penalties in by_user.items():
                self.log(f"\n👤 User: {uid}")
                
                if user_penalties["unpaid"]:
                    total_unpaid = sum(float(p["amount"]) for p in user_penalties["unpaid"])
                    unpaid_with_recipients = [p for p in user_penalties["unpaid"] if p.get("recipient_id")]
                    unpaid_recipient_total = sum(float(p["amount"]) for p in unpaid_with_recipients) * 0.85
                    
                    self.log(f"  💸 Unpaid: {len(user_penalties['unpaid'])} penalties, ${total_unpaid:.2f}")
                    if unpaid_with_recipients:
                        self.log(f"     📤 With recipients: {len(unpaid_with_recipients)} penalties (${unpaid_recipient_total:.2f} potential payout at 85%)")
                    for p in user_penalties["unpaid"][:3]:  # Show first 3
                        recipient_note = f" → {p.get('recipient_id', 'No recipient')}" if p.get('recipient_id') else ""
                        self.log(f"    - {p['id']}: ${p['amount']} on {p['penalty_date']}{recipient_note}")
                    if len(user_penalties["unpaid"]) > 3:
                        self.log(f"    ... and {len(user_penalties['unpaid']) - 3} more")
                
                if user_penalties["processing"]:
                    total_processing = sum(float(p["amount"]) for p in user_penalties["processing"])
                    self.log(f"  ⏳ Processing: {len(user_penalties['processing'])} penalties, ${total_processing:.2f}")
                    for p in user_penalties["processing"][:2]:  # Show first 2
                        self.log(f"    - {p['id']}: ${p['amount']} (PaymentIntent: {p.get('payment_intent_id', 'N/A')})")
                
                if user_penalties["paid"]:
                    total_paid = sum(float(p["amount"]) for p in user_penalties["paid"])
                    paid_with_transfers = [p for p in user_penalties["paid"] if p.get("transfer_id")]
                    paid_transfer_total = sum(float(p["amount"]) for p in paid_with_transfers) * 0.85
                    
                    self.log(f"  ✅ Paid: {len(user_penalties['paid'])} penalties, ${total_paid:.2f}")
                    if paid_with_transfers:
                        self.log(f"     📤 With transfers: {len(paid_with_transfers)} penalties (${paid_transfer_total:.2f} transferred at 85%)")
            
            self.log("\n✅ Penalty status check completed!")
            
        except Exception as e:
            self.log(f"❌ Error checking penalty status: {e}", "ERROR")
            raise

    async def create_test_penalties(self, user_id: str, count: int = 3, amount: float = 5.0, with_recipient: bool = True):
        """
        Create test penalties for a user
        
        Args:
            user_id: User ID to create penalties for
            count: Number of penalties to create
            amount: Amount per penalty
            with_recipient: Whether to include a recipient_id (for testing payouts)
        """
        self.log(f"🧪 Creating {count} test penalties for user {user_id} (${amount} each, with_recipient={with_recipient})")
        
        try:
            # Get a habit for this user
            habits = self.supabase.table("habits").select("*").eq("user_id", user_id).eq("is_active", True).limit(1).execute()
            
            if habits.data:
                habit = habits.data[0]
                habit_id = habit["id"]
                recipient_id = habit.get("recipient_id") if with_recipient else None
                self.log(f"Using existing habit: {habit_id}, recipient: {recipient_id or 'None'}")
            else:
                self.log(f"❌ No active habits found for user {user_id}. Please create a habit first.")
                return
            
            created_penalties = []
            for i in range(count):
                penalty_date = (datetime.now().date() - timedelta(days=i+1)).isoformat()
                
                penalty_data = {
                    "user_id": user_id,
                    "recipient_id": recipient_id,
                    "amount": amount,
                    "penalty_date": penalty_date,
                    "is_paid": False
                }
                
                result = self.supabase.table("penalties").insert(penalty_data).execute()
                if result.data:
                    created_penalties.append(result.data[0])
                    self.log(f"  ✅ Created penalty {i+1}: ID {result.data[0]['id']}, ${amount}, {penalty_date}")
            
            self.log(f"✅ Created {len(created_penalties)} test penalties")
            return created_penalties
            
        except Exception as e:
            self.log(f"❌ Error creating test penalties: {e}", "ERROR")
            raise


async def main():
    print("🤖 Scheduler Simulation - NEW Improved Payment System")
    print("=" * 60)
    print("🆕 NEW: $5 total minimum for charges + $5.00 minimum for transfers!")
    print("🔄 OLD: $10 per recipient + 15% destination charges")
    print("=" * 60)
    
    while True:
        print("\nSelect simulation mode:")
        print("📅 NORMAL TIMING (respects timezone and hour requirements):")
        print("1. 📊 Show user summary")
        print("2. 🔄 Daily penalty check")
        print("3. 💰 Weekly penalty aggregation (NEW: $5 total + 15% fee)")
        print("4. 📅 Weekly habit penalties")
        print("5. 🚀 Run all simulations")
        print("\n🧪 BYPASS TIMING (process all users immediately):")
        print("6. 🧪 Daily penalty check (BYPASS)")
        print("7. 🧪 Weekly penalty aggregation (BYPASS)")
        print("8. 🧪 Weekly habit penalties (BYPASS)")
        print("9. 🧪 Run all simulations (BYPASS)")
        print("\n💰 RECIPIENT PAYOUT TESTING:")
        print("12. 📋 Check penalty status")
        print("13. 🧪 Test recipient payouts ($5.00 min)")
        print("14. 🧪 Create test penalties")
        print("15. 🧪 Simulate payment success + payouts")
        print("\n⚙️ ADVANCED:")
        print("10. ⚙️ Run with actual charging + NEW separate transfers (REAL MONEY!)")
        print("11. ❌ Exit")
        
        choice = input("\nEnter your choice (1-15): ").strip()
        
        if choice == "1":
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            await simulator.show_user_summary()
            
        elif choice == "2":
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            await simulator.simulate_daily_penalty_check()
            
        elif choice == "3":
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            await simulator.simulate_weekly_penalty_aggregation()
            
        elif choice == "4":
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            await simulator.simulate_weekly_habit_penalties()
            
        elif choice == "5":
            print("\n🚀 Running all simulations (normal timing)...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            
            print("\n" + "="*60)
            await simulator.show_user_summary()
            
            print("\n" + "="*60)
            await simulator.simulate_daily_penalty_check()
            
            print("\n" + "="*60)
            await simulator.simulate_weekly_penalty_aggregation()
            
            print("\n" + "="*60)
            await simulator.simulate_weekly_habit_penalties()
            
        elif choice == "6":
            print("\n🧪 Running daily penalty check with TIMING BYPASS...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=True)
            await simulator.simulate_daily_penalty_check()
            
        elif choice == "7":
            print("\n🧪 Running weekly penalty aggregation with TIMING BYPASS...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=True)
            await simulator.simulate_weekly_penalty_aggregation()
            
        elif choice == "8":
            print("\n🧪 Running weekly habit penalties with TIMING BYPASS...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=True)
            await simulator.simulate_weekly_habit_penalties()
            
        elif choice == "9":
            print("\n🧪 Running all simulations with TIMING BYPASS...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=True)
            
            print("\n" + "="*60)
            await simulator.show_user_summary()
            
            print("\n" + "="*60)
            await simulator.simulate_daily_penalty_check()
            
            print("\n" + "="*60)
            await simulator.simulate_weekly_penalty_aggregation()
            
            print("\n" + "="*60)
            await simulator.simulate_weekly_habit_penalties()
            
        elif choice == "10":
            confirm = input("⚠️ This will create REAL charges! Type 'CONFIRM' to proceed: ")
            if confirm == "CONFIRM":
                use_bypass = input("Bypass timing checks? (y/n): ").lower() == 'y'
                simulator = SchedulerSimulator(verbose=True, actually_charge=True, bypass_timing=use_bypass)
                
                print("\n💳 Starting real money penalty aggregation with automatic recipient payouts...")
                processed_penalty_ids = await simulator.simulate_weekly_penalty_aggregation()
                
                if processed_penalty_ids:
                    print(f"\n✅ Successfully processed {len(processed_penalty_ids)} penalties!")
                    print("🎯 With the NEW system: Platform charged once, then transfers sent to recipients.")
                    print("💰 No additional transfer fees - Recipients get 85% of penalty amounts!")
                    print("🏦 Platform retains 15% fee for processing and operations.")
                    
                    # Show final status for verification
                    print(f"\n📊 Checking final penalty status...")
                    penalties_check = simulator.supabase.table("penalties") \
                        .select("*") \
                        .in_("id", processed_penalty_ids) \
                        .execute()
                    
                    total_amount = sum(float(p["amount"]) for p in penalties_check.data)
                    recipient_penalties = [p for p in penalties_check.data if p.get("recipient_id")]
                    platform_penalties = [p for p in penalties_check.data if not p.get("recipient_id")]
                    
                    if recipient_penalties:
                        recipient_amount = sum(float(p["amount"]) for p in recipient_penalties)
                        print(f"💸 Recipient penalties: {len(recipient_penalties)} penalties, ${recipient_amount:.2f}")
                        print(f"   📤 Recipients received: ${recipient_amount * 0.85:.2f} (via separate transfers)")
                        print(f"   🏦 Platform retained: ${recipient_amount * 0.15:.2f} (15% platform fee)")
                    
                    if platform_penalties:
                        platform_amount = sum(float(p["amount"]) for p in platform_penalties)
                        print(f"💰 Platform penalties: {len(platform_penalties)} penalties, ${platform_amount:.2f}")
                        print(f"   🏦 Platform received: ${platform_amount:.2f} (no recipients)")
                    
                    print(f"\n🎉 Total processed: ${total_amount:.2f} across {len(processed_penalty_ids)} penalties")
                    print("✨ NEW system efficiency: Reduced fees + faster recipient payouts!")
                else:
                    print("📭 No penalties were successfully processed")
                    
            else:
                print("❌ Cancelled")
                
        elif choice == "11":
            print("👋 Goodbye!")
            break
            
        elif choice == "12":
            print("\n📋 Checking penalty status...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            user_filter = input("Enter user ID to filter (or press Enter for all users): ").strip()
            await simulator.check_penalty_status(user_filter if user_filter else None)
            
        elif choice == "13":
            print("\n🧪 Testing recipient payouts...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            user_filter = input("Enter user ID to filter (or press Enter for all users): ").strip()
            penalty_ids_input = input("Enter comma-separated penalty IDs (or press Enter to auto-detect): ").strip()
            penalty_ids = [pid.strip() for pid in penalty_ids_input.split(",")] if penalty_ids_input else None
            await simulator.test_recipient_payouts(penalty_ids, user_filter if user_filter else None)
            
        elif choice == "14":
            print("\n🧪 Creating test penalties...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            user_id = input("Enter user ID: ").strip()
            if not user_id:
                print("❌ User ID is required")
                continue
            count = int(input("Enter number of penalties to create (default 3): ").strip() or "3")
            amount = float(input("Enter penalty amount (default $5.00): ").strip() or "5.0")
            with_recipient = input("Include recipient for payout testing? (y/n, default y): ").strip().lower() != 'n'
            await simulator.create_test_penalties(user_id, count, amount, with_recipient)
            
        elif choice == "15":
            print("\n🧪 Simulating payment success and recipient payouts...")
            simulator = SchedulerSimulator(verbose=True, actually_charge=False, bypass_timing=False)
            penalty_ids_input = input("Enter comma-separated penalty IDs: ").strip()
            if not penalty_ids_input:
                print("❌ Penalty IDs are required")
                continue
            penalty_ids = [pid.strip() for pid in penalty_ids_input.split(",")]
            await simulator.simulate_payment_success(penalty_ids)
            
        else:
            print("❌ Invalid choice. Please select 1-15.")
        
        input("\nPress Enter to continue...")


if __name__ == "__main__":
    asyncio.run(main()) 