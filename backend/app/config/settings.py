from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    # Database settings
    supabase_url: str
    supabase_key: str
    supabase_service_key: str
    
    # Stripe settings
    stripe_secret_key: str
    stripe_webhook_secret: str
    
    # App settings
    app_env: str = "development"
    debug: bool = True
    base_url: str = "http://localhost:8000/api"  # Default for development
    
    # Branch settings
    branch_public_key: str
    branch_secret_key: str

    # Twilio settings
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_verify_service_sid: str = ""
    
    # AWS settings
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""
    aws_region: str = "us-east-1"
    
    # OpenAI settings
    openai_api_key: str = ""

    # GitHub OAuth settings
    github_client_id: str = ""
    github_client_secret: str = ""
    
    # Riot Games API settings
    riot_api_key: str = ""
    
    # APNs (Apple Push Notifications) settings
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_bundle_id: str = "com.joythief.app"
    apns_key_path: str = ""
    apns_use_sandbox: str = "false"  # Changed to production for App Store
    
    # FCM (Firebase Cloud Messaging) settings
    fcm_server_key: str = ""
    
    # Notification settings
    notifications_enabled: str = "true"
    
    # Admin settings
    admin_bypass_phone: str = ""  # Phone number for admin bypass authentication
    
    class Config:
        env_file = ".env"
        env_file_encoding = 'utf-8'

@lru_cache()
def get_settings():
    return Settings() 