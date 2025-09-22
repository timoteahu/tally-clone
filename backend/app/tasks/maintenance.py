import logging
from supabase import Client
from config.database import get_supabase_client

# Set up logging
logger = logging.getLogger(__name__)

async def archive_old_feed_cards_task():
    """Archive and purge feed cards older than 24 hours.

    This simply calls the Postgres stored function `archive_old_feed_cards`, which
    performs the delete in-database.  The heavy work (archiving via trigger +
    cascading deletes) happens inside Postgres so this task is lightweight.
    """
    import ssl
    import time
    max_retries = 3
    retry_delay = 2  # seconds
    
    for attempt in range(max_retries):
        try:
            supabase: Client = get_supabase_client()
            supabase.rpc("archive_old_feed_cards").execute()
            logger.info("✅ Archived & purged feed cards older than 24h")
            return  # Success, exit function
        except ssl.SSLError as e:
            if attempt < max_retries - 1:
                logger.warning(f"SSL error in archive_old_feed_cards_task (attempt {attempt + 1}/{max_retries}): {e}. Retrying in {retry_delay}s...")
                time.sleep(retry_delay)
                retry_delay *= 2  # Exponential backoff
            else:
                logger.error(f"❌ archive_old_feed_cards_task failed after {max_retries} attempts: {e}")
        except Exception as e:
            logger.error(f"❌ archive_old_feed_cards_task: {e}")
            break  # Don't retry for non-SSL errors 