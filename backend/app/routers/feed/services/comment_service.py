from typing import List, Optional, Dict
from datetime import datetime
from fastapi import HTTPException, BackgroundTasks
from pydantic import BaseModel
from supabase._async.client import AsyncClient
from models.schemas import Comment, User
from utils.activity_tracking import track_user_activity
from ..utils.comment_utils import organize_comments_flattened
from .notification_service import handle_comment_notifications
from utils.memory_cleanup import _cleanup_memory
from utils.memory_optimization import disable_print
import uuid
import logging

logger = logging.getLogger(__name__)
print = disable_print()


class CommentCreate(BaseModel):
    post_id: str
    content: str
    parent_comment_id: Optional[str] = None


async def create_new_comment(
    comment_data: CommentCreate,
    current_user: User,
    background_tasks: BackgroundTasks,
    supabase: AsyncClient
) -> Comment:
    """
    Create a new comment on a post.
    Memory optimized with explicit cleanup.
    """
    post_result = None
    parent_result = None
    reply_target_user_result = None
    result = None
    
    try:
        user_id = str(current_user.id)
        comment_id = str(uuid.uuid4())
        
        # Validate that the post exists
        post_result = await supabase.table("posts").select("id").eq("id", comment_data.post_id).execute()
        if not post_result.data:
            raise HTTPException(status_code=404, detail="Post not found")
        
        # Clean up post_result early
        _cleanup_memory(post_result)
        post_result = None
        
        # If parent_comment_id is provided, validate it exists and get the parent comment details
        actual_reply_target = None
        
        if comment_data.parent_comment_id:
            parent_result = await supabase.table("comments").select("id, parent_comment_id, user_id, content, created_at, is_edited").eq("id", comment_data.parent_comment_id).execute()
            if not parent_result.data:
                print(f"❌ [CREATE_COMMENT] Parent comment not found: {comment_data.parent_comment_id}")
                raise HTTPException(status_code=404, detail="Parent comment not found")
            
            parent_data = parent_result.data[0]
            
            # Get the user name of the person being replied to
            reply_target_user_result = await supabase.table("users").select("name, avatar_url_80, avatar_url_200, avatar_url_original, avatar_version").eq("id", parent_data["user_id"]).execute()
            reply_target_user_name = reply_target_user_result.data[0]["name"] if reply_target_user_result.data else "Unknown User"
            reply_target_avatar_info = reply_target_user_result.data[0] if reply_target_user_result.data else {}
            
            # Store who we're actually replying to (for @mention display)
            actual_reply_target = {
                "id": str(parent_data["id"]),
                "content": parent_data["content"],
                "created_at": parent_data["created_at"],
                "user_id": str(parent_data["user_id"]),
                "user_name": reply_target_user_name,
                "user_avatar_url_80": reply_target_avatar_info.get("avatar_url_80"),
                "user_avatar_url_200": reply_target_avatar_info.get("avatar_url_200"),
                "user_avatar_url_original": reply_target_avatar_info.get("avatar_url_original"),
                "user_avatar_version": reply_target_avatar_info.get("avatar_version"),
                "is_edited": parent_data["is_edited"]
            }
            
            # Cleanup intermediate objects
            _cleanup_memory(parent_result, reply_target_user_result, parent_data, reply_target_avatar_info)
            parent_result = reply_target_user_result = None
            
        else:
            print(f"💬 [CREATE_COMMENT] This is a top-level comment (no parent)")
        
        # Create the comment with direct parent relationship (no flattening)
        comment_insert_data = {
            "id": comment_id,
            "post_id": comment_data.post_id,
            "user_id": user_id,
            "content": comment_data.content,
            "parent_comment_id": comment_data.parent_comment_id,
            "is_edited": False,
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat()
        }
        
        result = await supabase.table("comments").insert(comment_insert_data).execute()
        
        if not result.data:
            print(f"❌ [CREATE_COMMENT] Failed to insert comment")
            raise HTTPException(status_code=500, detail="Failed to create comment")
        
        created_comment = result.data[0]
        
        # Track user activity after successful comment
        await track_user_activity(supabase, user_id)
        
        # Return the comment with user name and parent comment details
        comment_response = Comment(
            id=created_comment["id"],
            content=created_comment["content"],
            created_at=created_comment["created_at"],
            user_id=created_comment["user_id"],
            user_name=current_user.name,
            user_avatar_url_80=created_comment.get('user_avatar_url_80'),
            user_avatar_url_200=created_comment.get('user_avatar_url_200'),
            user_avatar_url_original=created_comment.get('user_avatar_url_original'),
            user_avatar_version=created_comment.get('user_avatar_version'),
            is_edited=created_comment["is_edited"],
            parent_comment=actual_reply_target
        )
        
        # ENHANCED: Add notifications to background tasks for immediate response
        background_tasks.add_task(
            handle_comment_notifications,
            user_id=user_id,
            post_id=comment_data.post_id,
            comment_data={
                "id": str(comment_response.id),
                "content": comment_response.content,
                "created_at": comment_response.created_at.isoformat() if hasattr(comment_response.created_at, 'isoformat') else str(comment_response.created_at),
                "user_id": str(comment_response.user_id),
                "user_name": comment_response.user_name,
                "user_avatar_url_80": comment_response.user_avatar_url_80,
                "user_avatar_url_200": comment_response.user_avatar_url_200,
                "user_avatar_url_original": comment_response.user_avatar_url_original,
                "user_avatar_version": comment_response.user_avatar_version,
                "is_edited": comment_response.is_edited,
                "parent_comment": actual_reply_target,
                "post_id": comment_data.post_id
            },
            parent_comment_id=comment_data.parent_comment_id,
            supabase_client=supabase
        )
        
        # Final cleanup
        _cleanup_memory(result, comment_insert_data, created_comment)
        
        return comment_response
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error creating comment: {e}")
        # Cleanup on error
        _cleanup_memory(post_result, parent_result, reply_target_user_result, result)
        raise HTTPException(status_code=500, detail=str(e))


