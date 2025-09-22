import asyncio
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta
from supabase._async.client import AsyncClient
from utils import (
    cleanup_memory,
    disable_print,
    memory_optimized,
    DataFetcher,
    generate_verification_image_urls,
    generate_profile_photo_url,
    generate_post_image_urls
)
import json
import stripe
import uuid

# Disable verbose printing for performance
print = disable_print()

@memory_optimized(cleanup_args=False)
async def fetch_habits(supabase: AsyncClient, user_id: str) -> List[Dict[str, Any]]:
    """Fetch user's active habits using optimized habit service"""
    try:
        # OPTIMIZATION: Use the optimized habit service instead of direct database query
        from routers.habits.services.habit_crud_service import get_user_habits_service
        from models.schemas import User
        from uuid import UUID
        
        # Create a User object for the service (it expects this for validation)
        current_user = User(id=UUID(user_id), name="", phone_number="")
        
        # Use the optimized habit service which has selective column fetching
        habits = await get_user_habits_service(
            user_id=user_id,
            current_user=current_user,
            supabase=supabase,
            include_completed=False  # Only active habits for sync
        )
        
        # Convert to dict format expected by sync service
        habits_list = []
        for habit in habits:
            habit_dict = habit.model_dump()
            # Convert UUIDs to strings for JSON serialization
            for field in ['id', 'user_id', 'recipient_id', 'custom_habit_type_id']:
                if habit_dict.get(field):
                    habit_dict[field] = str(habit_dict[field])
            habits_list.append(habit_dict)
        
        # Limit to reasonable number for performance
        return habits_list[:50]
        
    except Exception as e:
        print(f"❌ [Sync] Error fetching habits: {e}")
        # Fallback to direct query if service fails (should not happen)
        try:
            columns = "id, name, recipient_id, habit_type, weekdays, penalty_amount, user_id, created_at, updated_at, study_duration_minutes, screen_time_limit_minutes, restricted_apps, alarm_time, private, custom_habit_type_id, habit_schedule_type, weekly_target, week_start_day, commit_target, daily_limit_hours, hourly_penalty_rate, games_tracked, health_target_value, health_target_unit, health_data_type"
            result = await supabase.table("habits").select(columns).eq("user_id", user_id).eq("is_active", True).limit(50).execute()
            
            habits_list = [
                {**dict(habit), **{k: str(v) for k, v in dict(habit).items() 
                 if k in ['id', 'user_id', 'recipient_id', 'custom_habit_type_id'] and v}}
                for habit in result.data
            ]
            return habits_list
        except Exception as fallback_error:
            print(f"❌ [Sync] Fallback query also failed: {fallback_error}")
            return []

@memory_optimized(cleanup_args=False)
async def fetch_friends(supabase: AsyncClient, user_id: str) -> List[Dict[str, Any]]:
    """Fetch user's friends with memory optimization"""
    try:
        # MEMORY OPTIMIZATION: Use optimized RPC and limit results
        result = await supabase.rpc("get_user_friends", {"user_id": user_id}).execute()
        
        if not result.data:
            return []
        
        # Limit friends to reasonable number and select only needed fields
        limited_friends = result.data[:100]  # Limit to 100 friends max
        
        return [
            {
                "id": str(friend_data['friend_id']),
                "friend_id": str(friend_data['friend_id']),
                "name": friend_data.get("friend_name", ""),
                "phone_number": friend_data.get("friend_phone", "")
            }
            for friend_data in limited_friends
        ]
    except Exception as e:
        print(f"❌ [Sync] Error fetching friends: {e}")
        return []

@memory_optimized(cleanup_args=False)
async def fetch_friends_with_stripe(supabase: AsyncClient, user_id: str) -> List[Dict[str, Any]]:
    """Fetch ALL friends including their Stripe Connect status"""
    try:
        # Get ALL user's friends (not just those with Stripe)
        result = await supabase.rpc("get_user_friends", {
            "user_id": user_id
        }).execute()
        
        all_friends = []
        if result.data:
            # Get friend IDs
            friend_ids = [friend_data['friend_id'] for friend_data in result.data]
            
            if friend_ids:
                # Get friend details including Stripe status
                friends_info_result = await supabase.table("users").select(
                    "id, name, phone_number, stripe_connect_status, stripe_connect_account_id"
                ).in_("id", friend_ids).execute()
                
                for user_data in friends_info_result.data:
                    stripe_status = user_data.get("stripe_connect_status")
                    stripe_account_id = user_data.get("stripe_connect_account_id")
                    
                    all_friends.append({
                        "id": user_data["id"],
                        "name": user_data.get("name", ""), 
                        "phone_number": user_data.get("phone_number", ""),
                        "stripe_connect_status": bool(stripe_status) if stripe_status is not None else False,
                        "stripe_connect_account_id": stripe_account_id,
                        "has_stripe": bool(stripe_status is True and stripe_account_id)  # Helper field
                    })
            
            print(f"✅ Found {len(all_friends)} total friends")
        
        return all_friends
        
    except Exception as e:
        print(f"Error fetching friends: {e}")
        return []

