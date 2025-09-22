import time
from typing import Optional, Dict, Any
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory, disable_print, memory_optimized

# Disable verbose printing for performance
print = disable_print()

# MEMORY OPTIMIZATION: Unified URL cache with LRU eviction
_url_cache = {}
_cache_access_order = []  # LRU tracking
_cache_size_limit = 200  # Increased limit for multiple URL types

def _cleanup_cache():
    """Aggressive cache cleanup with LRU eviction"""
    current_time = time.time()
    
    # Remove expired entries
    expired_keys = []
    for key in list(_url_cache.keys()):
        if key not in _cache_access_order:
            expired_keys.append(key)
        elif current_time >= _url_cache.get(key, {}).get('expires_at', 0):
            expired_keys.append(key)
    
    for key in expired_keys:
        _url_cache.pop(key, None)
        if key in _cache_access_order:
            _cache_access_order.remove(key)
    
    # LRU eviction if cache is too large
    while len(_url_cache) > _cache_size_limit:
        oldest_key = _cache_access_order.pop(0)
        _url_cache.pop(oldest_key, None)
    
    if expired_keys:
        print(f"🧹 URL cache cleanup: removed {len(expired_keys)} entries, {len(_url_cache)} remaining")

def _get_cached_url(cache_key: str) -> Optional[str]:
    """Get cached URL if not expired with LRU tracking"""
    if cache_key in _url_cache:
        cache_entry = _url_cache[cache_key]
        if time.time() < cache_entry.get('expires_at', 0):
            # Update LRU order
            if cache_key in _cache_access_order:
                _cache_access_order.remove(cache_key)
            _cache_access_order.append(cache_key)
            return cache_entry.get('url')
        else:
            # Expired - remove immediately
            _url_cache.pop(cache_key, None)
            if cache_key in _cache_access_order:
                _cache_access_order.remove(cache_key)
    return None

def _set_cached_url(cache_key: str, url: str, ttl: int = 1800) -> None:
    """Cache URL with aggressive size management"""
    # Cleanup before adding
    _cleanup_cache()
    
    _url_cache[cache_key] = {
        'url': url,
        'expires_at': time.time() + ttl
    }
    if cache_key in _cache_access_order:
        _cache_access_order.remove(cache_key)
    _cache_access_order.append(cache_key)

