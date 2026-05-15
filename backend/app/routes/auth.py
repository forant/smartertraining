from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import create_access_token
from app.db import get_session
from app.models import User
from app.schemas import AppleAuthRequest, AuthResponse
from app.services.apple_auth import verify_apple_identity_token
from app.config import settings

router = APIRouter(prefix="/v1/auth", tags=["auth"])


@router.post("/apple", response_model=AuthResponse)
async def apple_auth(
    body: AppleAuthRequest,
    session: AsyncSession = Depends(get_session),
):
    claims = await verify_apple_identity_token(
        body.identity_token, settings.apple_bundle_id
    )
    if claims is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid identity token",
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
        # Only update if current value is None and new value is provided.
        if user.full_name is None and body.full_name is not None:
            user.full_name = body.full_name
        if user.email is None:
            new_email = body.email or claims.get("email")
            if new_email is not None:
                user.email = new_email

    await session.commit()
    await session.refresh(user)

    token, expires_at = create_access_token(user.id)

    return AuthResponse(
        access_token=token,
        expires_at=expires_at,
        user_id=user.id,
    )
