import logging
from typing import Dict, Optional, Tuple

import jwt
import httpx
from jwt.algorithms import RSAAlgorithm

logger = logging.getLogger(__name__)

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"


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
