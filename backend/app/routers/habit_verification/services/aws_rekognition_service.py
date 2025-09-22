from typing import Tuple, Dict, Any, Optional
from utils.aws_client_manager import get_aws_rekognition_client, AWSResponseCleaner
from utils.memory_optimization import cleanup_memory, memory_optimized
from utils.memory_monitoring import MemoryMonitor
from utils.moderation import is_content_appropriate

# Note: perform_content_analysis is deprecated - use OpenAI Vision API instead
# Export perform_content_moderation for NSFW checks alongside OpenAI

@memory_optimized(cleanup_args=False)
async def perform_face_verification(
    identity_bytes: bytes, 
    selfie_bytes: bytes
) -> Tuple[bool, str, float]:
    """
    Face verification using singleton AWS client with memory optimization.
    
    Returns:
        Tuple[bool, str, float]: (success, message, similarity_score)
    """
    with MemoryMonitor("face_verification") as monitor:
        # Get singleton client
        rekognition_client = get_aws_rekognition_client()
        if not rekognition_client:
            return False, "verification service temporarily unavailable", 0.0
        
        monitor.checkpoint("client_obtained")
        
        # Use AWS response cleaner for automatic cleanup
        with AWSResponseCleaner() as aws_cleaner:
            try:
                # Perform face comparison using singleton client
                response = rekognition_client.compare_faces(
                    SourceImage={'Bytes': identity_bytes},
                    TargetImage={'Bytes': selfie_bytes},
                    SimilarityThreshold=80
                )
                
                # Register response for automatic cleanup
                aws_cleaner.register(response)
                monitor.checkpoint("face_comparison_complete")
                
                if not response or not response.get('FaceMatches'):
                    return False, "couldn't detect your face in the selfie. make sure your face is clearly visible and well-lit", 0.0
                
                # Extract similarity immediately
                similarity = response['FaceMatches'][0]['Similarity']
                monitor.checkpoint("similarity_extracted")
                
                if similarity < 80:
                    return False, f"🤔 The face in the selfie doesn't match your identity snapshot clearly enough ({similarity:.1f}% match). Please take a clearer selfie.", similarity
                
                return True, "", similarity
                
            except Exception as e:
                monitor.checkpoint(f"error_{type(e).__name__}")
                return False, "Face verification failed. Please try again.", 0.0
        
        # AWS response automatically cleaned up by context manager

# DEPRECATED: Content analysis now handled by OpenAI Vision API
# Keeping only for backward compatibility - DO NOT USE
# @memory_optimized(cleanup_args=False)
# async def perform_content_analysis(
#     content_bytes: bytes,
#     context_validator,
#     habit_type: str,
#     context_error_message: str
# ) -> Tuple[bool, str]:
#     """
#     DEPRECATED - Use OpenAI Vision API instead
#     Content analysis using singleton AWS client with memory optimization.
#     
#     Returns:
#         Tuple[bool, str]: (success, message)
#     """
#     with MemoryMonitor("content_analysis") as monitor:
#         # Get singleton client
#         rekognition_client = get_aws_rekognition_client()
#         if not rekognition_client:
#             return False, "🔍 We couldn't analyze the content image properly. Please try taking another photo with better lighting."
#         
#         monitor.checkpoint("client_obtained")
#         
#         # Use AWS response cleaner for automatic cleanup
#         with AWSResponseCleaner() as aws_cleaner:
#             try:
#                 # Label detection
#                 labels_response = detect_labels_optimized(content_bytes, rekognition_client)
#                 aws_cleaner.register(labels_response)
#                 monitor.checkpoint("labels_detected")
#                 
#                 if not labels_response:
#                     return False, "🔍 We couldn't analyze the content image properly. Please try taking another photo with better lighting."
#                 
#                 # Extract labels immediately
#                 labels = labels_response.get('Labels', [])
#                 is_valid_context = context_validator(labels)
#                 monitor.checkpoint("context_validated")
#                 
#                 if not is_valid_context:
#                     context_description = {
#                         "gym": "gym",
#                         "alarm": "bathroom",
#                     }.get(habit_type, habit_type)
#                     
#                     return False, context_error_message
#                 
#                 # Content moderation
#                 moderation_response = detect_moderation_labels_optimized(content_bytes, rekognition_client)
#                 aws_cleaner.register(moderation_response)
#                 monitor.checkpoint("moderation_checked")
#                 
#                 is_appropriate, moderation_reason = is_content_appropriate(moderation_response)
#                 
#                 if not is_appropriate:
#                     return False, f"🚫 {moderation_reason}"
#                 
#                 return True, ""
#                 
#             except Exception as e:
#                 monitor.checkpoint(f"error_{type(e).__name__}")
#                 return False, "Content analysis failed. Please try again."
#         
#         # AWS responses automatically cleaned up by context manager

