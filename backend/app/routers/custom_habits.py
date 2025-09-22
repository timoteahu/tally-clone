"""
Custom Habit Types Router

This module handles API endpoints for creating and managing custom habit types.
Users can create custom habit types with descriptions, and the system generates
keywords using OpenAI for verification purposes.

Author: Joy Thief Team
"""

from fastapi import APIRouter, Depends, HTTPException, status
from models.schemas import (
    CustomHabitTypeCreate,
    CustomHabitTypeResponse,
    CustomHabitType,
    User,
    CustomHabitTypeUpdate
)
from config.database import get_supabase_client
from supabase import Client
from typing import List, Optional
from services.openai_service import openai_service
from routers.auth import get_current_user_lightweight
from uuid import UUID, uuid4
from datetime import datetime
import logging
import re

logger = logging.getLogger(__name__)
router = APIRouter()

def validate_type_identifier(type_identifier: str) -> bool:
    """
    Validate that the type identifier meets requirements:
    - No spaces (use underscores instead)
    - Only alphanumeric characters and underscores
    - Not empty
    - Max 50 characters
    """
    if not type_identifier:
        return False
    if len(type_identifier) > 50:
        return False
    if ' ' in type_identifier:
        return False
    # Allow only alphanumeric characters and underscores
    return type_identifier.replace('_', '').isalnum()

def sanitize_type_identifier(type_identifier: str) -> str:
    """
    Sanitize the type identifier by replacing spaces with underscores
    and ensuring it meets validation requirements.
    """
    # Replace spaces with underscores
    sanitized = type_identifier.replace(' ', '_')
    
    # Remove any characters that aren't alphanumeric or underscore
    sanitized = ''.join(c for c in sanitized if c.isalnum() or c == '_')
    
    # Remove leading/trailing underscores and collapse multiple underscores
    sanitized = '_'.join(part for part in sanitized.split('_') if part)
    
    # Ensure it's not empty and not too long
    if not sanitized:
        sanitized = "custom_habit"
    if len(sanitized) > 50:
        sanitized = sanitized[:50]
    
    return sanitized.lower()

async def check_type_identifier_uniqueness(user_id: str, type_identifier: str, exclude_id: Optional[str], supabase: Client) -> bool:
    """
    Check if the type identifier is unique for this user.
    Returns True if unique, False if already exists.
    """
    try:
        query = supabase.table("active_custom_habit_types").select("id").eq("user_id", user_id).eq("type_identifier", type_identifier)
        
        # If updating, exclude the current record
        if exclude_id:
            query = query.neq("id", exclude_id)
        
        result = query.execute()
        return len(result.data) == 0
    except Exception as e:
        logger.error(f"Error checking type identifier uniqueness: {e}")
        return False

