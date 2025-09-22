#!/usr/bin/env python3
"""
Heroku Worker Dyno - Scheduler Service
Runs all scheduled tasks independently from the web dynos

Updated to use the restructured task modules:
- daily_penalties.py - Daily penalty checking and creation  
- weekly_penalties.py - Weekly penalty checking and charging
- gaming_habits.py - Gaming habit penalty checking
- github_habits.py - GitHub habit penalty checking and progress updates
- payment_processing.py - Payment intent updates and transfers
- habit_management.py - Habit notifications and staging changes
- maintenance.py - Feed card archiving and cleanup tasks
- scheduler_utils.py - Shared utility functions
- scheduler.py - Main scheduler setup orchestrating all tasks
"""

import asyncio
import logging
import os
import sys

# Import scheduler setup (now properly organized across multiple modules)
from tasks.scheduler import setup_scheduler

# Configure logging for Heroku
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [SCHEDULER] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

async def main():
    """Main scheduler worker entry point"""
    logger.info("🕒 Starting Joy Thief Scheduler Worker (Restructured)")
    
    # Get environment configuration
    development_mode = os.getenv("DEVELOPMENT", "false").lower() == "true"
    
    logger.info(f"📋 Worker Configuration:")
    logger.info(f"   Environment: {'Development' if development_mode else 'Production'}")
    logger.info(f"   Heroku App: {os.getenv('HEROKU_APP_NAME', 'Unknown')}")
    logger.info(f"   Dyno: {os.getenv('DYNO', 'Unknown')}")
    logger.info(f"   Working Directory: {os.getcwd()}")
    
    logger.info(f"📦 Task Organization:")
    logger.info(f"   • Daily Penalties: tasks.daily_penalties")
    logger.info(f"   • Weekly Penalties: tasks.weekly_penalties") 
    logger.info(f"   • Gaming Habits: tasks.gaming_habits")
    logger.info(f"   • GitHub Habits: tasks.github_habits")
    logger.info(f"   • Payment Processing: tasks.payment_processing")
    logger.info(f"   • Habit Management: tasks.habit_management")
    logger.info(f"   • Maintenance: tasks.maintenance")
    logger.info(f"   • Shared Utils: tasks.scheduler_utils")
    
    try:
        # Set up scheduler with appropriate mode (now using restructured modules)
        scheduler = setup_scheduler(development_mode=development_mode)
        scheduler.start()
        
        logger.info("✅ Scheduler started successfully with restructured tasks")
        
        # Log all scheduled jobs
        jobs = scheduler.get_jobs()
        logger.info(f"📅 Running {len(jobs)} scheduled jobs:")
        for job in jobs:
            next_run = getattr(job, 'next_run_time', 'Unknown')
            logger.info(f"   • {job.id}: {job.trigger} (next: {next_run})")
        
        logger.info("🔄 Scheduler worker is running with organized task modules...")
        logger.info("   Each task type is now in its own file for easier debugging")
        logger.info("   Web dynos can focus on API requests while this handles background tasks")
        logger.info("   Press Ctrl+C or send SIGTERM to stop")
        
        # Keep worker running indefinitely
        try:
            while True:
                await asyncio.sleep(3600)  # Wake up every hour for health check
                logger.debug("💓 Scheduler worker heartbeat")
                
        except KeyboardInterrupt:
            logger.info("⏹️ Received shutdown signal (KeyboardInterrupt)")
        except asyncio.CancelledError:
            logger.info("⏹️ Received shutdown signal (CancelledError)")
            
    except Exception as e:
        logger.error(f"❌ Failed to start scheduler worker: {e}")
        logger.exception("Full error details:")
        raise
        
    finally:
        # Clean shutdown
        if 'scheduler' in locals():
            logger.info("🛑 Shutting down scheduler...")
            scheduler.shutdown(wait=True)
            logger.info("✅ Scheduler shutdown complete")

def signal_handler(signum, frame):
    """Handle SIGTERM from Heroku dyno restarts"""
    logger.info(f"📡 Received signal {signum}, initiating graceful shutdown...")
    # The main loop will catch this and exit gracefully
    raise KeyboardInterrupt()

if __name__ == "__main__":
    # Handle Heroku's SIGTERM for graceful shutdowns
    import signal
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        # Run the worker
        asyncio.run(main())
        
    except KeyboardInterrupt:
        logger.info("👋 Scheduler worker terminated gracefully")
        sys.exit(0)
        
    except Exception as e:
        logger.error(f"💥 Scheduler worker crashed: {e}")
        logger.exception("Crash details:")
        sys.exit(1) 