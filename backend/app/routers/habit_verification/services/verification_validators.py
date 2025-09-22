"""
DEPRECATED: This module is no longer used.
All habit verification is now handled by OpenAI Vision API.
Keeping for reference only.
"""

from typing import List
from utils.memory_optimization import disable_print

# Disable verbose printing for performance
print = disable_print()

def is_context_related(labels: list, keywords: list, context_name: str) -> bool:
    """Check if detected labels match given keywords using case-insensitive matching"""
    # Convert keywords to lowercase for case-insensitive comparison
    keywords_lower = [keyword.lower() for keyword in keywords]
    
    for label in labels:
        label_name = label['Name'].lower()
        
        # Check for exact matches first
        if label_name in keywords_lower:
            print(f"Found {context_name}-related label: {label['Name']} (confidence: {label['Confidence']:.2f}%)")
            return True
            
        # Check for partial matches (keyword contained in label)
        for keyword in keywords_lower:
            if keyword in label_name:
                print(f"Found {context_name}-related label: {label['Name']} (confidence: {label['Confidence']:.2f}%)")
                return True
                
    return False

def is_gym_related(labels: list) -> bool:
    """Check if detected labels are gym-related using official AWS Rekognition labels"""
    # Official AWS Rekognition gym/fitness labels from taxonomy v3.0 (verified)
    gym_labels = [
        'Gym', 'Gym Weights', 'Fitness', 'Working Out', 'Exercise Bike',
        'Treadmill', 'Battling Ropes', 'Bench Press', 'Bicep Curls',
        'Dead Lift', 'Elliptical Trainer', 'Handstand', 'Headstand',
        'Leg Press', 'Overhead Press', 'Plank Exercise', 'Pull Ups',
        'Push Ups', 'Rowing Machine', 'Running', 'Skipping Rope',
        'Squat', 'Stretch', 'Gymnast', 'Gymnastics'
    ]
    
    return is_context_related(labels, gym_labels, "gym")

def is_bathroom_related(labels: list) -> bool:
    """Check if detected labels are bathroom-related using official AWS Rekognition labels"""
    # Official AWS Rekognition bathroom labels from taxonomy v3.0 (100% verified)
    bathroom_labels = [
        'Bathroom', 'Toilet', 'Sink', 'Mirror', 'Shower', 'Bathtub',
        'Bath Towel', 'Bathing', 'Bathing Cap', 'Shower Curtain',
        'Shower Faucet', 'Sink Faucet', 'Toilet Paper', 'Double Sink'
    ]
    return is_context_related(labels, bathroom_labels, "bathroom")

def is_custom_habit_related(labels: list, custom_keywords: list, type_identifier: str) -> bool:
    """Check if detected labels match custom habit keywords"""
    if not custom_keywords:
        return False
    return is_context_related(labels, custom_keywords, type_identifier)

def is_yoga_related(labels: list) -> bool:
    """Check if detected labels are yoga-related using official AWS Rekognition labels"""
    # Official AWS Rekognition yoga labels from taxonomy v3.0 (verified)
    yoga_labels = [
        'Yoga', 'Bridge Yoga Pose', 'Downward Dog Yoga Pose', 'Lotus Yoga Pose',
        'Tree Yoga Pose', 'Triangle Yoga Pose', 'Warrior Yoga Pose',
        'Pilates', 'Stretch', 'Tai Chi', 'Handstand', 'Headstand'
    ]
    return is_context_related(labels, yoga_labels, "yoga")

def is_outdoors_related(labels: list) -> bool:
    """Check if detected labels are outdoors activity-related using official AWS Rekognition labels"""
    # Official AWS Rekognition outdoors/nature labels from taxonomy v3.0 (verified)
    outdoors_labels = [
        'Running', 'Cycling', 'Nature', 'Outdoors', 'Trail', 'Path',
        'Tree', 'Mountain', 'Hill', 'Park', 'Grass', 'Sky',
        'Cloud', 'Sun', 'Landscape', 'Scenery', 'Field',
        'Garden', 'Beach', 'Coast', 'Lake', 'River', 'Water', 'Sand',
        'Rock', 'Sunrise', 'Sunset', 'Weather',
        'Spring', 'Summer', 'Autumn', 'Winter',
        'Agriculture', 'Farm', 'Countryside', 'Valley', 'Desert',
        'Canyon', 'Cliff', 'Glacier', 'Volcano'
    ]
    return is_context_related(labels, outdoors_labels, "outdoors")

def is_cycling_related(labels: list) -> bool:
    """Check if detected labels are cycling-related using official AWS Rekognition labels"""
    # Official AWS Rekognition cycling labels from taxonomy v3.0 (verified)
    cycling_labels = [
        'Bicycle', 'Cycling', 'Mountain Bike', 'Exercise Bike', 
        'Helmet', 'Wheel', 'Tire', 'Spoke',
        'Pedal', 'Chain', 'Gear', 'Brake'
    ]
    return is_context_related(labels, cycling_labels, "cycling")

def is_cooking_related(labels: list) -> bool:
    """Check if detected labels are cooking-related using official AWS Rekognition labels"""
    # Official AWS Rekognition cooking/kitchen labels from taxonomy v3.0 (verified)
    cooking_labels = [
        'Kitchen', 'Cooking', 'Food', 'Meal', 'Stove', 'Oven',
        'Microwave', 'Refrigerator', 'Dishwasher', 'Sink',
        'Cabinet', 'Pantry', 'Cooker',
        'Cooking Pan', 'Cooking Pot', 'Cookware', 'Chopping Board',
        'Chopping Ingredients', 'Chopsticks', 'Baking', 'Blending Ingredients',
        'Boiling', 'Culinary', 'China Cabinet', 'Cooking Batter', 'Cooking Oil',
        'Bowl', 'Plate', 'Cup', 'Glass', 'Spoon', 'Fork', 'Knife',
        'Bread', 'Cheese', 'Meat', 'Vegetable', 'Fruit', 'Beverage'
    ]
    return is_context_related(labels, cooking_labels, "cooking")

def is_health_activity_related(labels: list) -> bool:
    """Check if detected labels are health/activity-related using official AWS Rekognition labels"""
    # Broad health and activity labels covering all health habit types
    # Combines gym, outdoors, cycling, sports, and general activity labels
    health_activity_labels = [
        # General fitness/health
        'Fitness', 'Working Out', 'Exercise', 'Sport', 'Sports',
        'Running', 'Walking', 'Jogging', 'Stretch', 'Training',
        
        # Gym equipment
        'Gym', 'Gym Weights', 'Exercise Bike', 'Treadmill', 'Weights',
        'Dumbbell', 'Barbell', 'Bench Press', 'Elliptical Trainer',
        
        # Outdoor activities
        'Cycling', 'Bicycle', 'Mountain Bike', 'Outdoors', 'Nature',
        'Trail', 'Path', 'Park', 'Tree', 'Sky',
        
        # Yoga/mindfulness
        'Yoga', 'Meditation', 'Pilates', 'Tai Chi',
        
        # Sleep/rest areas
        'Bed', 'Bedroom', 'Pillow', 'Blanket',
        
        # General activity indicators
        'Person', 'Human', 'Adult', 'Man', 'Woman',
        'Shoe', 'Sneaker', 'Athletic Shoe', 'Clothing', 'T-Shirt',
        'Watch', 'Wristwatch', 'Phone', 'Mobile Phone',
        
        # Body parts (for health activities)
        'Hand', 'Arm', 'Leg', 'Foot'
    ]
    return is_context_related(labels, health_activity_labels, "health activity") 