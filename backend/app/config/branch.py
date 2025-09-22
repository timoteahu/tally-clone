import os
from pydantic_settings import BaseSettings

class BranchSettings(BaseSettings):
    """
    Configuration settings for the application.
    
    Note: Branch.io integration is now handled entirely in the frontend.
    This configuration is maintained for other application settings.
    """
    
    # Supabase settings
    supabase_url: str = os.getenv("SUPABASE_URL", "")
    supabase_key: str = os.getenv("SUPABASE_KEY", "")
    
    # Stripe settings
    stripe_secret_key: str = os.getenv("STRIPE_SECRET_KEY", "")
    stripe_webhook_secret: str = os.getenv("STRIPE_WEBHOOK_SECRET", "")
    
    # App settings
    app_env: str = os.getenv("APP_ENV", "development")
    debug: bool = os.getenv("DEBUG", "False").lower() == "true"
    
    class Config:
        env_file = ".env"
        env_file_encoding = 'utf-8'
        extra = "allow"  # This allows extra fields in the environment

# For backward compatibility, keeping the same variable name
branch_settings = BranchSettings() 