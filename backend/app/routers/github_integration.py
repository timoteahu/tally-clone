from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, Request
from fastapi.responses import RedirectResponse, JSONResponse
from config.database import get_async_supabase_client
from supabase._async.client import AsyncClient
from routers.auth import get_current_user_lightweight
from utils.timezone_utils import get_user_timezone
import os, httpx, logging
from typing import Optional
import datetime
import pytz
from datetime import time, timedelta
from utils.github_commits import get_commit_count, get_current_week_github_commits

logger = logging.getLogger(__name__)
router = APIRouter()

GITHUB_CLIENT_ID = os.getenv("GITHUB_CLIENT_ID")
GITHUB_CLIENT_SECRET = os.getenv("GITHUB_CLIENT_SECRET")

if not GITHUB_CLIENT_ID or not GITHUB_CLIENT_SECRET:
    logger.warning("GitHub OAuth env vars not set – GitHub integration routes will fail")

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

async def exchange_code_for_token(code: str) -> dict:
    """Exchange the one-time GitHub `code` for an access token and refresh token."""
    token_url = "https://github.com/login/oauth/access_token"
    async with httpx.AsyncClient() as client:
        headers = {"Accept": "application/json"}
        data = {
            "client_id": GITHUB_CLIENT_ID,
            "client_secret": GITHUB_CLIENT_SECRET,
            "code": code,
        }
        resp = await client.post(token_url, headers=headers, data=data, timeout=15)
        if resp.status_code != 200:
            raise HTTPException(status_code=500, detail="Failed to exchange GitHub code")
        return resp.json()

async def refresh_github_token(refresh_token: str) -> dict:
    """Refresh an expired GitHub access token using the refresh token."""
    token_url = "https://github.com/login/oauth/access_token"
    async with httpx.AsyncClient() as client:
        headers = {"Accept": "application/json"}
        data = {
            "client_id": GITHUB_CLIENT_ID,
            "client_secret": GITHUB_CLIENT_SECRET,
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        }
        resp = await client.post(token_url, headers=headers, data=data, timeout=15)
        if resp.status_code != 200:
            logger.error(f"Failed to refresh GitHub token: {resp.status_code} {resp.text}")
            raise HTTPException(status_code=500, detail="Failed to refresh GitHub token")
        return resp.json()

async def fetch_github_user(access_token: str) -> dict:
    """Fetch the authenticated GitHub user profile."""
    async with httpx.AsyncClient() as client:
        headers = {"Authorization": f"Bearer {access_token}", "Accept": "application/json"}
        resp = await client.get("https://api.github.com/user", headers=headers, timeout=15)
        if resp.status_code != 200:
            raise HTTPException(status_code=500, detail="Failed to fetch GitHub user profile")
        return resp.json()

# ---------------------------------------------------------------------------
# 1) Step 1 – return an authorization URL the mobile app can open
# ---------------------------------------------------------------------------
@router.get("/auth-url")
async def get_github_auth_url(request: Request, redirect_uri: Optional[str] = None):
    """Generate the GitHub OAuth authorize URL and return JSON so the mobile app can open it in Safari/WebAuth session."""
    if not GITHUB_CLIENT_ID:
        raise HTTPException(status_code=500, detail="GitHub client ID not configured")

    # Fallback redirect URI – uses the single custom scheme `tally://` registered in the iOS app
    redirect_uri = redirect_uri or "tally://github/callback"

    logger.debug(f"[GitHub] Building authorize URL for redirect_uri={redirect_uri}")
    scopes = "repo read:user"
    authorize_url = (
        f"https://github.com/login/oauth/authorize?client_id={GITHUB_CLIENT_ID}"
        f"&scope={scopes.replace(' ', '%20')}"
        f"&redirect_uri={redirect_uri}"
        f"&response_type=code"
        f"&access_type=offline"  # Request refresh token
    )
    return {"url": authorize_url}

# ---------------------------------------------------------------------------
# 2) Step 2 – app sends the `code` back to exchange & persist
# ---------------------------------------------------------------------------
class CodeExchangeRequest(httpx.Headers):
    code: str

