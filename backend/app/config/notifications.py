import os
from typing import Optional
from config.settings import get_settings

# Get settings instance
settings = get_settings()

class NotificationConfig:
    """Configuration for push notifications"""
    
    # FCM (Firebase Cloud Messaging) configuration
    FCM_SERVER_KEY: Optional[str] = settings.fcm_server_key if settings.fcm_server_key else None
    
    # APNs (Apple Push Notification service) configuration
    APNS_KEY_ID: Optional[str] = settings.apns_key_id if settings.apns_key_id else None
    APNS_TEAM_ID: Optional[str] = settings.apns_team_id if settings.apns_team_id else None
    APNS_BUNDLE_ID: Optional[str] = settings.apns_bundle_id
    APNS_KEY_PATH: Optional[str] = settings.apns_key_path if settings.apns_key_path else None
    APNS_USE_SANDBOX: bool = settings.apns_use_sandbox.lower() == "true"
    
    # Environment settings
    NOTIFICATIONS_ENABLED: bool = settings.notifications_enabled.lower() == "true"
    
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

# Global notification config instance
notification_config = NotificationConfig() 