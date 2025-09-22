from datetime import datetime, timedelta, date, time
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
import pytz
import logging

# Import all task modules
from .daily_penalties import check_and_charge_penalties
from .weekly_penalties import check_weekly_penalties
from .payment_processing import update_processing_payment_statuses, process_all_eligible_transfers, check_and_charge_unpaid_penalties
from .habit_management import process_habit_notifications, cleanup_old_habit_notifications
from .github_habits import update_github_weekly_progress_task
from .leetcode_habits import update_leetcode_weekly_progress_task
from .maintenance import archive_old_feed_cards_task

# Import utility functions from other modules
from utils.habit_staging import process_staged_habit_changes, cleanup_old_staged_changes

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)  # Ensure logger itself is set to INFO level

def setup_scheduler(development_mode=False):
    """
    Set up the APScheduler to run tasks at specific times
    """
    scheduler = AsyncIOScheduler()
    
    # Configure scheduler to be more tolerant of delays
    scheduler.configure(
        job_defaults={
            'misfire_grace_time': 30,  # Allow jobs to start up to 30 seconds late without warning
            'max_instances': 1  # Prevent multiple instances of the same job from running
        }
    )
    
    if development_mode:
        # For development/testing: run more frequently
        scheduler.add_job(
            check_and_charge_penalties,
            CronTrigger(minute='*'),
            id="check_and_charge_penalties",
            replace_existing=True
        )
        # NEW: Hourly payment processing (every 10 minutes in development)
        scheduler.add_job(
            check_and_charge_unpaid_penalties,
            CronTrigger(minute='*/10'),
            id="check_and_charge_unpaid_penalties", 
            replace_existing=True
        )
        # Weekly penalty checking every 5 minutes for testing
        scheduler.add_job(
            check_weekly_penalties,
            CronTrigger(minute='*/5'),  # Every 5 minutes for testing
            id="check_weekly_penalties",
            replace_existing=True
        )
        # Process staged habit changes every 2 minutes for testing
        scheduler.add_job(
            process_staged_habit_changes,
            CronTrigger(minute='*/2'),
            id="process_staged_habit_changes",
            replace_existing=True
        )
        # Update payment statuses every 5 minutes in development for testing
        scheduler.add_job(
            update_processing_payment_statuses,
            CronTrigger(minute='*/5'),  # Changed from 2 to 5 minutes to reduce overlap
            id="update_payment_statuses",
            replace_existing=True
        )
        # Process eligible transfers every 3 minutes in development
        scheduler.add_job(
            process_all_eligible_transfers,
            CronTrigger(minute='*/3'),
            id="process_eligible_transfers",
            replace_existing=True
        )
        # Archive old feed cards
        scheduler.add_job(
            archive_old_feed_cards_task,
            CronTrigger(minute='*/5'),
            id="archive_old_feed_cards",
            replace_existing=True
        )
        # Process habit notifications every 2 minutes in development
        scheduler.add_job(
            process_habit_notifications,
            CronTrigger(minute='*/2'),
            id="process_habit_notifications",
            replace_existing=True
        )
        # Clean up old notifications every 30 minutes in development
        scheduler.add_job(
            cleanup_old_habit_notifications,
            CronTrigger(minute='*/30'),
            id="cleanup_old_habit_notifications",
            replace_existing=True
        )
        # Update GitHub weekly progress every 10 minutes in development
        scheduler.add_job(
            update_github_weekly_progress_task,
            CronTrigger(minute='*/10'),
            id="update_github_weekly_progress",
            replace_existing=True
        )
        # Update LeetCode weekly progress every 10 minutes in development
        scheduler.add_job(
            update_leetcode_weekly_progress_task,
            CronTrigger(minute='*/10'),
            id="update_leetcode_weekly_progress",
            replace_existing=True
        )
    else:
        # Production: Run daily penalties every hour to handle different timezones
        # This allows us to check penalties at end-of-day for users across all timezones
        scheduler.add_job(
            check_and_charge_penalties,
            CronTrigger(minute=0),  # Every hour at minute 0
            id="check_and_charge_penalties",
            replace_existing=True
        )
        # NEW: Hourly payment processing for users with ≥$5 unpaid penalties
        scheduler.add_job(
            check_and_charge_unpaid_penalties,
            CronTrigger(minute=15),  # Every hour at minute 15
            id="check_and_charge_unpaid_penalties",
            replace_existing=True
        )
        # Check weekly habits for missed completions at specific timing
        scheduler.add_job(
            check_weekly_penalties,
            CronTrigger(minute=30),  # Every hour at minute 30 (offset from daily penalty checks)
            id="check_weekly_penalties",
            replace_existing=True
        )
        # Process staged habit changes every hour to handle different timezones
        scheduler.add_job(
            process_staged_habit_changes,
            CronTrigger(minute=30),  # Every hour at minute 30 (offset from penalty checks)
            id="process_staged_habit_changes",
            replace_existing=True
        )
        # Clean up old staged changes daily at 2:00 UTC
        scheduler.add_job(
            cleanup_old_staged_changes,
            CronTrigger(hour=2, minute=0),
            id="cleanup_old_staged_changes",
            replace_existing=True
        )
        # Update payment statuses every 15 minutes
        scheduler.add_job(
            update_processing_payment_statuses,
            CronTrigger(minute='*/15'),  # Every 15 minutes
            id="update_payment_statuses",
            replace_existing=True
        )
        # Process eligible transfers every 15 minutes in production
        scheduler.add_job(
            process_all_eligible_transfers,
            CronTrigger(minute='*/15'),  # Every 15 minutes
            id="process_eligible_transfers",
            replace_existing=True
        )
        # Archive old feed cards hourly
        scheduler.add_job(
            archive_old_feed_cards_task,
            CronTrigger(minute=15),  # Every hour at minute 15
            id="archive_old_feed_cards",
            replace_existing=True
        )
        # Process habit notifications every 5 minutes in production
        scheduler.add_job(
            process_habit_notifications,
            CronTrigger(minute='*/5'),
            id="process_habit_notifications",
            replace_existing=True
        )
        # Clean up old notifications daily at 3:00 UTC
        scheduler.add_job(
            cleanup_old_habit_notifications,
            CronTrigger(hour=3, minute=0),
            id="cleanup_old_habit_notifications",
            replace_existing=True
        )
        # Update GitHub weekly progress every 30 minutes in production
        scheduler.add_job(
            update_github_weekly_progress_task,
            CronTrigger(minute='*/30'),  # Every 30 minutes
            id="update_github_weekly_progress",
            replace_existing=True
        )
        # Update LeetCode weekly progress every 30 minutes in production
        scheduler.add_job(
            update_leetcode_weekly_progress_task,
            CronTrigger(minute='*/30'),  # Every 30 minutes
            id="update_leetcode_weekly_progress",
            replace_existing=True
        )
    
    # After all scheduler.add_job calls but before return scheduler
    # Log all scheduled jobs for visibility
    for job in scheduler.get_jobs():
        next_run = getattr(job, 'next_run_time', None)
        print(f"[Scheduler] Job '{job.id}' scheduled, trigger: {job.trigger}, next run: {next_run}")

    # Attach listeners to log job runs and errors if not already set
    from apscheduler.events import EVENT_JOB_EXECUTED, EVENT_JOB_ERROR

    def _log_job_event(event):
        job = scheduler.get_job(event.job_id)
        if event.exception:
            print(f"[Scheduler] Job '{event.job_id}' raised an exception: {event.exception}")
        else:
            print(f"[Scheduler] Job '{event.job_id}' executed successfully at {event.scheduled_run_time}")

    scheduler.add_listener(_log_job_event, EVENT_JOB_EXECUTED | EVENT_JOB_ERROR)

    # Add GitHub token refresh tasks
    from tasks.github_token_refresh import setup_github_token_refresh_tasks
    setup_github_token_refresh_tasks(scheduler)
    
    return scheduler