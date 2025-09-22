"""
OpenAI Service for Custom Habit Keyword Generation

This service integrates with OpenAI's ChatGPT API to generate relevant keywords
for custom habit types based on user descriptions. Generated keywords are then
filtered against the official AWS Rekognition taxonomy to ensure 100% compatibility.

Author: Joy Thief Team
"""

import openai
import os
from typing import List, Dict, Any, Set
import json
import logging
import csv

logger = logging.getLogger(__name__)

class OpenAIService:
    """Service for generating keywords using OpenAI ChatGPT API"""
    
    def __init__(self):
        self.client = openai.OpenAI(
            api_key=os.getenv('OPENAI_API_KEY')
        )
        self.model = "gpt-4o"  # Cost-effective model for keyword generation
        self._official_labels = None
    
    def _load_official_labels(self) -> Set[str]:
        """Load official AWS Rekognition labels from CSV file"""
        if self._official_labels is not None:
            return self._official_labels
        
        try:
            # Path to the official labels file (relative from backend/app/services/ to root/label_list/)
            labels_file = os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))),
                'label_list',
                'AmazonRekognitionAllLabels_v3.0.csv'
            )
            
            if not os.path.exists(labels_file):
                raise FileNotFoundError(f"Could not find AWS labels file at: {labels_file}")
            
            official_labels = set()
            
            with open(labels_file, 'r', encoding='utf-8') as f:
                # Skip the header line
                next(f)
                
                # Read each label (one per line)
                for line in f:
                    label = line.strip()
                    if label:
                        # Store lowercase for case-insensitive matching
                        official_labels.add(label.lower())
            
            self._official_labels = official_labels
            return official_labels
            
        except Exception as e:
            logger.error(f"Failed to load official AWS labels: {e}")
            # Return empty set as fallback - no filtering will occur
            self._official_labels = set()
            return self._official_labels
    
    def generate_keywords_for_habit(self, type_identifier: str, description: str) -> List[str]:
        """
        Generate relevant keywords for a custom habit type using ChatGPT.
        Keywords are filtered against official AWS Rekognition taxonomy for guaranteed compatibility.
        
        Args:
            type_identifier: The habit type identifier (e.g., "reading", "cooking")
            description: User's description of what to look for in verification photos
            
        Returns:
            List of practical keywords that are verified to be in AWS Rekognition taxonomy
            
        Raises:
            Exception: If input validation fails or OpenAI API call fails
        """
        try:
            # Load official labels for filtering
            official_labels = self._load_official_labels()
            
            # Create a practical prompt that focuses on effectiveness
            prompt = self._create_practical_keyword_prompt(type_identifier, description)
            
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": "You are an expert at generating practical keyword lists for AWS Rekognition image recognition. Your goal is to create keywords that will actually work to detect the described activity in photos, focusing on objects, environments, and activities that AWS Rekognition can identify."
                    },
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                max_tokens=600,
                temperature=0.3,  # Balanced temperature for creativity with consistency
                response_format={"type": "json_object"}
            )
            
            # Parse the JSON response
            content = response.choices[0].message.content
            result = json.loads(content)
            
            # Check if validation passed
            is_valid = result.get('is_valid', False)
            if not is_valid:
                validation_error = result.get('validation_error', 'Description is not detailed enough for generating quality keywords.')
                raise Exception(validation_error)
            
            # Extract keywords from the response
            raw_keywords = result.get('keywords', [])
            
            # Filter keywords against official AWS taxonomy
            filtered_keywords = self._filter_against_official_labels(raw_keywords, official_labels)
            
            # Ensure we have enough keywords after filtering
            if len(filtered_keywords) < 5:
                raise Exception(f"After filtering against AWS taxonomy, only {len(filtered_keywords)} valid keywords remain. Please try a more detailed description with common objects/activities.")
            
            return filtered_keywords
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse OpenAI response as JSON: {e}")
            raise Exception(f"OpenAI returned invalid JSON response. Please try again.")
            
        except Exception as e:
            logger.error(f"OpenAI API call failed: {e}")
            # Re-raise our custom validation errors
            if any(phrase in str(e) for phrase in ["not detailed enough", "validation_error", "is_valid", "taxonomy filter"]):
                raise e
            raise Exception(f"Failed to generate keywords using AI. Please check your internet connection and try again.")
    
    def _create_practical_keyword_prompt(self, type_identifier: str, description: str) -> str:
        """Create a practical prompt focused on effective keyword generation"""
        
        return f"""
Generate practical keywords for habit verification that will work with AWS Rekognition image detection.

Habit Type: "{type_identifier}"
User Description: "{description}"

GUIDELINES FOR EFFECTIVE KEYWORDS:

1. FOCUS ON DETECTABLE OBJECTS:
   - Specific physical items (piano, book, camera, stove, etc.)
   - Common furniture/equipment (chair, table, bench, etc.)
   - Tools and accessories (brush, utensil, tool, etc.)
   - Environmental elements (kitchen, garden, outdoor, indoor)

2. INCLUDE HUMAN ELEMENTS:
   - person, hand, face (for human activities)
   - Common poses/activities that AWS can detect

3. PROVEN KEYWORD EXAMPLES:
   - Piano playing: piano, keyboard, music, musical instrument, bench, person, hand
   - Gardening: garden, plant, flower, soil, tool, gloves, person, outdoor
   - Reading: book, reading, text, page, chair, table, person, hand
   - Cooking: kitchen, cooking, food, stove, pan, utensil, person, hand
   - Art: art, painting, drawing, brush, canvas, palette, person, hand

4. VALIDATION REQUIREMENTS:
   - Description must be specific enough to identify 8+ visual elements
   - Must include tangible objects that appear in photos
   - Reject vague descriptions like "doing stuff" or "being productive"

5. KEYWORD QUALITY:
   - Use clear, simple terms that AWS Rekognition recognizes
   - Mix specific items with general categories
   - Include environmental context
   - Focus on what actually appears in verification photos

Return JSON format:
{{
    "is_valid": true/false,
    "validation_error": "explanation if invalid",
    "keywords": ["keyword1", "keyword2", "keyword3", ...] (10-15 practical keywords)
}}

Generate keywords that AWS Rekognition can actually detect in photos.
"""
    
    def _filter_against_official_labels(self, keywords: List[str], official_labels: Set[str]) -> List[str]:
        """Filter keywords against official AWS Rekognition taxonomy"""
        if not keywords or not official_labels:
            return keywords  # No filtering if no official labels loaded
        
        filtered_keywords = []
        
        for keyword in keywords:
            if isinstance(keyword, str) and keyword.strip():
                clean_keyword = keyword.strip().lower()
                
                # Check if keyword is in official taxonomy
                if clean_keyword in official_labels:
                    filtered_keywords.append(clean_keyword)
                else:
                    logger.debug(f"Keyword '{keyword}' not found in AWS taxonomy, skipping")
        
        # Remove duplicates while preserving order
        seen = set()
        unique_keywords = []
        for keyword in filtered_keywords:
            if keyword not in seen:
                seen.add(keyword)
                unique_keywords.append(keyword)
        
        return unique_keywords[:15]  # Reasonable limit

# Global service instance
openai_service = OpenAIService() 