async def get_comments_for_multiple_posts(
    post_ids: List[str],
    current_user: User,
    supabase: AsyncClient
) -> Dict[str, List[Comment]]:
    """Get comments for specific posts (optimized for comments-only refresh and memory)"""
    comments_result = None
    users_result = None
    parent_result = None
    parent_users_result = None
    
    try:
        if not post_ids:
            return {}
        
        print(f"💬 [FeedAPI] Getting comments for {len(post_ids)} posts: {post_ids}")
        
        # Get all comments for the posts first
        comments_result = await supabase.table("comments").select(
            "id, content, created_at, user_id, post_id, is_edited, parent_comment_id"
        ).in_("post_id", post_ids).order("created_at").execute()
        
        print(f"💬 [FeedAPI] Raw comments query returned {len(comments_result.data) if comments_result.data else 0} comments")
        
        if not comments_result.data:
            return {post_id: [] for post_id in post_ids}
        
        raw_comments = comments_result.data
        
        # Clear comments_result early to free memory
        comments_result = None
        _cleanup_memory(raw_comments)
        
        # Get unique user IDs from comments (memory efficient)
        user_ids = list(set(comment['user_id'] for comment in raw_comments))
        
        # Get user information for all comment authors
        users_result = await supabase.table("users").select(
            "id, name, avatar_url_80, avatar_url_200, avatar_url_original, avatar_version"
        ).in_("id", user_ids).execute()
        
        # Create a lookup map for user data
        user_data_map = {str(user['id']): user for user in users_result.data} if users_result.data else {}
        
        # Clear users_result early
        _cleanup_memory(users_result, user_ids)
        users_result = None
        
        # Get parent comment IDs and fetch their details
        parent_comment_ids = [
            comment['parent_comment_id'] for comment in raw_comments 
            if comment['parent_comment_id']
        ]
        
        print(f"💬 [FeedAPI] Found {len(parent_comment_ids)} parent comment IDs")
        
        parent_comments_data = {}
        if parent_comment_ids:
            parent_result = await supabase.table("comments").select(
                "id, content, created_at, user_id, is_edited"
            ).in_("id", parent_comment_ids).execute()
            
            print(f"💬 [FeedAPI] Parent comments query returned {len(parent_result.data) if parent_result.data else 0} parents")
            
            # Get user data for parent comment authors
            parent_user_ids = list(set(parent['user_id'] for parent in parent_result.data)) if parent_result.data else []
            
            if parent_user_ids:
                parent_users_result = await supabase.table("users").select(
                    "id, name, avatar_url_80, avatar_url_200, avatar_url_original, avatar_version"
                ).in_("id", parent_user_ids).execute()
                
                parent_user_data_map = {str(user['id']): user for user in parent_users_result.data} if parent_users_result.data else {}
                
                # Cleanup intermediate data
                _cleanup_memory(parent_users_result, parent_user_ids)
                parent_users_result = None
            else:
                parent_user_data_map = {}
            
            # Process parent comments efficiently
            for parent in parent_result.data:
                parent_user_data = parent_user_data_map.get(str(parent['user_id']))
                if parent_user_data:
                    parent['user_data'] = parent_user_data
                parent_comments_data[parent['id']] = parent
            
            # Cleanup
            _cleanup_memory(parent_result, parent_user_data_map)
            parent_result = None
        
        # Process comments in memory-efficient batches
        comments_by_post = _process_comments_by_post_batch(
            raw_comments, post_ids, user_data_map, parent_comments_data
        )
        
        # Final cleanup
        _cleanup_memory(raw_comments, user_data_map, parent_comments_data, parent_comment_ids)
        
        print(f"💬 [FeedAPI] Returning comments for {len([p for p in comments_by_post.values() if p])} posts with data")
        return comments_by_post
        
    except Exception as e:
        print(f"❌ [FeedAPI] Error getting comments for posts: {e}")
        # Cleanup on error
        _cleanup_memory(comments_result, users_result, parent_result, parent_users_result)
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Failed to get comments")


