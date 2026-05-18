"""Add apple_refresh_token to users table

Revision ID: 002
Revises: 001
Create Date: 2026-05-18 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("apple_refresh_token", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "apple_refresh_token")
