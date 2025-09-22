"""
Health Data Processing Utilities

This module provides utilities for processing Apple Health data,
verifying health habits, and managing health-based habit verification.
"""

import logging
from datetime import datetime, date, timedelta
from typing import Dict, List, Optional, Tuple
from supabase._async.client import AsyncClient
import pytz

logger = logging.getLogger(__name__)

# HealthKit data type mappings
HEALTH_DATA_TYPE_MAPPINGS = {
    'health_steps': {
        'healthkit_type': 'stepCount',
        'unit': 'steps',
        'display_name': 'Steps',
        'default_target': 10000,
        'aggregation': 'sum'
    },
    'health_walking_running_distance': {
        'healthkit_type': 'distanceWalkingRunning',
        'unit': 'miles',
        'display_name': 'Walking + Running Distance',
        'default_target': 3.0,
        'aggregation': 'sum'
    },
    'health_flights_climbed': {
        'healthkit_type': 'flightsClimbed',
        'unit': 'flights',
        'display_name': 'Flights Climbed',
        'default_target': 10,
        'aggregation': 'sum'
    },
    'health_exercise_minutes': {
        'healthkit_type': 'appleExerciseTime',
        'unit': 'minutes',
        'display_name': 'Exercise Minutes',
        'default_target': 30,
        'aggregation': 'sum'
    },
    'health_cycling_distance': {
        'healthkit_type': 'distanceCycling',
        'unit': 'miles',
        'display_name': 'Cycling Distance',
        'default_target': 5.0,
        'aggregation': 'sum'
    },
    'health_sleep_hours': {
        'healthkit_type': 'sleepAnalysis',
        'unit': 'hours',
        'display_name': 'Sleep',
        'default_target': 8.0,
        'aggregation': 'average'
    },
    'health_water_intake': {
        'healthkit_type': 'dietaryWater',
        'unit': 'liters',
        'display_name': 'Water Intake',
        'default_target': 2.5,
        'aggregation': 'sum'
    },
    'health_heart_rate': {
        'healthkit_type': 'heartRate',
        'unit': 'bpm',
        'display_name': 'Heart Rate',
        'default_target': 70,
        'aggregation': 'average'
    },
    'health_calories_burned': {
        'healthkit_type': 'activeEnergyBurned',
        'unit': 'calories',
        'display_name': 'Calories Burned',
        'default_target': 500,
        'aggregation': 'sum'
    },
    'health_mindful_minutes': {
        'healthkit_type': 'mindfulSession',
        'unit': 'minutes',
        'display_name': 'Mindful Minutes',
        'default_target': 10,
        'aggregation': 'sum'
    }
}

def get_health_data_config(habit_type: str) -> Optional[Dict]:
    """Get configuration for a health data type"""
    return HEALTH_DATA_TYPE_MAPPINGS.get(habit_type)

def is_health_habit_type(habit_type: str) -> bool:
    """Check if a habit type is a health-based habit"""
    return habit_type in HEALTH_DATA_TYPE_MAPPINGS

async def get_user_health_data_for_date(
    supabase: AsyncClient,
    user_id: str,
    data_type: str,
    target_date: date
) -> Optional[float]:
    """
    Get health data value for a specific user, data type, and date.
    
    Args:
        supabase: Database client
        user_id: User ID
        data_type: HealthKit data type identifier
        target_date: Date to get data for
        
    Returns:
        Health data value or None if not found
    """
    try:
        result = await supabase.table("user_health_data").select("value").eq(
            "user_id", user_id
        ).eq("data_type", data_type).eq("date", target_date.isoformat()).execute()
        
        if result.data:
            return float(result.data[0]['value'])
        return None
        
    except Exception as e:
        logger.error(f"Error getting health data for user {user_id}, type {data_type}, date {target_date}: {e}")
        return None

