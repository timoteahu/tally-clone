from fastapi import HTTPException
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
import logging

logger = logging.getLogger(__name__)

def is_custom_habit_type(habit_type: str) -> bool:
    """Check if a habit type is a custom type (starts with 'custom_')"""
    return habit_type.startswith('custom_')

def extract_custom_type_identifier(habit_type: str) -> str:
    """Extract the identifier from a custom habit type string"""
    return habit_type[7:] if habit_type.startswith('custom_') else habit_type

@memory_optimized(cleanup_args=False)
@memory_profile("validate_custom_habit_type")
async def validate_custom_habit_type(custom_habit_type_id: str, user_id: str, supabase: AsyncClient) -> bool:
    """Validate that the custom habit type exists and belongs to the user"""
    try:
        result = await supabase.table("active_custom_habit_types").select("id").eq(
            "id", custom_habit_type_id
        ).eq("user_id", user_id).execute()
        
        return len(result.data) > 0
    except Exception as e:
        logger.error(f"Error validating custom habit type: {e}")
        return False

@memory_optimized(cleanup_args=False)
@memory_profile("validate_recipient_stripe_connect")
async def validate_recipient_stripe_connect(recipient_id: str, supabase: AsyncClient) -> bool:
    """
    Validate that a recipient has an active Stripe Connect account.
    
    Args:
        recipient_id: The recipient's user ID
        supabase: Database client
        
    Returns:
        bool: True if the recipient has active Stripe Connect
        
    Raises:
        HTTPException: If the recipient doesn't have Stripe Connect set up
    """
    if not recipient_id:
        return True
        
    try:
        # Check recipient's Stripe Connect status
        recipient_result = await supabase.table("users").select(
            "stripe_connect_account_id, stripe_connect_status"
        ).eq("id", recipient_id).execute()
        
        if not recipient_result.data:
            raise HTTPException(status_code=400, detail="Recipient not found")
            
        recipient = recipient_result.data[0]
        
        if not recipient.get("stripe_connect_account_id") or not recipient.get("stripe_connect_status"):
            raise HTTPException(
                status_code=400, 
                detail="The selected accountability partner needs to set up their payout method first."
            )
            
        return True
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error validating recipient Stripe Connect: {e}")
        raise HTTPException(status_code=500, detail="Error validating recipient")

@memory_optimized(cleanup_args=False)
@memory_profile("validate_unique_recipients")
async def validate_unique_recipients(user_id: str, new_recipient_id: str, current_habit_id: str, supabase: AsyncClient) -> bool:
    """
    Validate that a user has 3 unique recipients before allowing the same recipient to be added to another habit.
    Premium users bypass this restriction.
    
    Args:
        user_id: The user creating/updating the habit
        new_recipient_id: The recipient being assigned to the habit
        current_habit_id: The habit being updated (None for new habits)
        supabase: Database client
        
    Returns:
        bool: True if the assignment is allowed, False otherwise
        
    Raises:
        HTTPException: If the validation fails with appropriate error message
    """
    try:
        # If no recipient is being assigned, validation passes
        if not new_recipient_id:
            return True
        
        # Check if user is premium - premium users bypass unique recipients restriction
        user_result = await supabase.table("users").select("ispremium").eq("id", user_id).execute()
        if user_result.data and user_result.data[0].get("ispremium", False):
            return True  # Premium users can assign same recipient to multiple habits
            
        # Get all existing habits for this user with recipients
        result = await supabase.table("habits").select("id, recipient_id").eq("user_id", user_id).eq("is_active", True).execute()
        
        if not result.data:
            # No existing habits, so this is allowed
            return True
            
        existing_habits = result.data
        
        # Get unique recipients (excluding the current habit being updated)
        unique_recipients = set()
        recipient_usage_count = 0
        
        for habit in existing_habits:
            # Skip the current habit if we're updating (not creating)
            if current_habit_id and habit['id'] == current_habit_id:
                continue
                
            recipient_id = habit.get('recipient_id')
            if recipient_id:
                unique_recipients.add(recipient_id)
                
                # Count how many times the new recipient is already used
                if recipient_id == new_recipient_id:
                    recipient_usage_count += 1
        
        # Check if this recipient is already used and we don't have 3 unique recipients yet
        if recipient_usage_count > 0 and len(unique_recipients) < 3:
            raise HTTPException(
                status_code=400,
                detail=f"You must have 3 unique accountability partners before you can assign the same person to multiple habits. You currently have {len(unique_recipients)} unique accountability partners. Upgrade to Premium to remove this restriction."
            )
        
        return True
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error validating unique recipients: {e}")
        raise HTTPException(status_code=500, detail="Error validating recipient assignment") 