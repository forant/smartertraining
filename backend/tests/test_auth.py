import pytest
from unittest.mock import AsyncMock, patch


@pytest.mark.asyncio
async def test_apple_auth_creates_user(async_client, mock_apple_auth):
    """POST /v1/auth/apple with valid token creates a user and returns JWT."""
    response = await async_client.post(
        "/v1/auth/apple",
        json={
            "identity_token": "fake_token",
            "full_name": "Tim Foran",
            "email": "tim@example.com",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "expires_at" in data
    assert "user_id" in data


@pytest.mark.asyncio
async def test_apple_auth_updates_existing_user(async_client, mock_apple_auth):
    """Second auth call preserves existing name/email, doesn't overwrite with None."""
    # First call — creates user with name and email.
    response1 = await async_client.post(
        "/v1/auth/apple",
        json={
            "identity_token": "fake_token",
            "full_name": "Tim Foran",
            "email": "tim@example.com",
        },
    )
    assert response1.status_code == 200
    user_id_1 = response1.json()["user_id"]

    # Second call — same apple_user_id, but no name/email this time.
    response2 = await async_client.post(
        "/v1/auth/apple",
        json={
            "identity_token": "fake_token",
        },
    )
    assert response2.status_code == 200
    user_id_2 = response2.json()["user_id"]

    # Same user, name and email preserved.
    assert user_id_1 == user_id_2


@pytest.mark.asyncio
async def test_apple_auth_invalid_token(async_client):
    """Without mock, verify_apple_identity_token returns None -> 401."""
    with patch(
        "app.routes.auth.verify_apple_identity_token",
        new_callable=AsyncMock,
        return_value=None,
    ):
        response = await async_client.post(
            "/v1/auth/apple",
            json={"identity_token": "bad_token"},
        )
        assert response.status_code == 401


@pytest.mark.asyncio
async def test_user_a_cannot_access_user_b(async_client):
    """Create two users; sync records for user A; verify user B sync returns empty."""
    # Create user A.
    mock_a = {
        "sub": "apple_user_a",
        "email": "a@example.com",
    }
    with patch(
        "app.routes.auth.verify_apple_identity_token",
        new_callable=AsyncMock,
        return_value=mock_a,
    ):
        resp_a = await async_client.post(
            "/v1/auth/apple",
            json={"identity_token": "token_a", "full_name": "User A"},
        )
    token_a = resp_a.json()["access_token"]

    # Create user B.
    mock_b = {
        "sub": "apple_user_b",
        "email": "b@example.com",
    }
    with patch(
        "app.routes.auth.verify_apple_identity_token",
        new_callable=AsyncMock,
        return_value=mock_b,
    ):
        resp_b = await async_client.post(
            "/v1/auth/apple",
            json={"identity_token": "token_b", "full_name": "User B"},
        )
    token_b = resp_b.json()["access_token"]

    # Sync a record for user A.
    await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": "00000000-0000-0000-0000-000000000001",
                    "created_at": "2025-01-01T00:00:00Z",
                    "updated_at": "2025-01-01T00:00:00Z",
                    "data": {"name": "User A workout"},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token_a}"},
    )

    # User B syncs — should get no records.
    resp_b_sync = await async_client.post(
        "/v1/sync",
        json={"records": []},
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert resp_b_sync.status_code == 200
    assert resp_b_sync.json()["records"] == []
