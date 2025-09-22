from pydantic import BaseModel, Field, EmailStr, constr
from typing import List, Optional, Dict, Any
from enum import Enum
from datetime import date, datetime
from uuid import UUID
from pydantic.json import timedelta_isoformat
from pydantic import field_validator, model_validator

class UserBase(BaseModel):
    phone_number: constr(pattern=r'^\+?1?\d{9,15}$')
    name: str
    timezone: str = "UTC"

class UserCreate(UserBase):
    verification_code: str = Field(..., min_length=6, max_length=6)
    inviter_id: Optional[int] = None

    class Config:
        json_encoders = {
            UUID: str
        }

class UserLogin(BaseModel):
    phone_number: constr(pattern=r'^\+?1?\d{9,15}$')
    verification_code: str = Field(..., min_length=6, max_length=6)

class User(UserBase):
    id: UUID
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    profile_photo_url: Optional[str] = None
    profile_photo_filename: Optional[str] = None
    # Cached avatar system fields
    avatar_version: Optional[int] = None
    avatar_url_80: Optional[str] = None
    avatar_url_200: Optional[str] = None
    avatar_url_original: Optional[str] = None
    onboarding_state: int = 0
    ispremium: bool = False
    last_active: Optional[datetime] = None
    # OPTIMIZATION: Pre-computed zero-penalty habit count (avoids calculation)
    zero_penalty_habit_count: Optional[int] = Field(0, description="Cached count of zero-penalty picture habits")

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class HabitType(str, Enum):
    GYM = "gym"
    STUDYING = "studying"
    SCREEN_TIME = "screenTime"
    ALARM = "alarm"
    YOGA = "yoga"
    OUTDOORS = "outdoors"
    CYCLING = "cycling"
    COOKING = "cooking"
    LEAGUE_OF_LEGENDS = "league_of_legends"
    VALORANT = "valorant"
    # Apple Health habit types
    HEALTH_STEPS = "health_steps"
    HEALTH_WALKING_RUNNING_DISTANCE = "health_walking_running_distance"
    HEALTH_FLIGHTS_CLIMBED = "health_flights_climbed"
    HEALTH_EXERCISE_MINUTES = "health_exercise_minutes"
    HEALTH_CYCLING_DISTANCE = "health_cycling_distance"
    HEALTH_SLEEP_HOURS = "health_sleep_hours"
    HEALTH_WATER_INTAKE = "health_water_intake"
    HEALTH_HEART_RATE = "health_heart_rate"
    HEALTH_CALORIES_BURNED = "health_calories_burned"
    HEALTH_MINDFUL_MINUTES = "health_mindful_minutes"

