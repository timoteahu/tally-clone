import asyncio
from typing import Optional
from fastapi import HTTPException
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory, disable_print, memory_optimized

# Disable verbose printing for performance
print = disable_print()

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
                raise HTTPException(
                    status_code=500, 
                    detail=f"Failed to upload {file_name} after {retries} attempts: {str(e)}"
                )
            
            # Wait before retrying with exponential backoff
            await asyncio.sleep(delay)
            delay *= 2  # Exponential back-off

@memory_optimized(cleanup_args=False)
async def download_identity_snapshot_from_storage(user_id: str, supabase: AsyncClient) -> bytes:
    """
    Download identity snapshot with memory optimization and proper error handling.
    
    Args:
        user_id: User ID for the identity snapshot
        supabase: Async Supabase client
        
    Returns:
        Identity snapshot bytes
        
    Raises:
        HTTPException: If download fails
    """
    try:
        filename = f"{user_id}.jpg"
        
        # Download from Supabase storage
        response = await supabase.storage.from_("identity-snapshots").download(filename)
        
        if not response:
            raise HTTPException(
                status_code=400, 
                detail="Identity snapshot not found. Please upload an identity snapshot in settings first."
            )
        
        # Extract bytes immediately and clear the response object
        identity_bytes = bytes(response)
        
        # Explicit cleanup of response object
        try:
            if hasattr(response, 'close'):
                response.close()
            if hasattr(response, 'clear'):
                response.clear()
            cleanup_memory(response)
        except Exception:
            pass
        
        print(f"📷 Identity snapshot downloaded: {len(identity_bytes) / 1024:.1f}KB")
        return identity_bytes
            
    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except Exception as e:
        print(f"Failed to download identity snapshot for user {user_id}: {e}")
        raise HTTPException(
            status_code=400, 
            detail="Failed to download identity snapshot from storage"
        )

@memory_optimized(cleanup_args=False)
async def generate_signed_url_optimized(
    supabase: AsyncClient,
    bucket_name: str,
    file_path: str,
    expires_in: int = 3600
) -> Optional[str]:
    """
    Generate a signed URL for a file in Supabase storage with memory optimization.
    
    Args:
        supabase: Async Supabase client
        bucket_name: Storage bucket name
        file_path: Path to the file in storage
        expires_in: URL expiration time in seconds
        
    Returns:
        Signed URL string or None if generation fails
    """
    try:
        # Generate signed URL
        response = await supabase.storage.from_(bucket_name).create_signed_url(
            file_path, 
            expires_in=expires_in
        )
        
        if not response:
            return None
        
        # Extract URL immediately
        signed_url = response.get('signedURL') if isinstance(response, dict) else response
        
        # Cleanup response object
        try:
            if isinstance(response, dict):
                response.clear()
            cleanup_memory(response)
        except Exception:
            pass
        
        return signed_url
        
    except Exception as e:
        print(f"Error generating signed URL for {file_path}: {e}")
        return None

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

def get_file_extension(filename: str) -> str:
    """
    Get file extension from filename.
    
    Args:
        filename: Name of the file
        
    Returns:
        File extension (including the dot) or empty string
    """
    if '.' in filename:
        return filename.rsplit('.', 1)[-1].lower()
    return ''

def is_valid_image_extension(filename: str) -> bool:
    """
    Check if filename has a valid image extension.
    
    Args:
        filename: Name of the file to check
        
    Returns:
        True if valid image extension, False otherwise
    """
    valid_extensions = {
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'tif'
    }
    extension = get_file_extension(filename)
    return extension in valid_extensions

def generate_storage_filename(user_id: str, verification_id: str, file_type: str = "content") -> str:
    """
    Generate a standardized filename for storage.
    
    Args:
        user_id: User ID
        verification_id: Verification ID
        file_type: Type of file ("content", "selfie", "photo")
        
    Returns:
        Standardized filename
    """
    if file_type == "content":
        return f"{user_id}_{verification_id}.jpg"
    elif file_type == "selfie":
        return f"{user_id}_{verification_id}_selfie.jpg"
    elif file_type == "photo":
        return f"{user_id}_{verification_id}_photo.jpg"
    else:
        return f"{user_id}_{verification_id}_{file_type}.jpg" 