from datetime import datetime, date
from supabase._async.client import AsyncClient
import logging

logger = logging.getLogger(__name__)

async def track_user_activity(supabase: AsyncClient, user_id: str):
    """
    Track user activity by updating last_active timestamp and recording daily active user.
    This should be called whenever a user performs a significant action.
    
    Args:
        supabase: The Supabase client
        user_id: The user's ID
    """
    try:
        # Update last_active timestamp
        await supabase.table("users").update({
            "last_active": datetime.utcnow().isoformat()
        }).eq("id", user_id).execute()
        
        # Record daily active user (upsert to avoid duplicates)
        today = date.today()
        await supabase.table("daily_active_users").upsert({
            "date": today.isoformat(),
            "user_id": user_id,
            "created_at": datetime.utcnow().isoformat()
        }).execute()
        
    except Exception as e:
        # Log error but don't fail the main operation
        logger.error(f"Failed to track user activity for user {user_id}: {e}")

def get_activity_display_text(last_active: datetime) -> str:
    """
    Convert last_active timestamp to human-readable text.
    
    Args:
        last_active: The last active timestamp
        
    Returns:
        Human-readable activity text like "Active now", "Active 2h ago", etc.
    """
    if not last_active:
        return "Never active"
    
    now = datetime.utcnow()
    diff = now - last_active
    
    # Active now (within 5 minutes)
    if diff.total_seconds() < 300:
        return "active now"
    
    # Hours
    hours = diff.total_seconds() / 3600
    if hours < 1:
        minutes = int(diff.total_seconds() / 60)
        return f"active {minutes}m ago"
    elif hours < 24:
        return f"active {int(hours)}h ago"
    
    # Days
    days = diff.days
    if days == 1:
        return "active yesterday"
    elif days < 7:
        return f"active {days}d ago"
    elif days < 14:
        return "active 1w ago"
    elif days < 30:
        weeks = days // 7
        return f"active {weeks}w ago"
    else:
        return "active 2+ weeks ago"