@memory_optimized(cleanup_args=False)
async def perform_content_moderation(content_bytes: bytes) -> Tuple[bool, str]:
    """
    Content moderation using AWS Rekognition for NSFW detection.
    This is still used alongside OpenAI verification.
    
    Returns:
        Tuple[bool, str]: (is_appropriate, reason)
    """
    with MemoryMonitor("content_moderation") as monitor:
        # Get singleton client
        rekognition_client = get_aws_rekognition_client()
        if not rekognition_client:
            return True, ""  # Default to appropriate if service unavailable
        
        monitor.checkpoint("client_obtained")
        
        # Use AWS response cleaner for automatic cleanup
        with AWSResponseCleaner() as aws_cleaner:
            try:
                # Content moderation only
                moderation_response = detect_moderation_labels_optimized(content_bytes, rekognition_client)
                aws_cleaner.register(moderation_response)
                monitor.checkpoint("moderation_checked")
                
                is_appropriate, moderation_reason = is_content_appropriate(moderation_response)
                
                if not is_appropriate:
                    return False, f"🚫 {moderation_reason}"
                
                return True, ""
                
            except Exception as e:
                monitor.checkpoint(f"error_{type(e).__name__}")
                return True, ""  # Default to appropriate on error

# DEPRECATED: Label detection now handled by OpenAI Vision API
# def detect_labels_optimized(image_bytes: bytes, rekognition_client) -> Optional[Dict[str, Any]]:
#     """
#     DEPRECATED - Use OpenAI Vision API instead
#     Detect labels using singleton client with memory optimization.
#     """
#     try:
#         response = rekognition_client.detect_labels(
#             Image={'Bytes': image_bytes},
#             MaxLabels=50,  # Restore original for proper detection
#             MinConfidence=70
#         )
#         return response
#     except Exception as e:
#         return None

def detect_moderation_labels_optimized(image_bytes: bytes, rekognition_client) -> Optional[Dict[str, Any]]:
    """
    Detect moderation labels using singleton client with memory optimization.
    """
    try:
        response = rekognition_client.detect_moderation_labels(
            Image={'Bytes': image_bytes},
            MinConfidence=75
        )
        return response
    except Exception as e:
        return None

def is_content_appropriate(moderation_response: dict) -> Tuple[bool, str]:
    """
    Check if image content is appropriate for Apple App Store compliance.
    
    Apple App Store guidelines require family-friendly content suitable for all ages.
    This is more restrictive than general NSFW filtering to ensure app store approval.
    
    Args:
        moderation_response: AWS Rekognition detect_moderation_labels response
    
    Returns:
        tuple: (is_appropriate: bool, reason: str)
    """
    if not moderation_response:
        # If moderation fails, allow the image (fail open for better UX)
        return True, ""
    
    moderation_labels = moderation_response.get('ModerationLabels', [])
    
    if not moderation_labels:
        return True, ""
    
    # Log detected inappropriate content for monitoring
    flagged_labels = [f"{label['Name']} ({label.get('Confidence', 0):.1f}%)" for label in moderation_labels]
    
    # Apple App Store Compliance: Block content that would violate their guidelines
    # These are stricter than general NSFW to ensure family-friendly content
    # Using only verified AWS Rekognition Content Moderation labels (Model v7.0)
    APPLE_BLOCKED_CATEGORIES = [
        # Sexual/Adult Content (Apple is very strict - these are verified AWS labels)
        'Explicit Nudity',
        'Graphic Male Nudity',
        'Graphic Female Nudity', 
        'Sexual Activity',
        'Partial Nudity',
        'Female Swimwear Or Underwear',
        'Male Swimwear Or Underwear',
        'Revealing Clothes',
        
        # Violence/Disturbing Content (verified AWS labels)
        'Graphic Violence',
        'Violence',
        'Visually Disturbing',
        'Emaciated Bodies',
        'Corpses',
        'Hanging',
        'Weapons',
        'Weapon Violence',
        
        # Discrimination/Hate (verified AWS labels)
        'Hate Symbols',
        'Nazi Party',
        'White Supremacy',
        
        # Substances (Apple is strict - verified AWS labels)
        'Drugs',
        'Drug Products',
        'Drug Paraphernalia',
        'Pills',
        'Smoking',
        'Tobacco',
        'Alcohol',
        'Alcoholic Beverages',
        'Beer',
        'Wine',
        
        # Gambling (verified AWS label)
        'Gambling',
        
        # Inappropriate Gestures (verified AWS labels)
        'Rude Gestures',
        'Middle Finger',
        
        # Additional Apple App Store Requirements
        'Explosions And Blasts',
        'Self Injury'
    ]
    
    # Check each detected label against blocked categories
    for label in moderation_labels:
        label_name = label.get('Name', '')
        confidence = label.get('Confidence', 0)
        
        # Use 75% confidence threshold for habit verification (balanced approach)
        # Higher precision to avoid false positives while catching actual inappropriate content
        if confidence >= 75:
            if label_name in APPLE_BLOCKED_CATEGORIES:
                reason = f"Content blocked for App Store compliance: {label_name} ({confidence:.1f}% confidence)"
                return False, reason
    
    return True, ""

