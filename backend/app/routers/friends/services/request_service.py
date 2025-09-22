from fastapi import HTTPException, status
from typing import List
from models.schemas import (
    FriendRequest, FriendRequestCreate, FriendRequestWithDetails,
    FriendRequestAcceptResponse, FriendRequestDeclineResponse, 
    FriendRequestCancelResponse, User
)
from supabase._async.client import AsyncClient
from uuid import UUID
from utils.activity_tracking import track_user_activity
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile
from ..utils.cache_utils import invalidate_relationship_cache

@memory_optimized(cleanup_args=False)
@memory_profile("request_service_send")
async def send_friend_request_service(
    request_data: FriendRequestCreate,
    current_user: User,
    supabase: AsyncClient
):
    """Send a friend request to another user"""
    try:
        sender_id = str(current_user.id)
        receiver_id = str(request_data.receiver_id)
        
        # Track user activity when sending friend request
        await track_user_activity(supabase, sender_id)
        
        # Use the simplified database function (1 call instead of 6)
        result = await supabase.rpc("send_friend_request_simple", {
            "sender_id": sender_id,
            "receiver_id": receiver_id,
            "message": request_data.message
        }).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to send friend request"
            )
        
        result_data = result.data[0]
        
        # Check for errors from the database function
        if result_data.get('error'):
            error_message = result_data['error']
            if 'not found' in error_message.lower():
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_message)
            else:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_message)
        
        # Convert the simplified result to match the original FriendRequest model
        friend_request = FriendRequest(
            id=UUID(result_data['relationship_id']),
            sender_id=UUID(sender_id),
            receiver_id=UUID(receiver_id),
            status="pending",
            message=request_data.message,
            created_at=result_data['rel_created_at'],
            updated_at=result_data['rel_updated_at']
        )
        
        # Invalidate relationship cache for both users to ensure fresh search results
        invalidate_relationship_cache(sender_id)
        invalidate_relationship_cache(receiver_id)
        
        return friend_request
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in send_friend_request_service: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to send friend request: {str(e)}"
        )

@memory_optimized(cleanup_args=False)
@memory_profile("request_service_get_received")
async def get_received_requests_service(
    current_user: User,
    supabase: AsyncClient
):
    """Get friend requests received by the current user"""
    try:
        user_id = str(current_user.id)
        
        # Use the new database function with avatar data (1 call with optimized join)
        result = await supabase.rpc("get_received_friend_requests_with_avatars", {
            "user_id": user_id
        }).execute()
        
        if not result.data:
            return []
        
        requests = []
        for req_data in result.data:
            # Convert to match the original FriendRequestWithDetails model with avatar data
            requests.append(FriendRequestWithDetails(
                id=UUID(req_data['relationship_id']),
                sender_id=UUID(req_data['sender_id']),
                receiver_id=UUID(user_id),
                status='pending',
                message=req_data['message'],
                created_at=req_data['created_at'],
                updated_at=req_data['created_at'],  # Same as created for pending requests
                sender_name=req_data['sender_name'],
                sender_phone=req_data['sender_phone'],
                receiver_name="",  # Current user - can be filled if needed
                receiver_phone="",  # Current user - can be filled if needed
                # Add avatar fields
                sender_avatar_version=req_data.get('sender_avatar_version'),
                sender_avatar_url_80=req_data.get('sender_avatar_url_80'),
                sender_avatar_url_200=req_data.get('sender_avatar_url_200'),
                sender_avatar_url_original=req_data.get('sender_avatar_url_original')
            ))
        
        return requests
        
    except Exception as e:
        print(f"Error in get_received_requests_service: {str(e)}")
        # Fallback to the old function if the new one fails
        try:
            result = await supabase.rpc("get_received_friend_requests", {
                "user_id": user_id
            }).execute()
            
            if not result.data:
                return []
            
            requests = []
            for req_data in result.data:
                # Convert to match the original FriendRequestWithDetails model without avatar data
                requests.append(FriendRequestWithDetails(
                    id=UUID(req_data['relationship_id']),
                    sender_id=UUID(req_data['sender_id']),
                    receiver_id=UUID(user_id),
                    status='pending',
                    message=req_data['message'],
                    created_at=req_data['created_at'],
                    updated_at=req_data['created_at'],  # Same as created for pending requests
                    sender_name=req_data['sender_name'],
                    sender_phone=req_data['sender_phone'],
                    receiver_name="",  # Current user - can be filled if needed
                    receiver_phone="",  # Current user - can be filled if needed
                    # No avatar fields for fallback
                    sender_avatar_version=None,
                    sender_avatar_url_80=None,
                    sender_avatar_url_200=None,
                    sender_avatar_url_original=None
                ))
            
            return requests
        except Exception as fallback_error:
            print(f"Error in get_received_requests_service (fallback): {fallback_error}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to get received requests: {str(fallback_error)}"
            )

