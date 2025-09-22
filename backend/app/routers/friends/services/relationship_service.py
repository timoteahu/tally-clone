from fastapi import HTTPException, Body
from models.schemas import User
from supabase._async.client import AsyncClient
from typing import List, Optional, Dict, Any
from pydantic import BaseModel
import re
from uuid import UUID
from utils.memory_optimization import memory_optimized
from utils.memory_monitoring import memory_profile

class ContactMatchRequest(BaseModel):
    phone_numbers: Optional[List[str]] = None

class UnifiedFriendData(BaseModel):
    friends: List[Dict[str, Any]]
    received_friend_requests: List[Dict[str, Any]]
    sent_friend_requests: List[Dict[str, Any]]
    contacts_on_tally: List[Dict[str, Any]]
    total_count: int

class FriendsOnlyData(BaseModel):
    friends: List[Dict[str, Any]]
    total_count: int

class DiscoverOnlyData(BaseModel):
    contacts_on_tally: List[Dict[str, Any]]
    total_count: int

class RequestsOnlyData(BaseModel):
    received_friend_requests: List[Dict[str, Any]]
    sent_friend_requests: List[Dict[str, Any]]
    total_count: int

class UnifiedRecommendationsData(BaseModel):
    contacts_on_tally: List[Dict[str, Any]]
    friend_recommendations: List[Dict[str, Any]]
    total_count: int