def is_content_appropriate_for_profile(moderation_response: dict) -> Tuple[bool, str]:
    """
    Check if image content is appropriate for profile photos with stricter standards.
    
    Profile photos have stricter requirements since they represent the user publicly.
    Uses lower confidence threshold for more sensitive detection.
    
    Args:
        moderation_response: AWS Rekognition detect_moderation_labels response
    
    Returns:
        tuple: (is_appropriate: bool, reason: str)
    """
    if not moderation_response:
        # If moderation fails, allow the image (fail open for better UX)
        return True, ""
    
    moderation_labels = moderation_response.get('ModerationLabels', [])
    
    if not moderation_labels:
        return True, ""
    
    # Log detected inappropriate content for monitoring
    flagged_labels = [f"{label['Name']} ({label.get('Confidence', 0):.1f}%)" for label in moderation_labels]
    
    # Same blocked categories as habit verification but with stricter confidence
    APPLE_BLOCKED_CATEGORIES = [
        # Sexual/Adult Content (Apple is very strict - these are verified AWS labels)
        'Explicit Nudity',
        'Graphic Male Nudity',
        'Graphic Female Nudity', 
        'Sexual Activity',
        'Partial Nudity',
        'Female Swimwear Or Underwear',
        'Male Swimwear Or Underwear',
        'Revealing Clothes',
        
        # Violence/Disturbing Content (verified AWS labels)
        'Graphic Violence',
        'Violence',
        'Visually Disturbing',
        'Emaciated Bodies',
        'Corpses',
        'Hanging',
        'Weapons',
        'Weapon Violence',
        
        # Discrimination/Hate (verified AWS labels)
        'Hate Symbols',
        'Nazi Party',
        'White Supremacy',
        
        # Substances (Apple is strict - verified AWS labels)
        'Drugs',
        'Drug Products',
        'Drug Paraphernalia',
        'Pills',
        'Smoking',
        'Tobacco',
        'Alcohol',
        'Alcoholic Beverages',
        'Beer',
        'Wine',
        
        # Gambling (verified AWS label)
        'Gambling',
        
        # Inappropriate Gestures (verified AWS labels)
        'Rude Gestures',
        'Middle Finger',
        
        # Additional Apple App Store Requirements
        'Explosions And Blasts',
        'Self Injury'
    ]
    
    # Check each detected label against blocked categories
    for label in moderation_labels:
        label_name = label.get('Name', '')
        confidence = label.get('Confidence', 0)
        
        # Use 60% confidence threshold for profile photos (more sensitive)
        # Lower threshold for profile photos to maintain higher standards
        if confidence >= 60:
            if label_name in APPLE_BLOCKED_CATEGORIES:
                reason = f"Profile image blocked for App Store compliance: {label_name} ({confidence:.1f}% confidence)"
                return False, reason
    
    return True, "" 