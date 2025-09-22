from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, timezone, timedelta, date
from supabase._async.client import AsyncClient
from models.schemas import User
from utils import (
    AsyncCoordinator,
    cleanup_memory,
    disable_print,
    memory_optimized,
    get_user_timezone,
    get_user_date_range_in_timezone,
    get_week_boundaries_in_timezone,
    generate_verification_image_urls
)
from utils.weekly_habits import get_weekly_progress_summary, get_week_dates
import pytz
import json
import asyncio

# Disable verbose printing to reduce response latency
print = disable_print()

@memory_optimized(cleanup_args=False)
async def fetch_weekly_progress(supabase: AsyncClient, user_id: str, if_modified_since: Optional[str] = None) -> List[Dict[str, Any]]:
    """Fetch weekly progress data with memory optimization"""
    try:
        # NEW: Add timestamp to track data freshness and avoid unnecessary cleanup during resyncs
        current_timestamp = datetime.now(timezone.utc).isoformat()
        
        # FIXED: Only do cleanup if this is a full refresh (no If-Modified-Since header) to avoid interference during resyncs
        # This prevents delta syncs from corrupting existing weekly progress data
        is_full_refresh = if_modified_since is None
        
        if is_full_refresh:
            # CRITICAL FIX: Clean up any stale/incorrect completion flags first
            print("🧹 [Sync] Full refresh - cleaning up stale weekly progress data...")
            try:
                # Get all weekly progress records for this user for current week
                current_week_start = get_week_dates(date.today())[0]
                cleanup_result = await supabase.table("weekly_habit_progress") \
                    .select("id, current_completions, target_completions, is_week_complete") \
                    .eq("user_id", user_id) \
                    .eq("week_start_date", current_week_start.isoformat()) \
                    .execute()
                
                # Fix any records where is_week_complete doesn't match actual progress
                fixed_count = 0
                for record in cleanup_result.data:
                    actual_complete = record["current_completions"] >= record["target_completions"]
                    if record["is_week_complete"] != actual_complete:
                        # Fix the completion flag
                        await supabase.table("weekly_habit_progress") \
                            .update({"is_week_complete": actual_complete}) \
                            .eq("id", record["id"]) \
                            .execute()
                        fixed_count += 1
                        print(f"🔧 [Sync] Fixed weekly progress {record['id']}: {record['current_completions']}/{record['target_completions']} -> complete: {actual_complete}")
                
                if fixed_count > 0:
                    print(f"✅ [Sync] Fixed {fixed_count} stale weekly progress records")
                else:
                    print("✅ [Sync] No stale data found, all weekly progress records are correct")
                    
            except Exception as cleanup_error:
                print(f"⚠️ [Sync] Failed to cleanup stale data (continuing anyway): {cleanup_error}")
            
            # ADDITIONAL: Ensure weekly progress exists for all weekly habits (only during full refresh)
            try:
                # Get all weekly habits for this user
                weekly_habits = await supabase.table("habits").select("id, weekly_target, week_start_day, created_at") \
                    .eq("user_id", user_id) \
                    .eq("habit_schedule_type", "weekly") \
                    .eq("is_active", True) \
                    .execute()
                
                for habit in weekly_habits.data:
                    # Check if progress record exists for current week
                    current_week_start = get_week_dates(date.today(), habit.get('week_start_day', 0))[0]
                    existing_progress = await supabase.table("weekly_habit_progress") \
                        .select("id") \
                        .eq("habit_id", habit["id"]) \
                        .eq("week_start_date", current_week_start.isoformat()) \
                        .execute()
                    
                    if not existing_progress.data:
                        # Create missing progress record
                        progress_data = {
                            "habit_id": habit["id"],
                            "user_id": user_id,
                            "week_start_date": current_week_start.isoformat(),
                            "current_completions": 0,
                            "target_completions": habit["weekly_target"],
                            "is_week_complete": False
                        }
                        await supabase.table("weekly_habit_progress").insert(progress_data).execute()
                        print(f"✅ [Sync] Created missing weekly progress for habit {habit['id']}")
            
            except Exception as ensure_error:
                print(f"⚠️ [Sync] Failed to ensure weekly progress records exist: {ensure_error}")
        else:
            print("🔄 [Sync] Delta sync - skipping cleanup to preserve data consistency")
        
        # Get current week progress from the actual weekly_habit_progress table
        current_week_progress = await get_weekly_progress_summary(supabase, user_id, None)
        
        progress_data = []
        
        for progress_record in current_week_progress:
            # Extract habit data from the joined result
            habit_data = progress_record.get('habit', {})
            
            progress_obj = {
                "habit_id": str(progress_record["habit_id"]),
                "current_completions": progress_record["current_completions"],
                "target_completions": progress_record["target_completions"],
                "is_week_complete": progress_record["is_week_complete"],
                "week_start_date": progress_record["week_start_date"],
                "week_end_date": progress_record.get("week_end_date", ""),  # Calculate if needed
                "habit_name": habit_data.get("name", ""),
                "completion_percentage": min(100, (progress_record["current_completions"] / progress_record["target_completions"] * 100)) if progress_record["target_completions"] > 0 else 0,
                # NEW: Add data timestamp for frontend validation
                "data_timestamp": current_timestamp
            }
            
            # Add week_end_date if not present
            if not progress_obj["week_end_date"]:
                week_start_date = datetime.strptime(progress_record["week_start_date"], "%Y-%m-%d").date()
                week_end_date = week_start_date + timedelta(days=6)
                progress_obj["week_end_date"] = week_end_date.isoformat()
            
            progress_data.append(progress_obj)
            
        print(f"✅ [Backend] Fetched {len(progress_data)} weekly progress records from weekly_habit_progress table")
        for progress in progress_data:
            print(f"   📊 {progress['habit_name']}: {progress['current_completions']}/{progress['target_completions']} (complete: {progress['is_week_complete']}) - {progress['completion_percentage']:.1f}%")
        
        return progress_data
        
    except Exception as e:
        print(f"❌ Error fetching weekly progress: {e}")
        # Fallback to empty list instead of manual calculation
        return []

