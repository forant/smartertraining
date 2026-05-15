import json
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest

from app.services.ai_coach_service import (
    _build_user_message,
    _fallback_response,
    generate_explanation,
)


# --- Unit: _build_user_message ---


def test_build_user_message_includes_recommendation():
    data = {"recommendation": {"type": "endurance", "title": "Zone 2 Ride", "summary": "Aerobic base"}}
    msg = _build_user_message(data)
    assert "endurance" in msg
    assert "Zone 2 Ride" in msg
    assert "Aerobic base" in msg


def test_build_user_message_includes_check_in():
    data = {
        "recommendation": {"type": "recovery"},
        "check_in": {"feel": "Bad", "legs": "Heavy", "motivation": "Low", "time": 30},
    }
    msg = _build_user_message(data)
    assert "feel=Bad" in msg
    assert "legs=Heavy" in msg
    assert "time=30min" in msg


def test_build_user_message_includes_context():
    data = {
        "recommendation": {"type": "recovery"},
        "life_context": ["Poor sleep", "High work stress"],
        "recent_activities": [{"type": "Tennis", "timing": "yesterday", "intensity": "hard"}],
    }
    msg = _build_user_message(data)
    assert "Poor sleep" in msg
    assert "Tennis" in msg
    assert "yesterday" in msg


def test_build_user_message_excludes_secrets():
    data = {
        "recommendation": {"type": "endurance", "title": "Ride"},
        "check_in": {"feel": "Good"},
        "jwt": "secret-token",
        "api_key": "sk-secret",
        "password": "hunter2",
    }
    msg = _build_user_message(data)
    assert "secret-token" not in msg
    assert "sk-secret" not in msg
    assert "hunter2" not in msg


def test_build_user_message_limits_activities():
    data = {
        "recommendation": {"type": "endurance"},
        "recent_activities": [{"type": f"Activity{i}"} for i in range(10)],
    }
    msg = _build_user_message(data)
    assert "Activity4" in msg
    assert "Activity5" not in msg


# --- Unit: _fallback_response ---


def test_fallback_response_shape():
    result = _fallback_response("steady endurance ride")
    assert result["coach_explanation"] == "steady endurance ride"
    assert result["is_fallback"] is True
    assert result["confidence"] == "low"
    assert result["continuity_note"] is None
    assert result["tomorrow_implication"] is None


# --- Integration: generate_explanation ---


@pytest.mark.asyncio
async def test_generate_explanation_fallback_when_no_api_key():
    data = {"recommendation": {"type": "endurance", "reason": "Aerobic base work"}}
    with patch("app.services.ai_coach_service.settings") as mock_settings:
        mock_settings.openai_api_key = None
        with patch("app.services.ai_coach_service._get_client", return_value=None):
            result = await generate_explanation(data)
    assert result["is_fallback"] is True
    assert result["coach_explanation"] == "Aerobic base work"


@pytest.mark.asyncio
async def test_generate_explanation_fallback_on_timeout():
    import asyncio

    data = {"recommendation": {"type": "quality", "reason": "Time for intervals"}}

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(
        side_effect=asyncio.TimeoutError()
    )

    with patch("app.services.ai_coach_service._get_client", return_value=mock_client):
        result = await generate_explanation(data)

    assert result["is_fallback"] is True
    assert result["coach_explanation"] == "Time for intervals"


@pytest.mark.asyncio
async def test_generate_explanation_fallback_on_bad_json():
    data = {"recommendation": {"type": "recovery", "reason": "Rest day"}}

    mock_choice = AsyncMock()
    mock_choice.message.content = "not valid json"
    mock_response = AsyncMock()
    mock_response.choices = [mock_choice]

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

    with patch("app.services.ai_coach_service._get_client", return_value=mock_client):
        result = await generate_explanation(data)

    assert result["is_fallback"] is True


@pytest.mark.asyncio
async def test_generate_explanation_fallback_on_missing_field():
    data = {"recommendation": {"type": "recovery", "reason": "Rest day"}}

    mock_choice = AsyncMock()
    mock_choice.message.content = json.dumps({"somethingElse": "no coach explanation"})
    mock_response = AsyncMock()
    mock_response.choices = [mock_choice]

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

    with patch("app.services.ai_coach_service._get_client", return_value=mock_client):
        result = await generate_explanation(data)

    assert result["is_fallback"] is True


@pytest.mark.asyncio
async def test_generate_explanation_success():
    data = {"recommendation": {"type": "endurance", "reason": "Aerobic base"}}

    ai_response = {
        "coachExplanation": "Good day for steady work.",
        "continuityNote": "Building on yesterday's recovery.",
        "tomorrowImplication": None,
        "confidence": "high",
    }
    mock_choice = AsyncMock()
    mock_choice.message.content = json.dumps(ai_response)
    mock_response = AsyncMock()
    mock_response.choices = [mock_choice]

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

    with patch("app.services.ai_coach_service._get_client", return_value=mock_client):
        result = await generate_explanation(data)

    assert result["is_fallback"] is False
    assert result["coach_explanation"] == "Good day for steady work."
    assert result["continuity_note"] == "Building on yesterday's recovery."
    assert result["confidence"] == "high"


# --- Endpoint: auth required ---


@pytest.mark.asyncio
async def test_coach_endpoint_requires_auth(async_client):
    response = await async_client.post(
        "/v1/coach/explanation",
        json={"recommendation": {"type": "endurance"}},
    )
    assert response.status_code == 422 or response.status_code == 401