@memory_optimized(cleanup_args=False)
async def generate_signed_url_optimized(
    supabase: AsyncClient,
    bucket_name: str,
    file_path: str,
    expires_in: int = 3600
) -> Optional[str]:
    """
    Generate a signed URL for any file in Supabase storage with memory optimization.
    
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
async def generate_profile_photo_url(supabase, profile_photo_filename: Optional[str]) -> Optional[str]:
    """
    Generate a signed URL for a profile photo filename.
    Returns None if no filename is provided or if an error occurs.
    """
    if not profile_photo_filename:
        return None
    
    # Check cache first
    cache_key = f"profile-photos:{profile_photo_filename}"
    cached_url = _get_cached_url(cache_key)
    if cached_url:
        return cached_url
    
    try:
        # Ensure filename has .jpg extension for storage lookup
        if not profile_photo_filename.endswith('.jpg'):
            storage_filename = f"{profile_photo_filename}.jpg"
        else:
            storage_filename = profile_photo_filename
        
        # Use the optimized signed URL function
        signed_url = await generate_signed_url_optimized(
            supabase, "profile-photos", storage_filename, 3600
        )
        
        # Cache the result
        if signed_url:
            _set_cached_url(cache_key, signed_url)
        
        return signed_url
        
    except Exception as e:
        print(f"Error generating signed URL for profile photo: {e}")
        return None

@memory_optimized(cleanup_args=False)
async def generate_identity_snapshot_url(supabase: AsyncClient, identity_snapshot_filename: Optional[str]) -> Optional[str]:
    """
    Generate a signed URL for an identity snapshot filename.
    Returns None if no filename is provided or if an error occurs.
    """
    if not identity_snapshot_filename:
        return None
    
    # Check cache first
    cache_key = f"identity-snapshots:{identity_snapshot_filename}"
    cached_url = _get_cached_url(cache_key)
    if cached_url:
        return cached_url
    
    try:
        # Ensure filename has .jpg extension for storage lookup
        if not identity_snapshot_filename.endswith('.jpg'):
            storage_filename = f"{identity_snapshot_filename}.jpg"
        else:
            storage_filename = identity_snapshot_filename
        
        # Use the optimized signed URL function
        signed_url = await generate_signed_url_optimized(
            supabase, "identity-snapshots", storage_filename, 3600
        )
        
        # Cache the result
        if signed_url:
            _set_cached_url(cache_key, signed_url)
        
        return signed_url
        
    except Exception as e:
        print(f"Error generating signed URL for identity snapshot: {e}")
        return None

@memory_optimized(cleanup_args=False)
async def generate_post_image_url(supabase, image_filename: Optional[str], is_private: bool) -> Optional[str]:
    """
    Generate a signed URL for a post image filename.
    Returns None if no filename is provided or if an error occurs.
    """
    if not image_filename:
        return None
    
    # Check cache first
    bucket_name = 'private_images' if is_private else 'public_images'
    cache_key = f"{bucket_name}:{image_filename}"
    cached_url = _get_cached_url(cache_key)
    if cached_url:
        return cached_url
    
    try:
        # Ensure filename has .jpg extension for storage lookup
        if not image_filename.endswith('.jpg'):
            storage_filename = f"{image_filename}.jpg"
        else:
            storage_filename = image_filename
        
        # Use the optimized signed URL function
        signed_url = await generate_signed_url_optimized(
            supabase, bucket_name, storage_filename, 3600
        )
        
        # Cache the result
        if signed_url:
            _set_cached_url(cache_key, signed_url)
        
        return signed_url
        
    except Exception as e:
        print(f"Error generating signed URL for post image: {e}")
        return None

@memory_optimized(cleanup_args=False)
async def generate_post_image_urls(supabase, post: dict, is_private: bool) -> dict:
    """
    Generate signed URLs for both selfie and content images in a post.
    Returns a dict with 'selfie_image_url' and 'content_image_url' keys.
    """
    urls = {}
    
    # Generate selfie image URL
    selfie_filename = post.get("selfie_image_filename")
    if selfie_filename:
        urls["selfie_image_url"] = await generate_post_image_url(supabase, selfie_filename, is_private)
    elif post.get("user_id") and post.get("id"):
        # Fallback to legacy pattern for selfie (based on post ID)
        legacy_selfie_filename = f"{post['user_id']}_{post['id']}_selfie.jpg"
        urls["selfie_image_url"] = await generate_post_image_url(supabase, legacy_selfie_filename, is_private)
    
    # Generate content image URL using existing image_filename field
    content_filename = post.get("image_filename")
    if content_filename:
        urls["content_image_url"] = await generate_post_image_url(supabase, content_filename, is_private)
    elif post.get("user_id") and post.get("id"):
        # Fallback to legacy pattern for content (based on post ID)
        legacy_content_filename = f"{post['user_id']}_{post['id']}.jpg"
        urls["content_image_url"] = await generate_post_image_url(supabase, legacy_content_filename, is_private)
    
    # Don't cleanup the post dict - it's still needed by the caller!
    
    return urls

@memory_optimized(cleanup_args=False)
async def generate_verification_image_url(supabase, image_filename: Optional[str], is_private: bool) -> Optional[str]:
    """
    Generate a signed URL for a verification image filename.
    Returns None if no filename is provided or if an error occurs.
    """
    if not image_filename:
        return None
    
    # Check cache first
    bucket_name = 'private_images' if is_private else 'public_images'
    cache_key = f"{bucket_name}:{image_filename}"
    cached_url = _get_cached_url(cache_key)
    if cached_url:
        return cached_url
    
    try:
        # Ensure filename has .jpg extension for storage lookup
        if not image_filename.endswith('.jpg'):
            storage_filename = f"{image_filename}.jpg"
        else:
            storage_filename = image_filename
        
        # Use the optimized signed URL function
        signed_url = await generate_signed_url_optimized(
            supabase, bucket_name, storage_filename, 3600
        )
        
        # Cache the result
        if signed_url:
            _set_cached_url(cache_key, signed_url)
        
        return signed_url
        
    except Exception as e:
        print(f"Error generating signed URL for verification image: {e}")
        return None

@memory_optimized(cleanup_args=False)
async def generate_verification_image_urls(supabase, verification_data: dict, is_private: bool) -> dict:
    """
    Generate signed URLs for both selfie and content images in a verification.
    Returns a dict with 'selfie_image_url' and 'content_image_url' keys.
    """
    urls = {}
    
    # Generate selfie image URL
    selfie_filename = verification_data.get("selfie_image_filename")
    if selfie_filename:
        urls["selfie_image_url"] = await generate_verification_image_url(supabase, selfie_filename, is_private)
    elif verification_data.get("user_id") and verification_data.get("id"):
        # Fallback to legacy pattern for selfie
        legacy_selfie_filename = f"{verification_data['user_id']}_{verification_data['id']}_selfie.jpg"
        urls["selfie_image_url"] = await generate_verification_image_url(supabase, legacy_selfie_filename, is_private)
    
    # Generate content image URL using existing image_filename field
    content_filename = verification_data.get("image_filename")
    if content_filename:
        urls["content_image_url"] = await generate_verification_image_url(supabase, content_filename, is_private)
    elif verification_data.get("user_id") and verification_data.get("id"):
        # Fallback to legacy pattern for content
        legacy_content_filename = f"{verification_data['user_id']}_{verification_data['id']}.jpg"
        urls["content_image_url"] = await generate_verification_image_url(supabase, legacy_content_filename, is_private)
    
    # Don't cleanup verification_data - it's still needed by the caller!
    # The caller is responsible for cleanup when done with the data
    
    return urls 