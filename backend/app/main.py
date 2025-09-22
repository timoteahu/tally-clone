from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware  # Add compression
from fastapi.responses import Response, FileResponse
from routers import (
    users, logs, penalties, payments, auth, invites, friends, feed,
    custom_habits, sync, notifications, test_penalty, habit_notifications,
    github_integration, gaming, activity, health_integration, leetcode_integration
)  # habit_reminders disabled until Twilio configured
# OPTIMIZATION: Use the new optimized modular habit verification
from routers.habit_verification import router as habit_verification_router
from routers.habits import router as habits_router
from fastapi.staticfiles import StaticFiles
from tasks.scheduler import setup_scheduler, check_and_charge_penalties
import os
from pathlib import Path
import logging
from fastapi import Request

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Joy Thief API",
    description="API for the Joy Thief habit tracking application",
    version="1.0.0"
)

# MEMORY OPTIMIZATION: Add compression middleware to reduce response sizes
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MEMORY OPTIMIZATION: Add response caching middleware
@app.middleware("http")
async def add_cache_control_headers(request, call_next):
    response = await call_next(request)
    
    # Add cache headers for static-like endpoints
    if request.url.path in ["/api/sync/delta"]:
        response.headers["Cache-Control"] = "private, max-age=60"  # Cache for 1 minute
    elif "image" in request.url.path or "static" in request.url.path:
        response.headers["Cache-Control"] = "public, max-age=3600"  # Cache images for 1 hour
    
    # Add ETag for better caching
    if hasattr(response, 'body') and response.status_code == 200:
        import hashlib
        etag = hashlib.md5(str(response.body)[:100].encode()).hexdigest()
        response.headers["ETag"] = f'"{etag}"'
    
    return response

# Memory optimization middleware - Skip for high-performance endpoints
@app.middleware("http")
async def memory_cleanup_middleware(request: Request, call_next):
    response = await call_next(request)
    
    # Skip cleanup for high-performance endpoints to reduce latency
    if request.url.path in ["/api/sync/delta"]:
        return response
    
    return response

# Mount static files directory for icons
static_dir = Path(__file__).parent.parent / "static"
if static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

# Register routers
app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(users.router, prefix="/api/users", tags=["users"])
app.include_router(habits_router, prefix="/api/habits", tags=["habits"])
app.include_router(custom_habits.router, prefix="/api/custom-habits", tags=["custom-habits"])
app.include_router(logs.router, prefix="/api/logs", tags=["logs"])
app.include_router(penalties.router, prefix="/api/penalties", tags=["penalties"])
app.include_router(payments.router, prefix="/api/payments", tags=["payments"])
app.include_router(invites.router, prefix="/api/invites", tags=["invites"])  # DEPRECATED: Legacy compatibility only
app.include_router(habit_verification_router, prefix="/api/habit-verification", tags=["habit-verification"])
app.include_router(friends.router, prefix="/api/friends", tags=["friends"])
app.include_router(feed.router, prefix="/api/feed", tags=["feed"])
app.include_router(notifications.router, prefix="/api/notifications", tags=["notifications"])
# GitHub integrations router
app.include_router(github_integration.router, prefix="/api/github", tags=["github"])
# LeetCode integrations router
app.include_router(leetcode_integration.router, prefix="/api/leetcode", tags=["leetcode"])
app.include_router(habit_notifications.router, prefix="/api/habit-notifications", tags=["habit-notifications"])
# app.include_router(habit_reminders.router, prefix="/api/habit-reminders", tags=["habit-reminders"])  # Disabled until Twilio phone number configured
app.include_router(sync.router, prefix="/api/sync", tags=["sync"])
app.include_router(test_penalty.router, prefix="/api/test", tags=["test"])  # ✅ Add test penalty router
app.include_router(gaming.router, prefix="/api/gaming", tags=["gaming"])  # Gaming habits
app.include_router(activity.router, prefix="/api/activity", tags=["activity"])  # Activity tracking
app.include_router(health_integration.router, prefix="/api/health", tags=["health"]) # Health integration router
# app.include_router(support.router, prefix="/api/support", tags=["support"])  # Support requests - commented out as module doesn't exist

@app.on_event("startup")
async def startup_event():
    # Setup memory monitoring for optimization tracking
    try:
        from utils.memory_monitor import setup_memory_monitoring
        setup_memory_monitoring()
        logger.info("Memory monitoring enabled for R14 error prevention")
    except Exception as e:
        logger.warning(f"Memory monitoring setup failed: {e}")
    
    # Only start scheduler if we're NOT running as a web dyno
    # The worker dyno will handle all scheduled tasks
    dyno_type = os.getenv("DYNO", "").startswith("web")
    is_web_dyno = dyno_type or os.getenv("WEB_CONCURRENCY") is not None
    
    if not is_web_dyno:
        # Running locally or in non-web context - start scheduler
        scheduler = setup_scheduler(development_mode=False)
        scheduler.start()
        logger.info("Scheduler started (non-web environment)")
    else:
        # Running as Heroku web dyno - scheduler runs in worker dyno
        logger.info("Web dyno started - scheduler runs in worker dyno")
        logger.info("This dyno focuses on API requests only")

@app.get("/")
async def root():
    return {"message": "Joy Thief API is running"}

# Add endpoints to handle WebView automatic requests for icons
@app.get("/favicon.ico")
async def favicon():
    static_path = Path(__file__).parent.parent / "static" / "favicon.ico"
    if static_path.exists():
        return FileResponse(str(static_path), media_type="image/x-icon")
    return Response(status_code=204)

@app.get("/apple-touch-icon.png")
async def apple_touch_icon():
    static_path = Path(__file__).parent.parent / "static" / "apple-touch-icon.png"
    if static_path.exists():
        return FileResponse(str(static_path), media_type="image/png")
    return Response(status_code=204)

@app.get("/apple-touch-icon-precomposed.png") 
async def apple_touch_icon_precomposed():
    static_path = Path(__file__).parent.parent / "static" / "apple-touch-icon-precomposed.png"
    if static_path.exists():
        return FileResponse(str(static_path), media_type="image/png")
    return Response(status_code=204)

@app.post("/test-check")
async def test_check():
    """Test endpoint to manually trigger the penalty check"""
    await check_and_charge_penalties()
    return {"message": "Penalty check completed"}

if __name__ == "__main__":
    import uvicorn
    
    # Get environment variables
    development_mode = os.getenv("DEVELOPMENT", "true").lower() == "true"
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", 8000))
    
    if development_mode:
        # Development: Use multiple workers to prevent blocking
        # Note: workers > 1 disables auto-reload, so we use threads instead
        uvicorn.run(
            "main:app",
            host=host,
            port=port,
            reload=True,  # Auto-reload for development
            workers=1,    # Keep at 1 for reload to work
            # Use larger thread pool to handle concurrent requests
            limit_concurrency=100,
            timeout_keep_alive=5
        )
    else:
        # Production: Use multiple workers for better performance
        uvicorn.run(
            "main:app",
            host=host,
            port=port,
            workers=4,    # Multiple workers for production
            reload=False,
            limit_concurrency=1000,
            timeout_keep_alive=30
        ) 