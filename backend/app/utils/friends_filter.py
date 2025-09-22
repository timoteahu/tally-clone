from supabase._async.client import AsyncClient
from typing import List, Dict, Any

async def get_eligible_friends_with_stripe(supabase: AsyncClient, user_id: str, all_friends_with_stripe: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Filter friends with Stripe Connect based on the unique recipients restriction.
    Users must have 3 unique recipients before they can reuse the same recipient for multiple habits.
    Premium users bypass this restriction.
    
    Args:
        supabase: Database client
        user_id: The user's ID
        all_friends_with_stripe: All friends with Stripe Connect
        
    Returns:
        List of friends that can be selected as recipients based on the restriction
    """
    try:
        # Check if user is premium - premium users bypass the restriction
        user_result = await supabase.table("users").select("ispremium").eq("id", user_id).execute()
        if user_result.data and user_result.data[0].get("ispremium", False):
            return all_friends_with_stripe  # Premium users can select any friend
        
        # Get all existing habits for this user with recipients
        habits_result = await supabase.table("habits").select("id, recipient_id").eq("user_id", user_id).eq("is_active", True).execute()
        
        if not habits_result.data:
            # No existing habits, so all friends are available
            return all_friends_with_stripe
        
        existing_habits = habits_result.data
        
        # Count unique recipients and their usage
        unique_recipients = set()
        recipient_usage_count = {}
        
        for habit in existing_habits:
            recipient_id = habit.get('recipient_id')
            if recipient_id:
                unique_recipients.add(recipient_id)
                recipient_usage_count[recipient_id] = recipient_usage_count.get(recipient_id, 0) + 1
        
        # If user has less than 3 unique recipients, they can only select:
        # 1. Friends they haven't used yet as recipients
        if len(unique_recipients) < 3:
            # Filter out friends who are already being used as recipients
            # (they can't be used again until user has 3 unique recipients)
            eligible_friends = []
            for friend in all_friends_with_stripe:
                friend_id = friend.get("friend_id")  # Use friend_id instead of id
                # Allow selection if this friend is not currently being used as a recipient
                if friend_id not in recipient_usage_count:
                    eligible_friends.append(friend)
            
            print(f"🔍 [Filter] User has {len(unique_recipients)} unique recipients (need 3). Filtered to {len(eligible_friends)}/{len(all_friends_with_stripe)} eligible friends")
            return eligible_friends
        else:
            # User has 3+ unique recipients, so they can select any friend
            print(f"✅ [Filter] User has {len(unique_recipients)} unique recipients (≥3). All {len(all_friends_with_stripe)} friends available")
            return all_friends_with_stripe
            
    except Exception as e:
        print(f"❌ [Filter] Error filtering eligible friends: {e}")
        # On error, return all friends to avoid blocking user
        return all_friends_with_stripe 