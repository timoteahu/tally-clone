import re
from typing import Optional
from utils.memory_optimization import disable_print

# Disable verbose printing for performance  
print = disable_print()

def validate_type_identifier(type_identifier: str) -> bool:
    """
    Validate custom habit type identifier format.
    
    Args:
        type_identifier: Type identifier string to validate
        
    Returns:
        True if valid format, False otherwise
    """
    if not type_identifier or not isinstance(type_identifier, str):
        return False
    
    # Must be 2-50 characters, alphanumeric and underscores only
    if not re.match(r'^[a-zA-Z0-9_]{2,50}$', type_identifier):
        return False
    
    # Cannot start with a number
    if type_identifier[0].isdigit():
        return False
    
    # Cannot be just underscores
    if type_identifier.replace('_', '') == '':
        return False
    
    return True

def validate_phone_number(phone_number: str) -> bool:
    """
    Validate phone number format.
    
    Args:
        phone_number: Phone number string to validate
        
    Returns:
        True if valid format, False otherwise
    """
    if not phone_number or not isinstance(phone_number, str):
        return False
    
    # Remove common formatting characters
    cleaned = re.sub(r'[\s\-\(\)\+]', '', phone_number)
    
    # Must be 10-15 digits
    if not re.match(r'^\d{10,15}$', cleaned):
        return False
    
    return True

def validate_email(email: str) -> bool:
    """
    Validate email address format.
    
    Args:
        email: Email address string to validate
        
    Returns:
        True if valid format, False otherwise
    """
    if not email or not isinstance(email, str):
        return False
    
    # Basic email regex pattern
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    
    if not re.match(pattern, email):
        return False
    
    # Check length constraints
    if len(email) > 254:  # RFC 5321 limit
        return False
    
    # Check local part length
    local_part = email.split('@')[0]
    if len(local_part) > 64:  # RFC 5321 limit
        return False
    
    return True

def validate_name(name: str) -> dict:
    """
    Validate user name with detailed feedback.
    
    Args:
        name: Name string to validate
        
    Returns:
        Dict with validation results and feedback
    """
    if not name or not isinstance(name, str):
        return {
            "valid": False,
            "error": "Name is required"
        }
    
    name = name.strip()
    
    if len(name) < 2:
        return {
            "valid": False,
            "error": "Name must be at least 2 characters"
        }
    
    if len(name) > 30:
        return {
            "valid": False,
            "error": "Name must be 30 characters or less"
        }
    
    # Validate characters (letters, numbers, spaces, hyphens, underscores)
    if not re.match(r'^[a-zA-Z0-9\s\-_]+$', name):
        return {
            "valid": False,
            "error": "Name can only contain letters, numbers, spaces, hyphens, and underscores"
        }
    
    return {
        "valid": True,
        "cleaned_name": name
    }

def validate_timezone(timezone_str: str) -> bool:
    """
    Validate timezone string.
    
    Args:
        timezone_str: Timezone string to validate
        
    Returns:
        True if valid timezone, False otherwise
    """
    if not timezone_str or not isinstance(timezone_str, str):
        return False
    
    try:
        import pytz
        pytz.timezone(timezone_str)
        return True
    except pytz.exceptions.UnknownTimeZoneError:
        return False

def validate_password_strength(password: str) -> dict:
    """
    Validate password strength with detailed feedback.
    
    Args:
        password: Password string to validate
        
    Returns:
        Dict with validation results and feedback
    """
    if not password or not isinstance(password, str):
        return {
            "valid": False,
            "score": 0,
            "errors": ["Password is required"]
        }
    
    errors = []
    score = 0
    
    # Length check
    if len(password) < 8:
        errors.append("Password must be at least 8 characters")
    else:
        score += 1
    
    # Uppercase letter check
    if not re.search(r'[A-Z]', password):
        errors.append("Password must contain at least one uppercase letter")
    else:
        score += 1
    
    # Lowercase letter check
    if not re.search(r'[a-z]', password):
        errors.append("Password must contain at least one lowercase letter")
    else:
        score += 1
    
    # Number check
    if not re.search(r'\d', password):
        errors.append("Password must contain at least one number")
    else:
        score += 1
    
    # Special character check
    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        errors.append("Password must contain at least one special character")
    else:
        score += 1
    
    # Length bonus
    if len(password) >= 12:
        score += 1
    
    return {
        "valid": len(errors) == 0,
        "score": score,
        "max_score": 6,
        "errors": errors,
        "strength": "weak" if score < 3 else "medium" if score < 5 else "strong"
    } 