@memory_optimized(cleanup_args=False)
async def fetch_verification_data(supabase: AsyncClient, user_id: str) -> Tuple[Dict[str, bool], Dict[str, List[Dict[str, Any]]], Dict[str, Dict[str, bool]]]:
    """Fetch verification data with memory optimization"""
    try:
        # Get user's timezone for date calculations
        timezone = await get_user_timezone(supabase, user_id)
        tz = pytz.timezone(timezone)
        
        # Get today's verification data with memory optimization
        user_now = datetime.now(tz)
        today_user_tz = user_now.date()
        
        start_of_day_local = tz.localize(datetime.combine(today_user_tz, datetime.min.time()))
        end_of_day_local = tz.localize(datetime.combine(today_user_tz, datetime.max.time()))
        
        start_of_day_utc = start_of_day_local.astimezone(pytz.utc)
        end_of_day_utc = end_of_day_local.astimezone(pytz.utc)
        
        # MEMORY OPTIMIZATION: Limit fields and number of verifications
        # Use JOIN to avoid N+1 queries and limit to recent verifications only
        verification_result = await supabase.table("habit_verifications").select(
            "id, habit_id, user_id, verification_type, verified_at, status, verification_result, "
            "image_filename, selfie_image_filename, habits!inner(private)"
        ).eq("user_id", user_id) \
         .gte("verified_at", start_of_day_utc.isoformat()) \
         .lte("verified_at", end_of_day_utc.isoformat()) \
         .limit(50) \
         .execute()  # Limit to 50 verifications max
        
        verified_habits_today = {}
        habit_verifications = {}
        weekly_verified_habits = {}
        
        print(f"🔍 [Sync] Found {len(verification_result.data)} verifications for today")
        
        # MEMORY OPTIMIZATION: Process verifications in smaller batches
        ver_sem = asyncio.Semaphore(5)  # Reduced from 10 to 5 for lower memory usage
        
        async def process_verification(verification):
            async with ver_sem:
                try:
                    habit_id = verification["habit_id"]
                    is_private = verification["habits"]["private"] if verification.get("habits") else False
                    
                    # Remove joined data to save memory
                    verification.pop("habits", None)
                    
                    # Only generate image URLs if needed, don't preload all
                    verification_data = {
                        "id": verification["id"],
                        "habit_id": habit_id,
                        "user_id": verification["user_id"],
                        "verification_type": verification["verification_type"],
                        "verified_at": verification["verified_at"],
                        "status": verification["status"],
                        "verification_result": verification["verification_result"],
                        # Skip image URLs for now to save memory - can be loaded on demand
                    }
                    
                    return habit_id, verification_data
                except Exception as e:
                    print(f"⚠️ [Sync] Error processing verification: {e}")
                    return None
        
        # Process verifications in batches
        verification_tasks = [process_verification(v) for v in verification_result.data]
        ver_results = await asyncio.gather(*verification_tasks, return_exceptions=True)
        
        for res in ver_results:
            if not res:
                continue
            habit_id_res, verification_data_res = res
            verified_habits_today[habit_id_res] = True
            habit_verifications.setdefault(habit_id_res, []).append(verification_data_res)
        
        # MEMORY OPTIMIZATION: Simplified weekly data fetch - only get counts, not full data
        days_since_sunday = (today_user_tz.weekday() + 1) % 7
        week_start = today_user_tz - timedelta(days=days_since_sunday)
        week_end = week_start + timedelta(days=6)

        # Just fetch daily counts instead of full verification data for the week
        counts_result = await supabase.table("user_verification_daily_counts").select(
            "verification_date, count"
        ).eq("user_id", user_id).gte("verification_date", week_start.isoformat()).lte("verification_date", week_end.isoformat()).execute()
        
        # Build simplified weekly map with just counts
        for i in range(7):
            date_key = (week_start + timedelta(days=i)).isoformat()
            weekly_verified_habits[date_key] = {}
            
            # Add count if available
            for count_row in (counts_result.data or []):
                if count_row["verification_date"] == date_key and count_row["count"] > 0:
                    # Create placeholder entries to indicate activity
                    for idx in range(min(count_row["count"], 10)):  # Limit to 10 max
                        weekly_verified_habits[date_key][f"placeholder_{idx}"] = True
                    break
        
        print(f"✅ [Sync] Processed verification data:")
        print(f"   📊 Verified habits today: {len(verified_habits_today)}")
        print(f"   📊 Habit verifications: {len(habit_verifications)}")
        print(f"   📊 Weekly verified habits: {len(weekly_verified_habits)} days")

        return verified_habits_today, habit_verifications, weekly_verified_habits
        
    except Exception as e:
        print(f"❌ [Sync] Error fetching verification data: {e}")
        return {}, {}, {}