class HabitBase(BaseModel):
    name: str
    recipient_id: Optional[UUID] = None
    habit_type: str
    # Schedule type and related fields
    habit_schedule_type: str = Field("daily", description="Schedule type: 'daily', 'weekly', or 'one_time'")
    # For daily habits
    weekdays: Optional[List[int]] = Field(None, description="List of weekday numbers (0-6, Sunday=0) for daily habits")
    # For weekly habits
    weekly_target: Optional[int] = Field(None, description="Number of times per week for weekly habits")
    week_start_day: Optional[int] = Field(0, description="Week start day (0=Sunday, 1=Monday)")
    # GitHub commits specific
    commit_target: Optional[int] = Field(None, description="Daily commit goal for GitHub commit habits")
    
    # Gaming habits specific
    daily_limit_hours: Optional[float] = Field(None, description="Daily gaming time limit in hours")
    hourly_penalty_rate: Optional[float] = Field(None, description="Penalty amount per hour over limit")
    games_tracked: Optional[List[str]] = Field(None, description="List of games to track ['lol', 'valorant']")

    # Apple Health habits specific
    health_target_value: Optional[float] = Field(None, description="Target value for health habits (e.g., 10000 steps, 8 hours sleep)")
    health_target_unit: Optional[str] = Field(None, description="Unit for the health target (steps, miles, hours, minutes, etc.)")
    health_data_type: Optional[str] = Field(None, description="HealthKit data type identifier for API integration")

    # Common fields
    penalty_amount: Optional[float] = Field(None, description="Penalty amount (can be 0 for zero-credit habits)")
    is_zero_penalty: Optional[bool] = Field(False, description="Whether this is a zero-penalty picture habit (max 3 per user)")
    alarm_time: Optional[str] = Field(None, description="Time in HH:mm format for alarm habits")
    custom_habit_type_id: Optional[UUID] = Field(None, description="Reference to custom habit type for custom habits")
    private: bool = False
    streak: Optional[int] = 0  # Add streak field with default value 0
    auto_pay_enabled: bool = True

    @field_validator('habit_schedule_type')
    @classmethod
    def validate_schedule_type(cls, v):
        if v not in ['daily', 'weekly', 'one_time']:
            raise ValueError('habit_schedule_type must be either "daily", "weekly", or "one_time"')
        return v

    @field_validator('week_start_day')
    @classmethod
    def validate_week_start_day(cls, v):
        if v is not None and (v < 0 or v > 6):
            raise ValueError('week_start_day must be between 0 (Sunday) and 6 (Saturday)')
        return v

    @model_validator(mode='after')
    def validate_habit_schedule_data(self):
        if self.habit_schedule_type == 'daily':
            if not self.weekdays or len(self.weekdays) == 0:
                raise ValueError('Daily habits must specify weekdays')
            if self.weekly_target is not None:
                raise ValueError('Daily habits cannot have weekly_target')
        elif self.habit_schedule_type == 'weekly':
            # Debug logging for weekly habit validation
            import logging
            logger = logging.getLogger(__name__)
            logger.info(f"Validating weekly habit: weekdays={self.weekdays}, weekly_target={self.weekly_target}, habit_type={self.habit_type}, commit_target={self.commit_target}")
            
            if self.weekdays:
                raise ValueError('Weekly habits cannot specify weekdays')
            
            # Special handling for GitHub and LeetCode weekly habits
            if self.habit_type in ['github_commits', 'leetcode']:
                # For GitHub/LeetCode weekly habits, prefer commit_target if provided, otherwise use weekly_target
                if not self.commit_target and self.weekly_target is not None:
                    # Convert weekly_target to commit_target for backward compatibility
                    logger.info(f"Converting weekly_target {self.weekly_target} to commit_target for {self.habit_type} habit")
                    object.__setattr__(self, 'commit_target', self.weekly_target)
                
                # Now validate commit_target (the actual weekly goal)
                if not self.commit_target or self.commit_target < 1:
                    raise ValueError(f'Weekly {self.habit_type} habits must have commit_target (weekly goal) greater than 0')
                if self.commit_target > 100:
                    raise ValueError(f'Weekly {self.habit_type} habits must have commit_target between 1 and 100')
                
                # Set weekly_target to 1 for weekly GitHub/LeetCode habits (checked once per week)
                logger.info(f"Setting weekly_target to 1 for {self.habit_type} weekly habit (was {self.weekly_target})")
                object.__setattr__(self, 'weekly_target', 1)
            else:
                # For regular weekly habits, use weekly_target as the goal
                if not self.weekly_target or self.weekly_target < 1:
                    raise ValueError('Weekly habits must have weekly_target greater than 0')
                # Regular weekly habits are limited to 1-7 times per week
                if self.weekly_target > 7:
                    raise ValueError('Regular weekly habits must have weekly_target between 1 and 7')
                # Regular weekly habits don't use commit_target
                if self.commit_target is not None:
                    logger.info(f"Clearing commit_target for regular weekly habit (was {self.commit_target})")
                    object.__setattr__(self, 'commit_target', None)
                    
        elif self.habit_schedule_type == 'one_time':
            if self.weekdays:
                raise ValueError('One-time habits cannot specify weekdays')
            if self.weekly_target is not None:
                raise ValueError('One-time habits cannot have weekly_target')
        
        # Validate gaming habits
        if self.habit_type in ['league_of_legends', 'valorant']:
            if not self.daily_limit_hours or self.daily_limit_hours <= 0:
                raise ValueError('Gaming habits must specify daily_limit_hours greater than 0')
            if not self.hourly_penalty_rate or self.hourly_penalty_rate <= 0:
                raise ValueError('Gaming habits must specify hourly_penalty_rate greater than 0')
            if not self.games_tracked or len(self.games_tracked) == 0:
                raise ValueError('Gaming habits must specify at least one game in games_tracked')
            if self.habit_type == 'league_of_legends' and 'lol' not in self.games_tracked:
                raise ValueError('League of Legends habit must include "lol" in games_tracked')
            if self.habit_type == 'valorant' and 'valorant' not in self.games_tracked:
                raise ValueError('Valorant habit must include "valorant" in games_tracked')
        
        # Validate health habits
        health_habit_types = [
            'health_steps', 'health_walking_running_distance', 'health_flights_climbed',
            'health_exercise_minutes', 'health_cycling_distance', 'health_sleep_hours',
            'health_water_intake', 'health_heart_rate', 'health_calories_burned', 'health_mindful_minutes'
        ]
        if self.habit_type in health_habit_types:
            if not self.health_target_value or self.health_target_value <= 0:
                raise ValueError('Health habits must specify health_target_value greater than 0')
            if not self.health_target_unit:
                raise ValueError('Health habits must specify health_target_unit')
            if not self.health_data_type:
                raise ValueError('Health habits must specify health_data_type')
        
        return self

