import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import create_access_token, get_current_user_id
from app.db import get_session
from app.models import Profile, TrainingRecord, User
from app.schemas import AppleAuthRequest, AuthResponse
from app.services.apple_auth import (
    exchange_authorization_code,
    revoke_apple_token,
    verify_apple_identity_token,
)
from app.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["auth"])


@router.post("/auth/apple", response_model=AuthResponse)
async def apple_auth(
    body: AppleAuthRequest,
    session: AsyncSession = Depends(get_session),
):
    claims, error_reason = await verify_apple_identity_token(
        body.identity_token, settings.apple_bundle_id
    )
    if claims is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=error_reason or "Invalid identity token",
        )

    apple_user_id = claims["sub"]

    result = await session.execute(
        select(User).where(User.apple_user_id == apple_user_id)
    )
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            apple_user_id=apple_user_id,
            email=body.email or claims.get("email"),
            full_name=body.full_name,
        )
        session.add(user)
        await session.flush()
    else:
        if user.full_name is None and body.full_name is not None:
            user.full_name = body.full_name
        if user.email is None:
            new_email = body.email or claims.get("email")
            if new_email is not None:
                user.email = new_email

    if body.authorization_code:
        refresh_token = await exchange_authorization_code(body.authorization_code)
        if refresh_token:
            user.apple_refresh_token = refresh_token

    await session.commit()
    await session.refresh(user)

    token, expires_at = create_access_token(user.id)

    return AuthResponse(
        access_token=token,
        expires_at=expires_at,
        user_id=user.id,
    )


@router.delete("/account", status_code=204)
async def delete_account(
    user_id: UUID = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    """Delete the authenticated user's account and all associated data."""
    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if user is None:
        return

    if user.apple_refresh_token:
        revoked = await revoke_apple_token(user.apple_refresh_token)
        if not revoked:
            logger.warning("Failed to revoke Apple token for user %s", user_id)

    await session.execute(
        delete(TrainingRecord).where(TrainingRecord.user_id == user_id)
    )
    await session.execute(
        delete(Profile).where(Profile.user_id == user_id)
    )
    await session.delete(user)
    await session.commit()