@router.post("/exchange-token")
async def github_exchange_token(body: dict,  # expects {"code": "..."}
                                current_user=Depends(get_current_user_lightweight),
                                supabase: AsyncClient = Depends(get_async_supabase_client)):
    code = body.get("code")
    logger.debug(f"[GitHub] /exchange-token called by user={current_user.id}, code={code}")
    if not code:
        raise HTTPException(status_code=400, detail="Missing code")

    # 1. Exchange code for access token and refresh token
    token_json = await exchange_code_for_token(code)
    logger.debug(f"[GitHub] Token exchange response: {token_json}")
    
    access_token = token_json.get("access_token")
    refresh_token = token_json.get("refresh_token")  # May be None for classic OAuth
    expires_in = token_json.get("expires_in")  # Seconds until expiration
    
    if not access_token:
        raise HTTPException(status_code=400, detail="GitHub token exchange failed")

    # 2. Fetch user profile (login/ id)
    profile_json = await fetch_github_user(access_token)
    logger.debug(f"[GitHub] Fetched user profile: {profile_json}")
    github_login = profile_json.get("login")
    github_id = profile_json.get("id")

    # 3. Calculate expiration time
    expires_at = None
    if expires_in:
        expires_at = (datetime.datetime.utcnow() + datetime.timedelta(seconds=expires_in)).isoformat()

    # 4. Persist tokens with expiration info
    try:
        update_payload = {
            "user_id": str(current_user.id),
            "github_username": github_login,
            "github_id": github_id,
            "github_access_token": access_token,
            "github_refresh_token": refresh_token,  # Store refresh token
            "github_token_expires_at": expires_at,  # Store expiration
            "github_token_scopes": token_json.get("scope", "").split(",") if token_json.get("scope") else [],
            "github_token_error": None,  # Clear any previous errors
            "github_token_error_at": None,
        }
        logger.debug(f"[GitHub] Saving to DB payload={update_payload}")
        await supabase.table("user_tokens").upsert(update_payload, on_conflict="user_id").execute()

        logger.info(f"[GitHub] User {current_user.id} connected GitHub account {github_login}")
        if refresh_token:
            logger.info(f"[GitHub] Stored refresh token for auto-renewal")
        else:
            logger.info(f"[GitHub] Using classic OAuth (no refresh token)")
            
    except Exception as e:
        logger.error(f"Failed to save GitHub token: {e}")
        raise HTTPException(status_code=500, detail="Failed to save GitHub credentials")

    return {"status": "connected", "github_username": github_login, "has_refresh_token": bool(refresh_token)}

# ---------------------------------------------------------------------------
# 3) Step 3 – status endpoint so the app knows if the account is connected
# ---------------------------------------------------------------------------
@router.get("/status")
async def github_status(current_user=Depends(get_current_user_lightweight),
                        supabase: AsyncClient = Depends(get_async_supabase_client)):
    """Get GitHub connection status with token validation"""
    try:
        user_id = str(current_user.id)
        result = await supabase.table("user_tokens") \
            .select("github_username, github_access_token, github_token_error") \
            .eq("user_id", user_id) \
            .execute()
        
        if not result.data or not result.data[0].get("github_username"):
            return {"status": "not_connected"}
        
        # Check if there's a token error
        token_error = result.data[0].get("github_token_error")
        if token_error:
            if token_error == "token_expired":
                return {"status": "token_expired", "message": "GitHub token has expired. Please reconnect."}
            else:
                return {"status": "error", "message": f"GitHub API error: {token_error}"}
        
        # Check if we have a valid token
        access_token = result.data[0].get("github_access_token")
        if not access_token:
            return {"status": "token_missing", "message": "GitHub token missing. Please reconnect."}
        
        # Validate the token
        from utils.github_commits import check_github_token_validity
        token_status = await check_github_token_validity(access_token)
        
        if not token_status["valid"]:
            # Update the error in the database
            from utils.github_commits import handle_github_token_error
            await handle_github_token_error(supabase, user_id, token_status.get("error", "unknown"))
            
            if token_status.get("error") == "token_expired":
                return {"status": "token_expired", "message": "GitHub token has expired. Please reconnect."}
            else:
                return {"status": "error", "message": token_status.get("message", "GitHub connection error")}
        
        return {"status": "connected"}
        
    except Exception as e:
        logger.error(f"Error checking GitHub status for user {current_user.id}: {e}")
        return {"status": "error", "message": "Failed to check GitHub status"}

@router.get("/today-count")
async def github_today_commit_count(current_user=Depends(get_current_user_lightweight),
                                    supabase: AsyncClient = Depends(get_async_supabase_client)):
    """Return today's commit count for the authenticated user in their timezone."""
    try:
        user_id = str(current_user.id)
        
        # Get user's timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        
        # Get today's date range in user's timezone
        user_now = datetime.datetime.now(user_tz)
        today_date = user_now.date()
        
        # Create timezone-aware datetime objects for start and end of today
        start_local = user_tz.localize(datetime.datetime.combine(today_date, time.min))
        end_local = user_tz.localize(datetime.datetime.combine(today_date, time.max))
        
        # Convert to UTC for GitHub API (GitHub expects UTC timestamps)
        start_utc = start_local.astimezone(pytz.UTC).replace(tzinfo=None)
        end_utc = end_local.astimezone(pytz.UTC).replace(tzinfo=None)
        
        logger.debug(f"Fetching commits for user {user_id} for date {today_date} in timezone {user_timezone}")
        logger.debug(f"Local range: {start_local} to {end_local}")
        logger.debug(f"UTC range: {start_utc} to {end_utc}")
        
        # Use the new error handling function
        from utils.github_commits import get_commit_count_with_error_handling
        count = await get_commit_count_with_error_handling(supabase, user_id, start_utc, end_utc)
        
        if count is None:
            # Check if there's a token error in the database
            token_result = await supabase.table("user_tokens") \
                .select("github_token_error, github_token_error_at") \
                .eq("user_id", user_id) \
                .execute()
            
            if token_result.data and token_result.data[0].get("github_token_error"):
                error_type = token_result.data[0]["github_token_error"]
                if error_type == "token_expired":
                    raise HTTPException(
                        status_code=401, 
                        detail="GitHub access token has expired. Please reconnect your GitHub account in Settings."
                    )
                else:
                    raise HTTPException(
                        status_code=503, 
                        detail=f"GitHub API temporarily unavailable: {error_type}"
                    )
            else:
                raise HTTPException(status_code=404, detail="GitHub not connected")
        
        return {"count": count}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting today's GitHub commit count: {e}")
        raise HTTPException(status_code=500, detail="Failed to get commit count")