class HabitCreate(HabitBase):
    user_id: UUID
    # Optional fields for specific habit features
    study_duration_minutes: Optional[int] = None
    screen_time_limit_minutes: Optional[int] = None
    restricted_apps: Optional[List[str]] = None

    class Config:
        json_encoders = {
            UUID: str
        }

class Habit(HabitBase):
    id: UUID
    user_id: UUID
    created_at: datetime
    updated_at: datetime
    study_duration_minutes: Optional[int] = None
    screen_time_limit_minutes: Optional[int] = None
    restricted_apps: Optional[List[str]] = None
    streak: Optional[int] = 0  # Include streak in the main Habit model
    completed_at: Optional[datetime] = None

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class HabitUpdate(BaseModel):
    name: Optional[str] = None
    recipient_id: Optional[str] = None
    habit_type: Optional[str] = None
    habit_schedule_type: Optional[str] = None
    weekdays: Optional[List[int]] = None
    weekly_target: Optional[int] = None
    week_start_day: Optional[int] = None
    penalty_amount: Optional[float] = None
    study_duration_minutes: Optional[int] = None
    screen_time_limit_minutes: Optional[int] = None
    restricted_apps: Optional[List[str]] = None
    alarm_time: Optional[str] = None
    custom_habit_type_id: Optional[UUID] = None
    private: Optional[bool] = None
    # Health habit fields
    health_target_value: Optional[float] = None
    health_target_unit: Optional[str] = None
    health_data_type: Optional[str] = None

    class Config:
        json_encoders = {
            UUID: str
        }

class HabitLogBase(BaseModel):
    image_url: str
    submission_date: date

class HabitLogCreate(HabitLogBase):
    habit_id: int

class HabitLog(HabitLogBase):
    id: int
    habit_id: int
    user_id: int
    is_verified: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class PenaltyBase(BaseModel):
    amount: float
    penalty_date: date

class PenaltyCreate(PenaltyBase):
    habit_id: int

class Penalty(PenaltyBase):
    id: int
    habit_id: int
    user_id: int
    recipient_id: Optional[int] = None
    is_paid: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class InviteBase(BaseModel):
    """
    DEPRECATED: Invite models are maintained for backward compatibility only.
    New invites are handled via frontend Branch.io integration.
    """
    inviter_user_id: UUID
    invite_link: str
    habit_id: Optional[UUID] = None
    invited_user_id: Optional[UUID] = None
    invite_status: str = "pending"
    expires_at: Optional[datetime] = None

class InviteCreate(InviteBase):
    """DEPRECATED: Use frontend Branch.io integration for new invites."""
    pass

class Invite(InviteBase):
    """DEPRECATED: Legacy invite model for backward compatibility."""
    id: UUID
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class FriendBase(BaseModel):
    user_id: UUID = Field(..., description="UUID of the user")
    friend_id: UUID = Field(..., description="UUID of the friend")

    class Config:
        json_encoders = {
            UUID: str
        }

class FriendCreate(FriendBase):
    pass

class Friend(BaseModel):
    id: UUID
    user_id: UUID
    friend_id: UUID
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

