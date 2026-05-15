import re
from typing import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


def _make_async_url(url: str) -> str:
    """Convert postgres:// or postgresql:// URLs to postgresql+asyncpg://."""
    return re.sub(r"^postgresql?://", "postgresql+asyncpg://", url)


engine = create_async_engine(_make_async_url(settings.database_url), echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session
