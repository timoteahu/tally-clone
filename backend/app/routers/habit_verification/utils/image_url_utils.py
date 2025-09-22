import time
from typing import Optional, Dict
from supabase._async.client import AsyncClient
from utils.memory_optimization import cleanup_memory, disable_print, memory_optimized

# Disable verbose printing for performance
print = disable_print()

# MEMORY OPTIMIZATION: Reduce cache size and implement LRU eviction
_url_cache = {}
_cache_access_order = []  # LRU tracking
_cache_size_limit = 100  # Reduced from 1000 to prevent memory growth

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

def _set_cached_url(cache_key: str, url: str) -> None:
    """Cache URL with aggressive size management"""
    # Cleanup before adding
    _cleanup_cache()
    
    _url_cache[cache_key] = {
        'url': url,
        'expires_at': time.time() + 1800  # 30 minutes
    }
    if cache_key in _cache_access_order:
        _cache_access_order.remove(cache_key)
    _cache_access_order.append(cache_key)

@memory_optimized(cleanup_args=False)
async def generate_verification_image_url(supabase, image_filename: Optional[str], is_private: bool) -> Optional[str]:
    """
    Generate a signed URL for a verification image filename.
    Returns None if no filename is provided or if an error occurs.
    Uses flat storage structure: {user_id}_{verification_id}.jpg
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
        
        # Fix: Use proper isinstance check for AsyncClient
        if isinstance(supabase, AsyncClient):
            signed_url_response = await supabase.storage.from_(bucket_name).create_signed_url(
                storage_filename, 
                expires_in=3600
            )
        else:
            signed_url_response = supabase.storage.from_(bucket_name).create_signed_url(
                storage_filename, 
                expires_in=3600
            )
        
        verification_image_url = signed_url_response.get('signedURL') if isinstance(signed_url_response, dict) else signed_url_response
        
        # Cache the result
        if verification_image_url:
            _set_cached_url(cache_key, verification_image_url)
        
        # Clean up response
        cleanup_memory(signed_url_response)
        
        return verification_image_url
        
    except Exception as e:
        print(f"Error generating signed URL for verification image: {e}")
        return None

@memory_optimized(cleanup_args=False)
async def generate_verification_image_urls(supabase, verification_data: dict, is_private: bool) -> dict:
    """
    Generate signed URLs for both selfie and content images in a verification.
    Returns a dict with 'selfie_image_url' and 'content_image_url' keys.
    Uses existing image_filename for content image to maintain backward compatibility.
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
    
    return urls 