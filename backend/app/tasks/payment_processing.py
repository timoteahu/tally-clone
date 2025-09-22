from datetime import datetime, timedelta, date
import pytz
import logging
import stripe
import os
from dotenv import load_dotenv
from supabase._async.client import AsyncClient
from config.database import get_async_supabase_client
from utils.memory_optimization import memory_optimized, cleanup_memory
from utils.memory_monitoring import memory_profile
from .scheduler_utils import get_user_timezone_async

# Load environment variables and set up Stripe
# Get the correct path to .env file (in backend root, not app)
current_dir = os.path.dirname(os.path.abspath(__file__))
app_dir = os.path.dirname(current_dir)
backend_dir = os.path.dirname(app_dir)
env_path = os.path.join(backend_dir, '.env')
load_dotenv(env_path)
stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

# Set up logging
logger = logging.getLogger(__name__)

@memory_optimized(cleanup_args=False)
@memory_profile("update_processing_payment_statuses")
async def update_processing_payment_statuses():
    """
    Check PaymentIntent statuses for penalties marked as 'processing' and update them accordingly.
    OPTIMIZED: Uses async client and batch operations for better performance.
    """
    supabase = await get_async_supabase_client()
    start_time = datetime.now(pytz.UTC)
    
    try:
        # OPTIMIZATION: Use selective columns instead of SELECT *
        processing_penalties = await supabase.table("penalties").select(
            "id, payment_intent_id, payment_status, habit_id, recipient_id, amount"
        ).eq("payment_status", "processing").not_.is_("payment_intent_id", "null").execute()
        
        if not processing_penalties.data:
            logger.info("No penalties with processing status found")
            return
        
        query_time = datetime.now(pytz.UTC)
        logger.info(f"Found {len(processing_penalties.data)} processing penalties (query took {(query_time - start_time).total_seconds():.2f}s)")
        updated_count = 0
        
        # OPTIMIZATION: Group penalties by payment intent to avoid duplicate API calls
        by_payment_intent = {}
        for penalty in processing_penalties.data:
            payment_intent_id = penalty.get("payment_intent_id")
            if payment_intent_id:
                if payment_intent_id not in by_payment_intent:
                    by_payment_intent[payment_intent_id] = []
                by_payment_intent[payment_intent_id].append(penalty)
        
        # OPTIMIZATION: Process payment intents in smaller batches
        payment_intent_ids = list(by_payment_intent.keys())
        batch_size = 10
        
        for i in range(0, len(payment_intent_ids), batch_size):
            batch_payment_intents = payment_intent_ids[i:i + batch_size]
            
            for payment_intent_id in batch_payment_intents:
                penalties = by_payment_intent[payment_intent_id]
                
                try:
                    # Retrieve PaymentIntent from Stripe
                    stripe_start = datetime.now(pytz.UTC)
                    payment_intent = stripe.PaymentIntent.retrieve(payment_intent_id)
                    stripe_time = (datetime.now(pytz.UTC) - stripe_start).total_seconds()
                    
                    old_status = penalties[0].get("payment_status", "unknown")
                    payment_type = payment_intent.metadata.get("type", "unknown")
                    
                    # OPTIMIZATION: Prepare batch updates
                    penalty_ids = [p["id"] for p in penalties]
                    
                    if payment_intent.status == "succeeded":
                        # OPTIMIZATION: Batch update penalties as succeeded
                        await supabase.table("penalties").update({
                            "payment_status": "succeeded",
                            "is_paid": True
                        }).in_("id", penalty_ids).execute()
                        
                        updated_count += len(penalties)
                        logger.info(f"✅ Marked {len(penalties)} penalties as succeeded")
                        
                        # NEW: If this is the new payment type, trigger recipient transfers
                        if payment_type == "weekly_aggregate_with_separate_transfers":
                            logger.info(f"🎯 Triggering recipient transfers for payment {payment_intent_id}")
                            await process_recipient_transfers(supabase, penalties)
                        elif payment_type == "weekly_aggregate_with_recipient":
                            logger.info(f"💰 Destination charge completed - recipients paid automatically")
                        
                    elif payment_intent.status == "canceled":
                        # OPTIMIZATION: Batch update canceled penalties
                        await supabase.table("penalties").update({
                            "is_paid": False,
                            "payment_status": "canceled",
                            "payment_intent_id": None  # Clear to allow retry
                        }).in_("id", penalty_ids).execute()
                        
                        updated_count += len(penalties)
                        logger.warning(f"❌ {len(penalties)} penalties: {old_status} → canceled")
                    
                    elif payment_intent.status == "payment_failed":
                        # OPTIMIZATION: Batch update failed penalties
                        await supabase.table("penalties").update({
                            "is_paid": False,
                            "payment_status": "failed",
                            "payment_intent_id": None  # Clear to allow retry
                        }).in_("id", penalty_ids).execute()
                        
                        updated_count += len(penalties)
                        logger.warning(f"❌ {len(penalties)} penalties: {old_status} → failed")
                    
                    elif payment_intent.status == "requires_action":
                        # OPTIMIZATION: Batch update requiring action
                        await supabase.table("penalties").update({
                            "payment_status": "requires_action"
                        }).in_("id", penalty_ids).execute()
                        
                        updated_count += len(penalties)
                        logger.warning(f"⚠️ {len(penalties)} penalties: {old_status} → requires_action")
                    
                    else:
                        # Still processing or other status
                        logger.info(f"⏳ {len(penalties)} penalties: still {payment_intent.status}")
                
                except stripe.error.StripeError as e:
                    logger.error(f"Stripe error for payment intent {payment_intent_id}: {e}")
                    continue
                except Exception as e:
                    logger.error(f"Error processing payment intent {payment_intent_id}: {e}")
                    continue
        
        end_time = datetime.now(pytz.UTC)
        total_time = (end_time - start_time).total_seconds()
        logger.info(f"Payment status update completed: {updated_count} penalties updated in {total_time:.2f}s")
        
        # Cleanup memory
        cleanup_memory(processing_penalties, by_payment_intent)
    
    except Exception as e:
        logger.error(f"Error in update_processing_payment_statuses: {e}")
        raise