@memory_optimized(cleanup_args=False)
async def fetch_friend_requests(supabase: AsyncClient, user_id: str) -> Dict[str, Any]:
    """Fetch friend requests with memory optimization"""
    try:
        # Use the new database functions with avatar data (1 call each instead of complex queries)
        # Fetch received friend requests using the optimized RPC function with avatars
        received_result = await supabase.rpc("get_received_friend_requests_with_avatars", {
            "user_id": user_id
        }).execute()
        
        # Fetch sent friend requests using the optimized RPC function with avatars
        sent_result = await supabase.rpc("get_sent_friend_requests_with_avatars", {
            "user_id": user_id
        }).execute()
        
        received_list = []
        if received_result.data:
            for request in received_result.data:
                request_obj = {
                    "id": str(request["relationship_id"]),
                    "sender_id": str(request["sender_id"]),
                    "sender_name": request.get("sender_name", ""),
                    "sender_phone": request.get("sender_phone", ""),
                    "message": request.get("message", ""),
                    "status": "pending",  # All received requests are pending
                    "created_at": request["created_at"],
                    # Add avatar fields for sender
                    "sender_avatar_version": request.get("sender_avatar_version"),
                    "sender_avatar_url_80": request.get("sender_avatar_url_80"),
                    "sender_avatar_url_200": request.get("sender_avatar_url_200"),
                    "sender_avatar_url_original": request.get("sender_avatar_url_original")
                }
                received_list.append(request_obj)
        
        sent_list = []
        if sent_result.data:
            for request in sent_result.data:
                request_obj = {
                    "id": str(request["relationship_id"]),
                    "receiver_id": str(request["receiver_id"]),
                    "receiver_name": request.get("receiver_name", ""),
                    "receiver_phone": request.get("receiver_phone", ""),
                    "message": request.get("message", ""),
                    "status": "pending",  # All sent requests from RPC are pending
                    "created_at": request["created_at"],
                    # Add avatar fields for receiver
                    "receiver_avatar_version": request.get("receiver_avatar_version"),
                    "receiver_avatar_url_80": request.get("receiver_avatar_url_80"),
                    "receiver_avatar_url_200": request.get("receiver_avatar_url_200"),
                    "receiver_avatar_url_original": request.get("receiver_avatar_url_original")
                }
                sent_list.append(request_obj)
        
        return {
            "received_requests": received_list,
            "sent_requests": sent_list
        }
    except Exception as e:
        print(f"Error fetching friend requests with avatars: {e}")
        # Fallback to old functions without avatars
        try:
            # Fetch received friend requests using the old RPC function
            received_result = await supabase.rpc("get_received_friend_requests", {
                "user_id": user_id
            }).execute()
            
            # Fetch sent friend requests using the old RPC function
            sent_result = await supabase.rpc("get_sent_friend_requests", {
                "user_id": user_id
            }).execute()
            
            received_list = []
            if received_result.data:
                for request in received_result.data:
                    request_obj = {
                        "id": str(request["relationship_id"]),
                        "sender_id": str(request["sender_id"]),
                        "sender_name": request.get("sender_name", ""),
                        "sender_phone": request.get("sender_phone", ""),
                        "message": request.get("message", ""),
                        "status": "pending",
                        "created_at": request["created_at"]
                    }
                    received_list.append(request_obj)
            
            sent_list = []
            if sent_result.data:
                for request in sent_result.data:
                    request_obj = {
                        "id": str(request["relationship_id"]),
                        "receiver_id": str(request["receiver_id"]),
                        "receiver_name": request.get("receiver_name", ""),
                        "receiver_phone": request.get("receiver_phone", ""),
                        "message": request.get("message", ""),
                        "status": "pending",
                        "created_at": request["created_at"]
                    }
                    sent_list.append(request_obj)
            
            return {
                "received_requests": received_list,
                "sent_requests": sent_list
            }
        except Exception as fallback_error:
            print(f"Error fetching friend requests (fallback): {fallback_error}")
            return {"received_requests": [], "sent_requests": []}