async def verify_health_habit(
    supabase: AsyncClient,
    habit_id: str,
    user_id: str,
    verification_date: date
) -> Dict[str, any]:
    """
    Verify a health habit for a specific date by checking if the target was met.
    
    Args:
        supabase: Database client
        habit_id: Habit ID
        user_id: User ID
        verification_date: Date to verify for
        
    Returns:
        Dict with verification result
    """
    try:
        # Get habit details
        habit_result = await supabase.table("habits").select("*").eq("id", habit_id).eq("user_id", user_id).execute()
        if not habit_result.data:
            return {"success": False, "error": "Habit not found"}
        
        habit = habit_result.data[0]
        
        # Check if it's a health habit
        if not is_health_habit_type(habit['habit_type']):
            return {"success": False, "error": "Not a health habit"}
        
        # Get health data type configuration
        config = get_health_data_config(habit['habit_type'])
        if not config:
            return {"success": False, "error": "Invalid health habit type"}
        
        # Get health data for the date
        healthkit_type = config['healthkit_type']
        actual_value = await get_user_health_data_for_date(
            supabase, user_id, healthkit_type, verification_date
        )
        
        if actual_value is None:
            return {
                "success": False, 
                "error": "No health data found for this date",
                "requires_data_sync": True
            }
        
        # Check if target was met
        target_value = habit.get('health_target_value', config['default_target'])
        is_target_met = actual_value >= target_value
        
        # Update or create progress record
        progress_data = {
            "habit_id": habit_id,
            "user_id": user_id,
            "date": verification_date.isoformat(),
            "target_value": target_value,
            "actual_value": actual_value,
            "unit": habit.get('health_target_unit', config['unit']),
            "data_type": healthkit_type,
            "is_target_met": is_target_met
        }
        
        await supabase.table("health_habit_progress").upsert(
            progress_data, 
            on_conflict="habit_id,date"
        ).execute()
        
        return {
            "success": True,
            "is_target_met": is_target_met,
            "actual_value": actual_value,
            "target_value": target_value,
            "unit": config['unit'],
            "progress_percentage": min(100, (actual_value / target_value * 100)) if target_value > 0 else 0
        }
        
    except Exception as e:
        logger.error(f"Error verifying health habit {habit_id}: {e}")
        return {"success": False, "error": "Verification failed"}

async def get_health_habit_streak(
    supabase: AsyncClient,
    habit_id: str,
    user_id: str
) -> int:
    """
    Calculate the current streak for a health habit.
    
    Args:
        supabase: Database client
        habit_id: Habit ID
        user_id: User ID
        
    Returns:
        Current streak count
    """
    try:
        # Get habit to determine timezone
        from utils.timezone_utils import get_user_timezone
        user_timezone = await get_user_timezone(supabase, user_id)
        user_tz = pytz.timezone(user_timezone)
        today = datetime.now(user_tz).date()
        
        # Get recent progress records
        start_date = today - timedelta(days=365)  # Look back up to a year
        
        progress_result = await supabase.table("health_habit_progress").select(
            "date, is_target_met"
        ).eq("habit_id", habit_id).gte("date", start_date.isoformat()).order("date", desc=True).execute()
        
        if not progress_result.data:
            return 0
        
        # Calculate streak
        streak = 0
        current_date = today
        
        # Convert progress data to a dict for easy lookup
        progress_dict = {
            datetime.fromisoformat(p['date']).date(): p['is_target_met']
            for p in progress_result.data
        }
        
        # Count consecutive days from today backwards
        while current_date in progress_dict:
            if progress_dict[current_date]:
                streak += 1
                current_date -= timedelta(days=1)
            else:
                break
        
        return streak
        
    except Exception as e:
        logger.error(f"Error calculating health habit streak for {habit_id}: {e}")
        return 0

