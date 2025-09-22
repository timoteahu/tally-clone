"""
OpenAI Vision Service for Habit Verification

This service uses OpenAI's Vision API to verify habit completion from images
with flexible, context-aware prompts. Returns structured JSON metadata for
training data collection.

Author: Tally Team
"""

import openai
import os
import base64
import json
from typing import Dict, Any, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class OpenAIVisionService:
    """Service for habit verification using OpenAI Vision API"""
    
    def __init__(self):
        self.client = openai.AsyncOpenAI(api_key=os.getenv('OPENAI_API_KEY'))
        self.model = "gpt-4o"  # Supports vision and JSON mode
    
    async def verify_habit(
        self, 
        image_bytes: bytes, 
        habit_type: str,
        habit_name: str = None,
        custom_description: str = None
    ) -> Dict[str, Any]:
        """
        Verify if the image shows the habit being performed.
        Returns structured metadata with verification result.
        
        Args:
            image_bytes: The image to verify
            habit_type: Type of habit (gym, alarm, custom_*, etc.)
            habit_name: Optional habit name for context
            custom_description: Optional description for custom habits
            
        Returns:
            Dictionary with verification metadata including:
            - habit: habit type
            - valid: boolean verification result
            - openai_confidence: confidence score 0.0-1.0
            - reason: explanation of the decision
            - labels: detected elements in the image
            - timestamp: when verification occurred
        """
        # Get appropriate prompt based on habit type
        prompt = self._get_verification_prompt(habit_type, habit_name, custom_description)
        
        # Encode image to base64
        base64_image = base64.b64encode(image_bytes).decode('utf-8')
        
        try:
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": "You are a habit verification assistant. Always respond with valid JSON."
                    },
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{base64_image}"}}
                        ]
                    }
                ],
                response_format={"type": "json_object"},
                max_tokens=300
            )
            
            # Parse JSON response
            raw_response = response.choices[0].message.content
            logger.info(f"Raw OpenAI response: {raw_response}")
            result = json.loads(raw_response)
            
            # Create metadata structure
            metadata = {
                "habit": habit_type,
                "valid": result.get("valid", False),
                "openai_confidence": result.get("confidence", 0.0),
                "reason": result.get("reason", ""),
                "is_screen": result.get("is_screen", False),
                "timestamp": datetime.utcnow().isoformat()
            }
            
            return metadata
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse OpenAI response as JSON: {e}")
            # Fallback metadata
            return {
                "habit": habit_type,
                "valid": True,  # Default to verified to not block users
                "openai_confidence": 0.5,
                "reason": "JSON parsing error - defaulting to verified",
                "is_screen": False,
                "timestamp": datetime.utcnow().isoformat()
            }
        except Exception as e:
            logger.error(f"OpenAI Vision API error: {e}")
            # Fallback metadata
            return {
                "habit": habit_type,
                "valid": True,  # Default to verified to not block users
                "openai_confidence": 0.5,
                "reason": "Verification service temporarily unavailable",
                "is_screen": False,
                "timestamp": datetime.utcnow().isoformat()
            }
    
    def _get_verification_prompt(self, habit_type: str, habit_name: str = None, custom_description: str = None) -> str:
        """Get appropriate prompt for habit type with structured JSON output"""
        
        base_json_format = """
        Return a JSON object with this exact structure:
        {
            "valid": true/false,
            "confidence": 0.0-1.0,
            "reason": "brief explanation",
            "is_screen": true/false
        }
        
        IMPORTANT: Set "is_screen" to true if this appears to be fake or not a real-world photo:
        - Photos of computer/phone/tablet screens showing images
        - Photos of TVs, monitors, or any digital displays
        - Screenshots that were photographed from a screen
        - Photos from Google Images, stock photos, or websites displayed on a screen
        - Images that show browser UI, window frames, or screen bezels
        - Photos with visible pixels, screen refresh lines, or moiré patterns
        - Images with unnatural lighting from a screen backlight
        - Any photo that appears to be a picture of another picture on a digital device
        
        Look for telltale signs like:
        - Screen glare or reflections
        - Visible pixels or scan lines
        - Browser tabs, URL bars, or UI elements
        - Unnatural color temperature from screen lighting
        - Image quality degradation from photographing a screen
        """
        
        # Only photo-verifiable habits
        prompts = {
            "gym": f"""
                Is this a REAL PHOTO (not from a screen) related to fitness, gym, or exercise in ANY way? 
                This includes: gym environments, any exercise equipment, locker rooms, 
                mirror selfies at the gym, workout clothes, protein shakes, gym parking lots,
                or ANY fitness-related content. Be very lenient - if there's any connection
                to fitness or gym, mark as valid.
                
                CRITICAL: Verify this is a real-world photo, not a picture of a screen showing a gym image.
                
                {base_json_format}
            """,
            
            "alarm": f"""
                Does this REAL PHOTO show someone has woken up and is out of bed?
                This includes: bathrooms, morning routines, getting ready, brushing teeth,
                making breakfast, morning coffee, or ANY indication they're awake and starting
                their day. Be very lenient.
                
                CRITICAL: Verify this is a real-world photo, not a screen showing a bathroom image.
                
                {base_json_format}
            """,
            
            "yoga": f"""
                Is this a REAL PHOTO related to yoga, meditation, or mindfulness practice?
                This includes: yoga mats, yoga poses, meditation spaces, peaceful environments,
                stretching, or any yoga-related content. Be lenient.
                
                CRITICAL: Verify this is a real-world photo, not a screen showing yoga images.
                
                {base_json_format}
            """,
            
            "outdoors": f"""
                Does this REAL PHOTO show outdoor activity or being outside?
                This includes: nature, parks, streets, running trails, hiking, walking,
                or any outdoor environment. Be very lenient.
                
                CRITICAL: Verify this is actually taken outdoors, not a screen showing outdoor images.
                
                {base_json_format}
            """,
            
            "cycling": f"""
                Is this a REAL PHOTO related to cycling or biking?
                This includes: bicycles, bike paths, cycling gear, helmets, bike storage,
                or any cycling-related content. Be lenient.
                
                CRITICAL: Verify this is a real-world photo, not a screen showing cycling images.
                
                {base_json_format}
            """,
            
            "cooking": f"""
                Is this a REAL PHOTO related to cooking or food preparation?
                This includes: kitchens, ingredients, cooking process, finished meals,
                recipes, or any cooking-related content. Be lenient.
                
                CRITICAL: Verify this is a real kitchen/food photo, not a screen showing recipes or food images.
                
                {base_json_format}
            """,
            
        }
        
        # Handle custom habits
        if habit_type.startswith("custom_") or habit_type not in prompts:
            name = habit_name or habit_type
            desc = custom_description or "the described activity"
            return f"""
                Is this a REAL PHOTO related to {name}: {desc}?
                Be lenient and verify if the image reasonably shows the person
                is doing this activity or something related to it.
                
                CRITICAL: Verify this is a real-world photo, not a screen showing related images.
                
                {base_json_format}
            """
        
        # Handle health habits - very lenient
        if habit_type.startswith("health_"):
            return f"""
                Is this a REAL PHOTO related to health, fitness, or wellness activities?
                This includes ANY physical activity, exercise, sports, or health-related content.
                Be very lenient.
                
                CRITICAL: Verify this is a real-world photo, not a screen showing health/fitness images.
                
                {base_json_format}
            """
        
        return prompts.get(habit_type, prompts["gym"])  # Default to gym prompt

# Global service instance
openai_vision_service = OpenAIVisionService()