@memory_optimized(cleanup_args=False)
@memory_profile("request_service_get_sent")
async def get_sent_requests_service(
    current_user: User,
    supabase: AsyncClient
):
    """Get friend requests sent by the current user"""
    try:
        user_id = str(current_user.id)
        
        # Use the new database function with avatar data (1 call with optimized join)
        result = await supabase.rpc("get_sent_friend_requests_with_avatars", {
            "user_id": user_id
        }).execute()
        
        if not result.data:
            return []
        
        requests = []
        for req_data in result.data:
            # Convert to match the original FriendRequestWithDetails model with avatar data
            requests.append(FriendRequestWithDetails(
                id=UUID(req_data['relationship_id']),
                sender_id=UUID(user_id),
                receiver_id=UUID(req_data['receiver_id']),
                status='pending',
                message=req_data['message'],
                created_at=req_data['created_at'],
                updated_at=req_data['created_at'],  # Same as created for pending requests
                sender_name="",  # Current user - can be filled if needed
                sender_phone="", # Current user - can be filled if needed
                receiver_name=req_data['receiver_name'],
                receiver_phone=req_data['receiver_phone'],
                # Add avatar fields (for the receiver since this is sent requests)
                sender_avatar_version=None,  # We don't need sender avatar since it's the current user
                sender_avatar_url_80=None,
                sender_avatar_url_200=None,
                sender_avatar_url_original=None
            ))
        
        return requests
        
    except Exception as e:
        print(f"Error in get_sent_requests_service: {str(e)}")
        # Fallback to the old function if the new one fails
        try:
            result = await supabase.rpc("get_sent_friend_requests", {
                "user_id": user_id
            }).execute()
            
            if not result.data:
                return []
            
            requests = []
            for req_data in result.data:
                # Convert to match the original FriendRequestWithDetails model without avatar data
                requests.append(FriendRequestWithDetails(
                    id=UUID(req_data['relationship_id']),
                    sender_id=UUID(user_id),
                    receiver_id=UUID(req_data['receiver_id']),
                    status='pending',
                    message=req_data['message'],
                    created_at=req_data['created_at'],
                    updated_at=req_data['created_at'],  # Same as created for pending requests
                    sender_name="",  # Current user - can be filled if needed
                    sender_phone="", # Current user - can be filled if needed
                    receiver_name=req_data['receiver_name'],
                    receiver_phone=req_data['receiver_phone'],
                    # No avatar fields for fallback
                    sender_avatar_version=None,
                    sender_avatar_url_80=None,
                    sender_avatar_url_200=None,
                    sender_avatar_url_original=None
                ))
            
            return requests
        except Exception as fallback_error:
            print(f"Error in get_sent_requests_service (fallback): {fallback_error}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to get sent requests: {str(fallback_error)}"
            )

