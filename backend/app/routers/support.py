from fastapi import APIRouter, Depends, HTTPException
from models.schemas import SupportMessage, SupportMessageCreate, User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from typing import List
from routers.auth import get_current_user
import logging

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/messages", response_model=SupportMessage)
async def create_support_message(
    message: SupportMessageCreate,
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Send a support/feedback message"""
    try:
        # Create the support message data
        message_data = {
            "user_id": str(current_user.id),
            "message": message.message
        }
        
        # Insert into database
        result = await supabase.table("support_messages").insert(message_data).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to send message")
            
        logger.info(f"Created support message {result.data[0]['id']} for user {current_user.id}")
        
        return SupportMessage(**result.data[0])
        
    except Exception as e:
        logger.error(f"Error creating support message: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to send message: {str(e)}")


@router.get("/messages", response_model=List[SupportMessage])
async def get_user_support_messages(
    current_user: User = Depends(get_current_user),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get all support messages for the current user"""
    try:
        # Get messages ordered by created_at descending (newest first)
        result = await supabase.table("support_messages")\
            .select("*")\
            .eq("user_id", str(current_user.id))\
            .order("created_at", desc=True)\
            .execute()
        
        return [SupportMessage(**msg) for msg in result.data]
        
    except Exception as e:
        logger.error(f"Error fetching support messages: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch messages: {str(e)}")