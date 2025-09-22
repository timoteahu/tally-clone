import stripe
from datetime import datetime, timedelta
from config.database import get_supabase_client
from config.stripe import create_payment_intent
from supabase import Client
import os
from dotenv import load_dotenv
import logging

# Load environment variables from backend root directory
current_dir = os.path.dirname(os.path.abspath(__file__))
app_dir = os.path.dirname(current_dir)
backend_dir = os.path.dirname(app_dir)
env_path = os.path.join(backend_dir, '.env')
load_dotenv(env_path)
stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

logger = logging.getLogger(__name__)

async def process_auto_payments(supabase: Client):
    """
    Process automatic payments for unpaid penalties
    """
    # Get all unpaid penalties that are eligible for auto-pay
    penalties = supabase.table("penalties")\
        .select("*, habits!inner(auto_pay_enabled, is_active), users!inner(default_payment_method_id)")\
        .eq("is_paid", False)\
        .eq("habits.auto_pay_enabled", True)\
        .eq("habits.is_active", True)\
        .not_.is_("users.default_payment_method_id", "null")\
        .execute()

    for penalty in penalties.data:
        try:
            # Get user's default payment method
            payment_method = penalty["users"]["default_payment_method_id"]
            
            # Create payment intent
            payment_intent = stripe.PaymentIntent.create(
                amount=int(penalty["amount"] * 100),  # Convert to cents
                currency="usd",
                customer=penalty["users"]["stripe_customer_id"],
                payment_method=payment_method,
                off_session=True,
                confirm=True,
                metadata={
                    "penalty_id": penalty["id"],
                    "user_id": penalty["user_id"]
                }
            )

            # Update penalty with payment intent ID
            supabase.table("penalties")\
                .update({
                    "payment_intent_id": payment_intent.id,
                    "payment_method_id": payment_method,
                    "payment_status": "processing"
                })\
                .eq("id", penalty["id"])\
                .execute()

        except stripe.error.CardError as e:
            # Handle card errors
            error_code = e.code
            if error_code == "authentication_required":
                # Payment requires authentication
                supabase.table("penalties")\
                    .update({
                        "payment_status": "requires_action",
                        "retry_count": penalty.get("retry_count", 0) + 1,
                        "last_retry_date": datetime.utcnow().isoformat()
                    })\
                    .eq("id", penalty["id"])\
                    .execute()
            else:
                # Other card errors
                supabase.table("penalties")\
                    .update({
                        "payment_status": "failed",
                        "retry_count": penalty.get("retry_count", 0) + 1,
                        "last_retry_date": datetime.utcnow().isoformat()
                    })\
                    .eq("id", penalty["id"])\
                    .execute()

        except Exception as e:
            # Handle other errors
            supabase.table("penalties")\
                .update({
                    "payment_status": "failed",
                    "retry_count": penalty.get("retry_count", 0) + 1,
                    "last_retry_date": datetime.utcnow().isoformat()
                })\
                .eq("id", penalty["id"])\
                .execute()

async def retry_failed_payments(supabase: Client):
    """
    Retry failed payments that haven't exceeded max retries
    """
    max_retries = 3
    retry_interval_days = 1

    # Get failed payments that haven't exceeded max retries
    failed_payments = supabase.table("penalties")\
        .select("*, habits!inner(auto_pay_enabled, is_active), users!inner(default_payment_method_id)")\
        .eq("payment_status", "failed")\
        .lt("retry_count", max_retries)\
        .eq("habits.auto_pay_enabled", True)\
        .eq("habits.is_active", True)\
        .not_.is_("users.default_payment_method_id", "null")\
        .execute()

    for payment in failed_payments.data:
        last_retry = datetime.fromisoformat(payment["last_retry_date"])
        if datetime.utcnow() - last_retry >= timedelta(days=retry_interval_days):
            await process_auto_payments(supabase) 