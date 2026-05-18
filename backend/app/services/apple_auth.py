import logging
import time
from typing import Dict, Optional, Tuple

import jwt
import httpx
from jwt.algorithms import RSAAlgorithm

from app.config import settings

logger = logging.getLogger(__name__)

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"
APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"


async def verify_apple_identity_token(
    identity_token: str, bundle_id: str
) -> Tuple[Optional[Dict], Optional[str]]:
    """
    Verify an Apple Sign In identity token.

    Fetches Apple's public JWKS, finds the matching key by kid,
    and verifies the JWT signature, audience, and issuer.

    Returns (claims_dict, None) on success, or (None, error_reason) on failure.
    """
    try:
        unverified_header = jwt.get_unverified_header(identity_token)
        kid = unverified_header.get("kid")
        if kid is None:
            logger.warning("Apple token missing kid in header")
            return None, "Token missing key ID"

        unverified_claims = jwt.decode(
            identity_token, options={"verify_signature": False}
        )
        token_aud = unverified_claims.get("aud")
        logger.info(
            "Apple token kid=%s aud=%s expected_aud=%s", kid, token_aud, bundle_id
        )

        async with httpx.AsyncClient() as client:
            response = await client.get(APPLE_JWKS_URL)
            response.raise_for_status()
            jwks = response.json()

        matching_key = None
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                matching_key = key
                break

        if matching_key is None:
            logger.warning("No matching Apple JWKS key for kid=%s", kid)
            return None, f"No matching key for kid {kid}"

        public_key = RSAAlgorithm.from_jwk(matching_key)

        claims = jwt.decode(
            identity_token,
            public_key,
            algorithms=["RS256"],
            audience=bundle_id,
            issuer=APPLE_ISSUER,
        )

        logger.info("Apple token verified for sub=%s", claims.get("sub"))
        return claims, None

    except jwt.InvalidAudienceError:
        logger.warning(
            "Apple token audience mismatch: got %s, expected %s",
            token_aud, bundle_id,
        )
        return None, "Audience mismatch"
    except jwt.ExpiredSignatureError:
        logger.warning("Apple token expired")
        return None, "Token expired"
    except jwt.InvalidIssuerError:
        logger.warning("Apple token issuer mismatch")
        return None, "Invalid issuer"
    except Exception as e:
        logger.exception("Apple token verification failed: %s", e)
        return None, str(e)


def generate_apple_client_secret() -> str:
    """Generate a short-lived client_secret JWT for Apple token endpoints (ES256)."""
    from cryptography.hazmat.primitives.serialization import load_pem_private_key

    now = int(time.time())
    key_pem = settings.apple_private_key.replace("\\n", "\n")
    private_key = load_pem_private_key(key_pem.encode(), password=None)
    payload = {
        "iss": settings.apple_team_id,
        "iat": now,
        "exp": now + 86400,
        "aud": APPLE_ISSUER,
        "sub": settings.apple_siwa_client_id,
    }
    return jwt.encode(
        payload,
        private_key,
        algorithm="ES256",
        headers={"kid": settings.apple_key_id},
    )


async def exchange_authorization_code(authorization_code: str) -> Optional[str]:
    """Exchange a SIWA authorization_code for a refresh_token. Returns the refresh token or None."""
    if not settings.apple_revocation_configured:
        logger.info("Apple revocation not configured — skipping code exchange")
        return None

    try:
        client_secret = generate_apple_client_secret()
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                APPLE_TOKEN_URL,
                data={
                    "client_id": settings.apple_siwa_client_id,
                    "client_secret": client_secret,
                    "code": authorization_code,
                    "grant_type": "authorization_code",
                },
            )
        if resp.status_code != 200:
            logger.warning("Apple code exchange failed: %s %s", resp.status_code, resp.text)
            return None
        return resp.json().get("refresh_token")
    except Exception as e:
        logger.exception("Apple code exchange error: %s", e)
        return None


async def revoke_apple_token(refresh_token: str) -> bool:
    """Revoke a SIWA refresh_token so the user's credential is fully invalidated."""
    if not settings.apple_revocation_configured:
        logger.info("Apple revocation not configured — skipping revoke")
        return False

    try:
        client_secret = generate_apple_client_secret()
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                APPLE_REVOKE_URL,
                data={
                    "client_id": settings.apple_siwa_client_id,
                    "client_secret": client_secret,
                    "token": refresh_token,
                    "token_type_hint": "refresh_token",
                },
            )
        if resp.status_code == 200:
            logger.info("Apple token revoked successfully")
            return True
        logger.warning("Apple token revocation failed: %s %s", resp.status_code, resp.text)
        return False
    except Exception as e:
        logger.exception("Apple token revocation error: %s", e)
        return False
