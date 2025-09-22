from typing import Optional
from supabase._async.client import AsyncClient
from utils.memory_optimization import disable_print

# Disable verbose printing for performance
print = disable_print()

async def validate_custom_habit_type(custom_habit_type_id: str, user_id: str, supabase: AsyncClient) -> bool:
    """
    Validate that a custom habit type exists and belongs to the user.
    
    Args:
        custom_habit_type_id: ID of the custom habit type to validate
        user_id: User ID to check ownership
        supabase: Async Supabase client
        
    Returns:
        True if valid, False otherwise
    """
    try:
        # Check if the custom habit type exists and belongs to the user
        result = await supabase.table("custom_habit_types").select("id, user_id").eq("id", custom_habit_type_id).eq("user_id", user_id).eq("is_active", True).execute()
        return len(result.data) > 0
    except Exception as e:
        print(f"Error validating custom habit type: {e}")
        return False

async def validate_recipient_stripe_connect(recipient_id: str, supabase: AsyncClient) -> bool:
    """
    Validate that a recipient has a valid Stripe Connect account.
    
    Args:
        recipient_id: ID of the recipient to validate
        supabase: Async Supabase client
        
    Returns:
        True if recipient has valid Stripe Connect, False otherwise
    """
    try:
        # Check if recipient has Stripe Connect enabled
        result = await supabase.table("users").select("stripe_connect_status, stripe_connect_account_id").eq("id", recipient_id).execute()
        
        if not result.data:
            return False
            
        user_data = result.data[0]
        stripe_status = user_data.get("stripe_connect_status")
        stripe_account_id = user_data.get("stripe_connect_account_id")
        
        # Must have both status enabled and account ID
        return stripe_status is True and stripe_account_id is not None
        
    except Exception as e:
        print(f"Error validating recipient Stripe Connect: {e}")
        return False

async def validate_unique_recipients(user_id: str, new_recipient_id: str, current_habit_id: str, supabase: AsyncClient) -> bool:
    """
    Validate that the user doesn't already have another habit with the same recipient.
    
    Args:
        user_id: User ID
        new_recipient_id: Recipient ID to validate
        current_habit_id: Current habit ID (to exclude from check)
        supabase: Async Supabase client
        
    Returns:
        True if unique (or allowed), False if duplicate found
    """
    try:
        # Check for existing habits with the same recipient
        query = supabase.table("habits").select("id").eq("user_id", user_id).eq("recipient_id", new_recipient_id).eq("is_active", True)
        
        # Exclude current habit if provided
        if current_habit_id:
            query = query.neq("id", current_habit_id)
        
        result = await query.execute()
        
        # Return True if no duplicates found
        return len(result.data) == 0
        
    except Exception as e:
        print(f"Error validating unique recipients: {e}")
        return False

async def validate_habit_schedule(habit_schedule_type: str, weekdays: list = None, weekly_target: int = None) -> bool:
    """
    Validate habit schedule configuration.
    
    Args:
        habit_schedule_type: Type of schedule (daily, weekly, one_time)
        weekdays: List of weekdays for daily habits
        weekly_target: Target for weekly habits
        
    Returns:
        True if valid configuration, False otherwise
    """
    try:
        if habit_schedule_type == "daily":
            # Daily habits must have weekdays specified
            if not weekdays or not isinstance(weekdays, list) or len(weekdays) == 0:
                return False
            # Weekdays should be integers 0-6
            for day in weekdays:
                if not isinstance(day, int) or day < 0 or day > 6:
                    return False
            return True
            
        elif habit_schedule_type == "weekly":
            # Weekly habits must have a target
            if not weekly_target or not isinstance(weekly_target, int) or weekly_target < 1:
                return False
            return True
            
        elif habit_schedule_type == "one_time":
            # One-time habits don't need additional validation
            return True
            
        else:
            # Unknown schedule type
            return False
            
    except Exception as e:
        print(f"Error validating habit schedule: {e}")
        return False 