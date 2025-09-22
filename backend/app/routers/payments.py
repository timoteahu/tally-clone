from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.encoders import jsonable_encoder
from config.database import get_async_supabase_client
from config.stripe import create_payment_intent, create_customer, attach_payment_method, STRIPE_WEBHOOK_SECRET
from supabase._async.client import AsyncClient
from routers.auth import get_current_user
import stripe
import logging
from typing import Optional, List
from pydantic import BaseModel
from models.schemas import User
from datetime import datetime
from utils.memory_optimization import disable_print

print = disable_print()

router = APIRouter()
logger = logging.getLogger(__name__)

class PaymentIntentCreate(BaseModel):
    amount: int
    currency: str = "usd"
    penalty_id: str
    customer_id: Optional[str] = None

class PaymentMethodAttach(BaseModel):
    payment_method_id: str
    customer_id: str

class HabitPaymentIntentCreate(BaseModel):
    habit_ids: List[str]

class ConnectAccountLinkCreate(BaseModel):
    account_id: str
    refresh_url: str
    return_url: str

@router.post("/create-payment-intent")
async def create_payment_intent_endpoint(
    payment_data: PaymentIntentCreate, 
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    try:
        
        # Get penalty details
        penalty = await supabase.table("penalties").select("*").eq("id", payment_data.penalty_id).execute()
        
        if not penalty.data:
            logger.error(f"Penalty not found for ID: {payment_data.penalty_id}")
            raise HTTPException(status_code=404, detail="Penalty not found")

        # Create payment intent
        payment_intent = create_payment_intent(
            amount=payment_data.amount,
            currency=payment_data.currency,
            metadata={
                "penalty_id": payment_data.penalty_id,
                "customer_id": payment_data.customer_id
            }
        )

        return {"clientSecret": payment_intent.client_secret}
    except Exception as e:
        logger.error(f"Error creating payment intent: {str(e)}")
        logger.error(f"Error type: {type(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/create-habit-payment-intent")
async def create_habit_payment_intent(
    request: Request,
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    try:
        # Get the request body
        body = await request.json()
        
        # Get the habit IDs from the request
        habit_ids = body.get("habit_ids", [])
        if not habit_ids:
            raise HTTPException(status_code=400, detail="No habit IDs provided")
        
        # Get the habits from the database
        habits = await supabase.table("habits").select("*").in_("id", habit_ids).eq("is_active", True).execute()
        if not habits.data:
            raise HTTPException(status_code=404, detail="Habits not found")
        
        # Calculate total amount (sum of all penalties)
        total_amount = sum(habit["penalty_amount"] for habit in habits.data)
        
        # Create a payment intent
        intent = stripe.PaymentIntent.create(
            amount=int(total_amount * 100),  # Convert to cents
            currency="usd",
            automatic_payment_methods={"enabled": True},
            metadata={
                "user_id": str(current_user.id),
                "habit_ids": ",".join(str(habit["id"]) for habit in habits.data)
            }
        )
        
        # Create a payment record for each habit
        for habit in habits.data:
            payment_data = {
                "user_id": str(current_user.id),
                "habit_id": habit["id"],
                "amount": habit["penalty_amount"],
                "status": "pending",
                "stripe_payment_intent_id": intent.id
            }
            await supabase.table("payments").insert(payment_data).execute()
        
        return {"clientSecret": intent.client_secret}
    except Exception as e:
        logger.error(f"Error creating payment intent: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/create-customer")
async def create_customer_endpoint(email: str, name: Optional[str] = None):
    try:
        customer = create_customer(email=email, name=name)
        return {"customer_id": customer.id}
    except Exception as e:
        logger.error(f"Error creating customer: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/attach-payment-method")
async def attach_payment_method_endpoint(payment_data: PaymentMethodAttach):
    try:
        payment_method = attach_payment_method(
            customer_id=payment_data.customer_id,
            payment_method_id=payment_data.payment_method_id
        )
        return {"success": True, "payment_method_id": payment_method.id}
    except Exception as e:
        logger.error(f"Error attaching payment method: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/connect/create-account")
async def create_connect_account(
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    try:
        logger.info(f"🔗 Creating Connect account for user: {current_user.id}")
        
        # Fetch user info from DB
        user_row = await supabase.table("users").select("*").eq("id", current_user.id).single().execute()
        if not user_row.data:
            raise HTTPException(status_code=404, detail="User not found")
        user = user_row.data

        # If user already has a Stripe Connect account and status is True, do nothing
        if user.get("stripe_connect_account_id") and user.get("stripe_connect_status"):
            logger.info(f"🔗 User already has Connect account: {user['stripe_connect_account_id']}")
            return {"account_id": user["stripe_connect_account_id"]}

        logger.info(f"🔗 Creating new Stripe Connect account for user: {user['name']}")
        
        # Create a new Stripe Connect account (user will enter payout/bank info during onboarding)
        account = stripe.Account.create(
            type="express",
            business_profile={"name": user["name"]},
            business_type="individual",
            country="US",
            capabilities={
                "card_payments": {"requested": True},
                "transfers": {"requested": True},
            },
            metadata={"user_id": str(current_user.id)}
        )
        account_id = account.id
        logger.info(f"✅ Stripe Connect account created: {account_id}")
        
        await supabase.table("users").update({
            "stripe_connect_account_id": account_id,
            "stripe_connect_status": True  # Set to True when account is created
        }).eq("id", current_user.id).execute()
        
        logger.info(f"✅ Database updated with account_id: {account_id}")

        return {"account_id": account_id}
    except Exception as e:
        logger.error(f"Error creating Connect account: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/connect/create-account-link")
async def create_connect_account_link(
    link_data: ConnectAccountLinkCreate,
    current_user: User = Depends(get_current_user)
):
    try:
        # Debug: Log the account_id being used
        logger.info(f"🔗 Creating account link for account_id: {link_data.account_id}")
        logger.info(f"🔗 User ID: {current_user.id}")
        
        # First, verify the account exists in Stripe
        try:
            account = stripe.Account.retrieve(link_data.account_id)
            logger.info(f"🔗 Account found in Stripe: {account.id}, status: {account.status}")
        except stripe.error.InvalidRequestError as e:
            logger.error(f"❌ Account {link_data.account_id} not found in Stripe: {str(e)}")
            raise HTTPException(status_code=400, detail=f"Account {link_data.account_id} not found in Stripe")
        
        # Create an account link for onboarding
        account_link = stripe.AccountLink.create(
            account=link_data.account_id,
            refresh_url=link_data.refresh_url,
            return_url=link_data.return_url,
            type="account_onboarding"
        )

        logger.info(f"✅ Account link created successfully: {account_link.url}")
        return {"url": account_link.url}
    except Exception as e:
        logger.error(f"Error creating account link: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/connect/account-status")
async def get_connect_account_status(
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    try:
        # Get the user's Stripe Connect account ID
        user = await supabase.table("users").select("stripe_connect_account_id").eq("id", current_user.id).single().execute()
        
        if not user.data or not user.data["stripe_connect_account_id"]:
            return {"status": "not_connected"}
        
        # Get the account status from Stripe
        account = stripe.Account.retrieve(user.data["stripe_connect_account_id"])
        
        # Determine actual status based on account state
        if account.details_submitted and account.charges_enabled and account.payouts_enabled:
            status = "connected"
        else:
            status = "pending"
        
        return {
            "status": status,
            "details_submitted": account.details_submitted,
            "charges_enabled": account.charges_enabled,
            "payouts_enabled": account.payouts_enabled
        }
    except Exception as e:
        logger.error(f"Error getting account status: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/webhook")
async def stripe_webhook(request: Request, supabase: AsyncClient = Depends(get_async_supabase_client)):
    # Enhanced debugging for webhook issues
    logger.debug(f"🔔 Webhook received - Method: {request.method}")
    logger.debug(f"🔔 Webhook URL: {request.url}")
    logger.debug(f"🔔 Webhook headers: {dict(request.headers)}")
    
    payload = await request.body()
    logger.debug(f"🔔 Webhook payload size: {len(payload)} bytes")
    
    sig_header = request.headers.get("stripe-signature")
    logger.debug(f"🔔 Stripe signature header: {sig_header}")

    if not sig_header:
        logger.error("❌ No Stripe signature header found")
        raise HTTPException(status_code=400, detail="No Stripe signature header")

    try:
        logger.debug(f"🔔 Using webhook secret: {STRIPE_WEBHOOK_SECRET[:20]}...")
        event = stripe.Webhook.construct_event(
            payload, sig_header, STRIPE_WEBHOOK_SECRET
        )
        logger.debug(f"✅ Webhook signature verified successfully")
        logger.debug(f"🔔 Event type: {event.type}, Event ID: {event.id}")
    except ValueError as e:
        logger.error(f"❌ Invalid payload: {str(e)}")
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError as e:
        logger.error(f"❌ Invalid signature: {str(e)}")
        logger.error(f"❌ Expected signature: {sig_header}")
        logger.error(f"❌ Webhook secret used: {STRIPE_WEBHOOK_SECRET[:20]}...")
        raise HTTPException(status_code=400, detail="Invalid signature")

    # Log the event for debugging
    logger.debug(f"🔔 Processing webhook event: {event.type}")

    if event.type == "payment_intent.succeeded":
        logger.debug("💰 Processing payment_intent.succeeded")
        payment_intent = event.data.object
        payment_intent_id = payment_intent.id
        
        # Query penalties by payment_intent_id instead of using metadata
        penalties_result = await supabase.table("penalties").select("*").eq("payment_intent_id", payment_intent_id).execute()
        penalties = penalties_result.data
        
        logger.debug(f"🔔 Found {len(penalties)} penalties for payment_intent: {payment_intent_id}")
        
        if penalties:
            # Get payment type from metadata to determine if this needs webhook processing
            payment_type = payment_intent.metadata.get("type", "unknown")
            
            # Only process if this is an old-style payment (new payments are handled by scheduler)
            if payment_type not in ["weekly_aggregate_with_separate_transfers", "weekly_aggregate_with_recipient"]:
                recipient_id = payment_intent.metadata.get("recipient_id")
                habit_id = payment_intent.metadata.get("habit_id")
                
                if recipient_id:
                    penalty_ids = [p["id"] for p in penalties]
                    total_amount = sum(float(p["amount"]) for p in penalties)
                    recipient = await supabase.table("users").select("*").eq("id", recipient_id).single().execute()
                    account_id = recipient.data.get("stripe_connect_account_id")
                    if account_id:
                        transfer = stripe.Transfer.create(
                            amount=int(total_amount * 100),
                            currency="usd",
                            destination=account_id,
                            transfer_group=f"habit_{habit_id}_week"
                        )
                        await supabase.table("penalties") \
                            .update({"is_paid": True, "transfer_id": transfer.id, "payment_status": "completed"}) \
                            .in_("id", penalty_ids).execute()
                        logger.debug(f"✅ Transfer created: {transfer.id} for ${total_amount}")
                    else:
                        logger.warning(f"⚠️ No Stripe Connect account found for recipient: {recipient_id}")
                else:
                    # No recipient, just mark as paid
                    penalty_ids = [p["id"] for p in penalties]
                    await supabase.table("penalties") \
                        .update({"is_paid": True, "payment_status": "completed"}) \
                        .in_("id", penalty_ids).execute()
                    logger.debug(f"✅ Marked penalties as paid: {penalty_ids}")
            else:
                logger.debug(f"ℹ️ New payment type {payment_type} - handled by scheduler, skipping webhook processing")
        else:
            logger.debug(f"ℹ️ No penalties found for payment_intent: {payment_intent_id}")

    elif event.type == "payment_intent.payment_failed":
        logger.debug("❌ Processing payment_intent.payment_failed")
        payment_intent = event.data.object
        payment_intent_id = payment_intent.id
        
        # Query penalties by payment_intent_id instead of using metadata
        penalties_result = await supabase.table("penalties").select("*").eq("payment_intent_id", payment_intent_id).execute()
        penalties = penalties_result.data
        
        if penalties:
            penalty_ids = [p["id"] for p in penalties]
            await supabase.table("penalties") \
                .update({"payment_status": "failed"}) \
                .in_("id", penalty_ids).execute()
            logger.debug(f"❌ Marked penalties as failed: {penalty_ids}")

    elif event.type == "payment_intent.canceled":
        logger.debug("🚫 Processing payment_intent.canceled")
        payment_intent = event.data.object
        payment_intent_id = payment_intent.id
        
        # Query penalties by payment_intent_id instead of using metadata
        penalties_result = await supabase.table("penalties").select("*").eq("payment_intent_id", payment_intent_id).execute()
        penalties = penalties_result.data
        
        if penalties:
            penalty_ids = [p["id"] for p in penalties]
            await supabase.table("penalties") \
                .update({"payment_status": "canceled"}) \
                .in_("id", penalty_ids).execute()
            logger.debug(f"🚫 Marked penalties as canceled: {penalty_ids}")

    elif event.type == "payment_intent.requires_action":
        logger.debug("⚠️ Processing payment_intent.requires_action")
        payment_intent = event.data.object
        payment_intent_id = payment_intent.id
        
        # Query penalties by payment_intent_id instead of using metadata
        penalties_result = await supabase.table("penalties").select("*").eq("payment_intent_id", payment_intent_id).execute()
        penalties = penalties_result.data
        
        if penalties:
            penalty_ids = [p["id"] for p in penalties]
            await supabase.table("penalties") \
                .update({"payment_status": "requires_action"}) \
                .in_("id", penalty_ids).execute()
            logger.debug(f"⚠️ Marked penalties as requires_action: {penalty_ids}")
            
    elif event.type == "setup_intent.succeeded":
        logger.debug("💳 Processing setup_intent.succeeded")
        setup_intent = event.data.object
        customer_id = setup_intent.customer
        payment_method_id = setup_intent.payment_method
        
        if customer_id and payment_method_id:
            # 1️⃣ Make sure the payment-method is attached to the customer (no-op if already attached)
            try:
                stripe.PaymentMethod.attach(payment_method_id, customer=customer_id)
            except stripe.error.InvalidRequestError as e:
                # If already attached, Stripe throws an error – ignore in that case
                if "already" not in str(e).lower():
                    logger.error(f"❌ Error attaching payment method: {e}")
                    raise
            # 2️⃣ Set it as dashboard-default so it shows in Stripe UI
            stripe.Customer.modify(
                customer_id,
                invoice_settings={"default_payment_method": payment_method_id}
            )
            logger.debug(f"✅ Set {payment_method_id} as default for customer {customer_id}")

            # 3️⃣ Update our database record
            user_result = await supabase.table("users").select("id").eq("stripe_customer_id", customer_id).single().execute()
            if user_result.data:
                user_id = user_result.data["id"]
                await supabase.table("users").update({
                    "default_payment_method_id": payment_method_id,
                    "updated_at": datetime.utcnow().isoformat()
                }).eq("id", user_id).execute()
                logger.debug(f"✅ Stored default_payment_method_id in DB for user {user_id}")
            else:
                logger.warning(f"⚠️ No user found for Stripe customer: {customer_id}")
        else:
            logger.warning(f"⚠️ Missing customer_id or payment_method_id in setup_intent.succeeded")

    elif event.type == "account.updated":
        logger.debug("🏢 Processing account.updated")
        account = event.data.object
        # Update the user's account status in the database
        is_fully_enabled = account.charges_enabled and account.payouts_enabled and account.details_submitted
        logger.debug(f"🏢 Account {account.id} - Charges: {account.charges_enabled}, Payouts: {account.payouts_enabled}, Details: {account.details_submitted}")
        
        # Update the user's Stripe Connect status
        user_result = await supabase.table("users").update({
            "stripe_connect_status": is_fully_enabled,
            "updated_at": datetime.utcnow().isoformat()  # Update timestamp to trigger sync
        }).eq("stripe_connect_account_id", account.id).execute()
        
        logger.debug(f"✅ Updated account status for {account.id}: {is_fully_enabled}")
        
        # TODO: Future enhancement - Send push notifications to friends
        # When push notifications are implemented:
        # 1. Get all friends of this user
        # 2. Send them a notification that their friend can now receive payments
        # 3. This ensures immediate visibility of Stripe Connect updates
        # 
        # Example implementation:
        # if is_fully_enabled and user_result.data:
        #     user_id = user_result.data[0]['id']
        #     friends = await get_user_friends(supabase, user_id)
        #     await send_push_notifications(friends, f"Your friend can now receive payments!")
    else:
        logger.debug(f"ℹ️ Unhandled event type: {event.type}")

    logger.debug(f"✅ Webhook processed successfully: {event.type}")
    return {"status": "success"}

@router.post("/create-setup-intent")
async def create_setup_intent(
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    try:
        user_id = current_user.id

        # 1⃣  Pull the user row so we know if a Stripe customer already exists
        user_row = await supabase.table("users").select("*").eq("id", user_id).single().execute()
        if not user_row.data:
            raise HTTPException(status_code=404, detail="User not found")

        stripe_customer_id = user_row.data["stripe_customer_id"]

        if not stripe_customer_id:
            customer = stripe.Customer.create(
                phone=current_user.phone_number,
                name=current_user.name
            )
            stripe_customer_id = customer.id
            await supabase.table("users").update(
                {"stripe_customer_id": stripe_customer_id}
            ).eq("id", user_id).execute()

        setup_intent = stripe.SetupIntent.create(
            customer=stripe_customer_id,
            payment_method_types=["card"],
            usage="off_session",
            metadata={
                "user_id": user_id
            }
        )

        ephemeral_key = stripe.EphemeralKey.create(
            customer=stripe_customer_id,
            stripe_version="2024-04-10"
        )

        # Debug prints removed for security

        return {
            "clientSecret": setup_intent.client_secret,
            "customerId": stripe_customer_id,
            "ephemeralKey": ephemeral_key.secret
        }

    except Exception as e:
        logger.exception("Error creating setup intent")
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/get-user-payment-method")
async def get_user_payment_method(
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    try:
        # Debug: get-user-payment-method called
        user_id = current_user.id
        user_row = await supabase.table("users").select("*").eq("id", user_id).single().execute()
        if not user_row.data:
            # User not found
            raise HTTPException(status_code=404, detail="User not found")

        stripe_customer_id = user_row.data.get("stripe_customer_id")
        
        if not stripe_customer_id:
            # Stripe customer ID not found
            return {
                "payment_method": None,
                "message": "No payment method set up yet"
            }

        payment_method = stripe.Customer.list_payment_methods(stripe_customer_id)
        if not payment_method.data:
            # No payment method found for customer
            return {
                "payment_method": None,
                "message": "No payment method set up yet"
            }
        
        # Returning payment method
        return {
            "payment_method": jsonable_encoder(payment_method.data[0])
        }
    except Exception as e:
        # Exception in get-user-payment-method
        logger.error(f"Error getting user payment method: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/connect/balance")
async def get_connect_balance(
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    try:
        # Get the user's Stripe Connect account ID
        user = await supabase.table("users").select("stripe_connect_account_id").eq("id", current_user.id).single().execute()
        
        if not user.data or not user.data["stripe_connect_account_id"]:
            return {"balance": 0, "currency": "usd"}
        
        # Get the balance from Stripe
        balance = stripe.Balance.retrieve(
            stripe_account=user.data["stripe_connect_account_id"]
        )
        
        # Calculate available balance (amount that can be paid out)
        available_balance = 0
        for balance_item in balance.available:
            if balance_item.currency == "usd":
                available_balance += balance_item.amount
        
        return {
            "balance": available_balance / 100,  # Convert from cents to dollars
            "currency": "usd"
        }
    except Exception as e:
        logger.error(f"Error getting balance: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/connect/withdraw")
async def create_withdrawal(
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    try:
        # Get the user's Stripe Connect account ID
        user = await supabase.table("users").select("stripe_connect_account_id").eq("id", current_user.id).single().execute()
        
        if not user.data or not user.data["stripe_connect_account_id"]:
            raise HTTPException(status_code=400, detail="No Stripe Connect account found")
        
        # Get current balance
        balance = stripe.Balance.retrieve(
            stripe_account=user.data["stripe_connect_account_id"]
        )
        
        # Calculate available balance
        available_balance = 0
        for balance_item in balance.available:
            if balance_item.currency == "usd":
                available_balance += balance_item.amount
        
        # Convert to dollars and check minimum
        available_balance_dollars = available_balance / 100
        if available_balance_dollars < 5:
            raise HTTPException(
                status_code=400, 
                detail="Minimum withdrawal amount is $5. Current balance: $%.2f" % available_balance_dollars
            )
        
        # Create a payout
        payout = stripe.Payout.create(
            amount=available_balance,
            currency="usd",
            stripe_account=user.data["stripe_connect_account_id"]
        )
        
        return {
            "status": "success",
            "amount": available_balance_dollars,
            "payout_id": payout.id
        }
    except Exception as e:
        logger.error(f"Error creating withdrawal: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/owed-per-recipient")
async def get_owed_per_recipient(
    supabase: AsyncClient = Depends(get_async_supabase_client),
    current_user: User = Depends(get_current_user)
):
    from datetime import datetime, timedelta
    today = datetime.utcnow().date()
    week_start = today - timedelta(days=today.weekday())
    week_end = week_start + timedelta(days=6)
    penalties = await supabase.table("penalties") \
        .select("*") \
        .eq("user_id", current_user.id) \
        .eq("is_paid", False) \
        .gte("penalty_date", week_start.isoformat()) \
        .lte("penalty_date", week_end.isoformat()).execute()

    # Group by recipient_id
    owed = {}
    for p in penalties.data:
        rid = p["recipient_id"]
        key = rid if rid is not None else "none"
        owed.setdefault(key, 0)
        owed[key] += float(p["amount"])
    # Optionally, fetch recipient names
    recipients = {}
    real_recipient_ids = [rid for rid in owed.keys() if rid != "none"]
    if real_recipient_ids:
        users = await supabase.table("users").select("id,name").in_("id", real_recipient_ids).execute()
        for u in users.data:
            recipients[u["id"]] = u["name"]
    return [
        {"recipient_id": rid, "recipient_name": recipients.get(rid, "No Recipient") if rid != "none" else "No Recipient", "amount_owed": amount}
        for rid, amount in owed.items()
    ]

