from fastapi import HTTPException
from models.schemas import Friend, FriendCreate, User, FriendRequest, FriendRequestCreate
from supabase._async.client import AsyncClient
from typing import List
from uuid import UUID
from pydantic import BaseModel
from typing import Optional
import asyncio
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from ..utils.cache_utils import get_user_relationship_data
import re

class FriendWithDetails(BaseModel):
    id: UUID
    friend_id: UUID
    name: str
    phone_number: str
    # Avatar fields for cached avatars
    avatar_version: Optional[int] = None
    avatar_url_80: Optional[str] = None
    avatar_url_200: Optional[str] = None
    avatar_url_original: Optional[str] = None
    last_active: Optional[str] = None

class UserSearchResult(BaseModel):
    id: UUID
    name: str
    phone_number: str
    # Avatar fields for cached avatars
    avatar_version: Optional[int] = None
    avatar_url_80: Optional[str] = None
    avatar_url_200: Optional[str] = None
    avatar_url_original: Optional[str] = None
    # Relationship status
    is_friend: bool = False
    has_pending_request: bool = False
    has_received_request: bool = False

@memory_optimized(cleanup_args=False)
@memory_profile("friend_service_add_friend")
async def add_friend_service(
    friend: FriendCreate, 
    current_user: User,
    supabase: AsyncClient
):
    """
    MODIFIED: Now sends friend request instead of creating immediate friendship.
    For backwards compatibility, this endpoint still accepts FriendCreate but sends a request.
    """
    try:
        # Convert UUIDs to strings for comparison
        current_user_id = str(current_user.id)
        friend_user_id = str(friend.user_id)
        friend_friend_id = str(friend.friend_id)
        
        # Determine who is sending the request to whom
        # If current user is the user_id, they're sending to friend_id
        # If current user is the friend_id, they're sending to user_id
        if current_user_id == friend_user_id:
            sender_id = current_user_id
            receiver_id = friend_friend_id
        elif current_user_id == friend_friend_id:
            sender_id = current_user_id
            receiver_id = friend_user_id
        else:
            raise HTTPException(
                status_code=403, 
                detail="Not authorized to create this friendship"
            )
        
        # Use the simplified database function (1 call instead of 6+)
        result = await supabase.rpc("send_friend_request_simple", {
            "sender_id": sender_id,
            "receiver_id": receiver_id,
            "message": "Friend request via direct add"
        }).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=500,
                detail="Failed to process friend request"
            )
        
        result_data = result.data[0]
        
        # Check for validation errors returned by the function
        if result_data.get('error'):
            error_message = result_data['error']
            if 'not found' in error_message.lower():
                raise HTTPException(status_code=404, detail=error_message)
            else:
                raise HTTPException(status_code=400, detail=error_message)
        
        # Return the successfully created friend request
        return FriendRequest(
            id=UUID(result_data['relationship_id']),
            sender_id=UUID(sender_id),
            receiver_id=UUID(receiver_id),
            status='pending',
            message=result_data['rel_message'],
            created_at=result_data['rel_created_at'],
            updated_at=result_data['rel_updated_at']
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in add_friend_service: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("friend_service_get_user_friends")
async def get_user_friends_service(user_id: str, supabase: AsyncClient):
    try:
        # Use the simplified database function with avatar data (1 call with optimized join)
        result = await supabase.rpc("get_user_friends_with_avatars", {
            "user_id": user_id
        }).execute()
        
        if not result.data:
            return []  # Return empty list if no friends
            
        # Transform the data to match our response model
        friends = []
        for friend_data in result.data:
            try:
                friends.append(FriendWithDetails(
                    id=UUID(friend_data['friend_id']),  # Using friend_id as the id
                    friend_id=UUID(friend_data['friend_id']),
                    name=friend_data['friend_name'],
                    phone_number=friend_data['friend_phone'],
                    avatar_version=friend_data.get('avatar_version'),
                    avatar_url_80=friend_data.get('avatar_url_80'),
                    avatar_url_200=friend_data.get('avatar_url_200'),
                    avatar_url_original=friend_data.get('avatar_url_original'),
                    last_active=friend_data.get('last_active')
                ))
            except Exception as ve:
                print(f"Error processing friend data: {ve}")
                continue
                
        return friends
    except Exception as e:
        print(f"Error in get_user_friends_service: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("friend_service_search_users")
async def search_users_service(
    query: str,
    current_user: User,
    supabase: AsyncClient
):
    """
    Search for all users on the app by username (name field).
    Returns users with their relationship status to the current user.
    Uses unified RPC approach with caching for optimal performance and consistency.
    """
    try:
        current_user_id = str(current_user.id)
        
        # Validate query to prevent wildcard/broad searches
        query_stripped = query.strip()
        
        # Check minimum length
        if len(query_stripped) < 1:
            return []
        
        # Prevent wildcard queries that are not allowed in usernames anyway
        # Note: usernames can only contain letters, numbers, spaces, hyphens, and underscores
        # So we only block characters that aren't allowed in usernames: *, %, ?, and other SQL wildcards
        prohibited_patterns = ['*', '%', '?']
        if any(pattern in query_stripped for pattern in prohibited_patterns):
            return []
        
        # Ensure query has meaningful content (not just special characters or spaces)
        # Allow letters, numbers, spaces, hyphens, and underscores (same as username validation)
        if not re.match(r'^[a-zA-Z0-9\s\-_]+$', query_stripped):
            return []
        
        # Minimum length requirement for meaningful search
        if len(query_stripped) < 2:
            return []
        
        # Parallel execution: search users and get relationship data simultaneously
        user_search_task = supabase.table("users").select(
            "id, name, phone_number, avatar_version, avatar_url_80, avatar_url_200, avatar_url_original"
        ).ilike("name", f"%{query_stripped}%").neq("id", current_user_id).execute()
        
        relationship_data_task = get_user_relationship_data(current_user_id, supabase)
        
        # Wait for both operations to complete
        user_result, relationship_data = await asyncio.gather(
            user_search_task, 
            relationship_data_task
        )
        
        if not user_result.data:
            return []
        
        # Extract relationship sets
        friend_ids = relationship_data['friend_ids']
        sent_request_ids = relationship_data['sent_request_ids']
        received_request_ids = relationship_data['received_request_ids']
        
        # Transform search results with relationship status
        search_results = []
        for user_data in user_result.data:
            user_id = str(user_data['id'])
            
            search_results.append(UserSearchResult(
                id=UUID(user_id),
                name=user_data['name'],
                phone_number=user_data['phone_number'],
                avatar_version=user_data.get('avatar_version'),
                avatar_url_80=user_data.get('avatar_url_80'),
                avatar_url_200=user_data.get('avatar_url_200'),
                avatar_url_original=user_data.get('avatar_url_original'),
                is_friend=user_id in friend_ids,
                has_pending_request=user_id in sent_request_ids,
                has_received_request=user_id in received_request_ids
            ))
        
        return search_results
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in search_users_service: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("friend_service_remove_friend")
async def remove_friend_service(
    friendship_id: str, 
    current_user: User,
    supabase: AsyncClient
):
    """Remove a friendship. User must be part of the friendship to remove it."""
    try:
        current_user_id = str(current_user.id)
        
        # In the simplified system, we delete the relationship where user is involved and status is 'friends'
        result = await supabase.table("user_relationships").delete().eq("id", friendship_id).eq("status", "friends").or_(
            f"user1_id.eq.{current_user_id},user2_id.eq.{current_user_id}"
        ).execute()
        
        if not result.data:
            raise HTTPException(status_code=404, detail="Friendship not found or you are not part of this friendship")
        
        return {"message": "Friendship removed successfully"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in remove_friend_service: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("friend_service_get_friends")
async def get_friends_service(
    current_user: User,
    supabase: AsyncClient
):
    """Get all friends for the current user"""
    try:
        current_user_id = str(current_user.id)
        
        # Use the simplified database function (1 call with optimized join)
        result = await supabase.rpc("get_user_friends", {
            "user_id": current_user_id
        }).execute()
        
        if not result.data:
            return []
            
        friends = []
        for friend_data in result.data:
            # Create a Friend object for each friendship
            # Note: In the simplified system, we need to create compatible Friend objects
            # We'll use the friend's ID as both id and friend_id for compatibility
            friends.append(Friend(
                id=UUID(friend_data['friend_id']),  # Using friend_id as the primary id
                user_id=UUID(current_user_id),
                friend_id=UUID(friend_data['friend_id']),
                created_at=friend_data['friendship_created_at'],
                updated_at=friend_data['friendship_created_at']
            ))
            
        return friends
    except Exception as e:
        print(f"Error in get_friends_service: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e)) 