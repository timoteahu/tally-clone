"""
Background task to refresh GitHub tokens before they expire.
This prevents users from experiencing token expiration issues.
"""

import asyncio
import logging
from datetime import datetime, timedelta
from config.database import get_async_supabase_client
from utils.github_commits import refresh_user_github_token

logger = logging.getLogger(__name__)

async def refresh_expiring_github_tokens():
    """
    Proactively refresh GitHub tokens that will expire within the next hour.
    This should be run periodically (e.g., every 30 minutes) as a background task.
    """
    try:
        supabase = await get_async_supabase_client()
        
        # Find tokens that expire within the next hour
        expire_threshold = (datetime.utcnow() + timedelta(hours=1)).isoformat()
        
        result = await supabase.table("user_tokens").select(
            "user_id, github_access_token, github_refresh_token, github_token_expires_at, github_username"
        ).not_.is_("github_refresh_token", "null") \
         .not_.is_("github_token_expires_at", "null") \
         .lte("github_token_expires_at", expire_threshold).execute()
        
        if not result.data:
            logger.info("No GitHub tokens require refresh")
            return
        
        logger.info(f"Found {len(result.data)} GitHub tokens that need refresh")
        
        refresh_count = 0
        error_count = 0
        
        for token_data in result.data:
            try:
                user_id = token_data["user_id"]
                refresh_token = token_data["github_refresh_token"]
                username = token_data.get("github_username", "unknown")
                
                logger.info(f"Refreshing GitHub token for user {user_id} (@{username})")
                
                new_access_token = await refresh_user_github_token(supabase, user_id, refresh_token)
                
                if new_access_token:
                    refresh_count += 1
                    logger.info(f"Successfully refreshed token for user {user_id}")
                else:
                    error_count += 1
                    logger.error(f"Failed to refresh token for user {user_id}")
                    
            except Exception as e:
                error_count += 1
                logger.error(f"Error refreshing token for user {token_data.get('user_id')}: {e}")
        
        logger.info(f"Token refresh completed: {refresh_count} successful, {error_count} errors")
        
    except Exception as e:
        logger.error(f"Error in refresh_expiring_github_tokens: {e}")

async def cleanup_expired_github_tokens():
    """
    Clean up GitHub tokens that have been expired for more than 7 days.
    This helps maintain database hygiene.
    """
    try:
        supabase = await get_async_supabase_client()
        
        # Find tokens expired for more than 7 days
        cleanup_threshold = (datetime.utcnow() - timedelta(days=7)).isoformat()
        
        result = await supabase.table("user_tokens").select("user_id, github_username") \
            .not_.is_("github_token_expires_at", "null") \
            .lte("github_token_expires_at", cleanup_threshold) \
            .is_("github_refresh_token", "null").execute()  # Only clean up tokens without refresh capability
        
        if not result.data:
            logger.info("No expired GitHub tokens to clean up")
            return
        
        logger.info(f"Cleaning up {len(result.data)} expired GitHub tokens")
        
        for token_data in result.data:
            user_id = token_data["user_id"]
            username = token_data.get("github_username", "unknown")
            
            # Clear the expired token data
            await supabase.table("user_tokens").update({
                "github_access_token": None,
                "github_refresh_token": None,
                "github_token_expires_at": None,
                "github_token_error": "token_expired_cleaned",
                "github_token_error_at": datetime.utcnow().isoformat()
            }).eq("user_id", user_id).execute()
            
            logger.info(f"Cleaned up expired token for user {user_id} (@{username})")
        
    except Exception as e:
        logger.error(f"Error in cleanup_expired_github_tokens: {e}")

# Scheduler integration
def setup_github_token_refresh_tasks(scheduler):
    """
    Add GitHub token refresh tasks to the scheduler.
    Call this from your main scheduler setup.
    """
    # Refresh expiring tokens every 30 minutes
    scheduler.add_job(
        refresh_expiring_github_tokens,
        'interval',
        minutes=30,
        id='refresh_github_tokens',
        replace_existing=True
    )
    
    # Clean up expired tokens daily at 3 AM
    scheduler.add_job(
        cleanup_expired_github_tokens,
        'cron',
        hour=3,
        minute=0,
        id='cleanup_github_tokens',
        replace_existing=True
    )
    
    logger.info("GitHub token refresh tasks scheduled") 