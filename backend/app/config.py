from typing import Optional

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://smartertraining:password@localhost:5432/smartertraining"
    jwt_secret: str = "change-me-to-a-real-secret"
    apple_bundle_id: str = "com.timforan.SmarterTraining"
    openai_api_key: Optional[str] = None
    openai_model: str = "gpt-4o-mini"

    model_config = {"env_file": ".env"}


settings = Settings()
