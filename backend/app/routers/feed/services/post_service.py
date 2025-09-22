from typing import Optional, Dict
from fastapi import HTTPException
from supabase._async.client import AsyncClient
from models.schemas import FeedPost, Comment, User
from ..utils.image_utils import generate_post_image_urls
from utils.memory_cleanup import _cleanup_memory
from utils.memory_optimization import disable_print
import logging

logger = logging.getLogger(__name__)
print = disable_print()


async def update_post_caption(
    verification_id: Optional[str],
    post_id: Optional[str],
    caption: str,
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, str]:
    """
    Update the caption of a post.
    Memory optimized with explicit cleanup.
    """
    verification_result = None
    post_result = None
    
    try:
        if not verification_id and not post_id:
            print("❌ [UpdateCaption] Either verification_id or post_id is required")
            raise HTTPException(status_code=400, detail="Either verification_id or post_id is required")
        
        user_id = str(current_user.id)
        
        if verification_id:
            # Handle verification_id case (preview posts)
            verification_result = await supabase.table("habit_verifications") \
                .select("id, user_id") \
                .eq("id", verification_id) \
                .eq("user_id", user_id) \
                .execute()
            
            if not verification_result.data:
                raise HTTPException(status_code=404, detail="Verification not found or not accessible")
            
            # Cleanup verification_result early
            _cleanup_memory(verification_result)
            verification_result = None
            
            # Update the corresponding post if it exists
            post_result = await supabase.table("posts") \
                .select("id") \
                .eq("habit_verification_id", verification_id) \
                .execute()
            
            if not post_result.data:
                raise HTTPException(status_code=404, detail="Post not found for this verification")
            
            # Cleanup post_result early
            _cleanup_memory(post_result)
            post_result = None
            
            # Update the post with the new caption
            await supabase.table("posts") \
                .update({"caption": caption if caption else "Habit verification completed"}) \
                .eq("habit_verification_id", verification_id) \
                .execute()
                
        elif post_id:
            # Handle post_id case (published feed posts)
            post_result = await supabase.table("posts") \
                .select("id, user_id") \
                .eq("id", post_id) \
                .eq("user_id", user_id) \
                .execute()
            
            if not post_result.data:
                raise HTTPException(status_code=404, detail="Post not found or not accessible")
            
            # Cleanup post_result early
            _cleanup_memory(post_result)
            post_result = None
            
            # Update the post with the new caption
            await supabase.table("posts") \
                .update({"caption": caption if caption else "Habit verification completed"}) \
                .eq("id", post_id) \
                .execute()
        
        return {"message": "Caption updated successfully", "caption": caption}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ [UpdateCaption] Error updating caption: {e}")
        # Cleanup on error
        _cleanup_memory(verification_result, post_result)
        raise HTTPException(status_code=500, detail="Failed to update caption")