def _process_comments_by_post_batch(
    raw_comments: List[dict], 
    post_ids: List[str], 
    user_data_map: dict, 
    parent_comments_data: dict
) -> Dict[str, List[Comment]]:
    """Process comments in memory-efficient batches"""
    comments_by_post: dict[str, list[Comment]] = {post_id: [] for post_id in post_ids}
    db_data_map: dict[str, dict] = {}
    
    try:
        # Process comments in smaller batches to reduce memory pressure
        batch_size = 50
        for i in range(0, len(raw_comments), batch_size):
            batch = raw_comments[i:i + batch_size]
            
            for comment_data in batch:
                post_id = str(comment_data['post_id'])
                comment_id = str(comment_data['id'])
                
                # Store minimal raw data for organization
                db_data_map[comment_id] = {
                    'id': comment_data['id'],
                    'parent_comment_id': comment_data['parent_comment_id']
                }
                
                # Build parent comment object if this is a reply
                parent_comment_obj = None
                if comment_data['parent_comment_id'] and comment_data['parent_comment_id'] in parent_comments_data:
                    parent_data = parent_comments_data[comment_data['parent_comment_id']]
                    parent_user_data = parent_data.get('user_data')
                    if parent_user_data:
                        # Parse parent comment's created_at string to datetime
                        parent_created_at = datetime.fromisoformat(parent_data['created_at'].replace('Z', '+00:00'))
                        
                        parent_comment_obj = {
                            "id": str(parent_data['id']),
                            "content": parent_data['content'],
                            "created_at": parent_created_at.isoformat(),
                            "user_id": str(parent_data['user_id']),
                            "user_name": parent_user_data['name'],
                            "user_avatar_url_80": parent_user_data.get('avatar_url_80'),
                            "user_avatar_url_200": parent_user_data.get('avatar_url_200'),
                            "user_avatar_url_original": parent_user_data.get('avatar_url_original'),
                            "user_avatar_version": parent_user_data.get('avatar_version'),
                            "is_edited": parent_data['is_edited']
                        }
                    else:
                        print(f"⚠️ [FeedAPI] Parent comment {parent_data['id']} missing user data")
                elif comment_data['parent_comment_id']:
                    print(f"❌ [FeedAPI] Could not find parent {comment_data['parent_comment_id']} for comment {comment_id}")
                
                # Create Comment object
                user_data = user_data_map.get(str(comment_data['user_id']))
                if not user_data:
                    print(f"⚠️ [FeedAPI] Comment {comment_id} missing user data, skipping")
                    continue
                
                # Parse comment's created_at string to datetime object
                comment_created_at = datetime.fromisoformat(comment_data['created_at'].replace('Z', '+00:00'))
                    
                comment = Comment(
                    id=comment_id,
                    content=comment_data['content'],
                    created_at=comment_created_at,
                    user_id=str(comment_data['user_id']),
                    user_name=user_data['name'],
                    user_avatar_url_80=user_data.get('avatar_url_80'),
                    user_avatar_url_200=user_data.get('avatar_url_200'),
                    user_avatar_url_original=user_data.get('avatar_url_original'),
                    user_avatar_version=user_data.get('avatar_version'),
                    is_edited=comment_data['is_edited'],
                    parent_comment=parent_comment_obj
                )
                
                comments_by_post[post_id].append(comment)
                
                # Cleanup temporary objects
                del comment_data, comment, parent_comment_obj
            
            # Cleanup batch
            del batch
            
        # Organize comments with flat threading
        for post_id in comments_by_post:
            comments = comments_by_post[post_id]
            if comments:
                # Filter db_data_map for this post's comments
                post_db_data = {
                    cid: data for cid, data in db_data_map.items() 
                    if any(str(c.id) == cid for c in comments)
                }
                print(f"💬 [FeedAPI] Organizing {len(comments)} comments for post {post_id}")
                organized_comments = organize_comments_flattened(comments, post_db_data)
                print(f"💬 [FeedAPI] Organization result: {len(organized_comments)} comments")
                
                # Debug: Log organization changes
                if len(organized_comments) != len(comments):
                    print(f"❌ [FeedAPI] WARNING: Lost comments during organization! {len(comments)} -> {len(organized_comments)}")
                    lost_ids = set(c.id for c in comments) - set(c.id for c in organized_comments)
                    print(f"❌ [FeedAPI] Lost comment IDs: {lost_ids}")
                
                comments_by_post[post_id] = organized_comments
                
                # Cleanup intermediate objects
                _cleanup_memory(comments, post_db_data)
        
        return comments_by_post
        
    except Exception as e:
        print(f"❌ [FeedAPI] Error in batch processing: {e}")
        _cleanup_memory(db_data_map)
        raise