@memory_optimized(cleanup_args=False)
async def fetch_feed(supabase: AsyncClient, user_id: str) -> List[Dict[str, Any]]:
    """Fetch the feed and process each post concurrently for maximum throughput."""
    try:
        # Grab raw feed data (single DB/RPC call)
        result = await supabase.rpc("get_user_feed", {"user_id_param": user_id}).execute()

        if not result.data:
            return []

        # Bound the per-post parallelism to avoid hammering Supabase storage
        post_sem = asyncio.Semaphore(10)

        async def process_post(post: dict):
            """Convert DB row => API response object (runs inside bounded semaphore)."""
            async with post_sem:
                try:
                    # Ensure comments are proper Python list
                    if isinstance(post.get('comments'), str):
                        post['comments'] = json.loads(post['comments'])

                    # Simplified comment mapping (keeps iOS happy)
                    comments = []
                    for comment_data in post['comments']:
                        comments.append({
                            "id": str(comment_data['id']),
                            "content": comment_data['content'],
                            "created_at": comment_data['created_at'],
                            "user_id": str(comment_data['user_id']),
                            "user_name": comment_data['user_name'],
                            "is_edited": comment_data['is_edited'],
                            "parent_comment": str(comment_data.get('parent_comment_id')) if comment_data.get('parent_comment_id') else None,
                            # 🔄  Avatar fields for comment authors
                            "user_avatar_version": comment_data.get("user_avatar_version"),
                            "user_avatar_url_80": comment_data.get("user_avatar_url_80"),
                            "user_avatar_url_200": comment_data.get("user_avatar_url_200"),
                            "user_avatar_url_original": comment_data.get("user_avatar_url_original"),
                        })

                    # Generate signed URLs for both selfie & content images (already concurrent inside)
                    image_urls = await generate_post_image_urls(
                        supabase,
                        post,
                        post.get("is_private", False)
                    )

                    return {
                        "post_id": str(post["post_id"]),
                        "caption": post.get("caption"),
                        "created_at": post["created_at"],
                        "is_private": post.get("is_private", False),
                        "image_url": image_urls.get("content_image_url") or image_urls.get("selfie_image_url"),
                        "selfie_image_url": image_urls.get("selfie_image_url"),
                        "content_image_url": image_urls.get("content_image_url"),
                        "user_id": str(post["user_id"]),
                        "user_name": post["user_name"],
                        # 🔄  Avatar fields for the post author (now available from SQL)
                        "user_avatar_version": post.get("user_avatar_version"),
                        "user_avatar_url_80": post.get("user_avatar_url_80"),
                        "user_avatar_url_200": post.get("user_avatar_url_200"),
                        "user_avatar_url_original": post.get("user_avatar_url_original"),
                        "habit_id": post.get("habit_id"),
                        "habit_name": post.get("habit_name"),
                        "habit_type": post.get("habit_type"),
                        "penalty_amount": round(float(post["penalty_amount"]), 2) if post.get("penalty_amount") is not None else None,
                        "comments": comments,
                        "streak": post.get("streak"),
                    }
                except Exception as post_err:
                    print(f"⚠️ [Sync] Failed to process feed post {post.get('post_id')}: {post_err}")
                    return None

        # Kick off parallel processing of every post
        processed = await asyncio.gather(*(process_post(p) for p in result.data))
        # Filter out any failures / None values
        return [p for p in processed if p]
    except Exception as e:
        print(f"Error fetching feed: {e}")
        return []

@memory_optimized(cleanup_args=False)
async def fetch_payment_method(supabase: AsyncClient, user_id: str) -> Optional[Dict[str, Any]]:
    """Fetch user's payment method from Stripe"""
    try:
        # Check if user has a connected Stripe customer
        user_result = await supabase.table("users").select("stripe_customer_id").eq("id", user_id).execute()
        if not user_result.data or not user_result.data[0].get("stripe_customer_id"):
            return None

        customer_id = user_result.data[0]["stripe_customer_id"]
        
        # Get payment methods from Stripe
        payment_methods = stripe.PaymentMethod.list(customer=customer_id, type="card")
        if not payment_methods.data:
            return None

        pm = payment_methods.data[0]  # Get the first payment method
        return {
            "payment_method": {
                "id": pm.id,
                "card": {
                    "brand": pm.card.brand,
                    "last4": pm.card.last4,
                    "exp_month": pm.card.exp_month,
                    "exp_year": pm.card.exp_year
                }
            }
        }
    except Exception as e:
        print(f"Error fetching payment method: {e}")
        return None

