from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple
from uuid import UUID

import jwt
from fastapi import Header, HTTPException, status

from app.config import settings

_ALGORITHM = "HS256"
_EXPIRY_DAYS = 30


def create_access_token(user_id: UUID) -> Tuple[str, datetime]:
    """Create a JWT access token for the given user. Returns (token, expires_at)."""
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(days=_EXPIRY_DAYS)
    payload = {
        "sub": str(user_id),
        "exp": expires_at,
        "iat": now,
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=_ALGORITHM)
    return token, expires_at


def verify_access_token(token: str) -> Optional[UUID]:
    """Decode and verify a JWT access token. Returns user_id or None on failure."""
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[_ALGORITHM])
        return UUID(payload["sub"])
    except (jwt.InvalidTokenError, KeyError, ValueError):
        return None


async def get_current_user_id(
    authorization: str = Header(...),
) -> UUID:
    """Extract and verify JWT from the Authorization header."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization header",
        )
    token = authorization[len("Bearer "):]
    user_id = verify_access_token(token)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    return user_id
