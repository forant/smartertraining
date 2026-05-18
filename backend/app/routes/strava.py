import logging
from typing import Optional

import httpx
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/strava", tags=["strava"])

STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token"


class StravaTokenRequest(BaseModel):
    code: Optional[str] = None
    refresh_token: Optional[str] = None
    grant_type: str


@router.post("/token")
async def strava_token(body: StravaTokenRequest):
    if not settings.strava_client_id or not settings.strava_client_secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Strava integration not configured",
        )

    form_data = {
        "client_id": settings.strava_client_id,
        "client_secret": settings.strava_client_secret,
        "grant_type": body.grant_type,
    }
    if body.code:
        form_data["code"] = body.code
    if body.refresh_token:
        form_data["refresh_token"] = body.refresh_token

    async with httpx.AsyncClient() as client:
        resp = await client.post(STRAVA_TOKEN_URL, data=form_data)

    if resp.status_code != 200:
        logger.warning("Strava token exchange failed: %s %s", resp.status_code, resp.text)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Strava token exchange failed",
        )

    return resp.json()
