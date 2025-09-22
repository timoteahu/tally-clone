from fastapi import HTTPException, status
from models.schemas import FriendRecommendation, FriendRecommendationResponse, User
from config.database import get_supabase_client
from supabase import Client
from typing import List, Dict, Any
from uuid import UUID
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile

@memory_optimized(cleanup_args=False)
@memory_profile("recommendation_service_get")
async def get_friend_recommendations_service(
    limit: int,
    current_user: User,
    supabase: Client
):
    """Get personalized friend recommendations for the current user."""
    try:
        # Call the database function to generate recommendations
        result = supabase.rpc(
            "generate_friend_recommendations",
            {
                "user_id_param": str(current_user.id),
                "limit_param": limit
            }
        ).execute()

        if not result.data:
            return FriendRecommendationResponse(recommendations=[])

        recommendations = []
        for rec in result.data:
            # Convert mutual friends preview from JSON to list of MutualFriend objects
            mutual_friends_preview = []
            if rec.get('mutual_friends_preview'):
                for mf in rec['mutual_friends_preview']:
                    mutual_friends_preview.append({
                        'id': UUID(mf['id']),
                        'name': mf['name']
                    })

            recommendations.append(FriendRecommendation(
                recommended_user_id=UUID(rec['recommended_user_id']),
                user_name=rec['user_name'],
                mutual_friends_count=int(rec['mutual_friends_count']),  # Convert bigint to int
                mutual_friends_preview=mutual_friends_preview,
                recommendation_reason=rec['recommendation_reason'],
                total_score=float(rec.get('total_score', 0.0)),
                avatar_version=rec.get('avatar_version'),
                avatar_url_80=rec.get('avatar_url_80'),
                avatar_url_200=rec.get('avatar_url_200'),
                avatar_url_original=rec.get('avatar_url_original')
            ))

        return FriendRecommendationResponse(recommendations=recommendations)

    except Exception as e:
        print(f"Error in get_friend_recommendations_service: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get friend recommendations: {str(e)}"
        )

@memory_optimized(cleanup_args=False)
@memory_profile("recommendation_service_send_request")
async def send_recommendation_request_service(
    recommended_user_id: UUID,
    current_user: User,
    supabase: Client
):
    """Send a friend request to a recommended user."""
    try:
        # Use the existing send_friend_request_simple function
        result = supabase.rpc(
            "send_friend_request_simple",
            {
                "sender_id": str(current_user.id),
                "receiver_id": str(recommended_user_id),
                "message": "Friend request from recommendations"
            }
        ).execute()

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
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=error_message
                )
            else:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=error_message
                )

        return {
            "message": "Friend request sent successfully",
            "request_id": result_data['relationship_id']
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in send_recommendation_request_service: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to send friend request: {str(e)}"
        )

@memory_optimized(cleanup_args=False)
@memory_profile("recommendation_service_get_contacts")
async def get_friend_recommendations_from_contacts_service(
    current_user: User,
    supabase: Client
):
    """
    Get friend recommendations based on user's contact list.
    This endpoint expects the frontend to send contact information via the body.
    """
    try:
        # Get current user's existing friends to exclude them from recommendations
        current_user_id = str(current_user.id)
        
        # Use the simplified function to get existing friends
        friends_result = supabase.rpc("get_user_friends", {
            "user_id": current_user_id
        }).execute()
        
        existing_friend_ids = set()
        if friends_result.data:
            existing_friend_ids = {friend['friend_id'] for friend in friends_result.data}
        
        # Also get pending friend requests to exclude them
        pending_result = supabase.table("user_relationships").select("user1_id, user2_id").or_(
            f"user1_id.eq.{current_user_id},user2_id.eq.{current_user_id}"
        ).eq("status", "pending").execute()
        
        pending_user_ids = set()
        if pending_result.data:
            for relationship in pending_result.data:
                if relationship['user1_id'] != current_user_id:
                    pending_user_ids.add(relationship['user1_id'])
                if relationship['user2_id'] != current_user_id:
                    pending_user_ids.add(relationship['user2_id'])
        
        # For now, return empty list as this endpoint needs contact integration
        # In a real implementation, you would:
        # 1. Accept contact list in request body
        # 2. Match phone numbers against users table
        # 3. Exclude existing friends and pending requests
        # 4. Return matched users as recommendations
        
        return []
        
    except Exception as e:
        print(f"Error getting friend recommendations: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to get friend recommendations")

@memory_optimized(cleanup_args=False)
@memory_profile("recommendation_service_match_contacts")
async def match_contacts_with_users_service(
    contacts: List[Dict[str, str]],
    current_user: User,
    supabase: Client
):
    """
    Match the provided contacts with existing users and return friend recommendations.
    """
    try:
        # This would contain the implementation for matching contacts with users
        # For now, return empty list as this requires contact integration
        return []
        
    except Exception as e:
        print(f"Error in match_contacts_with_users_service: {str(e)}")
        raise HTTPException(status_code=500, detail="Failed to match contacts with users") 