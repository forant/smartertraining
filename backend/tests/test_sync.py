import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch
from uuid import uuid4


async def _create_user_and_get_token(async_client, apple_sub="test_sync_user"):
    """Helper: create a user via mock Apple auth and return the JWT."""
    mock_claims = {"sub": apple_sub, "email": f"{apple_sub}@example.com"}
    with patch(
        "app.routes.auth.verify_apple_identity_token",
        new_callable=AsyncMock,
        return_value=mock_claims,
    ):
        resp = await async_client.post(
            "/v1/auth/apple",
            json={"identity_token": "fake", "full_name": "Test User"},
        )
    return resp.json()["access_token"]


@pytest.mark.asyncio
async def test_sync_inserts_records(async_client):
    """POST /v1/sync with records inserts them and returns them."""
    token = await _create_user_and_get_token(async_client)
    record_id = str(uuid4())

    resp = await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": record_id,
                    "created_at": "2025-06-01T10:00:00Z",
                    "updated_at": "2025-06-01T10:00:00Z",
                    "data": {"type": "endurance", "duration": 45},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["records"]) == 1
    assert data["records"][0]["record_id"] == record_id
    assert data["records"][0]["data"]["type"] == "endurance"


@pytest.mark.asyncio
async def test_sync_updates_newer_records(async_client):
    """Syncing with a newer updated_at updates the record."""
    token = await _create_user_and_get_token(async_client, "update_user")
    record_id = str(uuid4())

    # Insert original.
    await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": record_id,
                    "created_at": "2025-06-01T10:00:00Z",
                    "updated_at": "2025-06-01T10:00:00Z",
                    "data": {"version": 1},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )

    # Update with newer timestamp.
    resp = await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": record_id,
                    "created_at": "2025-06-01T10:00:00Z",
                    "updated_at": "2025-06-01T12:00:00Z",
                    "data": {"version": 2},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    records = resp.json()["records"]
    assert len(records) == 1
    assert records[0]["data"]["version"] == 2


@pytest.mark.asyncio
async def test_sync_ignores_older_records(async_client):
    """Syncing with an older updated_at does not overwrite the record."""
    token = await _create_user_and_get_token(async_client, "ignore_user")
    record_id = str(uuid4())

    # Insert with newer timestamp first.
    await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "checkin",
                    "record_id": record_id,
                    "created_at": "2025-06-01T10:00:00Z",
                    "updated_at": "2025-06-01T12:00:00Z",
                    "data": {"version": 2},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )

    # Attempt to sync with older timestamp.
    resp = await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "checkin",
                    "record_id": record_id,
                    "created_at": "2025-06-01T10:00:00Z",
                    "updated_at": "2025-06-01T08:00:00Z",
                    "data": {"version": 1},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    # Fetch all records to verify original is preserved.
    fetch_resp = await async_client.post(
        "/v1/sync",
        json={"records": []},
        headers={"Authorization": f"Bearer {token}"},
    )
    records = fetch_resp.json()["records"]
    assert len(records) == 1
    assert records[0]["data"]["version"] == 2


@pytest.mark.asyncio
async def test_sync_returns_since_timestamp(async_client):
    """Only records updated after client_last_synced_at are returned."""
    token = await _create_user_and_get_token(async_client, "since_user")
    rid_old = str(uuid4())
    rid_new = str(uuid4())

    # Insert an "old" record.
    await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": rid_old,
                    "created_at": "2025-01-01T00:00:00Z",
                    "updated_at": "2025-01-01T00:00:00Z",
                    "data": {"label": "old"},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )

    # Insert a "new" record.
    await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": rid_new,
                    "created_at": "2025-06-01T00:00:00Z",
                    "updated_at": "2025-06-01T00:00:00Z",
                    "data": {"label": "new"},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )

    # Sync with a timestamp between the two.
    resp = await async_client.post(
        "/v1/sync",
        json={
            "client_last_synced_at": "2025-03-01T00:00:00Z",
            "records": [],
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    records = resp.json()["records"]
    assert len(records) == 1
    assert records[0]["data"]["label"] == "new"


@pytest.mark.asyncio
async def test_unauthenticated_sync_rejected(async_client):
    """POST /v1/sync without auth returns 401."""
    resp = await async_client.post(
        "/v1/sync",
        json={"records": []},
    )
    assert resp.status_code in (401, 422)  # 422 if header missing, 401 if invalid
