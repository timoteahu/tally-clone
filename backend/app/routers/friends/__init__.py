from fastapi import APIRouter, Depends, HTTPException, Request, Body
from typing import List, Dict, Any
from models.schemas import (
    Friend, FriendCreate, User, FriendRequest, FriendRequestCreate,
    FriendRequestWithDetails, FriendRequestAcceptResponse, 
    FriendRequestDeclineResponse, FriendRequestCancelResponse,
    FriendRecommendation, FriendRecommendationResponse
)
from config.database import get_async_supabase_client, get_supabase_client
from supabase._async.client import AsyncClient
from supabase import Client
from routers.auth import get_current_user, get_current_user_lightweight
from uuid import UUID

# Import service functions
from .services.friend_service import (
    add_friend_service,
    get_user_friends_service,
    search_users_service,
    remove_friend_service,
    get_friends_service,
    FriendWithDetails,
    UserSearchResult
)
from .services.request_service import (
    send_friend_request_service,
    get_received_requests_service,
    get_sent_requests_service,
    accept_friend_request_service,
    decline_friend_request_service,
    cancel_friend_request_service
)
from .services.recommendation_service import (
    get_friend_recommendations_service,
    send_recommendation_request_service,
    get_friend_recommendations_from_contacts_service,
    match_contacts_with_users_service
)
from .services.relationship_service import (
    get_unified_friend_relationships_service,
    get_legacy_friends_service,
    get_friends_only_service,
    get_discover_only_service,
    get_requests_only_service,
    get_unified_recommendations_service,
    ContactMatchRequest,
    UnifiedFriendData,
    FriendsOnlyData,
    DiscoverOnlyData,
    RequestsOnlyData,
    UnifiedRecommendationsData
)

router = APIRouter()

# =============================================================================
# CORE FRIEND OPERATIONS
# =============================================================================

@router.post("/", response_model=FriendRequest)
async def add_friend(
    request: Request,
    friend: FriendCreate,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    MODIFIED: Now sends friend request instead of creating immediate friendship.
    For backwards compatibility, this endpoint still accepts FriendCreate but sends a request.
    """
    return await add_friend_service(friend, current_user, supabase)

@router.get("/user/{user_id}", response_model=List[FriendWithDetails])
async def get_user_friends(
    user_id: str, 
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    # Users can only view their own friends list
    if str(current_user.id) != user_id:
        raise HTTPException(status_code=403, detail="Not authorized to access this user's friends list")
    
    return await get_user_friends_service(user_id, supabase)

@router.get("/search", response_model=List[UserSearchResult])
async def search_users(
    query: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Search for all users on the app by username (name field).
    Returns users with their relationship status to the current user.
    Uses unified RPC approach with caching for optimal performance and consistency.
    """
    return await search_users_service(query, current_user, supabase)

@router.delete("/{friendship_id}")
async def remove_friend(
    friendship_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Remove a friendship. User must be part of the friendship to remove it."""
    return await remove_friend_service(friendship_id, current_user, supabase)

@router.get("/", response_model=List[Friend])
async def get_friends(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all friends for the current user"""
    return await get_friends_service(current_user, supabase)

# =============================================================================
# FRIEND REQUESTS
# =============================================================================

@router.post("/requests", response_model=FriendRequest)
async def send_friend_request(
    request_data: FriendRequestCreate,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Send a friend request to another user"""
    return await send_friend_request_service(request_data, current_user, supabase)

@router.get("/requests/received", response_model=List[FriendRequestWithDetails])
async def get_received_requests(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get friend requests received by the current user"""
    return await get_received_requests_service(current_user, supabase)

@router.get("/requests/sent", response_model=List[FriendRequestWithDetails])
async def get_sent_requests(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get friend requests sent by the current user"""
    return await get_sent_requests_service(current_user, supabase)

@router.post("/requests/{request_id}/accept", response_model=FriendRequestAcceptResponse)
async def accept_friend_request(
    request_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Accept a friend request"""
    return await accept_friend_request_service(request_id, current_user, supabase)

@router.post("/requests/{request_id}/decline", response_model=FriendRequestDeclineResponse)
async def decline_friend_request(
    request_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Decline a friend request"""
    return await decline_friend_request_service(request_id, current_user, supabase)

@router.delete("/requests/{request_id}", response_model=FriendRequestCancelResponse)
async def cancel_friend_request(
    request_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Cancel a friend request (sender only)"""
    return await cancel_friend_request_service(request_id, current_user, supabase)

# =============================================================================
# FRIEND RECOMMENDATIONS
# =============================================================================

@router.get("/recommendations", response_model=FriendRecommendationResponse)
async def get_friend_recommendations(
    limit: int = 10,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """Get personalized friend recommendations for the current user."""
    return await get_friend_recommendations_service(limit, current_user, supabase)

@router.post("/recommendations/{recommended_user_id}/send-request")
async def send_recommendation_request(
    recommended_user_id: UUID,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """Send a friend request to a recommended user."""
    return await send_recommendation_request_service(recommended_user_id, current_user, supabase)

@router.get("/recommendations/contacts", response_model=List[Dict[str, Any]])
async def get_friend_recommendations_from_contacts(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Get friend recommendations based on user's contact list.
    This endpoint expects the frontend to send contact information via the body.
    """
    return await get_friend_recommendations_from_contacts_service(current_user, supabase)

@router.post("/recommendations/contacts/match")
async def match_contacts_with_users(
    contacts: List[Dict[str, str]],  # Expected format: [{"name": "John", "phone": "+1234567890"}]
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Match the provided contacts with existing users and return friend recommendations.
    """
    return await match_contacts_with_users_service(contacts, current_user, supabase)

# =============================================================================
# RELATIONSHIP DATA ENDPOINTS
# =============================================================================

@router.post("/relationships/unified", response_model=UnifiedFriendData)
async def get_unified_friend_relationships(
    contact_request: ContactMatchRequest = Body(default=ContactMatchRequest()),
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get ALL friend relationship data in a single optimized call with contact matching"""
    return await get_unified_friend_relationships_service(contact_request, current_user, supabase)

@router.get("/relationships/legacy-friends", response_model=List[Dict[str, Any]])
async def get_legacy_friends(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Legacy endpoint for backward compatibility"""
    return await get_legacy_friends_service(current_user, supabase)

@router.get("/relationships/friends-only", response_model=FriendsOnlyData)
async def get_friends_only(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get only friends data for the Friends tab"""
    return await get_friends_only_service(current_user, supabase)

@router.post("/relationships/discover-only", response_model=DiscoverOnlyData)
async def get_discover_only(
    contact_request: ContactMatchRequest = Body(default=ContactMatchRequest()),
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get only contacts on tally data for the Discover tab"""
    return await get_discover_only_service(contact_request, current_user, supabase)

@router.get("/relationships/requests-only", response_model=RequestsOnlyData)
async def get_requests_only(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get only friend requests data for the Requests tab"""
    return await get_requests_only_service(current_user, supabase)

@router.post("/relationships/unified-recommendations", response_model=UnifiedRecommendationsData)
async def get_unified_recommendations(
    contact_request: ContactMatchRequest = Body(default=ContactMatchRequest()),
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get unified recommendations combining contacts on tally and friend recommendations for the Discover tab"""
    return await get_unified_recommendations_service(contact_request, current_user, supabase) 