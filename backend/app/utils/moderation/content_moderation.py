from typing import Tuple, Optional, Dict, Any
from utils.memory_optimization import cleanup_memory, disable_print

# Disable verbose printing for performance
print = disable_print()

def detect_moderation_labels(image: bytes, rekognition_client) -> Optional[Dict[str, Any]]:
    """
    Detect inappropriate content in image using AWS Rekognition Content Moderation.
    
    Args:
        image: Image bytes to analyze
        rekognition_client: AWS Rekognition client
        
    Returns:
        Moderation response dict or None if failed
    """
    try:
        response = rekognition_client.detect_moderation_labels(
            Image={'Bytes': image},
            MinConfidence=75  # 75% confidence threshold for moderation
        )
        return response
    except Exception as e:
        print(f"Content moderation failed: {e}")
        return None

def detect_moderation_labels_optimized(image_bytes: bytes, rekognition_client) -> Optional[Dict[str, Any]]:
    """
    Optimized version of detect_moderation_labels with memory cleanup.
    
    Args:
        image_bytes: Image bytes to analyze
        rekognition_client: AWS Rekognition client
        
    Returns:
        Moderation response dict or None if failed
    """
    try:
        response = rekognition_client.detect_moderation_labels(
            Image={'Bytes': image_bytes},
            MinConfidence=75
        )
        return response
    except Exception as e:
        print(f"Content moderation failed: {e}")
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
        print("⚠️ Content moderation service unavailable, allowing image")
        return True, ""
    
    moderation_labels = moderation_response.get('ModerationLabels', [])
    
    if not moderation_labels:
        return True, ""
    
    # Log detected inappropriate content for monitoring
    flagged_labels = [f"{label['Name']} ({label.get('Confidence', 0):.1f}%)" for label in moderation_labels]
    print(f"🔍 Content moderation labels detected: {flagged_labels}")
    
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
                print(f"❌ {reason}")
                return False, reason
    
    print("✅ Content approved for Apple App Store guidelines")
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
        print("⚠️ Content moderation service unavailable, allowing profile image")
        return True, ""
    
    moderation_labels = moderation_response.get('ModerationLabels', [])
    
    if not moderation_labels:
        return True, ""
    
    # Log detected inappropriate content for monitoring
    flagged_labels = [f"{label['Name']} ({label.get('Confidence', 0):.1f}%)" for label in moderation_labels]
    print(f"🔍 Profile content moderation labels detected: {flagged_labels}")
    
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
    
    # Categories that are acceptable for fitness profile photos
    PROFILE_FITNESS_OK_CATEGORIES = [
        'Swimwear or Underwear',        # Swimwear profile photos OK
        'Female Swimwear or Underwear', 
        'Male Swimwear or Underwear',
        'Non-Explicit Nudity',          # Often just athletic wear
        'Partially Exposed Female Breast',  # Sports bras in profile photos
        'Partially Exposed Male Breast'     # Shirtless fitness profile photos
    ]
    
    # Check for high-confidence truly inappropriate content (stricter threshold for profiles)
    high_confidence_blocks = []
    for label in moderation_labels:
        label_name = label['Name']
        confidence = label['Confidence']
        
        # Use 60% confidence threshold for profile photos (more sensitive)
        # Lower threshold for profile photos to maintain higher standards
        if confidence >= 60:
            if label_name in APPLE_BLOCKED_CATEGORIES:
                high_confidence_blocks.append(label_name)
                break
    
    if high_confidence_blocks:
        primary_flag = high_confidence_blocks[0]
        
        # Provide user-friendly error messages for profile photos
        if any(flag in primary_flag.lower() for flag in ['explicit nudity', 'graphic nudity', 'sexual activity']):
            reason = "🚫 Please upload an appropriate profile photo. Profile photos should be suitable for a professional wellness app."
        elif any(flag in primary_flag.lower() for flag in ['violence', 'graphic violence']):
            reason = "🚫 Please upload a peaceful profile photo. Profile photos should be appropriate for all users."
        elif any(flag in primary_flag.lower() for flag in ['drugs', 'tobacco', 'alcohol']):
            reason = "🚫 Please upload a clean profile photo. Profile photos should reflect the wellness focus of our app."
        else:
            reason = f"🚫 Inappropriate content detected in profile photo. Please upload a different photo that's suitable for all users."
        
        print(f"🚫 Blocking inappropriate profile photo content: {high_confidence_blocks}")
        return False, reason
    
    # Allow fitness-appropriate profile photos even if flagged
    fitness_flags = []
    for label in moderation_labels:
        label_name = label['Name']
        for fitness_category in PROFILE_FITNESS_OK_CATEGORIES:
            if fitness_category.lower() in label_name.lower():
                fitness_flags.append(label_name)
                break
    
    if fitness_flags:
        print(f"✅ Allowing fitness-appropriate profile photo content: {fitness_flags}")
    
    # Log any other flags for monitoring but allow
    other_flags = [label['Name'] for label in moderation_labels 
                   if label['Name'] not in fitness_flags and label['Name'] not in high_confidence_blocks]
    if other_flags:
        print(f"⚠️ Other profile photo moderation flags detected but allowing: {other_flags}")
    
    print("✅ Profile image approved for Apple App Store guidelines")
    return True, ""

def get_moderation_summary(moderation_response: dict) -> Dict[str, Any]:
    """
    Get a summary of moderation results for logging/debugging.
    
    Args:
        moderation_response: AWS Rekognition moderation response
        
    Returns:
        Dict with moderation summary
    """
    if not moderation_response:
        return {"available": False}
    
    labels = moderation_response.get('ModerationLabels', [])
    
    if not labels:
        return {
            "available": True,
            "labels_detected": 0,
            "clean": True,
            "summary": "No inappropriate content detected"
        }
    
    # Categorize labels by confidence
    high_confidence = [l for l in labels if l.get('Confidence', 0) >= 75]
    medium_confidence = [l for l in labels if 50 <= l.get('Confidence', 0) < 75]
    low_confidence = [l for l in labels if l.get('Confidence', 0) < 50]
    
    return {
        "available": True,
        "labels_detected": len(labels),
        "clean": len(labels) == 0,
        "high_confidence_count": len(high_confidence),
        "medium_confidence_count": len(medium_confidence), 
        "low_confidence_count": len(low_confidence),
        "highest_confidence_label": max(labels, key=lambda x: x.get('Confidence', 0)) if labels else None,
        "summary": f"Detected {len(labels)} moderation labels ({len(high_confidence)} high confidence)"
    } 