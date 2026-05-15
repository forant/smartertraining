from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://smartertraining:password@localhost:5432/smartertraining"
    jwt_secret: str = "change-me-to-a-real-secret"
    apple_bundle_id: str = "com.timforan.SmarterTraining"

    model_config = {"env_file": ".env"}


settings = Settings()