async def get_comments_for_single_post(
    post_id: str,
    current_user: User,
    supabase: AsyncClient
) -> List[Comment]:
    """Get comments for a specific post (optimized for single post refresh and memory)"""
    comments_result = None
    users_result = None
    parent_result = None
    parent_users_result = None
    
    try:
        print(f"💬 [FeedAPI] Getting comments for single post: {post_id}")
        
        # Get all comments for the post first
        comments_result = await supabase.table("comments").select(
            "id, content, created_at, user_id, post_id, is_edited, parent_comment_id"
        ).eq("post_id", post_id).order("created_at").execute()
        
        if not comments_result.data:
            return []
        
        raw_comments = comments_result.data
        
        # Clear comments_result early
        comments_result = None
        _cleanup_memory(raw_comments)
        
        # Get unique user IDs from comments
        user_ids = list(set(comment['user_id'] for comment in raw_comments))
        
        # Get user information for all comment authors
        users_result = await supabase.table("users").select(
            "id, name, avatar_url_80, avatar_url_200, avatar_url_original, avatar_version"
        ).in_("id", user_ids).execute()
        
        # Create a lookup map for user data
        user_data_map = {str(user['id']): user for user in users_result.data} if users_result.data else {}
        
        # Cleanup
        _cleanup_memory(users_result, user_ids)
        users_result = None
        
        # Get parent comment IDs and fetch their details
        parent_comment_ids = [
            comment['parent_comment_id'] for comment in raw_comments 
            if comment['parent_comment_id']
        ]
        
        parent_comments_data = {}
        if parent_comment_ids:
            parent_result = await supabase.table("comments").select(
                "id, content, created_at, user_id, is_edited"
            ).in_("id", parent_comment_ids).execute()
            
            # Get user data for parent comment authors
            parent_user_ids = list(set(parent['user_id'] for parent in parent_result.data)) if parent_result.data else []
            
            if parent_user_ids:
                parent_users_result = await supabase.table("users").select(
                    "id, name, avatar_url_80, avatar_url_200, avatar_url_original, avatar_version"
                ).in_("id", parent_user_ids).execute()
                
                parent_user_data_map = {str(user['id']): user for user in parent_users_result.data} if parent_users_result.data else {}
                
                # Cleanup
                _cleanup_memory(parent_users_result, parent_user_ids)
                parent_users_result = None
            else:
                parent_user_data_map = {}
            
            for parent in parent_result.data:
                parent_user_data = parent_user_data_map.get(str(parent['user_id']))
                if parent_user_data:
                    parent['user_data'] = parent_user_data
                parent_comments_data[parent['id']] = parent
            
            # Cleanup
            _cleanup_memory(parent_result, parent_user_data_map)
            parent_result = None
        
        # Process comments efficiently
        comments = []
        db_data_map = {}
        
        for comment_data in raw_comments:
            comment_id = str(comment_data['id'])
            
            # Store raw data for organization
            db_data_map[comment_id] = {
                'id': comment_data['id'],
                'parent_comment_id': comment_data['parent_comment_id']
            }
            
            # Build parent comment object if this is a reply
            parent_comment_obj = None
            if comment_data['parent_comment_id'] and comment_data['parent_comment_id'] in parent_comments_data:
                parent_data = parent_comments_data[comment_data['parent_comment_id']]
                parent_user_data = parent_data.get('user_data')
                if parent_user_data:
                    parent_comment_obj = {
                        "id": str(parent_data['id']),
                        "content": parent_data['content'],
                        "created_at": parent_data['created_at'],
                        "user_id": str(parent_data['user_id']),
                        "user_name": parent_user_data['name'],
                        "user_avatar_url_80": parent_user_data.get('avatar_url_80'),
                        "user_avatar_url_200": parent_user_data.get('avatar_url_200'),
                        "user_avatar_url_original": parent_user_data.get('avatar_url_original'),
                        "user_avatar_version": parent_user_data.get('avatar_version'),
                        "is_edited": parent_data['is_edited']
                    }
                else:
                    print(f"⚠️ [FeedAPI] Parent comment {parent_data['id']} missing user data")
            elif comment_data['parent_comment_id']:
                print(f"❌ [FeedAPI] Could not find parent {comment_data['parent_comment_id']} for comment {comment_id}")
            
            # Create Comment object
            user_data = user_data_map.get(str(comment_data['user_id']))
            if not user_data:
                print(f"⚠️ [FeedAPI] Comment {comment_id} missing user data, skipping")
                continue
                
            comment = Comment(
                id=comment_id,
                content=comment_data['content'],
                created_at=comment_data['created_at'],
                user_id=str(comment_data['user_id']),
                user_name=user_data['name'],
                user_avatar_url_80=user_data.get('avatar_url_80'),
                user_avatar_url_200=user_data.get('avatar_url_200'),
                user_avatar_url_original=user_data.get('avatar_url_original'),
                user_avatar_version=user_data.get('avatar_version'),
                is_edited=comment_data['is_edited'],
                parent_comment=parent_comment_obj
            )
            
            comments.append(comment)
        
        # Organize comments with flat threading
        organized_comments = []
        if comments:
            organized_comments = organize_comments_flattened(comments, db_data_map)
        
        print(f"💬 [FeedAPI] Returning {len(organized_comments)} organized comments for post {post_id}")
        
        # Final cleanup
        _cleanup_memory(raw_comments, user_data_map, parent_comments_data, comments, db_data_map, parent_comment_ids)
        
        return organized_comments
        
    except Exception as e:
        print(f"❌ [FeedAPI] Error getting comments for post {post_id}: {e}")
        # Cleanup on error
        _cleanup_memory(comments_result, users_result, parent_result, parent_users_result)
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Failed to get comments for post") 