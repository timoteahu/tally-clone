from datetime import date, datetime, timedelta
from config.database import get_supabase_client
from config.stripe import create_payment_intent
from supabase import Client
import logging
import stripe
import pytz

logger = logging.getLogger(__name__)

def get_user_timezone(supabase: Client, user_id: str) -> str:
    """Get user's timezone from the database"""
    user = supabase.table("users").select("timezone").eq("id", user_id).execute()
    if not user.data:
        return "UTC"
    
    timezone = user.data[0]["timezone"]
    
    # Handle timezone abbreviations by mapping them to proper pytz names
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
    
    # If it's an abbreviation, convert it
    if timezone in timezone_mapping:
        timezone = timezone_mapping[timezone]
    
    # Validate the timezone exists in pytz
    try:
        pytz.timezone(timezone)
        return timezone
    except pytz.exceptions.UnknownTimeZoneError:
        print(f"Unknown timezone: {timezone}, falling back to UTC")
        return "UTC"

def get_localized_date(supabase: Client, user_id: str) -> date:
    """Get current date in user's timezone"""
    timezone = get_user_timezone(supabase, user_id)
    return datetime.now(pytz.timezone(timezone)).date()

async def check_and_create_penalties(supabase: Client):
    """
    Check for missed habit submissions and create penalties
    Includes first-day grace period - no charging on the day the habit was created
    """
    # Get all active habits with creation timestamps
    habits = supabase.table("habits").select("*").eq("is_active", True).execute()
    
    for habit in habits.data:
        # Get user's timezone
        user_id = habit["user_id"]
        today = get_localized_date(supabase, user_id)
        yesterday = today - timedelta(days=1)
        
        # First-day grace period check
        habit_created_at = datetime.fromisoformat(habit['created_at'].replace('Z', '+00:00'))
        habit_creation_date = habit_created_at.date()
        
        # Skip penalty if the habit was created on or after the day we're checking penalties for
        if habit_creation_date >= yesterday:
            logger.info(f"First-day grace period: Habit {habit['id']} was created on {habit_creation_date}, skipping penalty for {yesterday} (habit created on or after penalty date)")
            continue
        
        # Get the last submission date for this habit
        last_log = supabase.table("habit_verifications")\
            .select("verified_at")\
            .eq("habit_id", habit["id"])\
            .order("verified_at", desc=True)\
            .limit(1)\
            .execute()
        
        last_submission_date = None
        if last_log.data:
            # Convert the stored date to user's timezone
            stored_date = datetime.strptime(last_log.data[0]["verified_at"], "%Y-%m-%d").date()
            timezone = pytz.timezone(get_user_timezone(supabase, user_id))
            localized_date = timezone.localize(datetime.combine(stored_date, datetime.min.time())).date()
            last_submission_date = localized_date
        
        # If there's no submission or the last submission was before yesterday
        if not last_submission_date or last_submission_date < yesterday:
            # Check if yesterday was a required weekday for this habit
            if yesterday.weekday() in habit["weekdays"]:
                # Check if penalty already exists for yesterday
                existing_penalty = supabase.table("penalties")\
                    .select("*")\
                    .eq("habit_id", habit["id"])\
                    .eq("penalty_date", yesterday.isoformat())\
                    .execute()
                
                if not existing_penalty.data:
                    # Create new penalty
                    penalty_data = {
                        "habit_id": habit["id"],
                        "user_id": habit["user_id"],
                        "amount": habit["penalty_amount"],
                        "penalty_date": yesterday.isoformat(),
                        "is_paid": False
                    }
                    
                    # Insert penalty into database
                    penalty = supabase.table("penalties").insert(penalty_data).execute()
                    
                    # Send habit reminder message to accountability partner
                    # TODO: Re-enable when Twilio phone number is configured
                    # try:
                    #     from services.simple_habit_reminders import simple_habit_reminder_service
                    #     
                    #     reminder_result = await simple_habit_reminder_service.send_habit_reminder(
                    #         habit_id=habit["id"],
                    #         message_type="daily_miss",
                    #         supabase_client=supabase,
                    #         missed_days=1
                    #     )
                    #     
                    #     if reminder_result["status"] == "sent":
                    #         logger.info(f"Sent daily miss reminder for habit {habit['id']} to {reminder_result['recipient_phone']}")
                    #     elif reminder_result["status"] == "skipped":
                    #         logger.info(f"Skipped reminder for habit {habit['id']}: {reminder_result.get('reason', 'unknown')}")
                    #     else:
                    #         logger.warning(f"Failed to send reminder for habit {habit['id']}: {reminder_result.get('error', 'unknown error')}")
                    #         
                    # except Exception as e:
                    #     logger.error(f"Error sending habit reminder: {str(e)}")
                    logger.info(f"Habit reminder disabled - Twilio phone number not configured. Penalty created for habit {habit['id']}")
                    
                    # Create payment intent for the penalty
                    try:
                        payment_intent = create_payment_intent(
                            amount=int(habit["penalty_amount"] * 100),  # Convert to cents
                            currency="usd",
                            metadata={
                                "penalty_id": penalty.data[0]["id"],
                                "user_id": habit["user_id"]
                            }
                        )
                        
                        # Update penalty with payment intent ID
                        supabase.table("penalties")\
                            .update({"payment_intent_id": payment_intent.id})\
                            .eq("id", penalty.data[0]["id"])\
                            .execute()
                            
                    except Exception as e:
                        logger.error(f"Error creating payment intent: {str(e)}") 