async def get_weekly_health_summary(
    supabase: AsyncClient,
    user_id: str,
    start_date: date,
    end_date: date
) -> Dict[str, any]:
    """
    Get a weekly summary of all health habits for a user.
    
    Args:
        supabase: Database client
        user_id: User ID
        start_date: Week start date
        end_date: Week end date
        
    Returns:
        Dict with weekly summary data
    """
    try:
        # Get all active health habits for the user
        health_habit_types = list(HEALTH_DATA_TYPE_MAPPINGS.keys())
        habits_result = await supabase.table("habits").select("*").eq(
            "user_id", user_id
        ).in_("habit_type", health_habit_types).eq("is_active", True).execute()
        
        if not habits_result.data:
            return {"habits": [], "summary": {"total_habits": 0, "targets_met": 0, "completion_rate": 0}}
        
        habit_summaries = []
        total_targets_met = 0
        total_possible_targets = 0
        
        for habit in habits_result.data:
            # Get progress for the week
            progress_result = await supabase.table("health_habit_progress").select("*").eq(
                "habit_id", habit['id']
            ).gte("date", start_date.isoformat()).lte("date", end_date.isoformat()).execute()
            
            targets_met = sum(1 for p in progress_result.data if p['is_target_met'])
            days_with_data = len(progress_result.data)
            
            # For daily health habits, calculate how many days were required this week
            if habit.get('habit_schedule_type') == 'daily':
                weekdays = habit.get('weekdays', [])
                required_days = 0
                current_date = start_date
                while current_date <= end_date:
                    day_of_week = current_date.weekday()
                    postgres_weekday = (day_of_week + 1) % 7  # Convert to PostgreSQL weekday format
                    if postgres_weekday in weekdays:
                        required_days += 1
                    current_date += timedelta(days=1)
            else:
                required_days = 7  # Assume daily tracking for weekly habits
            
            habit_summaries.append({
                "habit_id": habit['id'],
                "habit_name": habit['name'],
                "habit_type": habit['habit_type'],
                "targets_met": targets_met,
                "days_with_data": days_with_data,
                "required_days": required_days,
                "completion_rate": (targets_met / required_days * 100) if required_days > 0 else 0
            })
            
            total_targets_met += targets_met
            total_possible_targets += required_days
        
        overall_completion_rate = (total_targets_met / total_possible_targets * 100) if total_possible_targets > 0 else 0
        
        return {
            "habits": habit_summaries,
            "summary": {
                "total_habits": len(habits_result.data),
                "targets_met": total_targets_met,
                "total_possible": total_possible_targets,
                "completion_rate": overall_completion_rate
            },
            "week_start": start_date.isoformat(),
            "week_end": end_date.isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error getting weekly health summary for user {user_id}: {e}")
        return {"habits": [], "summary": {"total_habits": 0, "targets_met": 0, "completion_rate": 0}}

async def sync_health_data_batch(
    supabase: AsyncClient,
    user_id: str,
    health_data_points: List[Dict]
) -> Dict[str, any]:
    """
    Sync a batch of health data points and update related habits.
    
    Args:
        supabase: Database client
        user_id: User ID
        health_data_points: List of health data points to sync
        
    Returns:
        Dict with sync results
    """
    try:
        processed_count = 0
        updated_habits = set()
        errors = []
        
        for data_point in health_data_points:
            try:
                # Validate required fields
                required_fields = ['data_type', 'value', 'unit', 'date']
                if not all(field in data_point for field in required_fields):
                    errors.append(f"Missing required fields in data point: {data_point}")
                    continue
                
                # Parse date
                data_date = datetime.fromisoformat(data_point['date']).date()
                
                # Create health data record
                health_record = {
                    "user_id": user_id,
                    "data_type": data_point['data_type'],
                    "value": float(data_point['value']),
                    "unit": data_point['unit'],
                    "date": data_date.isoformat(),
                    "start_time": data_point.get('start_time'),
                    "end_time": data_point.get('end_time'),
                    "source_name": data_point.get('source_name'),
                    "metadata": data_point.get('metadata', {})
                }
                
                # Upsert health data
                await supabase.table("user_health_data").upsert(
                    health_record,
                    on_conflict="user_id,data_type,date"
                ).execute()
                
                processed_count += 1
                
                # Find and update related habits
                habit_type = None
                for ht, config in HEALTH_DATA_TYPE_MAPPINGS.items():
                    if config['healthkit_type'] == data_point['data_type']:
                        habit_type = ht
                        break
                
                if habit_type:
                    # Get active habits of this type
                    habits_result = await supabase.table("habits").select("*").eq(
                        "user_id", user_id
                    ).eq("habit_type", habit_type).eq("is_active", True).execute()
                    
                    for habit in habits_result.data:
                        # Update progress
                        target_value = habit.get('health_target_value') or HEALTH_DATA_TYPE_MAPPINGS[habit_type]['default_target']
                        is_target_met = float(data_point['value']) >= target_value
                        
                        progress_data = {
                            "habit_id": habit['id'],
                            "user_id": user_id,
                            "date": data_date.isoformat(),
                            "target_value": target_value,
                            "actual_value": float(data_point['value']),
                            "unit": data_point['unit'],
                            "data_type": data_point['data_type'],
                            "is_target_met": is_target_met
                        }
                        
                        await supabase.table("health_habit_progress").upsert(
                            progress_data,
                            on_conflict="habit_id,date"
                        ).execute()
                        
                        updated_habits.add(habit['id'])
                
            except Exception as e:
                errors.append(f"Error processing data point {data_point}: {str(e)}")
                continue
        
        return {
            "success": True,
            "processed_count": processed_count,
            "updated_habits": list(updated_habits),
            "errors": errors
        }
        
    except Exception as e:
        logger.error(f"Error syncing health data batch: {e}")
        return {
            "success": False,
            "error": str(e),
            "processed_count": 0,
            "updated_habits": [],
            "errors": []
        } 