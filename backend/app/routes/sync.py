from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.db import get_session
from app.models import TrainingRecord
from app.schemas import SyncRecordOut, SyncRequest, SyncResponse


def _ensure_aware(dt: datetime) -> datetime:
    """Ensure a datetime is timezone-aware (UTC). Needed for SQLite compat."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt

router = APIRouter(prefix="/v1", tags=["sync"])


@router.post("/sync", response_model=SyncResponse)
async def sync(
    body: SyncRequest,
    user_id: UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    server_time = datetime.now(timezone.utc)

    # Upsert incoming records (last-write-wins on updated_at).
    for rec in body.records:
        result = await session.execute(
            select(TrainingRecord).where(
                TrainingRecord.user_id == user_id,
                TrainingRecord.record_type == rec.record_type,
                TrainingRecord.record_id == rec.record_id,
            )
        )
        existing = result.scalar_one_or_none()

        if existing is None:
            new_record = TrainingRecord(
                user_id=user_id,
                record_type=rec.record_type,
                record_id=rec.record_id,
                data=rec.data,
                created_at=rec.created_at,
                updated_at=rec.updated_at,
                deleted_at=rec.deleted_at,
            )
            session.add(new_record)
        else:
            # Last-write-wins: only apply if incoming is newer.
            if _ensure_aware(rec.updated_at) > _ensure_aware(existing.updated_at):
                existing.data = rec.data
                existing.updated_at = rec.updated_at
                existing.deleted_at = rec.deleted_at

    await session.flush()

    # Return records changed since client_last_synced_at (or all if None).
    query = select(TrainingRecord).where(TrainingRecord.user_id == user_id)
    if body.client_last_synced_at is not None:
        query = query.where(
            TrainingRecord.updated_at > body.client_last_synced_at
        )

    result = await session.execute(query)
    records = result.scalars().all()

    await session.commit()

    return SyncResponse(
        server_time=server_time,
        records=[
            SyncRecordOut(
                record_type=r.record_type,
                record_id=r.record_id,
                created_at=r.created_at,
                updated_at=r.updated_at,
                deleted_at=r.deleted_at,
                data=r.data,
            )
            for r in records
        ],
    )
