from datetime import datetime
from typing import Dict, List, Optional
from uuid import UUID

from pydantic import BaseModel


# --- Auth ---


class AppleAuthRequest(BaseModel):
    identity_token: str
    authorization_code: Optional[str] = None
    full_name: Optional[str] = None
    email: Optional[str] = None


class AuthResponse(BaseModel):
    access_token: str
    expires_at: datetime
    user_id: UUID


# --- Sync ---


class SyncRecordIn(BaseModel):
    record_type: str
    record_id: UUID
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None
    data: Dict


class SyncRequest(BaseModel):
    client_last_synced_at: Optional[datetime] = None
    records: List[SyncRecordIn]


class SyncRecordOut(BaseModel):
    record_type: str
    record_id: UUID
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None
    data: Dict


class SyncResponse(BaseModel):
    server_time: datetime
    records: List[SyncRecordOut]


# --- Coach ---


class CoachExplanationRequest(BaseModel):
    recommendation: Dict
    check_in: Optional[Dict] = None
    training_memory: Optional[Dict] = None
    recent_activities: Optional[List[Dict]] = None
    life_context: Optional[List[str]] = None
    last_feedback: Optional[str] = None
    edited_workout: bool = False


class CoachExplanationResponse(BaseModel):
    coach_explanation: str
    continuity_note: Optional[str] = None
    tomorrow_implication: Optional[str] = None
    confidence: str = "high"
    is_fallback: bool = False


# --- Post-Workout Reflection ---


class DayGuidance(BaseModel):
    day_label: str
    guidance: str
    recommended_intensity: str


class PostWorkoutReflectionRequest(BaseModel):
    workout_summary: Dict
    recommendation: Dict
    executed_steps: Optional[List[Dict]] = None
    feedback: Optional[str] = None
    perceived_effort: Optional[int] = None
    user_note: Optional[str] = None
    check_in: Optional[Dict] = None
    life_context: Optional[List[str]] = None
    training_memory: Optional[Dict] = None


class PostWorkoutReflectionResponse(BaseModel):
    session_evaluation: str
    what_went_well: Optional[str] = None
    watch_out: Optional[str] = None
    next_two_days: List[DayGuidance]
    confidence: str = "high"
    is_fallback: bool = False
    generated_at: str
