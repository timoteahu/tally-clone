from fastapi import APIRouter, Depends, HTTPException, status
from typing import Optional
from datetime import datetime
from models.schemas import (
    Invite, InviteCreate, User, BranchInviteAcceptResponse
)
from routers.auth import get_current_user_lightweight
from config.database import get_supabase_client
from supabase import Client
import logging
from uuid import UUID

logger = logging.getLogger(__name__)
router = APIRouter()

# DEPRECATED: Invite creation is now handled by frontend Branch.io integration
# This router is maintained for backward compatibility only

@router.get("/lookup/{inviter_id}")
async def lookup_invite(
    inviter_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Look up an active invite by inviter user ID.
    
    DEPRECATED: This endpoint is maintained for backward compatibility.
    New invites are handled via frontend Branch.io integration.
    """
    try:
        # Check for active (non-expired) invite
        result = supabase.table("invites").select("*").eq(
            "inviter_user_id", inviter_id
        ).eq(
            "invite_status", "pending"
        ).gt(
            "expires_at", datetime.utcnow().isoformat()
        ).order("created_at", desc=True).limit(1).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=404,
                detail="No active invite found for this user"
            )
        
        invite_data = result.data[0]
        
        return Invite(
            id=invite_data["id"],
            inviter_user_id=invite_data["inviter_user_id"],
            invite_link=invite_data["invite_link"],
            habit_id=invite_data.get("habit_id"),
            invited_user_id=invite_data.get("invited_user_id"),
            invite_status=invite_data["invite_status"],
            expires_at=invite_data["expires_at"],
            created_at=invite_data["created_at"],
            updated_at=invite_data.get("updated_at")
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to lookup invite: {str(e)}"
        )

@router.post("/branch-accept/{inviter_id}", response_model=BranchInviteAcceptResponse)
async def accept_branch_invite(
    inviter_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Accept a Branch.io invite by creating immediate friendship.
    This endpoint is used for Branch.io invite acceptance and creates 
    an immediate friendship between the inviter and current user.
    """
    print(f"🎯 [accept_branch_invite] Called with inviter_id: {inviter_id}")
    print(f"👤 [accept_branch_invite] Current user: {current_user.name} (ID: {current_user.id})")
    
    try:
        # Prevent self-invitation
        if str(current_user.id) == str(inviter_id):
            print(f"🚫 [accept_branch_invite] Self-invitation detected")
            raise HTTPException(
                status_code=400,
                detail="Cannot accept your own invite"
            )

        print(f"🔍 [accept_branch_invite] Checking for existing friendship...")
        # Convert both IDs to UUID objects for safe comparison then sort
        try:
            inviter_uuid = UUID(str(inviter_id))
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid inviter_id format")

        current_uuid = current_user.id if isinstance(current_user.id, UUID) else UUID(str(current_user.id))

        # Sort to ensure consistent ordering regardless of invitation direction
        sorted_ids = sorted([current_uuid, inviter_uuid])
        user1_id, user2_id = map(str, sorted_ids)
        print(f"🔍 [accept_branch_invite] Checking relationship between {user1_id} and {user2_id}")
        
        existing_relationship = supabase.table("user_relationships").select("*").eq(
            "user1_id", user1_id
        ).eq(
            "user2_id", user2_id
        ).execute()
        
        print(f"📋 [accept_branch_invite] Existing relationships found: {len(existing_relationship.data)}")
        if existing_relationship.data:
            print(f"📋 [accept_branch_invite] Existing relationship: {existing_relationship.data[0]}")
        
        if existing_relationship.data:
            print(f"❌ [accept_branch_invite] Friendship already exists")
            raise HTTPException(
                status_code=400,
                detail="Friendship already exists"
            )

        print(f"🔍 [accept_branch_invite] Verifying inviter exists...")
        # Verify that the inviter exists
        inviter_result = supabase.table("users").select("id, name").eq("id", inviter_id).execute()
        print(f"📋 [accept_branch_invite] Inviter query result: {len(inviter_result.data)} users found")
        
        if not inviter_result.data:
            print(f"❌ [accept_branch_invite] Inviter not found in database")
            raise HTTPException(
                status_code=404,
                detail="Inviter not found"
            )
        
        inviter_name = inviter_result.data[0]["name"]
        print(f"✅ [accept_branch_invite] Inviter found: {inviter_name}")

        print(f"🔄 [accept_branch_invite] Creating friend request...")
        # Create friendship using the friend request system (from inviter to current user)
        send_result = supabase.rpc("send_friend_request_simple", {
            "sender_id": str(inviter_id),
            "receiver_id": str(current_user.id),
            "message": f"Friendship via Branch invite from {inviter_name}"
        }).execute()
        
        print(f"📋 [accept_branch_invite] Send request result: {send_result.data}")
        
        if not send_result.data or send_result.data[0].get('error'):
            error_msg = send_result.data[0].get('error') if send_result.data else "Unknown error"
            print(f"❌ [accept_branch_invite] Failed to create friend request: {error_msg}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to create friend request: {error_msg}"
            )
        
        # Get the relationship ID from the response
        relationship_id = send_result.data[0].get('relationship_id')
        print(f"📋 [accept_branch_invite] Relationship ID: {relationship_id}")
        
        if not relationship_id:
            print(f"❌ [accept_branch_invite] No relationship ID returned")
            raise HTTPException(
                status_code=500,
                detail="Failed to create friend request - no relationship ID returned"
            )

        print(f"🔄 [accept_branch_invite] Accepting friend request...")
        # Accept the friend request immediately to create the friendship
        accept_result = supabase.rpc("accept_friend_request_simple", {
            "relationship_id": relationship_id,
            "accepting_user_id": str(current_user.id)
        }).execute()
        
        print(f"📋 [accept_branch_invite] Accept request result: {accept_result.data}")
        
        if not accept_result.data or accept_result.data[0].get('error'):
            error_msg = accept_result.data[0].get('error') if accept_result.data else "Unknown error"
            print(f"❌ [accept_branch_invite] Failed to accept friend request: {error_msg}")
            raise HTTPException(
                status_code=500,
                detail=f"Failed to accept friend request: {error_msg}"
            )

        print(f"�� [accept_branch_invite] Branch invite acceptance successful!")
        response = {
            "message": f"Successfully connected with {inviter_name}!",
            "friendship_created": True,
            "inviter_id": inviter_id,
            "inviter_name": inviter_name
        }
        print(f"📋 [accept_branch_invite] Returning response: {response}")
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ [accept_branch_invite] Unexpected error: {str(e)}")
        import traceback
        print(f"❌ [accept_branch_invite] Traceback: {traceback.format_exc()}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to accept Branch invite: {str(e)}"
        )

@router.post("/accept/{invite_id}")
async def accept_invite(
    invite_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Accept an invite and create friendship.
    
    DEPRECATED: This endpoint is maintained for backward compatibility.
    New invite acceptance is handled via frontend Branch.io integration
    and uses the friend_requests system directly.
    """
    try:
        # Get the invite
        result = supabase.table("invites").select("*").eq("id", invite_id).execute()
        
        if not result.data:
            raise HTTPException(
                status_code=404,
                detail="Invite not found"
            )
        
        invite = result.data[0]
        
        # Check if invite is still valid
        if invite["invite_status"] != "pending":
            raise HTTPException(
                status_code=400,
                detail="Invite has already been used"
            )
        
        if datetime.fromisoformat(invite["expires_at"].replace('Z', '+00:00')) < datetime.utcnow().replace(tzinfo=None):
            raise HTTPException(
                status_code=400,
                detail="Invite has expired"
            )
        
        # Prevent self-invitation
        if str(current_user.id) == str(invite["inviter_user_id"]):
            raise HTTPException(
                status_code=400,
                detail="Cannot accept your own invite"
            )
        
        # Check if friendship already exists
        user1_id = str(min(current_user.id, invite['inviter_user_id']))
        user2_id = str(max(current_user.id, invite['inviter_user_id']))
        
        existing_relationship = supabase.table("user_relationships").select("*").eq(
            "user1_id", user1_id
        ).eq(
            "user2_id", user2_id
        ).execute()
        
        if existing_relationship.data:
            raise HTTPException(
                status_code=400,
                detail="Relationship already exists"
            )
        
        # Create friendship using the friend request system
        send_result = supabase.rpc("send_friend_request_simple", {
            "sender_id": str(invite["inviter_user_id"]),
            "receiver_id": str(current_user.id),
            "message": "Friendship via legacy invite acceptance"
        }).execute()
        
        if not send_result.data or send_result.data[0].get('error'):
            raise HTTPException(
                status_code=500,
                detail="Failed to create friend request"
            )
        
        # Accept the friend request immediately
        friend_request_id = send_result.data[0].get('request_id')
        if friend_request_id:
            accept_result = supabase.rpc("accept_friend_request_simple", {
                "request_id": friend_request_id,
                "accepter_id": str(current_user.id)
            }).execute()
            
            if not accept_result.data or accept_result.data[0].get('error'):
                raise HTTPException(
                    status_code=500,
                    detail="Failed to accept friend request"
                )
        
        # Update invite status
        supabase.table("invites").update({
            "invite_status": "accepted",
            "invited_user_id": str(current_user.id),
            "updated_at": datetime.utcnow().isoformat()
        }).eq("id", invite_id).execute()
        
        return {
            "message": "Invite accepted successfully",
            "friendship_created": True,
            "invite_id": invite_id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to accept invite: {str(e)}"
        )

@router.get("/user/{user_id}")
async def get_user_invites(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Get all invites for a specific user.
    
    DEPRECATED: This endpoint is maintained for backward compatibility.
    New invites are handled via frontend Branch.io integration.
    """
    try:
        # Only allow users to see their own invites
        if str(current_user.id) != user_id:
            raise HTTPException(
                status_code=403,
                detail="Not authorized to view these invites"
            )
        
        result = supabase.table("invites").select("*").eq(
            "inviter_user_id", user_id
        ).order("created_at", desc=True).execute()
        
        invites = []
        for invite_data in result.data:
            invites.append(Invite(
                id=invite_data["id"],
                inviter_user_id=invite_data["inviter_user_id"],
                invite_link=invite_data["invite_link"],
                habit_id=invite_data.get("habit_id"),
                invited_user_id=invite_data.get("invited_user_id"),
                invite_status=invite_data["invite_status"],
                expires_at=invite_data["expires_at"],
                created_at=invite_data["created_at"],
                updated_at=invite_data.get("updated_at")
            ))
        
        return invites
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get user invites: {str(e)}"
        ) 