async def get_post_by_verification_id(
    verification_id: str,
    current_user: User,
    supabase: AsyncClient
) -> FeedPost:
    """
    Get a post by its habit verification ID.
    Memory optimized with explicit cleanup.
    """
    post_result = None
    user_result = None
    habit_result = None
    comments_result = None
    comment_users_result = None
    image_urls = None
    
    try:
        user_id = str(current_user.id)
        
        # Get the post by verification ID and ensure it belongs to the current user
        post_result = await supabase.table("posts") \
            .select("*") \
            .eq("habit_verification_id", verification_id) \
            .eq("user_id", user_id) \
            .execute()
        
        if not post_result.data:
            raise HTTPException(status_code=404, detail="Post not found or not accessible")
        
        post = post_result.data[0]
        
        # Clear post_result early, keep only the post data
        _cleanup_memory(post_result)
        post_result = None
        
        # Get user name and avatar information
        user_result = await supabase.table("users") \
            .select("name, avatar_url_80, avatar_url_200, avatar_url_original, avatar_version") \
            .eq("id", user_id) \
            .execute()
        
        user_data = user_result.data[0] if user_result.data else {}
        user_name = user_data.get("name", "Unknown User")
        user_avatar_url_80 = user_data.get("avatar_url_80")
        user_avatar_url_200 = user_data.get("avatar_url_200")
        user_avatar_url_original = user_data.get("avatar_url_original")
        user_avatar_version = user_data.get("avatar_version")
        
        # Cleanup user_result early
        _cleanup_memory(user_result)
        user_result = None
        
        # Get habit information if available
        habit_name = None
        habit_type = None
        penalty_amount = None
        streak = None
        
        if post.get("habit_id"):
            habit_result = await supabase.table("habits") \
                .select("name, habit_type, penalty_amount, streak") \
                .eq("id", post["habit_id"]) \
                .eq("user_id", user_id) \
                .execute()
            
            if habit_result.data:
                habit_data = habit_result.data[0]
                habit_name = habit_data.get("name")
                habit_type = habit_data.get("habit_type")
                penalty_amount = habit_data.get("penalty_amount")
                streak = habit_data.get("streak")
                
                # Cleanup habit data
                _cleanup_memory(habit_result, habit_data)
                habit_result = None
        
        # Generate signed URLs for post images
        image_urls = await generate_post_image_urls(supabase, post, post['is_private'])
        
        # Get comments for this post (likely empty for new posts)
        comments_result = await supabase.table("comments") \
            .select("id, content, created_at, user_id, is_edited, parent_comment_id") \
            .eq("post_id", post["id"]) \
            .order("created_at") \
            .execute()
        
        # Process comments efficiently
        comments = []
        if comments_result.data:
            raw_comments = comments_result.data
            
            # Clear comments_result early
            _cleanup_memory(comments_result)
            comments_result = None
            
            # Get user names for comments
            comment_user_ids = list(set(comment['user_id'] for comment in raw_comments))
            comment_users_result = await supabase.table("users") \
                .select("id, name") \
                .in_("id", comment_user_ids) \
                .execute()
            
            comment_user_names = {user['id']: user['name'] for user in comment_users_result.data} if comment_users_result.data else {}
            
            # Cleanup comment users result
            _cleanup_memory(comment_users_result, comment_user_ids)
            comment_users_result = None
            
            # Process comments with memory efficiency
            for comment_data in raw_comments:
                comment = Comment(
                    id=str(comment_data['id']),
                    content=comment_data['content'],
                    created_at=comment_data['created_at'],
                    user_id=str(comment_data['user_id']),
                    user_name=comment_user_names.get(comment_data['user_id'], 'Unknown User'),
                    user_avatar_url_80=comment_data.get('user_avatar_url_80'),
                    user_avatar_url_200=comment_data.get('user_avatar_url_200'),
                    user_avatar_url_original=comment_data.get('user_avatar_url_original'),
                    user_avatar_version=comment_data.get('user_avatar_version'),
                    is_edited=comment_data['is_edited'],
                    parent_comment=None  # Simplified for new posts
                )
                comments.append(comment)
            
            # Cleanup intermediate data
            _cleanup_memory(raw_comments, comment_user_names)
        
        # Create and return FeedPost
        feed_post = FeedPost(
            post_id=str(post['id']),
            habit_id=str(post.get('habit_id')) if post.get('habit_id') else None,
            caption=post['caption'],
            created_at=post['created_at'],
            is_private=post['is_private'],
            image_url=image_urls.get('content_image_url') or image_urls.get('selfie_image_url'),
            selfie_image_url=image_urls.get('selfie_image_url'),
            content_image_url=image_urls.get('content_image_url'),
            user_id=str(post['user_id']),
            user_name=user_name,
            user_avatar_url_80=user_avatar_url_80,
            user_avatar_url_200=user_avatar_url_200,
            user_avatar_url_original=user_avatar_url_original,
            user_avatar_version=user_avatar_version,
            habit_name=habit_name,
            habit_type=habit_type,
            penalty_amount=round(float(penalty_amount), 2) if penalty_amount is not None else None,
            streak=streak,
            comments=comments
        )
        
        # Final cleanup
        _cleanup_memory(post, user_data, image_urls, comments)
        
        return feed_post
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ [FeedAPI] Error getting post by verification ID: {e}")
        # Cleanup on error
        _cleanup_memory(post_result, user_result, habit_result, comments_result, comment_users_result, image_urls)
        raise HTTPException(status_code=500, detail="Failed to get post") 