@memory_optimized(cleanup_args=False)
@memory_profile("request_service_accept")
async def accept_friend_request_service(
    request_id: str,
    current_user: User,
    supabase: AsyncClient
):
    """Accept a friend request"""
    try:
        user_id = str(current_user.id)
        
        # Track user activity when accepting friend request
        await track_user_activity(supabase, user_id)
        
        # Use the simplified database function (1 call instead of 5)
        result = await supabase.rpc("accept_friend_request_simple", {
            "relationship_id": request_id,
            "accepting_user_id": user_id
        }).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to accept friend request"
            )
        
        result_data = result.data[0]
        
        # Check for errors from the database function
        if result_data.get('error'):
            error_message = result_data['error']
            if 'not found' in error_message.lower():
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=error_message)
            elif 'cannot accept' in error_message.lower() or 'not part of' in error_message.lower():
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=error_message)
            else:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=error_message)
        
        # Invalidate relationship cache for both users (sender and receiver)
        # Extract user IDs from the operation result if available
        sender_id = result_data.get('sender_id')
        receiver_id = result_data.get('receiver_id') 
        
        if sender_id:
            invalidate_relationship_cache(str(sender_id))
        if receiver_id:
            invalidate_relationship_cache(str(receiver_id))
        
        # Always invalidate cache for current user
        invalidate_relationship_cache(user_id)
        
        return FriendRequestAcceptResponse(
            message="Friend request accepted successfully",
            friendship_id=UUID(request_id),  # Using relationship_id as friendship_id
            request_id=UUID(request_id)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in accept_friend_request_service: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to accept friend request: {str(e)}"
        )

@memory_optimized(cleanup_args=False)
@memory_profile("request_service_decline")
async def decline_friend_request_service(
    request_id: str,
    current_user: User,
    supabase: AsyncClient
):
    """Decline a friend request"""
    try:
        user_id = str(current_user.id)
        
        # Simply delete the relationship record (much simpler than before)
        result = await supabase.table("user_relationships").delete().eq("id", request_id).or_(
            f"user1_id.eq.{user_id},user2_id.eq.{user_id}"
        )
        
        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Friend request not found or you don't have permission to decline it"
            )
        
        # Invalidate relationship cache for current user
        # Note: We don't have access to other user's ID in this simplified delete,
        # but the current user's cache is the most important for immediate search updates
        invalidate_relationship_cache(user_id)
        
        return FriendRequestDeclineResponse(
            message="Friend request declined",
            request_id=UUID(request_id)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in decline_friend_request_service: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to decline friend request: {str(e)}"
        )

@memory_optimized(cleanup_args=False)
@memory_profile("request_service_cancel")
async def cancel_friend_request_service(
    request_id: str,
    current_user: User,
    supabase: AsyncClient
):
    """Cancel a friend request (sender only)"""
    try:
        user_id = str(current_user.id)
        
        # First, verify the request exists and user is the sender
        check_result = await supabase.table("user_relationships").select("*").eq("id", request_id).eq(
            "initiated_by", user_id
        ).eq("status", "pending").execute()
        
        if not check_result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Friend request not found or you can only cancel requests you sent"
            )
        
        # Now delete the relationship record
        delete_result = await supabase.table("user_relationships").delete().eq("id", request_id).eq(
            "initiated_by", user_id
        ).eq("status", "pending").execute()
        
        if not delete_result.data:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to cancel friend request"
            )
        
        # Get receiver ID from the original check result for cache invalidation
        original_request = check_result.data[0]
        receiver_id = None
        
        # Determine receiver ID (the user who is not the sender)
        if str(original_request.get('user1_id')) == user_id:
            receiver_id = str(original_request.get('user2_id'))
        elif str(original_request.get('user2_id')) == user_id:
            receiver_id = str(original_request.get('user1_id'))
        
        # Invalidate relationship cache for both users
        invalidate_relationship_cache(user_id)
        if receiver_id:
            invalidate_relationship_cache(receiver_id)
        
        return FriendRequestCancelResponse(
            message="Friend request cancelled",
            request_id=UUID(request_id)
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to cancel friend request: {str(e)}"
        ) 