# Friend Request Models
class FriendRequestStatus(str, Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"

class FriendRequestBase(BaseModel):
    receiver_id: UUID = Field(..., description="UUID of the user receiving the request")
    message: Optional[str] = Field(None, description="Optional message with the friend request")

class FriendRequestCreate(FriendRequestBase):
    pass

class FriendRequest(BaseModel):
    id: UUID
    sender_id: UUID
    receiver_id: UUID
    status: FriendRequestStatus = Field(..., description="Request status: pending or accepted")
    message: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class FriendRequestWithDetails(FriendRequest):
    """Friend request with sender and receiver user details"""
    sender_name: str
    sender_phone: str
    receiver_name: str
    receiver_phone: str

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class FriendRequestCooldown(BaseModel):
    id: UUID
    sender_id: UUID
    receiver_id: UUID
    declined_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

# Response models for friend request actions
class FriendRequestAcceptResponse(BaseModel):
    message: str
    friendship_id: UUID
    request_id: UUID

class FriendRequestDeclineResponse(BaseModel):
    message: str
    request_id: UUID

class FriendRequestCancelResponse(BaseModel):
    message: str
    request_id: UUID

# Branch invite acceptance response
class BranchInviteAcceptResponse(BaseModel):
    message: str
    friendship_created: bool
    inviter_id: str
    inviter_name: str

class ScreenTimeStatus(BaseModel):
    total_time_minutes: int
    limit_minutes: int
    restricted_apps: List[str]
    status: str  # "under_limit", "near_limit", "over_limit"

class ScreenTimeUpdate(BaseModel):
    total_time_minutes: int
    limit_minutes: int
    status: str  # "within_limit" or "over_limit"
    restricted_apps: List[str]

class Comment(BaseModel):
    id: UUID
    content: str
    created_at: datetime
    user_id: UUID
    user_name: str
    # Avatar fields
    user_avatar_url_80: Optional[str] = None
    user_avatar_url_200: Optional[str] = None
    user_avatar_url_original: Optional[str] = None
    user_avatar_version: Optional[int] = None
    is_edited: bool
    parent_comment: Optional[dict] = None  # Contains parent comment info if this is a reply

    class Config:
        json_encoders = {
            UUID: str,
            datetime: lambda v: v.astimezone(__import__('datetime').timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ') if v else None
        }

class HabitVerificationBase(BaseModel):
    habit_id: UUID
    user_id: UUID
    verification_type: str
    verified_at: datetime
    status: str
    verification_result: Optional[bool] = None

class HabitVerificationCreate(HabitVerificationBase):
    image_filename: Optional[str] = None

class HabitVerification(HabitVerificationBase):
    id: UUID
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    image_filename: Optional[str] = None  # Filename for image stored in bucket

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class RecipientAnalytics(BaseModel):
    id: UUID
    recipient_id: UUID
    habit_id: UUID
    habit_owner_id: UUID
    
    # Financial metrics
    total_earned: float
    pending_earnings: float
    
    # Performance metrics
    total_completions: int
    total_failures: int
    total_required_days: int
    success_rate: float
    
    # Tracking dates
    first_recipient_date: date
    last_verification_date: Optional[date] = None
    last_penalty_date: Optional[date] = None
    
    # Metadata
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class WeeklyProgress(BaseModel):
    """Weekly progress data for habits"""
    current_completions: int
    target_completions: int
    week_start_date: date
    
    class Config:
        from_attributes = True

class HabitWithAnalytics(BaseModel):
    """Habit data combined with recipient analytics for the recipient dashboard"""
    # Habit fields
    id: UUID
    name: str
    recipient_id: Optional[UUID] = None
    habit_type: str
    weekdays: Optional[List[int]] = None
    penalty_amount: float
    hourly_penalty_rate: Optional[float] = None
    daily_limit_hours: Optional[float] = None
    games_tracked: Optional[List[str]] = None
    user_id: UUID
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    study_duration_minutes: Optional[int] = None
    screen_time_limit_minutes: Optional[int] = None
    restricted_apps: Optional[List[str]] = None
    alarm_time: Optional[str] = None
    private: Optional[bool] = None
    custom_habit_type_id: Optional[UUID] = None
    habit_schedule_type: Optional[str] = None
    weekly_target: Optional[int] = None
    week_start_day: Optional[int] = None
    streak: Optional[int] = None
    commit_target: Optional[int] = None
    is_active: Optional[bool] = None
    completed_at: Optional[datetime] = None
    
    # Analytics data
    analytics: Optional[RecipientAnalytics] = None
    
    # Owner information
    owner_name: Optional[str] = None
    owner_phone: Optional[str] = None
    owner_last_active: Optional[datetime] = None
    
    # Weekly progress (for weekly habits)
    weekly_progress: Optional[WeeklyProgress] = None

    class Config:
        from_attributes = True

class PostBase(BaseModel):
    caption: str | None
    is_private: bool
    image_filename: str | None  # Existing field for content image
    selfie_image_filename: str | None  # New field for selfie image

class PostCreate(PostBase):
    user_id: UUID
    habit_verification_id: UUID | None = None

class Post(PostBase):
    id: UUID
    user_id: UUID
    habit_verification_id: UUID | None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class FeedPost(BaseModel):
    post_id: UUID
    habit_id: UUID | None  # Add the missing habit_id field
    caption: str | None
    created_at: datetime
    is_private: bool
    image_url: str | None  # Generated on-demand from image_filename (backward compatibility)
    selfie_image_url: str | None  # Generated on-demand from selfie_image_filename
    content_image_url: str | None  # Generated on-demand from image_filename (for consistency)
    user_id: UUID
    habit_name: str | None
    habit_type: str | None
    penalty_amount: float | None  # ✅ Add penalty_amount field
    user_name: str
    # Avatar fields
    user_avatar_url_80: Optional[str] = None
    user_avatar_url_200: Optional[str] = None
    user_avatar_url_original: Optional[str] = None
    user_avatar_version: Optional[int] = None
    streak: int | None
    comments: list[Comment]

    class Config:
        json_encoders = {
            UUID: str
        }

# MARK: - Custom Habit Type Schemas

class CustomHabitTypeBase(BaseModel):
    type_identifier: str
    description: str

class CustomHabitTypeCreate(CustomHabitTypeBase):
    pass

class CustomHabitTypeUpdate(BaseModel):
    """Update model for custom habit types - only description can be updated"""
    description: Optional[str] = None

class CustomHabitType(CustomHabitTypeBase):
    id: UUID
    user_id: UUID
    keywords: List[str]
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str,
            datetime: lambda v: v.isoformat()
        }

class CustomHabitTypeResponse(BaseModel):
    """User-facing response that excludes internal keywords"""
    id: UUID
    type_identifier: str
    description: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str,
            datetime: lambda v: v.isoformat()
        }

