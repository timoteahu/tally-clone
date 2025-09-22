# Import all service functions for the habit_verification module

# Image verification service
from .image_verification_service import process_image_verification

# Habit verification service  
from .habit_verification_service import (
    check_existing_verification,
    increment_habit_streak,
    decrement_habit_streak,
    reset_habit_streak,
    get_custom_habit_type_cached,  # OPTIMIZATION: Add cached function
    batch_update_streaks,
    clear_custom_habit_type_cache
)

# AWS Rekognition service
from .aws_rekognition_service import (
    perform_face_verification,
    perform_content_moderation,
    # Deprecated - using OpenAI Vision instead:
    # perform_content_analysis,
    # detect_labels_optimized,
    detect_moderation_labels_optimized
)

# Verification validators - DEPRECATED, using OpenAI Vision instead
# from .verification_validators import (
#     is_gym_related,
#     is_bathroom_related,
#     is_yoga_related,
#     is_outdoors_related,
#     is_cycling_related,
#     is_cooking_related,
#     is_health_activity_related,
#     is_custom_habit_related
# )

# Data retrieval service
from .data_retrieval_service import (
    get_latest_verification_service,
    get_verifications_by_habit_service,
    get_verification_by_date_service,
    get_verifications_batch_service  # OPTIMIZATION: Add batch function
)

# Health verification service
from .health_verification_service import (
    verify_health_habit_service,
    share_health_habit_photo_service
)

# Placeholder service functions (to be implemented)
def start_study_session_service(*args, **kwargs):
    raise NotImplementedError("Study session service not yet implemented")

def complete_study_session_service(*args, **kwargs):
    raise NotImplementedError("Study session service not yet implemented")

def get_screen_time_status_service(*args, **kwargs):
    raise NotImplementedError("Screen time service not yet implemented")

def update_screen_time_status_service(*args, **kwargs):
    raise NotImplementedError("Screen time service not yet implemented")

__all__ = [
    # Image verification
    "process_image_verification",
    
    # Habit verification
    "check_existing_verification",
    "increment_habit_streak", 
    "decrement_habit_streak",
    "reset_habit_streak",
    "get_custom_habit_type_cached",  # OPTIMIZATION: Add cached function
    "batch_update_streaks",
    "clear_custom_habit_type_cache",
    
    # AWS Rekognition (only what's actually imported)
    "perform_face_verification",
    "perform_content_moderation",
    "detect_moderation_labels_optimized",
    
    # Data retrieval
    "get_latest_verification_service",
    "get_verifications_by_habit_service", 
    "get_verification_by_date_service",
    "get_verifications_batch_service",  # OPTIMIZATION: Add batch function
    
    # Health verification
    "verify_health_habit_service",
    "share_health_habit_photo_service",
    
    # Placeholder services
    "start_study_session_service",
    "complete_study_session_service",
    "get_screen_time_status_service",
    "update_screen_time_status_service"
] 