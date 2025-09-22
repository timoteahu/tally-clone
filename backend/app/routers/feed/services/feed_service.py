from typing import List, Optional, Generator
from datetime import datetime
from fastapi import HTTPException
from supabase._async.client import AsyncClient
from models.schemas import FeedPost, Comment, User
from utils.activity_tracking import track_user_activity
from utils.memory_optimization import cleanup_memory, disable_print
from ..utils.comment_utils import organize_comments_flattened
from ..utils.image_utils import generate_post_image_urls
from utils.memory_cleanup import _cleanup_memory
import json

# Disable verbose printing to reduce response latency
print = disable_print()


async def get_user_feed(
    current_user: User,
    supabase: AsyncClient,
    since: Optional[str] = None
) -> List[FeedPost]:
    """
    Get the social feed for the current user.
    Returns all visible (public) posts from friends in the last 24 hours,
    including comments and poster information.
    Memory optimized with explicit cleanup.
    """
    result = None
    feed_posts = []
    
    try:
        # Track user activity when viewing feed
        await track_user_activity(supabase, str(current_user.id))
        user_id = str(current_user.id)
        
        # Call shared RPC to get feed for this user
        result = await supabase.rpc(
            "get_user_feed",
            {"user_id_param": user_id}
        ).execute()
        
        if not result.data:
            return []
            
        # Convert since string to datetime if provided
        since_dt: Optional[datetime] = None
        if since:
            try:
                since_dt = datetime.fromisoformat(since.replace('Z', '+00:00'))
            except Exception:
                pass
        
        # Process posts with memory efficiency - use generator pattern
        raw_posts = result.data
        
        # Clear result early to free memory
        result = None
        cleanup_memory(raw_posts)
        
        # Process posts in memory-efficient chunks
        for post in _process_posts_generator(raw_posts, since_dt):
            try:
                # Generate signed URLs for post images
                image_urls = await generate_post_image_urls(supabase, post, post['is_private'])
                
                # Create FeedPost object
                feed_post = FeedPost(
                    post_id=str(post['post_id']),
                    habit_id=str(post.get('habit_id')) if post.get('habit_id') else None,
                    caption=post['caption'],
                    created_at=post['created_at'],
                    is_private=post['is_private'],
                    image_url=image_urls.get('content_image_url') or image_urls.get('selfie_image_url'),
                    selfie_image_url=image_urls.get('selfie_image_url'),
                    content_image_url=image_urls.get('content_image_url'),
                    user_id=str(post['user_id']),
                    user_name=post['user_name'],
                    user_avatar_url_80=post.get('user_avatar_url_80'),
                    user_avatar_url_200=post.get('user_avatar_url_200'),
                    user_avatar_url_original=post.get('user_avatar_url_original'),
                    user_avatar_version=post.get('user_avatar_version'),
                    habit_name=post.get('habit_name'),
                    habit_type=post.get('habit_type'),
                    penalty_amount=round(float(post['penalty_amount']), 2) if post.get('penalty_amount') is not None else None,
                    streak=post.get('streak'),
                    comments=post.get('processed_comments', [])
                )
                
                feed_posts.append(feed_post)
                
                # Clean up intermediate objects
                cleanup_memory(image_urls, feed_post)
                
            except Exception as e:
                print(f"❌ [FeedAPI] Error processing post {post.get('post_id', 'unknown')}: {e}")
                continue
        
        # Final cleanup
        cleanup_memory(raw_posts)
        
        return feed_posts
        
    except Exception as e:
        print(f"❌ [FeedAPI] Error getting feed: {e}")
        # Cleanup on error
        cleanup_memory(result, feed_posts)
        raise HTTPException(status_code=500, detail=str(e))


def _process_posts_generator(raw_posts: List[dict], since_dt: Optional[datetime]) -> Generator[dict, None, None]:
    """Generator to process posts memory-efficiently"""
    for post in raw_posts:
        try:
            # Delta filter – skip posts older than or equal to 'since'
            if since_dt:
                try:
                    post_created = datetime.fromisoformat(post['created_at'].replace('Z', '+00:00'))
                    if post_created <= since_dt:
                        continue
                except Exception:
                    pass
            
            # Process comments efficiently
            processed_comments = _process_comments_efficiently(post.get('comments', []))
            post['processed_comments'] = processed_comments
            
            # Clean up original comments to save memory
            if 'comments' in post:
                del post['comments']
            
            yield post
            
        except Exception as e:
            print(f"❌ [FeedAPI] Error in post generator: {e}")
            continue