@memory_optimized(cleanup_args=False)
@memory_profile("process_recipient_transfers")
async def process_recipient_transfers(supabase: AsyncClient, penalties: list):
    """
    OPTIMIZED: Process transfers to recipients after successful platform charge
    Uses batch operations and selective queries for better performance.
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
            logger.info("📭 No penalties with recipients found for transfers")
            return
        
        logger.info(f"💸 Processing transfers to {len(recipient_groups)} recipients")
        
        # OPTIMIZATION: Pre-fetch all recipient data in a single batch query to avoid N+1
        recipient_ids = list(recipient_groups.keys())
        recipients_result = await supabase.table("users").select(
            "id, name, stripe_connect_account_id"  # Only fetch needed columns
        ).in_("id", recipient_ids).execute()
        
        # Create a map of recipient_id -> recipient data for quick lookup
        recipients_map = {r["id"]: r for r in recipients_result.data} if recipients_result.data else {}
        
        # OPTIMIZATION: Prepare batch updates for transfer IDs
        batch_penalty_updates = []
        
        for recipient_id, recipient_penalties in recipient_groups.items():
            try:
                # Get recipient data from pre-fetched map
                recipient_data = recipients_map.get(recipient_id)
                
                if not recipient_data or not recipient_data.get("stripe_connect_account_id"):
                    logger.warning(f"⚠️ Recipient {recipient_id} missing Connect account, skipping transfer")
                    continue
                
                recipient_connect_account = recipient_data["stripe_connect_account_id"]
                
                # Calculate amounts dynamically from existing penalty amounts
                recipient_penalty_amount = sum(float(p["amount"]) for p in recipient_penalties)
                recipient_penalty_ids = [str(p["id"]) for p in recipient_penalties]
                
                # Platform fee rate (15% - can be made configurable later)
                platform_fee_rate = 0.15  # 15% platform fee
                platform_fee = recipient_penalty_amount * platform_fee_rate
                transfer_amount = recipient_penalty_amount * (1 - platform_fee_rate)  # 85% to recipient
                
                # Skip if transfer amount is less than $5.00 minimum
                if transfer_amount < 5.00:
                    logger.info(f"⏭️ Skipping recipient {recipient_data.get('name', 'Unknown')}: transfer amount ${transfer_amount:.2f} < $5.00 minimum")
                    continue
                
                logger.info(f"🎯 Creating transfer for {recipient_data.get('name', 'Unknown')}")
                logger.info(f"   Transfer amount: ${transfer_amount:.2f}")
                
                # Create transfer to recipient
                transfer = stripe.Transfer.create(
                    amount=int(round(transfer_amount * 100)),  # Transfer amount after platform fee
                    currency="usd",
                    destination=recipient_connect_account,
                    metadata={
                        "recipient_id": recipient_id,
                        "penalty_count": str(len(recipient_penalty_ids)),
                        "original_amount": str(recipient_penalty_amount),
                        "platform_fee": str(platform_fee),
                        "platform_fee_rate": str(platform_fee_rate),
                        "type": "recipient_penalty_payout"
                    }
                )
                
                # OPTIMIZATION: Prepare batch update instead of individual updates
                for penalty_id in recipient_penalty_ids:
                    batch_penalty_updates.append({
                        "id": penalty_id,
                        "transfer_id": transfer.id,
                        "platform_fee_rate": platform_fee_rate
                    })
                
                logger.info(f"✅ Transfer created: {transfer.id}")
                
            except stripe.error.InvalidRequestError as e:
                if "Insufficient funds" in str(e):
                    logger.warning(f"⚠️ Insufficient platform balance for recipient {recipient_id}")
                    continue
                else:
                    logger.error(f"❌ Stripe error for recipient {recipient_id}: {e}")
                    continue
            except Exception as e:
                logger.error(f"❌ Error creating transfer for recipient {recipient_id}: {e}")
                continue
        
        # OPTIMIZATION: Execute batch updates for transfer IDs
        if batch_penalty_updates:
            batch_size = 25  # Process in smaller batches
            for i in range(0, len(batch_penalty_updates), batch_size):
                batch = batch_penalty_updates[i:i + batch_size]
                
                # Update penalties with transfer info in batch
                for update_data in batch:
                    await supabase.table("penalties").update({
                        "transfer_id": update_data["transfer_id"],
                        "platform_fee_rate": update_data["platform_fee_rate"]
                    }).eq("id", update_data["id"]).execute()
        
        logger.info(f"🎉 Recipient transfers completed!")
        cleanup_memory(recipient_groups, recipients_map, batch_penalty_updates)
        
    except Exception as e:
        logger.error(f"❌ Error in process_recipient_transfers: {e}")
        raise

@memory_optimized(cleanup_args=False)
@memory_profile("process_all_eligible_transfers")
async def process_all_eligible_transfers():
    """
    OPTIMIZED: Find and process all eligible penalties for transfers
    Uses batch operations and selective queries for better performance.
    """
    supabase = await get_async_supabase_client()
    
    try:
        logger.info("🔍 Finding all eligible penalties for transfers...")
        
        # OPTIMIZATION: Use selective columns for eligible penalties
        eligible_penalties = await supabase.table("penalties").select(
            "id, habit_id, recipient_id, amount, payment_status"
        ).in_("payment_status", ["succeeded", "completed"]).eq(
            "is_paid", True
        ).is_("transfer_id", "null").not_.is_("recipient_id", "null").execute()
        
        if not eligible_penalties.data:
            logger.info("📭 No eligible penalties found for transfers")
            return
        
        logger.info(f"💰 Found {len(eligible_penalties.data)} eligible penalties for transfers")
        
        # Group by recipient to show aggregation
        recipient_groups = {}
        for penalty in eligible_penalties.data:
            recipient_id = penalty.get("recipient_id")
            if recipient_id:
                if recipient_id not in recipient_groups:
                    recipient_groups[recipient_id] = []
                recipient_groups[recipient_id].append(penalty)
        
        logger.info(f"👥 Processing transfers for {len(recipient_groups)} recipients")
        
        # Process transfers using the existing function
        await process_recipient_transfers(supabase, eligible_penalties.data)
        cleanup_memory(eligible_penalties, recipient_groups)
        
    except Exception as e:
        logger.error(f"❌ Error in process_all_eligible_transfers: {e}")
        raise

@memory_optimized(cleanup_args=False)
@memory_profile("check_and_charge_unpaid_penalties")
async def check_and_charge_unpaid_penalties():
    """
    OPTIMIZED: Check for users with unpaid penalties >= $5 and charge them immediately.
    Uses batch operations and async client for better performance.
    """
    supabase = await get_async_supabase_client()
    utc_now = datetime.now(pytz.UTC)
    
    logger.info(f"🔄 Starting unpaid penalty check at {utc_now} UTC")
    
    try:
        # OPTIMIZATION: Get unique user IDs directly with selective columns
        users_with_penalties = await supabase.table("penalties").select(
            "user_id"
        ).eq("is_paid", False).execute()
        
        if not users_with_penalties.data:
            logger.info("📭 No users with unpaid penalties found")
            return
        
        # Get unique user IDs
        user_ids = list(set([p["user_id"] for p in users_with_penalties.data]))
        logger.info(f"👥 Found {len(user_ids)} users with unpaid penalties")
        
        charged_users = 0
        total_charged_amount = 0
        
        # OPTIMIZATION: Process users in batches
        batch_size = 10
        for i in range(0, len(user_ids), batch_size):
            batch_user_ids = user_ids[i:i + batch_size]
            
            for user_id in batch_user_ids:
                try:
                    # OPTIMIZATION: Get unpaid penalties with selective columns
                    unpaid_penalties = await supabase.table("penalties").select(
                        "id, amount, habit_id, recipient_id"
                    ).eq("user_id", user_id).eq("is_paid", False).execute()
                    
                    if not unpaid_penalties.data:
                        continue
                    
                    # Calculate total amount across ALL penalties
                    total_amount = sum(float(p["amount"]) for p in unpaid_penalties.data)
                    
                    # Only charge if total amount is $5 or more
                    if total_amount < 5.0:
                        logger.info(f"User {user_id}: Total penalties ${total_amount:.2f} < $5.00 minimum")
                        continue
                    
                    if total_amount <= 0:
                        continue
                    
                    # OPTIMIZATION: Get user's Stripe info with selective columns
                    user = await supabase.table("users").select(
                        "id, stripe_customer_id, default_payment_method_id"
                    ).eq("id", user_id).single().execute()
                    
                    if not user.data or not user.data.get("stripe_customer_id") or not user.data.get("default_payment_method_id"):
                        logger.warning(f"User {user_id} has unpaid penalties but no payment method configured")
                        continue
                    
                    penalty_ids = [str(p["id"]) for p in unpaid_penalties.data]
                    
                    logger.info(f"💳 Creating charge for user {user_id}: ${total_amount:.2f} ({len(penalty_ids)} penalties)")
                    
                    # Create single charge to platform
                    payment_intent = stripe.PaymentIntent.create(
                        amount=int(total_amount * 100),  # Convert to cents
                        currency="usd",
                        customer=user.data["stripe_customer_id"],
                        payment_method=user.data["default_payment_method_id"],
                        off_session=True,
                        confirm=True,
                        metadata={
                            "user_id": user_id,
                            "type": "hourly_aggregate_with_separate_transfers",
                            "penalty_count": str(len(penalty_ids)),
                            "total_amount": str(total_amount)
                        }
                    )
                    
                    # OPTIMIZATION: Batch update penalties with payment intent ID
                    await supabase.table("penalties").update({
                        "payment_intent_id": payment_intent.id, 
                        "payment_status": "processing"
                    }).in_("id", penalty_ids).execute()
                    
                    logger.info(f"✅ Created platform charge: {payment_intent.id}")
                    
                    # Check payment status immediately
                    payment_status = payment_intent.status
                    logger.info(f"📊 Payment status: {payment_status}")
                    
                    if payment_status == "succeeded":
                        # OPTIMIZATION: Batch update penalties as succeeded
                        await supabase.table("penalties").update({
                            "is_paid": True,
                            "payment_status": "succeeded"
                        }).in_("id", penalty_ids).execute()
                        
                        logger.info(f"✅ Penalties marked as succeeded")
                        
                        # Process transfers to recipients separately
                        await process_recipient_transfers(supabase, unpaid_penalties.data)
                        
                        # Update recipient analytics
                        try:
                            from utils.recipient_analytics import update_analytics_on_penalty_paid
                            
                            for penalty in unpaid_penalties.data:
                                recipient_id = penalty.get('recipient_id')
                                if recipient_id and recipient_id != 'None':
                                    try:
                                        await update_analytics_on_penalty_paid(
                                            supabase=supabase,
                                            habit_id=penalty["habit_id"],
                                            recipient_id=recipient_id,
                                            penalty_amount=float(penalty["amount"])
                                        )
                                    except Exception as e:
                                        logger.error(f"Error updating analytics for penalty {penalty['id']}: {e}")
                            
                            logger.info(f"Updated analytics for penalty payments")
                        except Exception as analytics_error:
                            logger.error(f"Error importing recipient analytics: {analytics_error}")
                    
                    else:
                        logger.info(f"⚠️ Payment not immediately succeeded, status: {payment_status}")
                    
                    charged_users += 1
                    total_charged_amount += total_amount
                    cleanup_memory(unpaid_penalties, user)
                    
                except Exception as e:
                    logger.error(f"Error processing penalties for user {user_id}: {e}")
                    continue
        
        logger.info(f"📊 Hourly penalty charging summary:")
        logger.info(f"   • Users with penalties: {len(user_ids)}")
        logger.info(f"   • Users charged: {charged_users}")
        logger.info(f"   • Total amount charged: ${total_charged_amount:.2f}")
        
        cleanup_memory(users_with_penalties, user_ids)
        
    except Exception as e:
        logger.error(f"Error in check_and_charge_unpaid_penalties: {e}")
        raise 