@router.post("/", response_model=CustomHabitType)
async def create_custom_habit_type(
    custom_habit: CustomHabitTypeCreate,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Create a new custom habit type for the current user.
    Non-premium users are limited to 1 custom habit type.
    """
    try:
        user_id = str(current_user.id)
        
        # Check if user is premium
        if not current_user.ispremium:
            # Count existing custom habit types for non-premium users
            existing_count_result = supabase.table("active_custom_habit_types").select("id").eq("user_id", user_id).execute()
            existing_count = len(existing_count_result.data) if existing_count_result.data else 0
            
            if existing_count >= 1:
                raise HTTPException(
                    status_code=403,
                    detail="Non-premium users are limited to 1 custom habit type. Please upgrade to premium to create more custom habits."
                )
        
        # Sanitize and validate type identifier
        sanitized_identifier = sanitize_type_identifier(custom_habit.type_identifier)
        
        if not validate_type_identifier(sanitized_identifier):
            raise HTTPException(
                status_code=400, 
                detail="Invalid type identifier. Use only letters, numbers, and underscores. No spaces allowed."
            )
        
        # Check uniqueness
        is_unique = await check_type_identifier_uniqueness(user_id, sanitized_identifier, None, supabase)
        if not is_unique:
            raise HTTPException(
                status_code=400,
                detail=f"Custom habit type '{sanitized_identifier}' already exists for this user."
            )
        
        # ---------------------------------------------------------------------
        # 🧠  Generate AI Keywords (required by table constraint)
        # ---------------------------------------------------------------------
        try:
            keywords = openai_service.generate_keywords_for_habit(
                sanitized_identifier,
                custom_habit.description
            )
        except Exception as e:
            logger.error(f"Keyword generation failed: {e}")
            raise HTTPException(status_code=400, detail=str(e))

        # ---------------------------------------------------------------------
        # 📥  Insert into BASE table `custom_habit_types` (NOT the view)
        # ---------------------------------------------------------------------
        custom_habit_data = {
            "id": str(uuid4()),
            "user_id": user_id,
            "type_identifier": sanitized_identifier,
            "description": custom_habit.description,
            "keywords": keywords,
            "is_active": True,
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat()
        }

        result = supabase.table("custom_habit_types").insert(custom_habit_data).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to create custom habit type")
        
        created_habit_type = result.data[0]
        
        # Convert to response model
        return CustomHabitType(
            id=UUID(created_habit_type["id"]),
            user_id=UUID(created_habit_type["user_id"]),
            type_identifier=created_habit_type["type_identifier"],
            description=created_habit_type["description"],
            keywords=created_habit_type.get("keywords", []),
            is_active=created_habit_type.get("is_active", True),
            created_at=created_habit_type["created_at"],
            updated_at=created_habit_type["updated_at"]
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating custom habit type: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/", response_model=List[CustomHabitTypeResponse])
async def get_user_custom_habit_types(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Get all custom habit types for the current user.
    """
    try:
        user_id = str(current_user.id)
        
        result = supabase.table("active_custom_habit_types").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
        
        if not result.data:
            return []
        
        # Convert to response models (exclude internal fields)
        return [
            CustomHabitTypeResponse(
                id=UUID(ht["id"]),
                type_identifier=ht["type_identifier"],
                description=ht["description"],
                created_at=ht["created_at"],
                updated_at=ht["updated_at"]
            ) for ht in result.data
        ]
        
    except Exception as e:
        logger.error(f"Error getting custom habit types: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/{custom_habit_type_id}", response_model=CustomHabitTypeResponse)
async def get_custom_habit_type(
    custom_habit_type_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Get a specific custom habit type by ID.
    """
    try:
        user_id = str(current_user.id)
        
        result = supabase.table("active_custom_habit_types").select("*").eq("id", custom_habit_type_id).eq("user_id", user_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=404, detail="Custom habit type not found")
        
        habit_type_data = result.data[0]
        
        return CustomHabitTypeResponse(
            id=UUID(habit_type_data["id"]),
            type_identifier=habit_type_data["type_identifier"],
            description=habit_type_data["description"],
            created_at=habit_type_data["created_at"],
            updated_at=habit_type_data["updated_at"]
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting custom habit type: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.put("/{custom_habit_type_id}", response_model=CustomHabitType)
async def update_custom_habit_type(
    custom_habit_type_id: str,
    custom_habit_update: CustomHabitTypeUpdate,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Update a custom habit type. Only the description can be updated.
    The type_identifier cannot be changed once created.
    """
    try:
        user_id = str(current_user.id)
        
        # Check if the custom habit type exists and belongs to the user
        existing_result = supabase.table("active_custom_habit_types").select("*").eq("id", custom_habit_type_id).eq("user_id", user_id).execute()
        
        if not existing_result.data:
            raise HTTPException(status_code=404, detail="Custom habit type not found")
        
        # Prepare update data (only description can be updated)
        update_data = {
            "updated_at": datetime.utcnow().isoformat()
        }
        
        if custom_habit_update.description is not None:
            update_data["description"] = custom_habit_update.description
        
        # Update the custom habit type
        result = supabase.table("custom_habit_types").update(update_data).eq("id", custom_habit_type_id).eq("user_id", user_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to update custom habit type")
        
        updated_habit_type = result.data[0]
        
        return CustomHabitType(
            id=UUID(updated_habit_type["id"]),
            user_id=UUID(updated_habit_type["user_id"]),
            type_identifier=updated_habit_type["type_identifier"],
            description=updated_habit_type["description"],
            keywords=updated_habit_type.get("keywords", []),
            is_active=updated_habit_type.get("is_active", True),
            created_at=updated_habit_type["created_at"],
            updated_at=updated_habit_type["updated_at"]
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating custom habit type: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/{custom_habit_type_id}")
async def delete_custom_habit_type(
    custom_habit_type_id: str,
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Delete a custom habit type.
    This will also check if any active habits are using this custom type.
    """
    try:
        user_id = str(current_user.id)
        
        # Check if the custom habit type exists and belongs to the user
        existing_result = supabase.table("active_custom_habit_types").select("*").eq("id", custom_habit_type_id).eq("user_id", user_id).execute()
        
        if not existing_result.data:
            raise HTTPException(status_code=404, detail="Custom habit type not found")
        
        # Check if any active habits are using this custom habit type
        habits_using_type = supabase.table("habits").select("id, name").eq("custom_habit_type_id", custom_habit_type_id).eq("is_active", True).execute()
        
        if habits_using_type.data:
            habit_names = [habit["name"] for habit in habits_using_type.data]
            raise HTTPException(
                status_code=400,
                detail=f"Cannot delete custom habit type. It is currently used by active habits: {', '.join(habit_names)}"
            )
        
        # Soft delete by setting is_active to false in base table
        result = supabase.table("custom_habit_types").update({"is_active": False, "updated_at": datetime.utcnow().isoformat()}).eq("id", custom_habit_type_id).eq("user_id", user_id).execute()
        
        if not result.data:
            raise HTTPException(status_code=500, detail="Failed to delete custom habit type")
        
        return {"message": "Custom habit type deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting custom habit type: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/available-types/list")
async def get_available_habit_types(
    current_user: User = Depends(get_current_user_lightweight),
    supabase: Client = Depends(get_supabase_client)
):
    """
    Get all available habit types for the user (built-in + custom).
    
    This is useful for habit creation forms to show all available options.
    """
    try:
        # Built-in habit types
        built_in_types = [
            {
                "type": "gym",
                "display_name": "Gym",
                "description": "Gym workout verification with photo",
                "is_custom": False
            },
            {
                "type": "studying",
                "display_name": "Study",
                "description": "Study session with time tracking",
                "is_custom": False
            },
            {
                "type": "screenTime",
                "display_name": "Screen Time",
                "description": "Screen time limit monitoring",
                "is_custom": False
            },
            {
                "type": "alarm",
                "display_name": "Alarm",
                "description": "Early morning alarm verification",
                "is_custom": False
            }
        ]
        
        # Get user's custom habit types
        custom_types = supabase.table("active_custom_habit_types").select(
            "type_identifier, description"
        ).eq("user_id", str(current_user.id)).execute()
        
        custom_habit_types = [
            {
                "type": f"custom_{item['type_identifier']}",
                "display_name": item["type_identifier"].replace("_", " ").title(),
                "description": item["description"],
                "is_custom": True
            }
            for item in custom_types.data
        ]
        
        return {
            "built_in_types": built_in_types,
            "custom_types": custom_habit_types,
            "total_available": len(built_in_types) + len(custom_habit_types)
        }
        
    except Exception as e:
        logger.error(f"Error fetching available habit types: {e}")
        raise HTTPException(
            status_code=500,
            detail="Failed to fetch available habit types"
        ) 