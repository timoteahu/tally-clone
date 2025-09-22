import os
from typing import Optional

class NotificationConfig:
    """Configuration for push notifications"""
    
    # FCM (Firebase Cloud Messaging) configuration
    FCM_SERVER_KEY: Optional[str] = os.getenv("FCM_SERVER_KEY")
    
    # APNs (Apple Push Notification service) configuration
    APNS_KEY_ID: Optional[str] = os.getenv("APNS_KEY_ID")
    APNS_TEAM_ID: Optional[str] = os.getenv("APNS_TEAM_ID")
    APNS_BUNDLE_ID: Optional[str] = os.getenv("APNS_BUNDLE_ID", "com.joythief.app")
    APNS_KEY_PATH: Optional[str] = os.getenv("APNS_KEY_PATH")
    
    # Environment settings
    NOTIFICATIONS_ENABLED: bool = os.getenv("NOTIFICATIONS_ENABLED", "true").lower() == "true"
    
    @classmethod
    def is_fcm_configured(cls) -> bool:
        """Check if FCM is properly configured"""
        return cls.FCM_SERVER_KEY is not None
    
    @classmethod
    def is_apns_configured(cls) -> bool:
        """Check if APNs is properly configured"""
        return all([
            cls.APNS_KEY_ID,
            cls.APNS_TEAM_ID,
            cls.APNS_BUNDLE_ID,
            cls.APNS_KEY_PATH
        ])

# Make configuration available at module level
notification_config = NotificationConfig() 