@router.get("/yesterday-count")
async def github_yesterday_commit_count(current_user=Depends(get_current_user_lightweight),
                                        supabase: AsyncClient = Depends(get_async_supabase_client)):
    """Return yesterday's commit count for the authenticated user in UTC timezone."""
    try:
        user_id = str(current_user.id)
        
        # Use EXACT same logic as test_github_commits.py (which works correctly)
        # Force UTC timezone since that's what works correctly
        
        # Get yesterday's date in UTC timezone (this is what works)
        utc_tz = pytz.timezone('UTC')
        utc_now = datetime.datetime.now(utc_tz)
        yesterday_date_utc = utc_now.date() - timedelta(days=1)
        
        # Create timezone-aware datetime objects for start and end of yesterday in UTC
        start_local = utc_tz.localize(datetime.datetime.combine(yesterday_date_utc, time.min))
        end_local = utc_tz.localize(datetime.datetime.combine(yesterday_date_utc, time.max))
        
        # Convert to UTC for GitHub API (GitHub expects UTC timestamps)
        start_utc = start_local.astimezone(pytz.UTC).replace(tzinfo=None)
        end_utc = end_local.astimezone(pytz.UTC).replace(tzinfo=None)
        
        logger.debug(f"Using EXACT test_github_commits.py logic (UTC timezone)")
        logger.debug(f"UTC yesterday: {yesterday_date_utc}")
        logger.debug(f"UTC range: {start_utc} to {end_utc}")
        
        # Use the new error handling function
        from utils.github_commits import get_commit_count_with_error_handling
        count = await get_commit_count_with_error_handling(supabase, user_id, start_utc, end_utc)
        
        if count is None:
            # Check if there's a token error in the database
            token_result = await supabase.table("user_tokens") \
                .select("github_token_error, github_token_error_at") \
                .eq("user_id", user_id) \
                .execute()
            
            if token_result.data and token_result.data[0].get("github_token_error"):
                error_type = token_result.data[0]["github_token_error"]
                if error_type == "token_expired":
                    raise HTTPException(
                        status_code=401, 
                        detail="GitHub access token has expired. Please reconnect your GitHub account in Settings."
                    )
                else:
                    raise HTTPException(
                        status_code=503, 
                        detail=f"GitHub API temporarily unavailable: {error_type}"
                    )
            else:
                raise HTTPException(status_code=404, detail="GitHub not connected")
        
        return {"count": count, "date": yesterday_date_utc.isoformat(), "timezone": "UTC"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting yesterday's GitHub commit count: {e}")
        raise HTTPException(status_code=500, detail="Failed to get commit count")

@router.get("/current-week-count")
async def github_current_week_commit_count(
    week_start_day: int = 0,
    current_user=Depends(get_current_user_lightweight),
    supabase: AsyncClient = Depends(get_async_supabase_client)
):
    """
    Get current week's commit count for weekly GitHub habits.
    For weekly GitHub habits, the commit goal is stored in commit_target field.
    
    Args:
        week_start_day: Day of week that starts the week (0=Sunday, 1=Monday, etc.)
    
    Returns:
        Current week's commit count and goal
    """
    try:
        user_id = str(current_user.id)
        
        # Get result from utility function (now uses user timezone)
        result = await get_current_week_github_commits(supabase, user_id, week_start_day)
        
        if result is None:
            raise HTTPException(status_code=404, detail="No GitHub integration found or no weekly GitHub habits")
        
        # Log timezone information for debugging
        logger.debug(f"GitHub weekly count for user {user_id}: week_start_day={week_start_day}, "
                    f"week_start={result['week_start_date']}, week_end={result['week_end_date']}")
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting current week GitHub commits: {e}")
        raise HTTPException(status_code=500, detail="Failed to get current week commit count") 