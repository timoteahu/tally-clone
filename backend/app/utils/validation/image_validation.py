import io
from PIL import Image, ImageOps
from typing import Dict, Any
from utils.memory_optimization import cleanup_memory, disable_print

# Disable verbose printing for performance
print = disable_print()

def validate_face_in_image(image_bytes: bytes, rekognition_client) -> Dict[str, Any]:
    """
    Validate that image contains exactly one face with high confidence using AWS Rekognition.
    
    Args:
        image_bytes: Image data as bytes
        rekognition_client: AWS Rekognition client
        
    Returns:
        Dict with validation results including success status, message, and face details
    """
    try:
        response = rekognition_client.detect_faces(
            Image={'Bytes': image_bytes},
            Attributes=['DEFAULT']
        )
        
        faces = response.get('FaceDetails', [])
        
        if len(faces) == 0:
            return {
                "valid": False,
                "reason": "no_face_detected",
                "message": "No face detected in the image. Please upload a clear photo of your face."
            }
        
        if len(faces) > 1:
            return {
                "valid": False,
                "reason": "multiple_faces",
                "message": f"Multiple faces detected ({len(faces)}). Please upload a photo with only your face."
            }
        
        # Check face confidence
        face = faces[0]
        confidence = face.get('Confidence', 0)
        
        if confidence < 95.0:  # 95% confidence threshold as per docs
            return {
                "valid": False,
                "reason": "low_confidence",
                "message": f"Face detection confidence too low ({confidence:.1f}%). Please upload a clearer photo."
            }
        
        return {
            "valid": True,
            "confidence": confidence,
            "face_details": face
        }
        
    except Exception as e:
        print(f"Face validation failed: {e}")
        return {
            "valid": False,
            "reason": "analysis_failed", 
            "message": "Could not analyze the image. Please try again."
        }

def validate_image_format(image_bytes: bytes) -> bool:
    """
    Validate if image bytes represent a valid image format.
    
    Args:
        image_bytes: Image bytes to validate
        
    Returns:
        True if valid image, False otherwise
    """
    try:
        with io.BytesIO(image_bytes) as buffer:
            with Image.open(buffer) as img:
                # Try to verify the image
                img.verify()
                return True
    except Exception:
        return False

def validate_image_size(image_bytes: bytes, max_size_mb: float = 10.0) -> Dict[str, Any]:
    """
    Validate image size constraints.
    
    Args:
        image_bytes: Image data as bytes
        max_size_mb: Maximum allowed size in megabytes
        
    Returns:
        Dict with validation results
    """
    size_mb = len(image_bytes) / 1024 / 1024
    
    if size_mb > max_size_mb:
        return {
            "valid": False,
            "reason": "size_too_large",
            "message": f"Image too large ({size_mb:.1f}MB). Maximum {max_size_mb}MB allowed.",
            "actual_size_mb": size_mb,
            "max_size_mb": max_size_mb
        }
    
    return {
        "valid": True,
        "size_mb": size_mb
    }

def validate_image_content_type(content_type: str) -> bool:
    """
    Validate image content type.
    
    Args:
        content_type: MIME content type string
        
    Returns:
        True if valid image content type, False otherwise
    """
    valid_content_types = [
        "image/jpeg", 
        "image/jpg", 
        "image/png", 
        "image/gif", 
        "image/webp"
    ]
    return content_type.lower() in valid_content_types

def validate_image_signature(image_bytes: bytes) -> Dict[str, Any]:
    """
    Validate image file signature (magic bytes).
    
    Args:
        image_bytes: Image data as bytes
        
    Returns:
        Dict with validation results including detected format
    """
    if len(image_bytes) < 8:
        return {
            "valid": False,
            "reason": "insufficient_data",
            "message": "Image data too short to validate"
        }
    
    # Check file signatures
    file_signature = image_bytes[:8]
    
    if file_signature.startswith(b'\xff\xd8\xff'):
        return {"valid": True, "format": "jpeg"}
    elif file_signature.startswith(b'\x89PNG\r\n\x1a\n'):
        return {"valid": True, "format": "png"}
    elif file_signature.startswith(b'GIF8'):
        return {"valid": True, "format": "gif"}
    elif file_signature.startswith(b'RIFF') and b'WEBP' in image_bytes[:12]:
        return {"valid": True, "format": "webp"}
    else:
        return {
            "valid": False,
            "reason": "invalid_signature",
            "message": "Invalid image file format. Only JPEG, PNG, GIF, and WebP are supported."
        }

def get_image_info(image_bytes: bytes) -> Dict[str, Any]:
    """
    Get basic information about an image.
    
    Args:
        image_bytes: Image bytes to analyze
        
    Returns:
        Dict with image information or error details
    """
    try:
        with io.BytesIO(image_bytes) as buffer:
            with Image.open(buffer) as img:
                return {
                    "valid": True,
                    "format": img.format,
                    "mode": img.mode,
                    "size": img.size,
                    "width": img.width,
                    "height": img.height,
                    "has_transparency": img.mode in ('RGBA', 'LA') or 'transparency' in img.info
                }
    except Exception as e:
        return {
            "valid": False,
            "error": str(e)
        }

def validate_image_comprehensive(
    image_bytes: bytes, 
    content_type: str = None,
    max_size_mb: float = 10.0,
    require_face: bool = False,
    rekognition_client = None
) -> Dict[str, Any]:
    """
    Comprehensive image validation combining multiple checks.
    
    Args:
        image_bytes: Image data as bytes
        content_type: Optional MIME content type
        max_size_mb: Maximum allowed size in megabytes
        require_face: Whether to require face detection
        rekognition_client: AWS Rekognition client for face detection
        
    Returns:
        Dict with comprehensive validation results
    """
    results = {
        "valid": True,
        "checks": {},
        "errors": []
    }
    
    # Size validation
    size_check = validate_image_size(image_bytes, max_size_mb)
    results["checks"]["size"] = size_check
    if not size_check["valid"]:
        results["valid"] = False
        results["errors"].append(size_check["message"])
    
    # Content type validation
    if content_type:
        content_type_valid = validate_image_content_type(content_type)
        results["checks"]["content_type"] = {"valid": content_type_valid}
        if not content_type_valid:
            results["valid"] = False
            results["errors"].append(f"Invalid content type: {content_type}")
    
    # Signature validation
    signature_check = validate_image_signature(image_bytes)
    results["checks"]["signature"] = signature_check
    if not signature_check["valid"]:
        results["valid"] = False
        results["errors"].append(signature_check["message"])
    
    # Format validation
    format_valid = validate_image_format(image_bytes)
    results["checks"]["format"] = {"valid": format_valid}
    if not format_valid:
        results["valid"] = False
        results["errors"].append("Invalid or corrupted image format")
    
    # Face validation (if required)
    if require_face and rekognition_client:
        face_check = validate_face_in_image(image_bytes, rekognition_client)
        results["checks"]["face"] = face_check
        if not face_check["valid"]:
            results["valid"] = False
            results["errors"].append(face_check["message"])
    
    # Image info
    if results["valid"]:
        info = get_image_info(image_bytes)
        results["image_info"] = info
    
    return results 