# Weekly Habit Progress schemas
class WeeklyHabitProgressBase(BaseModel):
    habit_id: UUID
    user_id: UUID
    week_start_date: date
    current_completions: int = 0
    target_completions: int
    is_week_complete: bool = False

class WeeklyHabitProgressCreate(WeeklyHabitProgressBase):
    pass

class WeeklyHabitProgress(WeeklyHabitProgressBase):
    id: UUID
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

# Friend Recommendation Models
class MutualFriend(BaseModel):
    id: UUID
    name: str

class FriendRecommendation(BaseModel):
    recommended_user_id: UUID
    user_name: str
    mutual_friends_count: int
    mutual_friends_preview: List[MutualFriend]
    recommendation_reason: str
    total_score: float

    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class FriendRecommendationResponse(BaseModel):
    recommendations: List[FriendRecommendation]
    
    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

# Gaming habit models
class RiotAccountCreate(BaseModel):
    riot_id: str = Field(..., description="Riot ID (username)")
    tagline: str = Field(..., description="Tagline (e.g., #NA1)")
    region: str = Field(..., description="Region (e.g., 'americas', 'europe', 'asia')")
    game_name: str = Field(..., description="Game name: 'lol' or 'valorant'")

class RiotAccount(BaseModel):
    id: UUID
    user_id: UUID
    riot_id: str
    tagline: str
    puuid: Optional[str] = None
    region: str
    game_name: str
    last_sync_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class GamingSession(BaseModel):
    id: UUID
    habit_id: UUID
    match_id: str
    game_start_time: datetime
    game_end_time: datetime
    duration_minutes: int
    game_mode: Optional[str] = None
    created_at: datetime
    
    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }

class GamingVerificationResult(BaseModel):
    total_minutes_yesterday: int
    daily_limit_hours: float
    overage_hours: float
    penalty_amount: float
    matches_counted: int
    sessions: List[GamingSession]

# Support Message models (simplified)
class SupportMessageCreate(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)

class SupportMessage(BaseModel):
    id: UUID
    user_id: UUID
    message: str
    created_at: datetime
    
    class Config:
        from_attributes = True
        json_encoders = {
            UUID: str
        }
