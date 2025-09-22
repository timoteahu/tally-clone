import time
from typing import Optional
from supabase._async.client import AsyncClient
from utils.memory_optimization import memory_optimized

# Improved cache for relationship data with size limits and LRU eviction
_relationship_cache = {}
_cache_access_order = []  # LRU tracking
_cache_size_limit = 200  # Limit cache size to prevent memory growth
_cache_ttl = 30  # 30 seconds cache

def _cleanup_relationship_cache():
    """Clean up expired entries and enforce size limits with LRU eviction"""
    current_time = time.time()
    
    # Remove expired entries
    expired_keys = []
    for key in list(_relationship_cache.keys()):
        if key not in _cache_access_order:
            expired_keys.append(key)
        elif current_time >= _relationship_cache.get(key, {}).get('expires_at', 0):
            expired_keys.append(key)
    
    for key in expired_keys:
        _relationship_cache.pop(key, None)
        if key in _cache_access_order:
            _cache_access_order.remove(key)
    
    # LRU eviction if cache is too large
    while len(_relationship_cache) > _cache_size_limit:
        oldest_key = _cache_access_order.pop(0)
        _relationship_cache.pop(oldest_key, None)

def _get_cached_relationship_data(cache_key: str):
    """Get cached relationship data if not expired with LRU tracking"""
    if cache_key in _relationship_cache:
        cache_entry = _relationship_cache[cache_key]
        if time.time() < cache_entry.get('expires_at', 0):
            # Update LRU order
            if cache_key in _cache_access_order:
                _cache_access_order.remove(cache_key)
            _cache_access_order.append(cache_key)
            return cache_entry.get('data')
        else:
            # Expired - remove immediately
            _relationship_cache.pop(cache_key, None)
            if cache_key in _cache_access_order:
                _cache_access_order.remove(cache_key)
    return None

def _set_cached_relationship_data(cache_key: str, data):
    """Cache relationship data with size management"""
    # Cleanup before adding
    _cleanup_relationship_cache()
    
    _relationship_cache[cache_key] = {
        'data': data,
        'expires_at': time.time() + _cache_ttl
    }
    if cache_key in _cache_access_order:
        _cache_access_order.remove(cache_key)
    _cache_access_order.append(cache_key)

@memory_optimized(cleanup_args=False)
async def get_user_relationship_data(user_id: str, supabase: AsyncClient, use_cache: bool = True):
    """
    Get user relationship data with improved caching for better performance.
    This ensures consistent relationship state across all endpoints.
    """
    cache_key = f"relationships:{user_id}"
    
    # Check cache first
    if use_cache:
        cached_data = _get_cached_relationship_data(cache_key)
        if cached_data is not None:
            return cached_data
    
    try:
        # Get unified relationship data (same as unified endpoint)
        result = await supabase.rpc("get_user_all_friend_data_no_contacts", {
            "user_id_param": user_id
        }).execute()
        
        # Process into lookup sets
        friend_ids = set()
        sent_request_ids = set()
        received_request_ids = set()
        
        if result.data:
            for row in result.data:
                data_type = row.get('data_type')
                target_user_id = str(row.get('user_id', ''))
                
                if data_type == 'friend':
                    friend_ids.add(target_user_id)
                elif data_type == 'sent_request':
                    sent_request_ids.add(target_user_id)
                elif data_type == 'received_request':
                    received_request_ids.add(target_user_id)
        
        relationship_data = {
            'friend_ids': friend_ids,
            'sent_request_ids': sent_request_ids,
            'received_request_ids': received_request_ids
        }
        
        # Cache the result
        if use_cache:
            _set_cached_relationship_data(cache_key, relationship_data)
            
        return relationship_data
        
    except Exception as e:
        print(f"Error fetching relationship data for user {user_id}: {str(e)}")
        # Return empty sets on error
        return {
            'friend_ids': set(),
            'sent_request_ids': set(),
            'received_request_ids': set()
        }

def invalidate_relationship_cache(user_id: str):
    """
    Invalidate relationship cache for a user. 
    Call this when friend requests are sent/accepted/cancelled.
    """
    cache_key = f"relationships:{user_id}"
    if cache_key in _relationship_cache:
        del _relationship_cache[cache_key]
        if cache_key in _cache_access_order:
            _cache_access_order.remove(cache_key) 