@memory_optimized(cleanup_args=False)
async def fetch_custom_habit_types(supabase: AsyncClient, user_id: str) -> List[Dict[str, Any]]:
    """Fetch user's custom habit types"""
    try:
        # Use active_custom_habit_types table which filters for is_active=True
        result = await supabase.table("active_custom_habit_types").select(
            "id, type_identifier, description, created_at, updated_at"
        ).eq("user_id", user_id).execute()

        custom_types = [
            {
                "id": str(habit_type["id"]),
                "type_identifier": habit_type["type_identifier"],
                "description": habit_type["description"],
                "created_at": habit_type["created_at"],
                "updated_at": habit_type["updated_at"]
            }
            for habit_type in result.data
        ]
        
        print(f"🔍 [Sync] Fetched {len(custom_types)} active custom habit types")
        for custom_type in custom_types:
            print(f"   📝 {custom_type['type_identifier']}: {custom_type['description']}")
        
        return custom_types
    except Exception as e:
        print(f"Error fetching custom habit types: {e}")
        return []

@memory_optimized(cleanup_args=False)
async def fetch_available_habit_types(supabase: AsyncClient, user_id: str) -> Optional[Dict[str, Any]]:
    """Fetch all available habit types (built-in + custom)"""
    try:
        # Built-in habit types (hardcoded) - match the ones from custom_habits.py
        built_in_types = [
            {"type": "gym", "display_name": "Gym", "description": "Gym workout verification with photo", "is_custom": False},
            {"type": "studying", "display_name": "Study", "description": "Study session with time tracking", "is_custom": False},
            {"type": "screenTime", "display_name": "Screen Time", "description": "Screen time limit monitoring", "is_custom": False},
            {"type": "alarm", "display_name": "Alarm", "description": "Early morning alarm verification", "is_custom": False},
            {"type": "yoga", "display_name": "Yoga Practice", "description": "Track your yoga sessions", "is_custom": False},
            {"type": "outdoors", "display_name": "Outdoor Activity", "description": "Track outdoor activities", "is_custom": False},
            {"type": "cycling", "display_name": "Cycling", "description": "Track your cycling sessions", "is_custom": False},
            {"type": "cooking", "display_name": "Cooking", "description": "Track your cooking activities", "is_custom": False}
        ]
        
        # Custom habit types for this user - use the correct table and filtering
        custom_types_result = await supabase.table("active_custom_habit_types").select(
            "type_identifier, description"
        ).eq("user_id", user_id).execute()
        
        custom_types = [
            {
                "type": f"custom_{custom_type['type_identifier']}",
                "display_name": custom_type["type_identifier"].replace("_", " ").title(),
                "description": custom_type["description"],
                "is_custom": True
            }
            for custom_type in custom_types_result.data
        ]
        
        print(f"🔍 [Sync] Built-in types: {len(built_in_types)}, Custom types: {len(custom_types)}")
        for custom_type in custom_types:
            print(f"   📝 Custom: {custom_type['display_name']} ({custom_type['type']})")
        
        return {
            "built_in_types": built_in_types,
            "custom_types": custom_types,
            "total_available": len(built_in_types) + len(custom_types)
        }
    except Exception as e:
        print(f"Error fetching available habit types: {e}")
        return None

@memory_optimized(cleanup_args=False)
async def fetch_onboarding_state(supabase: AsyncClient, user_id: str) -> int:
    """Fetch user's onboarding state"""
    try:
        user_result = await supabase.table("users").select("onboarding_state").eq("id", user_id).execute()
        if user_result.data:
            return user_result.data[0].get("onboarding_state", 0)
        return 0
    except Exception as e:
        print(f"Error fetching onboarding state: {e}")
        return 0

@memory_optimized(cleanup_args=False)
async def fetch_user_profile(supabase: AsyncClient, user_id: str) -> Optional[Dict[str, Any]]:
    """Fetch user's profile information"""
    try:
        user_result = await supabase.table("users").select(
            "id, name, phone_number, profile_photo_url, profile_photo_filename, onboarding_state, "
            "avatar_version, avatar_url_80, avatar_url_200, avatar_url_original"
        ).eq("id", user_id).execute()
        
        if user_result.data:
            user_info = user_result.data[0]
            profile_photo_url = await generate_profile_photo_url(supabase, user_info.get("profile_photo_filename"))
            if not profile_photo_url:
                profile_photo_url = user_info.get("profile_photo_url")
            
            return {
                "id": str(user_info["id"]),
                "name": user_info.get("name", ""),
                "phone_number": user_info.get("phone_number", ""),
                "onboarding_state": user_info.get("onboarding_state", 0),
                "profile_photo_url": profile_photo_url,
                # Add avatar fields for modern avatar system
                "avatar_version": user_info.get("avatar_version"),
                "avatar_url_80": user_info.get("avatar_url_80"),
                "avatar_url_200": user_info.get("avatar_url_200"),
                "avatar_url_original": user_info.get("avatar_url_original")
            }
        return None
    except Exception as e:
        print(f"Error fetching user profile: {e}")
        return None 