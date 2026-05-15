from typing import Dict, Optional

import jwt
import httpx
from jwt.algorithms import RSAAlgorithm

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"


async def verify_apple_identity_token(
    identity_token: str, bundle_id: str
) -> Optional[Dict]:
    """
    Verify an Apple Sign In identity token.

    Fetches Apple's public JWKS, finds the matching key by kid,
    and verifies the JWT signature, audience, and issuer.

    Returns the decoded claims dict on success, or None on any failure.
    """
    try:
        # Get the kid from the unverified header.
        unverified_header = jwt.get_unverified_header(identity_token)
        kid = unverified_header.get("kid")
        if kid is None:
            return None

        # Fetch Apple's JWKS.
        async with httpx.AsyncClient() as client:
            response = await client.get(APPLE_JWKS_URL)
            response.raise_for_status()
            jwks = response.json()

        # Find the matching key.
        matching_key = None
        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                matching_key = key
                break

        if matching_key is None:
            return None

        # Convert JWK to public key.
        public_key = RSAAlgorithm.from_jwk(matching_key)

        # Decode and verify the token.
        claims = jwt.decode(
            identity_token,
            public_key,
            algorithms=["RS256"],
            audience=bundle_id,
            issuer=APPLE_ISSUER,
        )

        return claims

    except Exception:
        return None
