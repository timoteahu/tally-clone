# Utils package with organized submodules for better maintainability

# Storage utilities - URL generation, file uploads, Supabase storage
from .storage import (
    generate_profile_photo_url,
    generate_post_image_url,
    generate_post_image_urls,
    generate_verification_image_url,
    generate_verification_image_urls,
    generate_identity_snapshot_url,
    generate_signed_url_optimized,
    upload_to_supabase_storage_with_retry,
    upload_to_supabase_storage_with_cache_control,
    async_upload_to_supabase_storage_with_retry
)

# Validation utilities - image validation, face detection, input validation
from .validation import (
    validate_face_in_image,
    validate_image_format,
    validate_image_size
)

# Content moderation utilities - AWS Rekognition, content filtering
from .moderation import (
    detect_moderation_labels,
    is_content_appropriate,
    is_content_appropriate_for_profile,
    detect_moderation_labels_optimized
)

# Data processing and coordination utilities - memory optimization, async coordination
from .data import (
    cleanup_memory,
    disable_print,
    memory_optimized,
    MemoryLimitedList,
    AsyncCoordinator,
    fetch_with_coordination,
    parallel_data_processing,
    DataFetcher,
    get_user_timezone,
    get_user_date_range_in_timezone,
    get_week_boundaries_in_timezone
)

# Monitoring utilities - memory monitoring, AWS client management
from .monitoring import (
    MemoryMonitor,
    memory_profile,
    log_memory_usage,
    get_system_memory_info,
    get_aws_rekognition_client,
    cleanup_aws_clients
)

__all__ = [
    # Storage utilities
    "generate_profile_photo_url",
    "generate_post_image_url",
    "generate_post_image_urls", 
    "generate_verification_image_url",
    "generate_verification_image_urls",
    "generate_identity_snapshot_url",
    "generate_signed_url_optimized",
    "upload_to_supabase_storage_with_retry",
    "upload_to_supabase_storage_with_cache_control",
    "async_upload_to_supabase_storage_with_retry",
    
    # Validation utilities
    "validate_face_in_image",
    "validate_image_format",
    "validate_image_size",
    
    # Moderation utilities
    "detect_moderation_labels",
    "is_content_appropriate",
    "is_content_appropriate_for_profile",
    "detect_moderation_labels_optimized",
    
    # Data utilities
    "cleanup_memory",
    "disable_print",
    "memory_optimized",
    "MemoryLimitedList",
    "AsyncCoordinator",
    "fetch_with_coordination",
    "parallel_data_processing",
    "DataFetcher",
    "get_user_timezone",
    "get_user_date_range_in_timezone",
    "get_week_boundaries_in_timezone",
    
    # Monitoring utilities
    "MemoryMonitor",
    "memory_profile",
    "log_memory_usage",
    "get_system_memory_info",
    "get_aws_rekognition_client",
    "cleanup_aws_clients"
] 