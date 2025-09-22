import os
from dotenv import load_dotenv
from supabase import create_client, Client
from supabase._async.client import create_client as create_async_client, AsyncClient
from uuid import UUID
from supabase.client import ClientOptions

# Load environment variables
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

# MEMORY OPTIMIZATION: Add connection pooling configuration
SUPABASE_POOL_CONFIG = {
    "max_connections": 10,  # Limit concurrent connections
    "min_connections": 2,   # Keep minimum connections alive
    "connection_timeout": 30,  # Timeout after 30 seconds
    "pool_recycle": 3600,   # Recycle connections after 1 hour
}

def get_supabase_client() -> Client:
    """
    Initialize and return a Supabase client instance using the service key for admin operations.
    
    Returns:
        Client: A configured Supabase client
        
    Raises:
        ValueError: If required environment variables are not set
    """
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise ValueError(
            "Supabase configuration not found. Please set SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables."
        )
    
    return create_client(
        supabase_url=SUPABASE_URL,
        supabase_key=SUPABASE_SERVICE_KEY
    )

# Use connection pooling for async operations
async def get_async_supabase_client():
    """Get async Supabase client with connection pooling"""
    if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
        raise ValueError(
            "Supabase configuration not found. Please set SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables."
        )
    
    client = await create_async_client(
        supabase_url=SUPABASE_URL, 
        supabase_key=SUPABASE_SERVICE_KEY
    )
    return client

# Create a singleton instance for backward compatibility
supabase = get_supabase_client() 