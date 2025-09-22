from typing import Optional
from supabase._async.client import AsyncClient
from utils.memory_cleanup import _cleanup_memory
from utils.memory_optimization import disable_print
import logging

logger = logging.getLogger(__name__)
print = disable_print()


async def handle_comment_notifications(
    user_id: str,
    post_id: str,
    comment_data: dict,
    parent_comment_id: Optional[str],
    supabase_client: AsyncClient
):
    """
    Handle all comment-related notifications in the background.
    Memory optimized with explicit cleanup.
    """
    try:
        # Import here to avoid circular imports
        from services.notification_service import notification_service
        
        # Handle push notifications for post author and reply target
        await send_comment_push_notifications(
            commenter_id=user_id,
            post_id=post_id,
            parent_comment_id=parent_comment_id,
            supabase_client=supabase_client
        )
        
        # Cleanup comment_data after processing
        _cleanup_memory(comment_data)
        
    except Exception as e:
        print(f"❌ [Comment Notifications] Failed to process notifications: {e}")
        # Cleanup on error
        _cleanup_memory(comment_data)
        # Don't raise the exception as this is background processing


async def send_comment_push_notifications(
    commenter_id: str,
    post_id: str,
    parent_comment_id: Optional[str],
    supabase_client: AsyncClient
):
    """
    Send push notifications for comments.
    Memory optimized with explicit cleanup.
    """
    commenter_result = None
    post_result = None
    post_creator_result = None
    verification_result = None
    habit_result = None
    parent_comment_result = None
    
    try:
        from services.notification_service import notification_service
        
        # Get commenter's name
        commenter_result = await supabase_client.table("users").select("name").eq("id", commenter_id).execute()
        commenter_name = commenter_result.data[0]["name"] if commenter_result.data else "Someone"
        
        # Cleanup commenter_result early
        _cleanup_memory(commenter_result)
        commenter_result = None
        
        # Get post details including author and habit_verification_id
        post_result = await supabase_client.table("posts") \
            .select("user_id, habit_verification_id") \
            .eq("id", post_id).execute()
        
        if not post_result.data:
            return
            
        post_author_id = str(post_result.data[0]["user_id"])
        habit_verification_id = post_result.data[0].get("habit_verification_id")
        
        # Cleanup post_result early
        _cleanup_memory(post_result)
        post_result = None
        
        # Get post creator's name
        post_creator_result = await supabase_client.table("users").select("name").eq("id", post_author_id).execute()
        post_creator_name = post_creator_result.data[0]["name"] if post_creator_result.data else "Someone"
        
        # Cleanup post_creator_result early
        _cleanup_memory(post_creator_result)
        post_creator_result = None
        
        # Get habit details from habit_verifications table
        habit_type = "habit"  # default fallback
        habit_name = "habit"  # default fallback
        
        if habit_verification_id:
            verification_result = await supabase_client.table("habit_verifications") \
                .select("verification_type, habit_id") \
                .eq("id", habit_verification_id).execute()
            
            if verification_result.data:
                habit_type = verification_result.data[0]["verification_type"]
                habit_id = verification_result.data[0].get("habit_id")
                
                # Cleanup verification_result early
                _cleanup_memory(verification_result)
                verification_result = None
                
                # Get the actual habit name from habits table
                if habit_id:
                    habit_result = await supabase_client.table("habits") \
                        .select("name") \
                        .eq("id", habit_id).execute()
                    
                    if habit_result.data:
                        habit_name = habit_result.data[0]["name"]
                    else:
                        # Fallback to habit type if habit name not found
                        habit_name = habit_type
                    
                    # Cleanup habit_result early
                    _cleanup_memory(habit_result)
                    habit_result = None
                else:
                    # Fallback to habit type if no habit_id
                    habit_name = habit_type
            else:
                # Cleanup verification_result if no data
                _cleanup_memory(verification_result)
                verification_result = None
        
        # Always notify the post author (if not commenting on their own post)
        if post_author_id != commenter_id:
            try:
                await notification_service.send_comment_notification(
                    recipient_user_id=post_author_id,
                    commenter_name=commenter_name,
                    habit_type=habit_type,
                    post_id=post_id,
                    supabase_client=supabase_client
                )
            except Exception as e:
                print(f"❌ [Comment Notifications] Failed to notify post author: {e}")
        
        # If this is a reply, also notify the parent comment author
        if parent_comment_id:
            try:
                parent_comment_result = await supabase_client.table("comments") \
                    .select("user_id") \
                    .eq("id", parent_comment_id).execute()
                
                if parent_comment_result.data:
                    parent_author_id = str(parent_comment_result.data[0]["user_id"])
                    
                    # Notify parent comment author (if different from commenter and post author)
                    if parent_author_id != commenter_id and parent_author_id != post_author_id:
                        await notification_service.send_reply_notification(
                            recipient_user_id=parent_author_id,
                            commenter_name=commenter_name,
                            post_id=post_id,
                            post_creator_name=post_creator_name,
                            habit_name=habit_name,
                            supabase_client=supabase_client
                        )
                    
                    # Cleanup parent_comment_result
                    _cleanup_memory(parent_comment_result)
                    parent_comment_result = None
                    
            except Exception as e:
                print(f"❌ [Comment Notifications] Failed to notify parent comment author: {e}")
                # Cleanup on error
                _cleanup_memory(parent_comment_result)
            
    except Exception as e:
        print(f"❌ [Comment Notifications] Failed to send push notifications: {e}")
        # Cleanup on error
        _cleanup_memory(
            commenter_result, post_result, post_creator_result, 
            verification_result, habit_result, parent_comment_result
        ) 