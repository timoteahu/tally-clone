from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from typing import List, Optional
from models.schemas import FeedPost, Comment, User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user, get_current_user_lightweight
from utils.memory_optimization import cleanup_memory, disable_print

# Import service functions
from .services.feed_service import get_user_feed, get_posts_for_user
from .services.comment_service import (
    create_new_comment,
    get_comments_for_multiple_posts,
    get_comments_for_single_post,
    CommentCreate
)
from .services.post_service import update_post_caption, get_post_by_verification_id
from utils.memory_cleanup import _cleanup_memory

# Disable verbose printing in this module to reduce response latency

router = APIRouter()

@router.get("/", response_model=List[FeedPost])
async def get_feed(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client),
    since: Optional[str] = None
):
    """
    Get the social feed for the current user.
    Returns all visible (public) posts from friends in the last 24 hours,
    including comments and poster information.
    Memory optimized endpoint.
    """
    return await get_user_feed(current_user, supabase, since)

@router.post("/comments", response_model=Comment)
async def create_comment(
    comment_data: CommentCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Create a new comment on a post.
    Memory optimized endpoint.
    """
    return await create_new_comment(comment_data, current_user, background_tasks, supabase)

@router.post("/comments/get")
async def get_comments_for_posts(
    request: dict,  # Contains post_ids array
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get comments for specific posts (optimized for comments-only refresh and memory)"""
    post_ids = request.get("post_ids", [])
    result = await get_comments_for_multiple_posts(post_ids, current_user, supabase)
    
    # Cleanup request data
    cleanup_memory(request, post_ids)
    
    return result

@router.get("/comments/{post_id}", response_model=List[Comment])
async def get_comments_for_post(
    post_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Get comments for a specific post (optimized for single post refresh and memory)"""
    return await get_comments_for_single_post(post_id, current_user, supabase)

@router.post("/update-caption")
async def update_caption(
    request: dict,  # Contains verification_id OR post_id and caption
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Update the caption of a post.
    Memory optimized endpoint.
    """
    verification_id = request.get("verification_id")
    post_id = request.get("post_id")
    caption = request.get("caption", "").strip()
    
    result = await update_post_caption(verification_id, post_id, caption, current_user, supabase)
    
    # Cleanup request data
    cleanup_memory(request)
    
    return result

@router.get("/post/by-verification/{verification_id}", response_model=FeedPost)
async def get_post_by_verification(
    verification_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get a post by its habit verification ID.
    Memory optimized endpoint.
    """
    return await get_post_by_verification_id(verification_id, current_user, supabase)

@router.get("/user/{user_id}", response_model=List[FeedPost])
async def get_user_posts(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get all posts for a specific user.
    Memory optimized endpoint.
    """
    return await get_posts_for_user(user_id, current_user, supabase) 