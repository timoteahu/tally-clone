from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import List, Optional
import logging
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user_lightweight
from datetime import datetime

router = APIRouter()
logger = logging.getLogger(__name__)

# Request/Response models
class DeviceTokenRequest(BaseModel):
    token: str
    platform: str  # "ios" or "android"

class DeviceTokenResponse(BaseModel):
    id: str
    token: str
    platform: str
    created_at: datetime
    is_active: bool

@router.post("/register-device-token")
async def register_device_token(
    device_token: DeviceTokenRequest,
    current_user=Depends(get_current_user_lightweight),  # Use lightweight auth - no profile image generation
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Register a device token for push notifications"""
    try:
        # Fix: Access User object attributes, not dict keys
        user_id = str(current_user.id) if hasattr(current_user, 'id') else str(current_user["id"])
        
        # First check if token exists globally (since token has unique constraint)
        existing_result = await supabase.table("device_tokens").select("*").eq("token", device_token.token).execute()
        
        if existing_result.data:
            existing_token = existing_result.data[0]
            
            # If token exists for current user
            if existing_token["user_id"] == user_id:
                if not existing_token["is_active"]:
                    # Reactivate the token
                    update_result = await supabase.table("device_tokens").update({
                        "is_active": True,
                        "updated_at": datetime.utcnow().isoformat()
                    }).eq("id", existing_token["id"]).execute()
                    
                    if update_result.data:
                        return {"message": "Device token reactivated successfully"}
                    else:
                        raise HTTPException(status_code=500, detail="Failed to reactivate device token")
                else:
                    return {"message": "Device token already registered"}
            else:
                # Token exists for different user - transfer ownership
                update_result = await supabase.table("device_tokens").update({
                    "user_id": user_id,
                    "platform": device_token.platform,
                    "is_active": True,
                    "updated_at": datetime.utcnow().isoformat()
                }).eq("id", existing_token["id"]).execute()
                
                if update_result.data:
                    return {"message": "Device token registered successfully"}
                else:
                    raise HTTPException(status_code=500, detail="Failed to transfer device token")
        
        # Insert new device token (token doesn't exist at all)
        insert_data = {
            "user_id": user_id,
            "token": device_token.token,
            "platform": device_token.platform,
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat(),
            "is_active": True
        }
        
        insert_result = await supabase.table("device_tokens").insert(insert_data).execute()
        
        if insert_result.data:
            return {"message": "Device token registered successfully"}
        else:
            raise HTTPException(status_code=500, detail="Failed to register device token")
            
    except Exception as e:
        logger.error(f"❌ [NotificationAPI] Error registering device token: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.delete("/unregister-device-token/{token}")
async def unregister_device_token(
    token: str,
    current_user=Depends(get_current_user_lightweight),  # Use lightweight auth
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Unregister a device token (mark as inactive)"""
    try:
        # Fix: Access User object attributes, not dict keys
        user_id = str(current_user.id) if hasattr(current_user, 'id') else str(current_user["id"])
        
        # Mark the token as inactive instead of deleting
        result = await supabase.table("device_tokens").update({
            "is_active": False,
            "updated_at": datetime.utcnow().isoformat()
        }).eq("user_id", user_id).eq("token", token).execute()
        
        if result.data:
            return {"message": "Device token unregistered successfully"}
        else:
            raise HTTPException(status_code=404, detail="Device token not found")
            
    except Exception as e:
        logger.error(f"Error unregistering device token: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/device-tokens", response_model=List[DeviceTokenResponse])
async def get_user_device_tokens(
    current_user=Depends(get_current_user_lightweight),  # Use lightweight auth
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all device tokens for the current user"""
    try:
        # Fix: Access User object attributes, not dict keys
        user_id = str(current_user.id) if hasattr(current_user, 'id') else str(current_user["id"])
        
        result = await supabase.table("device_tokens").select("*").eq("user_id", user_id).eq("is_active", True).execute()
        
        if result.data:
            tokens = []
            for token_data in result.data:
                tokens.append(DeviceTokenResponse(
                    id=token_data["id"],
                    token=token_data["token"],
                    platform=token_data["platform"],
                    created_at=datetime.fromisoformat(token_data["created_at"].replace('Z', '+00:00')),
                    is_active=token_data["is_active"]
                ))
            return tokens
        else:
            return []
            
    except Exception as e:
        logger.error(f"Error getting device tokens: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/test-notification")
async def test_notification(
    current_user=Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Test endpoint to send a test push notification"""
    try:
        from services.notification_service import notification_service
        
        # Fix: Access User object attributes, not dict keys
        user_id = str(current_user.id) if hasattr(current_user, 'id') else str(current_user["id"])
        user_name = current_user.name if hasattr(current_user, 'name') else current_user.get("name", "Test User")
        
        # Send a test notification
        await notification_service.send_comment_notification(
            recipient_user_id=user_id,
            commenter_name="Test System",
            habit_type="test",
            post_id="test-post-id",
            supabase_client=supabase
        )
        
        return {"message": "Test notification sent successfully"}
        
    except Exception as e:
        logger.error(f"Error sending test notification: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/test-database")
async def test_database_connection(
    current_user=Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Test database connection and device_tokens table"""
    try:
        # Fix: Access User object attributes, not dict keys
        user_id = str(current_user.id) if hasattr(current_user, 'id') else str(current_user["id"])
        
        # Test 1: Check if table exists by querying it
        query_result = await supabase.table("device_tokens").select("*").limit(1).execute()
        
        # Test 2: Try to insert a test record
        test_insert = {
            "user_id": user_id,
            "token": "test_token_12345",
            "platform": "ios",
            "is_active": True
        }
        insert_result = await supabase.table("device_tokens").insert(test_insert).execute()
        
        # Test 3: Clean up test record
        if insert_result.data:
            delete_result = await supabase.table("device_tokens").delete().eq("token", "test_token_12345").execute()
        
        return {
            "message": "Database test completed",
            "query_success": bool(query_result.data is not None),
            "insert_success": bool(insert_result.data),
            "table_accessible": True
        }
        
    except Exception as e:
        logger.error(f"❌ [NotificationAPI] Database test failed: {e}")
        return {
            "message": "Database test failed",
            "error": str(e),
            "table_accessible": False
        }

@router.delete("/clear-all-device-tokens")
async def clear_all_device_tokens(
    current_user=Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Clear all device tokens for the current user (stop all notifications)"""
    try:
        # Fix: Access User object attributes, not dict keys
        user_id = str(current_user.id) if hasattr(current_user, 'id') else str(current_user["id"])
        
        # Mark all tokens as inactive for this user
        result = await supabase.table("device_tokens").update({
            "is_active": False,
            "updated_at": datetime.utcnow().isoformat()
        }).eq("user_id", user_id).execute()
        
        token_count = len(result.data) if result.data else 0
        
        return {"message": f"Successfully cleared {token_count} device tokens"}
        
    except Exception as e:
        logger.error(f"❌ [NotificationAPI] Error clearing device tokens: {e}")
        raise HTTPException(status_code=500, detail="Internal server error") 