import pytest
from unittest.mock import AsyncMock, patch


async def _create_user(async_client, apple_id="test_apple_id_123", email="test@example.com"):
    """Helper: create a user via the auth endpoint and return the access token."""
    mock_claims = (
        {"sub": apple_id, "email": email},
        None,
    )
    with patch(
        "app.routes.auth.verify_apple_identity_token",
        new_callable=AsyncMock,
        return_value=mock_claims,
    ):
        resp = await async_client.post(
            "/v1/auth/apple",
            json={
                "identity_token": "fake_token",
                "full_name": "Test User",
                "email": email,
            },
        )
    assert resp.status_code == 200
    return resp.json()["access_token"]


@pytest.mark.asyncio
async def test_delete_account_removes_user(async_client):
    token = await _create_user(async_client)

    resp = await async_client.delete(
        "/v1/account",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_delete_account_is_idempotent(async_client):
    token = await _create_user(async_client)

    resp = await async_client.delete(
        "/v1/account",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 204

    resp2 = await async_client.delete(
        "/v1/account",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp2.status_code == 204


@pytest.mark.asyncio
async def test_delete_account_removes_training_records(async_client):
    token = await _create_user(async_client)

    await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": "00000000-0000-0000-0000-000000000001",
                    "created_at": "2025-01-01T00:00:00Z",
                    "updated_at": "2025-01-01T00:00:00Z",
                    "data": {"name": "Test workout"},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token}"},
    )

    sync_resp = await async_client.post(
        "/v1/sync",
        json={"records": []},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert len(sync_resp.json()["records"]) == 1

    resp = await async_client.delete(
        "/v1/account",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_delete_account_requires_auth(async_client):
    resp = await async_client.delete("/v1/account")
    assert resp.status_code == 422

    resp2 = await async_client.delete(
        "/v1/account",
        headers={"Authorization": "Bearer invalid_token"},
    )
    assert resp2.status_code == 401


@pytest.mark.asyncio
async def test_delete_account_revokes_apple_token(async_client):
    mock_claims = (
        {"sub": "revoke_test_user", "email": "revoke@example.com"},
        None,
    )
    with patch(
        "app.routes.auth.verify_apple_identity_token",
        new_callable=AsyncMock,
        return_value=mock_claims,
    ), patch(
        "app.routes.auth.exchange_authorization_code",
        new_callable=AsyncMock,
        return_value="fake_refresh_token",
    ):
        resp = await async_client.post(
            "/v1/auth/apple",
            json={
                "identity_token": "fake_token",
                "authorization_code": "fake_auth_code",
                "full_name": "Revoke User",
            },
        )
    token = resp.json()["access_token"]

    with patch(
        "app.routes.auth.revoke_apple_token",
        new_callable=AsyncMock,
        return_value=True,
    ) as mock_revoke:
        resp = await async_client.delete(
            "/v1/account",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 204
        mock_revoke.assert_called_once_with("fake_refresh_token")


@pytest.mark.asyncio
async def test_delete_account_proceeds_when_revoke_fails(async_client):
    mock_claims = (
        {"sub": "revoke_fail_user", "email": "fail@example.com"},
        None,
    )
    with patch(
        "app.routes.auth.verify_apple_identity_token",
        new_callable=AsyncMock,
        return_value=mock_claims,
    ), patch(
        "app.routes.auth.exchange_authorization_code",
        new_callable=AsyncMock,
        return_value="fake_refresh_token",
    ):
        resp = await async_client.post(
            "/v1/auth/apple",
            json={
                "identity_token": "fake_token",
                "authorization_code": "fake_auth_code",
                "full_name": "Fail User",
            },
        )
    token = resp.json()["access_token"]

    with patch(
        "app.routes.auth.revoke_apple_token",
        new_callable=AsyncMock,
        return_value=False,
    ):
        resp = await async_client.delete(
            "/v1/account",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 204

    resp2 = await async_client.delete(
        "/v1/account",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp2.status_code == 204


@pytest.mark.asyncio
async def test_delete_one_user_preserves_other(async_client):
    token_a = await _create_user(async_client, apple_id="user_a", email="a@test.com")
    token_b = await _create_user(async_client, apple_id="user_b", email="b@test.com")

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
    await async_client.post(
        "/v1/sync",
        json={
            "records": [
                {
                    "record_type": "workout",
                    "record_id": "00000000-0000-0000-0000-000000000002",
                    "created_at": "2025-01-01T00:00:00Z",
                    "updated_at": "2025-01-01T00:00:00Z",
                    "data": {"name": "User B workout"},
                }
            ]
        },
        headers={"Authorization": f"Bearer {token_b}"},
    )

    resp = await async_client.delete(
        "/v1/account",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert resp.status_code == 204

    sync_resp = await async_client.post(
        "/v1/sync",
        json={"records": []},
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert sync_resp.status_code == 200
    assert len(sync_resp.json()["records"]) == 1
    assert sync_resp.json()["records"][0]["data"]["name"] == "User B workout"
