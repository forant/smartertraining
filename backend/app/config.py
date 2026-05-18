from typing import Optional

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://smartertraining:password@localhost:5432/smartertraining"
    jwt_secret: str = "change-me-to-a-real-secret"
    apple_bundle_id: str = "com.timforan.SmarterTraining"
    openai_api_key: Optional[str] = None
    openai_model: str = "gpt-4o-mini"

    strava_client_id: Optional[str] = None
    strava_client_secret: Optional[str] = None

    # Sign in with Apple — required for token revocation on account deletion.
    # APPLE_TEAM_ID: Your Apple Developer Team ID (10-char alphanumeric).
    # APPLE_KEY_ID: Key ID for the Sign in with Apple private key.
    # APPLE_PRIVATE_KEY: The PEM-encoded ES256 private key (.p8 file contents).
    #   Set as a multi-line env var or use \n for newlines.
    # APPLE_CLIENT_ID: The Services ID or bundle ID used as the OAuth client_id.
    #   Defaults to apple_bundle_id if not set.
    apple_team_id: Optional[str] = None
    apple_key_id: Optional[str] = None
    apple_private_key: Optional[str] = None
    apple_client_id: Optional[str] = None

    @property
    def apple_siwa_client_id(self) -> str:
        return self.apple_client_id or self.apple_bundle_id

    @property
    def apple_revocation_configured(self) -> bool:
        return all([self.apple_team_id, self.apple_key_id, self.apple_private_key])

    model_config = {"env_file": ".env"}


settings = Settings()
