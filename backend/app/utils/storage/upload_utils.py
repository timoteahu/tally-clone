import asyncio
import time
import random
from typing import Optional
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory, disable_print, memory_optimized

# Disable verbose printing for performance
print = disable_print()

@memory_optimized(cleanup_args=False)
async def upload_to_supabase_storage_with_retry(
    supabase: AsyncClient, 
    bucket_name: str, 
    filename: str, 
    file_data: bytes, 
    content_type: str, 
    max_retries: int = 3
):
    """
    Upload file to Supabase storage with exponential back-off retries and memory optimization.
    Standard version without custom headers.
    """
    for attempt in range(max_retries):
        try:
            upload_response = await supabase.storage.from_(bucket_name).upload(
                filename, 
                file_data,
                {
                    "content-type": content_type,
                    "upsert": "true"
                }
            )
            
            print(f"📤 Uploaded {filename} to bucket '{bucket_name}' (attempt {attempt + 1})")
            return upload_response
            
        except Exception as e:
            error_str = str(e).lower()
            is_ssl_error = any(ssl_indicator in error_str for ssl_indicator in [
                'ssl', 'tls', 'bad record mac', 'connection reset', 'timeout'
            ])
            
            if attempt < max_retries - 1 and is_ssl_error:
                wait_time = (2 ** attempt) + random.uniform(0, 1)
                print(f"⚠️ Storage upload failed with SSL/network error (attempt {attempt + 1}): {e}")
                await asyncio.sleep(wait_time)
                continue
            else:
                print(f"❌ Storage upload failed permanently: {e}")
                raise e
    
    raise Exception("Storage upload failed after all retry attempts")

@memory_optimized(cleanup_args=False)
async def upload_to_supabase_storage_with_cache_control(
    supabase: AsyncClient, 
    bucket_name: str, 
    filename: str, 
    file_data: bytes, 
    content_type: str,
    cache_control: str,
    max_retries: int = 3
):
    """
    Upload file to Supabase storage with custom cache control headers and retry logic.
    """
    for attempt in range(max_retries):
        try:
            upload_response = await supabase.storage.from_(bucket_name).upload(
                filename, 
                file_data,
                {
                    "content-type": content_type,
                    "cache-control": cache_control,
                    "upsert": "true"
                }
            )
            
            print(f"📤 Uploaded {filename} to bucket '{bucket_name}' with cache control (attempt {attempt + 1})")
            return upload_response
            
        except Exception as e:
            error_str = str(e).lower()
            is_ssl_error = any(ssl_indicator in error_str for ssl_indicator in [
                'ssl', 'tls', 'bad record mac', 'connection reset', 'timeout'
            ])
            
            if attempt < max_retries - 1 and is_ssl_error:
                wait_time = (2 ** attempt) + random.uniform(0, 1)
                print(f"⚠️ Storage upload failed with SSL/network error (attempt {attempt + 1}): {e}")
                time.sleep(wait_time)
                continue
            else:
                print(f"❌ Storage upload failed permanently: {e}")
                raise e
    
    raise Exception("Storage upload failed after all retry attempts")

@memory_optimized(cleanup_args=False)
async def async_upload_to_supabase_storage_with_retry(
    supabase: AsyncClient,
    bucket_name: str,
    file_name: str,
    file_bytes: bytes,
    content_type: str,
    retries: int = 3,
    initial_delay: float = 1.0,
) -> None:
    """
    Upload a file to Supabase Storage with exponential back-off retries and memory optimization.
    Enhanced version with configurable delays and error handling.

    Args:
        supabase: Supabase async client instance
        bucket_name: Storage bucket name (e.g. "public_images" or "private_images")
        file_name: Destination object key / filename
        file_bytes: Raw file contents
        content_type: MIME type (e.g. "image/jpeg")
        retries: How many times to retry before failing
        initial_delay: Delay (seconds) before first retry
    """
    # Safety: ensure we have a real client
    if asyncio.iscoroutine(supabase):
        supabase = await supabase

    if not isinstance(supabase, AsyncClient):
        raise TypeError("supabase parameter must be an AsyncClient instance")

    delay = initial_delay
    last_exception = None
    
    for attempt in range(1, retries + 1):
        try:
            await supabase.storage.from_(bucket_name).upload(
                file_name,
                file_bytes,
                {
                    "content-type": content_type,
                    "upsert": "true",  # Allow overwriting
                },
            )
            print(f"📤 Uploaded {file_name} to bucket '{bucket_name}' (attempt {attempt})")
            return  # Success – exit the function
            
        except Exception as e:
            last_exception = e
            print(f"⚠️ Upload attempt {attempt} for {file_name} failed: {e}")
            
            if attempt == retries:
                # Exhausted retries – re-raise the last exception
                from fastapi import HTTPException
                raise HTTPException(
                    status_code=500, 
                    detail=f"Failed to upload {file_name} after {retries} attempts: {str(e)}"
                )
            
            # Wait before retrying with exponential backoff
            await asyncio.sleep(delay)
            delay *= 2  # Exponential back-off

@memory_optimized(cleanup_args=False)
async def delete_file_from_storage(
    supabase: AsyncClient,
    bucket_name: str,
    file_path: str
) -> bool:
    """
    Delete a file from Supabase storage with error handling.
    
    Args:
        supabase: Async Supabase client
        bucket_name: Storage bucket name
        file_path: Path to the file to delete
        
    Returns:
        True if deletion was successful, False otherwise
    """
    try:
        # Delete the file
        response = await supabase.storage.from_(bucket_name).remove([file_path])
        
        success = response is not None
        
        # Cleanup response
        try:
            if response:
                if hasattr(response, 'clear'):
                    response.clear()
                cleanup_memory(response)
        except Exception:
            pass
        
        if success:
            print(f"🗑️ Deleted {file_path} from {bucket_name}")
        else:
            print(f"⚠️ Failed to delete {file_path} from {bucket_name}")
        
        return success
        
    except Exception as e:
        print(f"Error deleting file {file_path}: {e}")
        return False

@memory_optimized(cleanup_args=False)
async def check_file_exists_in_storage(
    supabase: AsyncClient,
    bucket_name: str,
    file_path: str
) -> bool:
    """
    Check if a file exists in Supabase storage.
    
    Args:
        supabase: Async Supabase client
        bucket_name: Storage bucket name
        file_path: Path to check
        
    Returns:
        True if file exists, False otherwise
    """
    try:
        # Try to get file info
        response = await supabase.storage.from_(bucket_name).list(
            path=file_path,
            limit=1
        )
        
        exists = response and len(response) > 0
        
        # Cleanup response
        try:
            if response:
                if isinstance(response, list):
                    response.clear()
                cleanup_memory(response)
        except Exception:
            pass
        
        return exists
        
    except Exception as e:
        print(f"Error checking file existence for {file_path}: {e}")
        return False 