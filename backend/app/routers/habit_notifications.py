from fastapi import APIRouter, Depends, HTTPException, Query
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from typing import List, Optional, Dict, Any
from routers.auth import get_current_user_lightweight
from models.schemas import User
from services.habit_notification_scheduler import habit_notification_scheduler
import logging
from datetime import datetime, timedelta
import pytz

router = APIRouter()
logger = logging.getLogger(__name__)

@router.get("/scheduled/{user_id}")
async def get_scheduled_notifications(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0)
):
    """Get scheduled notifications for a user"""
    try:
        # Verify user permissions
        if str(current_user.id) != user_id and not current_user.is_admin:
            raise HTTPException(status_code=403, detail="Can only access your own notifications")
        
        # Get scheduled notifications
        result = await supabase.table('scheduled_notifications').select(
            '*'
        ).eq('user_id', user_id).order(
            'scheduled_time', desc=False
        ).range(offset, offset + limit - 1).execute()
        
        return {
            "notifications": result.data,
            "total": len(result.data),
            "limit": limit,
            "offset": offset
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting scheduled notifications: {e}")
        raise HTTPException(status_code=500, detail="Failed to get scheduled notifications")

@router.get("/scheduled/{user_id}/upcoming")
async def get_upcoming_notifications(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client),
    hours: int = Query(24, ge=1, le=168)  # Default 24 hours, max 1 week
):
    """Get upcoming notifications for a user within the specified hours"""
    try:
        # Verify user permissions
        if str(current_user.id) != user_id and not current_user.is_admin:
            raise HTTPException(status_code=403, detail="Can only access your own notifications")
        
        # Calculate time range
        now_utc = datetime.now(pytz.UTC)
        future_time = now_utc + timedelta(hours=hours)
        
        # Get upcoming notifications
        result = await supabase.table('scheduled_notifications').select(
            '*'
        ).eq('user_id', user_id).eq(
            'sent', False
        ).gte('scheduled_time', now_utc.isoformat()).lte(
            'scheduled_time', future_time.isoformat()
        ).order('scheduled_time', desc=False).execute()
        
        return {
            "notifications": result.data,
            "time_range_hours": hours,
            "from_time": now_utc.isoformat(),
            "to_time": future_time.isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting upcoming notifications: {e}")
        raise HTTPException(status_code=500, detail="Failed to get upcoming notifications")

@router.post("/reschedule-habit/{habit_id}")
async def reschedule_habit_notifications(
    habit_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Reschedule notifications for a specific habit (useful after habit updates)"""
    try:
        # Get the habit and verify ownership
        habit_result = await supabase.table('habits').select(
            '*'
        ).eq('id', habit_id).eq('is_active', True).execute()
        
        if not habit_result.data:
            raise HTTPException(status_code=404, detail="Habit not found")
        
        habit_data = habit_result.data[0]
        
        # Verify user owns this habit
        if str(current_user.id) != habit_data['user_id']:
            raise HTTPException(status_code=403, detail="Can only reschedule notifications for your own habits")
        
        # Delete existing unsent notifications for this habit
        await supabase.table('scheduled_notifications').delete().eq(
            'habit_id', habit_id
        ).eq('sent', False).execute()
        
        # Schedule new notifications
        await habit_notification_scheduler.schedule_notifications_for_habit(
            habit_data, supabase
        )
        
        return {
            "message": "Notifications rescheduled successfully",
            "habit_id": habit_id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error rescheduling habit notifications: {e}")
        raise HTTPException(status_code=500, detail="Failed to reschedule notifications")

@router.post("/reschedule-all")
async def reschedule_all_notifications(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Reschedule all notifications for the current user (useful after timezone changes or for troubleshooting)"""
    try:
        user_id = str(current_user.id)
        
        # Reschedule all notifications for this user
        await habit_notification_scheduler.reschedule_all_notifications_for_user(
            user_id, supabase
        )
        
        # Get count of rescheduled notifications
        notifications_result = await supabase.table('scheduled_notifications').select(
            'id'
        ).eq('user_id', user_id).eq('sent', False).execute()
        
        return {
            "message": "All notifications rescheduled successfully",
            "user_id": user_id,
            "notifications_count": len(notifications_result.data)
        }
        
    except Exception as e:
        logger.error(f"Error rescheduling all notifications: {e}")
        raise HTTPException(status_code=500, detail="Failed to reschedule all notifications")

@router.delete("/cancel/{notification_id}")
async def cancel_notification(
    notification_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Cancel a specific scheduled notification"""
    try:
        # Get the notification and verify ownership
        notification_result = await supabase.table('scheduled_notifications').select(
            '*'
        ).eq('id', notification_id).eq('sent', False).execute()
        
        if not notification_result.data:
            raise HTTPException(status_code=404, detail="Notification not found or already sent")
        
        notification_data = notification_result.data[0]
        
        # Verify user owns this notification
        if str(current_user.id) != notification_data['user_id']:
            raise HTTPException(status_code=403, detail="Can only cancel your own notifications")
        
        # Mark as sent/skipped to cancel it
        await supabase.table('scheduled_notifications').update({
            'sent': True,
            'sent_at': datetime.utcnow().isoformat(),
            'skipped': True,
            'skip_reason': 'cancelled_by_user'
        }).eq('id', notification_id).execute()
        
        return {
            "message": "Notification cancelled successfully",
            "notification_id": notification_id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error cancelling notification: {e}")
        raise HTTPException(status_code=500, detail="Failed to cancel notification")

@router.get("/stats/{user_id}")
async def get_notification_stats(
    user_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client),
    days: int = Query(7, ge=1, le=30)  # Default 7 days, max 30 days
):
    """Get notification statistics for a user"""
    try:
        # Verify user permissions
        if str(current_user.id) != user_id and not current_user.is_admin:
            raise HTTPException(status_code=403, detail="Can only access your own notification stats")
        
        # Calculate time range
        now_utc = datetime.now(pytz.UTC)
        past_time = now_utc - timedelta(days=days)
        
        # Get notification stats
        total_result = await supabase.table('scheduled_notifications').select(
            'id'
        ).eq('user_id', user_id).gte(
            'created_at', past_time.isoformat()
        ).execute()
        
        sent_result = await supabase.table('scheduled_notifications').select(
            'id'
        ).eq('user_id', user_id).eq('sent', True).gte(
            'created_at', past_time.isoformat()
        ).execute()
        
        skipped_result = await supabase.table('scheduled_notifications').select(
            'id'
        ).eq('user_id', user_id).eq('skipped', True).gte(
            'created_at', past_time.isoformat()
        ).execute()
        
        pending_result = await supabase.table('scheduled_notifications').select(
            'id'
        ).eq('user_id', user_id).eq('sent', False).gte(
            'scheduled_time', now_utc.isoformat()
        ).execute()
        
        # Get stats by notification type
        type_stats_result = await supabase.table('scheduled_notifications').select(
            'notification_type'
        ).eq('user_id', user_id).gte(
            'created_at', past_time.isoformat()
        ).execute()
        
        # Count by type
        type_counts = {}
        for notification in type_stats_result.data:
            notification_type = notification['notification_type']
            type_counts[notification_type] = type_counts.get(notification_type, 0) + 1
        
        total_scheduled = len(total_result.data)
        total_sent = len(sent_result.data)
        total_skipped = len(skipped_result.data)
        total_pending = len(pending_result.data)
        
        return {
            "period_days": days,
            "total_scheduled": total_scheduled,
            "total_sent": total_sent,
            "total_skipped": total_skipped,
            "total_pending": total_pending,
            "delivery_rate": round(total_sent / total_scheduled * 100, 2) if total_scheduled > 0 else 0,
            "skip_rate": round(total_skipped / total_scheduled * 100, 2) if total_scheduled > 0 else 0,
            "by_notification_type": type_counts,
            "from_date": past_time.isoformat(),
            "to_date": now_utc.isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting notification stats: {e}")
        raise HTTPException(status_code=500, detail="Failed to get notification stats")

@router.post("/test-send")
async def send_test_notification(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """Send a test notification to the current user"""
    try:
        user_id = str(current_user.id)
        
        # Send test notification using the notification scheduler
        await habit_notification_scheduler._send_notification_to_user(
            user_id=user_id,
            title="Test Notification",
            message="This is a test notification from Joy Thief. Your habit notification system is working!",
            notification_type="test",
            habit_id="test",
            supabase_client=supabase
        )
        
        return {
            "message": "Test notification sent successfully",
            "user_id": user_id
        }
        
    except Exception as e:
        logger.error(f"Error sending test notification: {e}")
        raise HTTPException(status_code=500, detail="Failed to send test notification") 