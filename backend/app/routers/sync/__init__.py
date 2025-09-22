from fastapi import APIRouter, Depends, HTTPException, Header
from typing import Optional
from models.schemas import User
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user_lightweight
from utils.memory_optimization import cleanup_memory, disable_print
# TODO: Replace preloader dependency with optimized habit services
# from routers.preloader import get_app_preload_data, PreloadedData

# Import service functions
from .services import get_delta_changes_service, DeltaChanges, get_payment_stats_service

# Disable verbose printing in this module to reduce response latency
print = disable_print()

router = APIRouter()

@router.get("/delta", response_model=DeltaChanges)
async def get_delta_changes(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client),
    if_modified_since: Optional[str] = Header(None, alias="If-Modified-Since")
):
    """
    Get ALL app data in delta format. This now serves as the complete preloader endpoint.
    Returns 304 Not Modified if no changes since last sync, 200 with ALL data otherwise.
    Memory optimized endpoint using optimized habit services.
    """
    try:
        return await get_delta_changes_service(current_user, supabase, if_modified_since)
    except Exception as e:
        print(f"Delta sync error: {e}")
        raise HTTPException(status_code=500, detail="Failed to get delta changes")

# DEPRECATED: This endpoint should be removed once frontend migration is complete
# @router.get("/full-refresh", response_model=PreloadedData)
# async def force_full_refresh(
#     current_user: User = Depends(get_current_user_lightweight),
#     supabase: AsyncClient = Depends(get_async_supabase_client)
# ):
#     """
#     DEPRECATED: Use /delta endpoint instead.
#     """
#     try:
#         return await get_app_preload_data(current_user, supabase)
#     except Exception as e:
#         print(f"Full refresh error: {e}")
#         raise HTTPException(status_code=500, detail="Failed to refresh data")

@router.get("/payment-stats")
async def get_payment_stats(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get payment statistics for the current user including:
    - Weekly payments (current week)
    - Daily payments breakdown (current week)
    - Monthly payments
    - Total payments
    Memory optimized endpoint.
    """
    try:
        result = await get_payment_stats_service(current_user, supabase)
        
        # Cleanup and return
        cleanup_memory(current_user, supabase)
        return result
        
    except Exception as e:
        print(f"Error fetching payment stats: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch payment statistics") 