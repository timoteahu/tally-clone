import asyncio
import json
import logging
import os
from typing import List, Optional, Dict, Any
from datetime import datetime
from aioapns import APNs, NotificationRequest, PushType
from supabase._async.client import AsyncClient

from config.notifications import notification_config

logger = logging.getLogger(__name__)

class NotificationService:
    """Service for sending push notifications to users"""
    
    def __init__(self):
        # Configure APNs
        self.apns_key_id = notification_config.APNS_KEY_ID
        self.apns_team_id = notification_config.APNS_TEAM_ID
        self.apns_bundle_id = notification_config.APNS_BUNDLE_ID
        self.apns_key_path = notification_config.APNS_KEY_PATH
        self.apns_use_sandbox = notification_config.APNS_USE_SANDBOX
        self.notifications_enabled = notification_config.NOTIFICATIONS_ENABLED
        
        # Initialize APNs client as None - will be initialized in async context
        self.apns_client = None
        self._apns_key_content = None
        
        if self.notifications_enabled and notification_config.is_apns_configured():
            try:
                # Get the absolute path to the key file
                key_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "AuthKey_7Q7P5Q34RQ.p8"))
                
                if not os.path.exists(key_path):
                    logger.error(f"APNs key file not found at {key_path}")
                    return
                
                # Read the key file
                with open(key_path, 'r') as key_file:
                    self._apns_key_content = key_file.read()
                
                # Log APNs configuration (without sensitive data)
                
            except (IOError, OSError) as e:
                logger.error(f"Failed to load APNs key file: {e}")
                self._apns_key_content = None
        else:
            logger.info("Push notifications disabled or not configured")
    
    async def _ensure_apns_client(self):
        """Ensure APNs client is initialized in the current event loop"""
        if self.apns_client is None and self._apns_key_content is not None:
            try:
                # Log the key content length for debugging (not the actual content)
                
                self.apns_client = APNs(
                    key=self._apns_key_content,
                    key_id=self.apns_key_id,
                    team_id=self.apns_team_id,
                    topic=self.apns_bundle_id,
                    use_sandbox=self.apns_use_sandbox,
                    max_connection_attempts=3
                )
            except (ValueError, ConnectionError, TimeoutError, OSError) as e:
                logger.error(f"Failed to initialize APNs client: {e}")
                # Log more details about the configuration
                logger.error(f"APNs config - key_id: {self.apns_key_id}, team_id: {self.apns_team_id}, bundle_id: {self.apns_bundle_id}, sandbox: {self.apns_use_sandbox}")
                self.apns_client = None

    async def _cleanup_invalid_device_token(self, token: str, supabase_client: AsyncClient):
        """Mark device token as inactive when APNs returns BadDeviceToken"""
        try:
            logger.info(f"🧹 [NotificationService] Cleaning up invalid device token: {token[:10]}...")
            
            # Mark the token as inactive instead of deleting it
            result = await supabase_client.table("device_tokens").update({
                "is_active": False,
                "updated_at": datetime.utcnow().isoformat()
            }).eq("token", token).execute()
            
            if result.data:
                logger.info(f"✅ [NotificationService] Successfully marked device token {token[:10]}... as inactive")
            else:
                logger.warning(f"⚠️ [NotificationService] No device token found to cleanup: {token[:10]}...")
                
        except (ValueError, KeyError) as e:
            logger.error(f"❌ [NotificationService] Error cleaning up device token {token[:10]}...: {e}")
        except (ConnectionError, TimeoutError, OSError) as e:
            logger.error(f"❌ [NotificationService] Connectivity error during device token cleanup {token[:10]}...: {e}")
    
    async def send_comment_notification(
        self, 
        recipient_user_id: str, 
        commenter_name: str, 
        habit_type: str,
        post_id: str,
        supabase_client,
        custom_message: Optional[str] = None
    ):
        """Send notification when someone comments on user's post"""
        
        if not self.notifications_enabled:
            logger.info("Push notifications disabled")
            return
            
        try:
            # Get recipient's device tokens
            device_tokens = await self.get_user_device_tokens(recipient_user_id, supabase_client)
            
            if not device_tokens:
                logger.info(f"No device tokens found for user {recipient_user_id}")
                return
            
            # Create notification payload
            title = "New Comment"
            # Use custom message if provided, otherwise default message
            if custom_message:
                body = custom_message
            else:
                body = f"{commenter_name} commented on your {habit_type} post"
            
            notification_data = {
                "type": "comment",
                "post_id": post_id,
                "commenter_name": commenter_name,
                "habit_type": habit_type
            }
            
            # Send to all user's devices
            await self.send_apns_notification(
                device_tokens=device_tokens,
                title=title,
                body=body,
                data=notification_data,
                supabase_client=supabase_client
            )
            
            
        except (ConnectionError, TimeoutError, OSError, ValueError) as e:
            logger.error(f"Failed to send comment notification: {e}")
    
    async def send_reply_notification(
        self, 
        recipient_user_id: str, 
        commenter_name: str, 
        post_id: str,
        post_creator_name: str,
        habit_name: str,
        supabase_client
    ):
        """Send notification when someone replies to user's comment"""
        
        if not self.notifications_enabled:
            logger.info("Push notifications disabled")
            return
            
        try:
            # Get recipient's device tokens
            device_tokens = await self.get_user_device_tokens(recipient_user_id, supabase_client)
            
            if not device_tokens:
                logger.info(f"No device tokens found for user {recipient_user_id}")
                return
            
            # Create notification payload with enhanced message
            title = "New Reply"
            body = f"{commenter_name} replied to your comment on {post_creator_name}'s {habit_name} post"
            
            notification_data = {
                "type": "comment_reply",
                "post_id": post_id,
                "commenter_name": commenter_name,
                "post_creator_name": post_creator_name,
                "habit_name": habit_name
            }
            
            # Send to all user's devices
            await self.send_apns_notification(
                device_tokens=device_tokens,
                title=title,
                body=body,
                data=notification_data,
                supabase_client=supabase_client
            )
            
            
        except (ConnectionError, TimeoutError, OSError, ValueError) as e:
            logger.error(f"Failed to send reply notification: {e}")
    
    async def send_tickle_notification(
        self,
        recipient_user_id: str,
        tickler_name: str,
        habit_name: str,
        supabase_client,
        custom_message: Optional[str] = None
    ):
        """Send immediate notification when someone tickles a habit"""
        
        if not self.notifications_enabled:
            logger.info("Push notifications disabled")
            return
            
        try:
            # Get recipient's device tokens
            device_tokens = await self.get_user_device_tokens(recipient_user_id, supabase_client)
            
            if not device_tokens:
                logger.info(f"No device tokens found for user {recipient_user_id}")
                return
            
            # Create notification payload
            title = f"{tickler_name} is tickling you!"
            
            # Use custom message if provided, otherwise default message
            if custom_message:
                body = custom_message
            else:
                body = f"Hey! Don't forget about your {habit_name} habit!"
            
            notification_data = {
                "type": "tickle",
                "habit_name": habit_name,
                "tickler_name": tickler_name
            }
            
            # Send to all user's devices
            await self.send_apns_notification(
                device_tokens=device_tokens,
                title=title,
                body=body,
                data=notification_data,
                supabase_client=supabase_client
            )
            
            logger.info(f"Sent tickle notification from {tickler_name} for {habit_name}")
            
        except (ConnectionError, TimeoutError, OSError, ValueError) as e:
            logger.error(f"Failed to send tickle notification: {e}")
    
    async def send_gaming_limit_warning_notification(
        self,
        user_id: str,
        habit_name: str,
        hours_remaining: float,
        current_hours: float,
        limit_hours: float,
        supabase_client
    ):
        """Send notification when user is approaching their gaming limit"""
        
        if not self.notifications_enabled:
            logger.info("Push notifications disabled")
            return
            
        try:
            # Get user's device tokens
            device_tokens = await self.get_user_device_tokens(user_id, supabase_client)
            
            if not device_tokens:
                logger.info(f"No device tokens found for user {user_id}")
                return
            
            # Create notification payload
            title = "Gaming Limit Warning"
            
            if hours_remaining <= 0:
                body = f"You've reached your {habit_name} limit of {limit_hours:.1f} hours!"
            else:
                hours_str = f"{hours_remaining:.1f} hour" if hours_remaining == 1 else f"{hours_remaining:.1f} hours"
                body = f"You have {hours_str} left of your {habit_name} limit today"
            
            notification_data = {
                "type": "gaming_limit_warning",
                "habit_name": habit_name,
                "hours_remaining": hours_remaining,
                "current_hours": current_hours,
                "limit_hours": limit_hours
            }
            
            # Send to all user's devices
            await self.send_apns_notification(
                device_tokens=device_tokens,
                title=title,
                body=body,
                data=notification_data,
                supabase_client=supabase_client
            )
            
            logger.info(f"Sent gaming limit warning to user {user_id} for {habit_name}")
            
        except (ConnectionError, TimeoutError, OSError, ValueError) as e:
            logger.error(f"Failed to send gaming limit warning notification: {e}")
    
    async def send_gaming_overage_notification(
        self,
        user_id: str,
        habit_name: str,
        overage_hours: float,
        penalty_amount: float,
        period: str,  # "day" or "week"
        supabase_client
    ):
        """Send notification when user has exceeded their gaming limit and been charged"""
        
        if not self.notifications_enabled:
            logger.info("Push notifications disabled")
            return
            
        try:
            # Get user's device tokens
            device_tokens = await self.get_user_device_tokens(user_id, supabase_client)
            
            if not device_tokens:
                logger.info(f"No device tokens found for user {user_id}")
                return
            
            # Create notification payload
            title = "Gaming Limit Exceeded"
            
            # Format the overage hours nicely
            hours_str = f"{overage_hours:.1f} hour" if overage_hours <= 1 else f"{overage_hours:.1f} hours"
            
            # Format the penalty amount
            penalty_str = f"${penalty_amount:.2f}"
            
            body = f"You exceeded your {habit_name} limit by {hours_str} this {period}. You've been charged {penalty_str}."
            
            notification_data = {
                "type": "gaming_overage",
                "habit_name": habit_name,
                "overage_hours": overage_hours,
                "penalty_amount": penalty_amount,
                "period": period
            }
            
            # Send to all user's devices
            await self.send_apns_notification(
                device_tokens=device_tokens,
                title=title,
                body=body,
                data=notification_data,
                supabase_client=supabase_client
            )
            
            logger.info(f"Sent gaming overage notification to user {user_id} for {habit_name}")
            
        except (ConnectionError, TimeoutError, OSError, ValueError) as e:
            logger.error(f"Failed to send gaming overage notification: {e}")
    
    async def send_habit_verification_notification(
        self,
        recipient_user_id: str,
        verifier_name: str,
        habit_name: str,
        habit_type: str,
        supabase_client
    ):
        """Send notification when someone verifies their habit to the habit recipient"""
        
        if not self.notifications_enabled:
            logger.info("Push notifications disabled")
            return
            
        try:
            # Get recipient's device tokens
            device_tokens = await self.get_user_device_tokens(recipient_user_id, supabase_client)
            
            if not device_tokens:
                logger.info(f"No device tokens found for user {recipient_user_id}")
                return
            
            # Create notification payload
            title = f"{verifier_name} completed their habit!"
            body = f"{verifier_name} just verified their {habit_name} habit"
            
            notification_data = {
                "type": "habit_verification",
                "verifier_name": verifier_name,
                "habit_name": habit_name,
                "habit_type": habit_type
            }
            
            # Send to all recipient's devices
            await self.send_apns_notification(
                device_tokens=device_tokens,
                title=title,
                body=body,
                data=notification_data,
                supabase_client=supabase_client
            )
            
            logger.info(f"Sent habit verification notification to recipient {recipient_user_id} for {verifier_name}'s {habit_name}")
            
        except (ConnectionError, TimeoutError, OSError, ValueError) as e:
            logger.error(f"Failed to send habit verification notification: {e}")
    
    async def send_new_post_notification(
        self,
        friends_user_ids: List[str],
        poster_name: str,
        habit_type: str,
        post_id: str,
        supabase_client
    ):
        """Send notification when someone creates a new post"""
        
        if not self.notifications_enabled:
            logger.info("Push notifications disabled")
            return
            
        try:
            # Batch fetch all device tokens for all friends in a single query to avoid N+1
            if not friends_user_ids:
                return
                
            tokens_result = await supabase_client.table("device_tokens") \
                .select("user_id, token") \
                .in_("user_id", friends_user_ids) \
                .eq("is_active", True) \
                .execute()
            
            # Group tokens by user_id
            user_tokens_map = {}
            if tokens_result.data:
                for row in tokens_result.data:
                    user_id = row["user_id"]
                    if user_id not in user_tokens_map:
                        user_tokens_map[user_id] = []
                    user_tokens_map[user_id].append(row["token"])
            
            # Create notification payload once (same for all friends)
            title = "New Post"
            body = f"{poster_name} just created a new {habit_type} post"
            
            notification_data = {
                "type": "new_post", 
                "post_id": post_id,
                "poster_name": poster_name,
                "habit_type": habit_type
            }
            
            # Send notifications to each friend's devices
            for friend_user_id in friends_user_ids:
                device_tokens = user_tokens_map.get(friend_user_id, [])
                
                if not device_tokens:
                    continue
                
                # Send to all friend's devices
                await self.send_apns_notification(
                    device_tokens=device_tokens,
                    title=title,
                    body=body,
                    data=notification_data,
                    supabase_client=supabase_client
                )
        except (ConnectionError, TimeoutError, OSError, ValueError) as e:
            logger.error(f"Failed to send new post notification: {e}")
    
    async def get_user_device_tokens(self, user_id: str, supabase_client) -> List[str]:
        """Get all device tokens for a user"""
        try:
            # Query device_tokens table for user's active tokens
            result = await supabase_client.table("device_tokens").select("token").eq("user_id", user_id).eq("is_active", True).execute()
            
            if result.data:
                return [row["token"] for row in result.data]
            return []
            
        except (ValueError, KeyError, ConnectionError, TimeoutError, OSError) as e:
            logger.error(f"Failed to get device tokens for user {user_id}: {e}")
            return []
    
    async def send_apns_notification(
        self,
        device_tokens: List[str],
        title: str,
        body: str,
        data: Dict[str, Any],
        badge: Optional[int] = None,
        supabase_client: Optional[AsyncClient] = None
    ):
        """Send APNs notification (iOS)"""
        
        # Ensure APNs client is initialized in current event loop
        await self._ensure_apns_client()
        
        if not self.apns_client:
            logger.warning("APNs client not configured")
            return
        
        # Create notification payload
        payload = {
            "aps": {
                "alert": {
                    "title": title,
                    "body": body
                },
                "sound": "default"
            }
        }
        
        # Add custom data
        for key, value in data.items():
            payload[key] = value
        
        # Add badge if specified
        if badge is not None:
            payload["aps"]["badge"] = badge
        
        # Send to each device token
        for token in device_tokens:
            try:
                request = NotificationRequest(
                    device_token=token,
                    message=payload,
                    push_type=PushType.ALERT
                )
                
                # Log the notification attempt
                
                response = await self.apns_client.send_notification(request)
                
                if response.is_successful:
                    logger.info(f"Successfully sent APNs notification to token {token[:10]}...")
                else:
                    logger.error(f"Failed to send APNs notification to token {token[:10]}...: {response.description}")
                    
                    # Check if it's a BadDeviceToken error and clean it up
                    if (response.description and "BadDeviceToken" in str(response.description)) or (hasattr(response, 'status') and response.status == 400):
                        if supabase_client:
                            logger.warning(f"🚫 [NotificationService] BadDeviceToken detected for {token[:10]}..., cleaning up")
                            await self._cleanup_invalid_device_token(token, supabase_client)
                        else:
                            logger.warning(f"🚫 [NotificationService] BadDeviceToken detected for {token[:10]}... but no supabase_client provided for cleanup")
                    
            except (ConnectionError, TimeoutError, OSError, ValueError) as e:
                logger.error(f"Error sending APNs notification to token {token[:10]}...: {str(e)}")
                # Log the full exception for debugging
                import traceback
                logger.error(f"Full exception: {traceback.format_exc()}")

# Global notification service instance
notification_service = NotificationService() 