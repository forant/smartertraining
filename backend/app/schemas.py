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
