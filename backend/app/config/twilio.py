import os
from typing import Optional
from twilio.rest import Client
import logging

logger = logging.getLogger(__name__)

# Singleton Twilio client
_twilio_client: Optional[Client] = None

def get_twilio_client() -> Optional[Client]:
    """
    Get or create a singleton Twilio client.
    This ensures we reuse the same client instance across all requests,
    preventing memory leaks from creating new clients repeatedly.
    """
    global _twilio_client
    
    if _twilio_client is None:
        try:
            account_sid = os.getenv("TWILIO_ACCOUNT_SID")
            auth_token = os.getenv("TWILIO_AUTH_TOKEN")
            
            if not account_sid or not auth_token:
                logger.error("Twilio credentials not configured")
                return None
            
            _twilio_client = Client(account_sid, auth_token)
            logger.info("✅ Created singleton Twilio client")
        except Exception as e:
            logger.error(f"Failed to create Twilio client: {e}")
            return None
    
    return _twilio_client

def reset_twilio_client():
    """
    Reset Twilio client (useful for testing or forced reconnection).
    This should rarely be needed in production.
    """
    global _twilio_client
    
    if _twilio_client:
        try:
            # Twilio client doesn't have an explicit close method, but we can
            # remove the reference and let garbage collection handle it
            _twilio_client = None
            logger.info("Reset Twilio client")
        except Exception as e:
            logger.error(f"Error resetting Twilio client: {e}")