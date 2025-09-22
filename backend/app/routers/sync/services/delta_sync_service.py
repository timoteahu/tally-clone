from typing import Optional
from datetime import datetime, timezone
from supabase._async.client import AsyncClient
from models.schemas import User
from utils.memory_optimization import cleanup_memory, disable_print
from utils.async_coordination import DataFetcher
from utils.timezone_utils import get_user_timezone
from .data_fetching_service import (
    fetch_habits, fetch_friends, fetch_friends_with_stripe, fetch_feed,
    fetch_payment_method, fetch_custom_habit_types, fetch_available_habit_types,
    fetch_onboarding_state, fetch_user_profile
)
from .progress_verification_service import (
    fetch_weekly_progress, fetch_verification_data, fetch_friend_requests,
    fetch_staged_deletions, fetch_friend_recommendations
)
from pydantic import BaseModel

# Disable verbose printing to reduce response latency
print = disable_print()

class DeltaChanges(BaseModel):
    """Response model for delta sync changes - now includes ALL app data"""
    habits_changed: Optional[list[str]] = None
    friends_changed: Optional[list[str]] = None  
    feed_posts_changed: Optional[list[str]] = None
    user_profile_changed: Optional[bool] = None
    last_modified: Optional[str] = None
    
    # Include ALL the data types from PreloadedData
    habits: Optional[list[dict]] = None
    friends: Optional[list[dict]] = None
    friends_with_stripe: Optional[list[dict]] = None
    payment_method: Optional[dict] = None
    feed_posts: Optional[list[dict]] = None
    custom_habit_types: Optional[list[dict]] = None
    available_habit_types: Optional[dict] = None
    onboarding_state: Optional[int] = None
    user_profile: Optional[dict] = None
    weekly_progress: Optional[list[dict]] = None
    
    # NEW: Add verification data
    verified_habits_today: Optional[dict[str, bool]] = None
    habit_verifications: Optional[dict[str, list[dict]]] = None
    weekly_verified_habits: Optional[dict[str, dict[str, bool]]] = None
    
    # NEW: Add friend requests data
    friend_requests: Optional[dict] = None
    
    # NEW: Add staged deletions data
    staged_deletions: Optional[dict] = None

    # NEW: Add friend recommendations data
    friend_recommendations: Optional[list[dict]] = None

    @property
    def has_changes(self) -> bool:
        """Check if there are any changes"""
        return bool(
            (self.habits_changed and len(self.habits_changed) > 0) or
            (self.friends_changed and len(self.friends_changed) > 0) or
            (self.feed_posts_changed and len(self.feed_posts_changed) > 0) or
            self.user_profile_changed
        )