def _process_comments_efficiently(raw_comments) -> List[Comment]:
    """Process comments with memory optimization"""
    if not raw_comments:
        return []
        
    # Ensure comments is a list
    if isinstance(raw_comments, str):
        try:
            raw_comments = json.loads(raw_comments)
        except Exception:
            return []
    
    comments = []
    comment_db_data = {}
    
    try:
        # Process each comment with minimal memory footprint
        for comment_data in raw_comments:
            # Store minimal DB data for organization
            comment_id = str(comment_data['id'])
            comment_db_data[comment_id] = {
                'id': comment_data['id'],
                'parent_comment_id': comment_data.get('parent_comment_id')
            }
            
            # Find parent comment details efficiently
            parent_comment_obj = None
            if comment_data.get('parent_comment_id'):
                for parent_data in raw_comments:
                    if parent_data['id'] == comment_data['parent_comment_id']:
                        parent_comment_obj = {
                            "id": str(parent_data['id']),
                            "content": parent_data['content'],
                            "created_at": parent_data['created_at'],
                            "user_id": str(parent_data['user_id']),
                            "user_name": parent_data['user_name'],
                            "is_edited": parent_data['is_edited']
                        }
                        break
            
            # Create Comment object
            comment = Comment(
                id=comment_id,
                content=comment_data['content'],
                created_at=comment_data['created_at'],
                user_id=str(comment_data['user_id']),
                user_name=comment_data['user_name'],
                user_avatar_url_80=comment_data.get('user_avatar_url_80'),
                user_avatar_url_200=comment_data.get('user_avatar_url_200'),
                user_avatar_url_original=comment_data.get('user_avatar_url_original'),
                user_avatar_version=comment_data.get('user_avatar_version'),
                is_edited=comment_data['is_edited'],
                parent_comment=parent_comment_obj
            )
            comments.append(comment)
        
        # Organize comments
        organized_comments = organize_comments_flattened(comments, comment_db_data)
        
        # Cleanup intermediate objects
        cleanup_memory(comments, comment_db_data)
        
        return organized_comments
        
    except Exception as e:
        print(f"❌ [FeedAPI] Error processing comments: {e}")
        cleanup_memory(comments, comment_db_data)
        return []


async def get_posts_for_user(
    user_id: str,
    current_user: User,
    supabase: AsyncClient
) -> List[FeedPost]:
    """
    Get all posts for a specific user.
    Memory optimized version with explicit cleanup.
    """
    result = None
    feed_posts = []
    
    try:
        # Track user activity when viewing user posts
        await track_user_activity(supabase, str(current_user.id))
        
        # Get posts for the specific user (public only)
        result = await supabase.rpc(
            "get_user_posts",
            {"user_id_param": user_id}
        ).execute()
        
        if not result.data:
            return []
        
        raw_posts = result.data
        
        # Clear result early to free memory
        result = None
        cleanup_memory(raw_posts)
        
        # Process posts with memory efficiency
        for post in raw_posts:
            try:
                # Parse comments efficiently
                processed_comments = []
                if post.get('comments'):
                    try:
                        comment_db_data = json.loads(post['comments'])
                        processed_comments = []
                        
                        for comment_data in comment_db_data:
                            comment = Comment(
                                id=comment_data['id'],
                                content=comment_data['content'],
                                created_at=comment_data['created_at'],
                                user_id=comment_data['user_id'],
                                user_name=comment_data['user_name'],
                                user_avatar_url_80=comment_data.get('user_avatar_url_80'),
                                user_avatar_url_200=comment_data.get('user_avatar_url_200'),
                                user_avatar_url_original=comment_data.get('user_avatar_url_original'),
                                user_avatar_version=comment_data.get('user_avatar_version'),
                                is_edited=comment_data.get('is_edited', False),
                                parent_comment=None
                            )
                            processed_comments.append(comment)
                        
                        # Organize and cleanup
                        processed_comments = organize_comments_flattened(processed_comments, {})
                        cleanup_memory(comment_db_data)
                        
                    except Exception as e:
                        print(f"❌ [FeedAPI] Error parsing comments for post {post.get('post_id')}: {e}")
                        processed_comments = []
                
                # Generate signed URLs for post images
                image_urls = await generate_post_image_urls(supabase, post, post['is_private'])
                
                # Create FeedPost
                feed_post = FeedPost(
                    post_id=str(post['post_id']),
                    habit_id=str(post.get('habit_id')) if post.get('habit_id') else None,
                    caption=post['caption'],
                    created_at=post['created_at'],
                    is_private=post['is_private'],
                    image_url=image_urls.get('content_image_url') or image_urls.get('selfie_image_url'),
                    selfie_image_url=image_urls.get('selfie_image_url'),
                    content_image_url=image_urls.get('content_image_url'),
                    user_id=str(post['user_id']),
                    user_name=post['user_name'],
                    user_avatar_url_80=post.get('user_avatar_url_80'),
                    user_avatar_url_200=post.get('user_avatar_url_200'),
                    user_avatar_url_original=post.get('user_avatar_url_original'),
                    user_avatar_version=post.get('user_avatar_version'),
                    habit_name=post.get('habit_name'),
                    habit_type=post.get('habit_type'),
                    penalty_amount=round(float(post['penalty_amount']), 2) if post.get('penalty_amount') is not None else None,
                    streak=post.get('streak'),
                    comments=processed_comments
                )
                
                feed_posts.append(feed_post)
                
                # Cleanup intermediate objects
                cleanup_memory(image_urls, processed_comments)
                
            except Exception as e:
                print(f"❌ [FeedAPI] Error processing user post: {e}")
                continue
        
        # Final cleanup
        cleanup_memory(raw_posts)
        
        return feed_posts
        
    except Exception as e:
        print(f"❌ [FeedAPI] Error getting user posts: {e}")
        cleanup_memory(result, feed_posts)
        raise HTTPException(status_code=500, detail=str(e)) 