@memory_optimized(cleanup_args=False)
@memory_profile("relationship_service_unified")
async def get_unified_friend_relationships_service(
    contact_request: ContactMatchRequest,
    current_user: User,
    supabase: AsyncClient
):
    """Get ALL friend relationship data in a single optimized call with contact matching"""
    try:
        user_id = str(current_user.id)
        
        # Clean and normalize phone numbers if provided
        phone_numbers = None
        if contact_request.phone_numbers:
            cleaned_numbers = []
            for phone in contact_request.phone_numbers:
                # Remove any non-digit characters except +
                cleaned = re.sub(r'[^\d+]', '', phone)
                
                # Normalize phone numbers (remove +1 prefix if present)
                if cleaned.startswith('+1') and len(cleaned) == 12:
                    normalized = cleaned[2:]  # Remove +1
                elif cleaned.startswith('1') and len(cleaned) == 11:
                    normalized = cleaned[1:]  # Remove leading 1
                else:
                    normalized = cleaned
                cleaned_numbers.append(normalized)

            phone_numbers = cleaned_numbers
        
        # Choose function based on whether we have contact phone numbers
        if phone_numbers:
            result = await supabase.rpc("get_user_all_friend_data", {
                "user_id_param": user_id,
                "contact_phone_numbers": phone_numbers
            }).execute()
        else:
            result = await supabase.rpc("get_user_all_friend_data_no_contacts", {
                "user_id_param": user_id
            }).execute()
        
        # Process and separate the unified data
        friends = []
        received_requests = []
        sent_requests = []
        contacts_on_tally = []
        
        if result.data:
            for row in result.data:
                data_type = row.get('data_type')
                
                # Build common user data
                user_data = {
                    "id": str(row['user_id']),
                    "name": row.get('name', ''),
                    "phone_number": row.get('phone_number', ''),
                    "avatar_version": row.get('avatar_version'),
                    "avatar_url_80": row.get('avatar_url_80'),
                    "avatar_url_200": row.get('avatar_url_200'),
                    "avatar_url_original": row.get('avatar_url_original'),
                    "created_at": row.get('created_at')
                }
                
                if data_type == 'friend':
                    friends.append({
                        **user_data,
                        "friend_id": str(row['user_id']),
                        "friendship_id": row.get('friendship_id')
                    })
                
                elif data_type == 'received_request':
                    received_requests.append({
                        "id": row.get('request_id'),
                        "sender_id": str(row['user_id']),
                        "sender_name": row.get('name', ''),
                        "sender_phone": row.get('phone_number', ''),
                        "sender_avatar_version": row.get('avatar_version'),
                        "sender_avatar_url_80": row.get('avatar_url_80'),
                        "sender_avatar_url_200": row.get('avatar_url_200'),
                        "sender_avatar_url_original": row.get('avatar_url_original'),
                        "message": row.get('message', ''),
                        "status": row.get('request_status', 'pending'),
                        "created_at": row.get('created_at')
                    })
                
                elif data_type == 'sent_request':
                    sent_requests.append({
                        "id": row.get('request_id'),
                        "receiver_id": str(row['user_id']),
                        "receiver_name": row.get('name', ''),
                        "receiver_phone": row.get('phone_number', ''),
                        "receiver_avatar_version": row.get('avatar_version'),
                        "receiver_avatar_url_80": row.get('avatar_url_80'),
                        "receiver_avatar_url_200": row.get('avatar_url_200'),
                        "receiver_avatar_url_original": row.get('avatar_url_original'),
                        "message": row.get('message', ''),
                        "status": row.get('request_status', 'pending'),
                        "created_at": row.get('created_at')
                    })
                
                elif data_type == 'contact_on_tally':
                    contacts_on_tally.append({
                        **user_data,
                        "user_id": str(row['user_id']),
                        "is_existing_user": True
                    })
        
        total_count = len(friends) + len(received_requests) + len(sent_requests) + len(contacts_on_tally)
        
        return UnifiedFriendData(
            friends=friends,
            received_friend_requests=received_requests,
            sent_friend_requests=sent_requests,
            contacts_on_tally=contacts_on_tally,
            total_count=total_count
        )
        
    except Exception as e:
        print(f"Error in get_unified_friend_relationships_service: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("relationship_service_legacy_friends")
async def get_legacy_friends_service(
    current_user: User,
    supabase: AsyncClient
):
    """Legacy endpoint for backward compatibility"""
    try:
        user_id = str(current_user.id)
        
        result = await supabase.rpc("get_user_all_friend_data", {
            "user_id_param": user_id
        }).execute()
        
        friends = []
        if result.data:
            for row in result.data:
                if row.get('data_type') == 'friend':
                    friends.append({
                        "id": str(row['user_id']),
                        "friend_id": str(row['user_id']),
                        "name": row.get('name', ''),
                        "phone_number": row.get('phone_number', ''),
                        "avatar_version": row.get('avatar_version'),
                        "avatar_url_80": row.get('avatar_url_80'),
                        "avatar_url_200": row.get('avatar_url_200'),
                        "avatar_url_original": row.get('avatar_url_original'),
                        "created_at": row.get('created_at')
                    })
        
        return friends
        
    except Exception as e:
        print(f"Error in get_legacy_friends_service: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("relationship_service_friends_only")
async def get_friends_only_service(
    current_user: User,
    supabase: AsyncClient
):
    """Get only friends data for the Friends tab"""
    try:
        user_id = str(current_user.id)
        
        # Use the existing database function but filter for friends only
        result = await supabase.rpc("get_user_all_friend_data", {
            "user_id_param": user_id
        }).execute()
        
        friends = []
        if result.data:
            for row in result.data:
                if row.get('data_type') == 'friend':
                    user_data = {
                        "id": str(row['user_id']),
                        "name": row.get('name', ''),
                        "phone_number": row.get('phone_number', ''),
                        "avatar_version": row.get('avatar_version'),
                        "avatar_url_80": row.get('avatar_url_80'),
                        "avatar_url_200": row.get('avatar_url_200'),
                        "avatar_url_original": row.get('avatar_url_original'),
                        "created_at": row.get('created_at'),
                        "last_active": row.get('last_active')
                    }
                    
                    friends.append({
                        **user_data,
                        "friend_id": str(row['user_id']),
                        "friendship_id": row.get('friendship_id'),
                        "last_active": row.get('last_active')
                    })
        
        return FriendsOnlyData(
            friends=friends,
            total_count=len(friends)
        )
        
    except Exception as e:
        print(f"Error in get_friends_only_service: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("relationship_service_discover_only")
async def get_discover_only_service(
    contact_request: ContactMatchRequest,
    current_user: User,
    supabase: AsyncClient
):
    """Get only contacts on tally data for the Discover tab"""
    try:
        user_id = str(current_user.id)
        
        # Clean and normalize phone numbers if provided
        phone_numbers = None
        if contact_request.phone_numbers:
            cleaned_numbers = []
            for phone in contact_request.phone_numbers:
                # Remove any non-digit characters except +
                cleaned = re.sub(r'[^\d+]', '', phone)
                
                # Normalize phone numbers (remove +1 prefix if present)
                if cleaned.startswith('+1') and len(cleaned) == 12:
                    normalized = cleaned[2:]  # Remove +1
                elif cleaned.startswith('1') and len(cleaned) == 11:
                    normalized = cleaned[1:]  # Remove leading 1
                else:
                    normalized = cleaned
                cleaned_numbers.append(normalized)

            phone_numbers = cleaned_numbers
        
        # Only call with contacts if we have them
        if phone_numbers:
            result = await supabase.rpc("get_user_all_friend_data", {
                "user_id_param": user_id,
                "contact_phone_numbers": phone_numbers
            }).execute()
        else:
            # Return empty data if no contacts provided
            return DiscoverOnlyData(
                contacts_on_tally=[],
                total_count=0
            )
        
        contacts_on_tally = []
        if result.data:
            for row in result.data:
                if row.get('data_type') == 'contact_on_tally':
                    user_data = {
                        "id": str(row['user_id']),
                        "name": row.get('name', ''),
                        "phone_number": row.get('phone_number', ''),
                        "avatar_version": row.get('avatar_version'),
                        "avatar_url_80": row.get('avatar_url_80'),
                        "avatar_url_200": row.get('avatar_url_200'),
                        "avatar_url_original": row.get('avatar_url_original'),
                        "created_at": row.get('created_at')
                    }
                    
                    contacts_on_tally.append({
                        **user_data,
                        "user_id": str(row['user_id']),
                        "is_existing_user": True
                    })
        
        return DiscoverOnlyData(
            contacts_on_tally=contacts_on_tally,
            total_count=len(contacts_on_tally)
        )
        
    except Exception as e:
        print(f"Error in get_discover_only_service: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("relationship_service_requests_only")
async def get_requests_only_service(
    current_user: User,
    supabase: AsyncClient
):
    """Get only friend requests data for the Requests tab"""
    try:
        user_id = str(current_user.id)
        
        # Use the existing database function but filter for requests only
        result = await supabase.rpc("get_user_all_friend_data", {
            "user_id_param": user_id
        }).execute()
        
        received_requests = []
        sent_requests = []
        
        if result.data:
            for row in result.data:
                data_type = row.get('data_type')
                
                if data_type == 'received_request':
                    received_requests.append({
                        "id": row.get('request_id'),
                        "sender_id": str(row['user_id']),
                        "sender_name": row.get('name', ''),
                        "sender_phone": row.get('phone_number', ''),
                        "sender_avatar_version": row.get('avatar_version'),
                        "sender_avatar_url_80": row.get('avatar_url_80'),
                        "sender_avatar_url_200": row.get('avatar_url_200'),
                        "sender_avatar_url_original": row.get('avatar_url_original'),
                        "message": row.get('message', ''),
                        "status": row.get('request_status', 'pending'),
                        "created_at": row.get('created_at')
                    })
                
                elif data_type == 'sent_request':
                    sent_requests.append({
                        "id": row.get('request_id'),
                        "receiver_id": str(row['user_id']),
                        "receiver_name": row.get('name', ''),
                        "receiver_phone": row.get('phone_number', ''),
                        "receiver_avatar_version": row.get('avatar_version'),
                        "receiver_avatar_url_80": row.get('avatar_url_80'),
                        "receiver_avatar_url_200": row.get('avatar_url_200'),
                        "receiver_avatar_url_original": row.get('avatar_url_original'),
                        "message": row.get('message', ''),
                        "status": row.get('request_status', 'pending'),
                        "created_at": row.get('created_at')
                    })
        
        total_count = len(received_requests) + len(sent_requests)
        
        return RequestsOnlyData(
            received_friend_requests=received_requests,
            sent_friend_requests=sent_requests,
            total_count=total_count
        )
        
    except Exception as e:
        print(f"Error in get_requests_only_service: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@memory_optimized(cleanup_args=False)
@memory_profile("relationship_service_unified_recommendations")
async def get_unified_recommendations_service(
    contact_request: ContactMatchRequest,
    current_user: User,
    supabase: AsyncClient
):
    """Get unified recommendations combining contacts on tally and friend recommendations for the Discover tab"""
    try:
        user_id = str(current_user.id)
        
        # 1. Get friend recommendations from the corrected database function
        recommendations_result = await supabase.rpc("generate_friend_recommendations", {
            "user_id_param": user_id,
            "limit_param": 20
        }).execute()

        friend_recommendations = []
        recommended_user_ids = set() # Set to store IDs for de-duplication
        if recommendations_result.data:
            for row in recommendations_result.data:
                recommended_id = row.get('out_recommended_user_id')
                if recommended_id:
                    friend_recommendations.append({
                        "recommended_user_id": recommended_id,
                        "user_name": row.get('out_user_name'),
                        "mutual_friends_count": row.get('out_mutual_friends_count'),
                        "mutual_friends_preview": row.get('out_mutual_friends_preview'),
                        "recommendation_reason": row.get('out_recommendation_reason'),
                        "total_score": row.get('out_total_score'),
                        "avatar_version": row.get('out_avatar_version'),
                        "avatar_url_80": row.get('out_avatar_url_80'),
                        "avatar_url_200": row.get('out_avatar_url_200'),
                        "avatar_url_original": row.get('out_avatar_url_original'),
                    })
                    recommended_user_ids.add(recommended_id)

        # 2. Get contacts on Tally, calling the correct database function
        phone_numbers = None
        if contact_request.phone_numbers:
            cleaned_numbers = []
            for phone in contact_request.phone_numbers:
                cleaned = re.sub(r'[^\d+]', '', phone)
                if cleaned.startswith('+1') and len(cleaned) == 12:
                    normalized = cleaned[2:]
                elif cleaned.startswith('1') and len(cleaned) == 11:
                    normalized = cleaned[1:]
                else:
                    normalized = cleaned
                cleaned_numbers.append(normalized)
            phone_numbers = cleaned_numbers
            
        rpc_params = {"user_id_param": user_id}
        if phone_numbers:
            rpc_params["contact_phone_numbers"] = phone_numbers
        
        contacts_result = await supabase.rpc("get_user_all_friend_data", rpc_params).execute()

        contacts_on_tally = []
        if contacts_result.data:
            for row in contacts_result.data:
                if row.get('data_type') == 'contact_on_tally':
                    user_id_str = str(row['user_id'])
                    
                    # De-duplication: Only add contact if not already in friend_recommendations
                    if user_id_str not in recommended_user_ids:
                        contacts_on_tally.append({
                            "id": user_id_str,
                            "user_id": user_id_str,
                            "name": row.get('name', ''),
                            "phone_number": row.get('phone_number', ''),
                            "avatar_version": row.get('avatar_version'),
                            "avatar_url_80": row.get('avatar_url_80'),
                            "avatar_url_200": row.get('avatar_url_200'),
                            "avatar_url_original": row.get('avatar_url_original'),
                            "created_at": row.get('created_at'),
                            "is_existing_user": True
                        })
        
        total_count = len(contacts_on_tally) + len(friend_recommendations)
        
        return UnifiedRecommendationsData(
            contacts_on_tally=contacts_on_tally,
            friend_recommendations=friend_recommendations,
            total_count=total_count
        )
        
    except Exception as e:
        # Improved error logging
        import traceback
        print(f"Error in get_unified_recommendations_service: {e}")
        print(traceback.format_exc())
        
        # Try to extract Postgres error details if available
        if hasattr(e, 'details'):
            raise HTTPException(status_code=500, detail=e.details)
        
        raise HTTPException(status_code=500, detail=str(e)) 