async def get_delta_changes_service(
    current_user: User,
    supabase: AsyncClient,
    if_modified_since: Optional[str] = None
) -> DeltaChanges:
    """
    Get ALL app data in delta format using high-level coordination utilities.
    Returns 304 Not Modified if no changes since last sync, 200 with ALL data otherwise.
    """
    try:
        user_id = str(current_user.id)
        print(f"Delta sync request for user {user_id} since {if_modified_since}")
        
        # Initialize response
        delta_response = DeltaChanges()
        
        # Parse the If-Modified-Since header (optional for full data load)
        since_date = None
        if if_modified_since:
            try:
                since_date = datetime.fromisoformat(if_modified_since.replace('Z', '+00:00'))
            except ValueError:
                try:
                    since_date = datetime.strptime(if_modified_since, "%a, %d %b %Y %H:%M:%S %Z")
                    since_date = since_date.replace(tzinfo=timezone.utc)
                except ValueError:
                    print(f"Invalid If-Modified-Since format: {if_modified_since}")
                    since_date = None
        
        # ALWAYS fetch ALL data using the new high-level DataFetcher
        print("Fetching all app data with coordinated parallelism...")
        
        # Use the high-level DataFetcher for organized, parallel data fetching
        fetcher = DataFetcher(max_concurrent=16)
        
        # Define all fetch operations with descriptive names
        fetch_operations = {
            'habits': lambda: fetch_habits(supabase, user_id),
            'friends': lambda: fetch_friends(supabase, user_id),
            'friends_with_stripe': lambda: fetch_friends_with_stripe(supabase, user_id),
            'feed_posts': lambda: fetch_feed(supabase, user_id),
            'payment_method': lambda: fetch_payment_method(supabase, user_id),
            'custom_habit_types': lambda: fetch_custom_habit_types(supabase, user_id),
            'friend_requests': lambda: fetch_friend_requests(supabase, user_id),
            'available_habit_types': lambda: fetch_available_habit_types(supabase, user_id),
            'onboarding_state': lambda: fetch_onboarding_state(supabase, user_id),
            'user_profile': lambda: fetch_user_profile(supabase, user_id),
            'weekly_progress': lambda: fetch_weekly_progress(supabase, user_id, if_modified_since),
            'verification_data': lambda: fetch_verification_data(supabase, user_id),
            'staged_deletions': lambda: fetch_staged_deletions(supabase, user_id),
            'friend_recommendations': lambda: fetch_friend_recommendations(supabase, user_id)
        }
        
        # Execute all fetches with coordinated parallelism
        results = await fetcher.fetch_multiple(fetch_operations)

        # Process results with clean error handling
        try:
            # Map results to response fields
            delta_response.habits = results.get('habits', [])
            delta_response.friends = results.get('friends', [])
            delta_response.friends_with_stripe = results.get('friends_with_stripe', [])
            delta_response.feed_posts = results.get('feed_posts', [])
            delta_response.payment_method = results.get('payment_method')
            delta_response.custom_habit_types = results.get('custom_habit_types', [])
            delta_response.friend_requests = results.get('friend_requests')
            delta_response.available_habit_types = results.get('available_habit_types')
            delta_response.onboarding_state = results.get('onboarding_state', 0)
            delta_response.user_profile = results.get('user_profile')
            delta_response.weekly_progress = results.get('weekly_progress', [])
            
            # Handle verification data tuple
            verification_data = results.get('verification_data')
            if verification_data and len(verification_data) == 3:
                delta_response.verified_habits_today, delta_response.habit_verifications, delta_response.weekly_verified_habits = verification_data
            else:
                delta_response.verified_habits_today = {}
                delta_response.habit_verifications = {}
                delta_response.weekly_verified_habits = {}
            
            # Handle other complex data
            delta_response.staged_deletions = results.get('staged_deletions', {})
            delta_response.friend_recommendations = results.get('friend_recommendations', [])

            # Set timestamps and change flags (always return data for full preload)
            delta_response.last_modified = datetime.now(timezone.utc).isoformat()
            delta_response.habits_changed = [str(h.get("id", "")) for h in (delta_response.habits or [])]
            delta_response.friends_changed = [str(f.get("friend_id", "")) for f in (delta_response.friends or [])]
            delta_response.feed_posts_changed = [str(p.get("post_id", "")) for p in (delta_response.feed_posts or [])]
            delta_response.user_profile_changed = delta_response.user_profile is not None
            
            print(f"Delta sync completed with coordinated data load")
            print(f"- Habits: {len(delta_response.habits or [])}")
            print(f"- Friends: {len(delta_response.friends or [])}")
            print(f"- Friends with Stripe: {len(delta_response.friends_with_stripe or [])}")
            print(f"- Feed posts: {len(delta_response.feed_posts or [])}")
            print(f"- Custom habit types: {len(delta_response.custom_habit_types or [])}")
            print(f"- Weekly progress: {len(delta_response.weekly_progress or [])}")
            print(f"- Verified habits today: {len(delta_response.verified_habits_today or {})}")
            print(f"- Friend recommendations: {len(delta_response.friend_recommendations or [])}")
            
            # DEBUG: Log first feed post structure if available
            if delta_response.feed_posts and len(delta_response.feed_posts) > 0:
                print(f"🔍 [DEBUG] First feed post structure: {delta_response.feed_posts[0]}")
            else:
                print(f"⚠️ [DEBUG] No feed posts returned")
            
            return delta_response
            
        except Exception as processing_error:
            print(f"Error processing results: {processing_error}")
            # Return empty response rather than failing completely
            delta_response.last_modified = datetime.now(timezone.utc).isoformat()
            return delta_response
        
    except Exception as e:
        print(f"Delta sync error: {e}")
        # Return basic response structure
        return DeltaChanges(last_modified=datetime.now(timezone.utc).isoformat())
    finally:
        # Cleanup memory using global utilities
        cleanup_memory(results if 'results' in locals() else None, fetch_operations if 'fetch_operations' in locals() else None) 