@memory_optimized(cleanup_args=False)
async def fetch_staged_deletions(supabase: AsyncClient, user_id: str) -> Dict[str, Any]:
    """Fetch staged deletions with memory optimization"""
    try:
        # Get all staged deletions for this user
        staging_result = await supabase.table("habit_change_staging") \
            .select("*") \
            .eq("user_id", user_id) \
            .eq("change_type", "delete") \
            .eq("applied", False) \
            .execute()
        
        staged_deletions = {}
        if staging_result.data:
            for record in staging_result.data:
                habit_id = record["habit_id"]
                staged_deletions[habit_id] = {
                    "scheduled_for_deletion": True,
                    "effective_date": record["effective_date"],
                    "user_timezone": record["user_timezone"],
                    "staging_id": record["id"],
                    "created_at": record["created_at"]
                }
        
        print(f"✅ [Sync] Found {len(staged_deletions)} staged deletions")
        return staged_deletions
        
    except Exception as e:
        print(f"❌ [Sync] Error fetching staged deletions: {e}")
        return {}

@memory_optimized(cleanup_args=False)
async def fetch_friend_recommendations(supabase: AsyncClient, user_id: str) -> List[Dict[str, Any]]:
    """Fetch friend recommendations with memory optimization"""
    try:
        # Limit recommendations to a reasonable number (e.g., 10)
        limit = 10
        result = await supabase.rpc("generate_friend_recommendations", {
            "user_id_param": user_id,
            "limit_param": limit
        }).execute()

        recommendations = []
        if result.data:
            for rec in result.data:
                # Mutual friends preview may come back as JSON string
                preview = rec.get("mutual_friends_preview", [])
                if isinstance(preview, str):
                    try:
                        preview = json.loads(preview)
                    except Exception:
                        preview = []

                recommendations.append({
                    "recommended_user_id": str(rec.get("recommended_user_id")),
                    "user_name": rec.get("user_name", ""),
                    "mutual_friends_count": int(rec.get("mutual_friends_count", 0)),
                    "mutual_friends_preview": preview,
                    "recommendation_reason": rec.get("recommendation_reason", ""),
                    "total_score": float(rec.get("total_score", 0.0))
                })
        return recommendations
    except Exception as e:
        print(f"Error fetching friend recommendations: {e}")
        return [] 