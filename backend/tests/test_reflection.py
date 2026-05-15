import json
from unittest.mock import AsyncMock, patch

import pytest

from app.services.ai_reflection_service import (
    _build_user_message,
    _fallback_response,
    generate_reflection,
)


# --- Unit: _build_user_message ---


def test_build_user_message_includes_workout_summary():
    data = {
        "workout_summary": {
            "title": "Zone 2 Ride",
            "workout_type": "endurance",
            "duration_seconds": 2700,
            "average_power": 180,
        }
    }
    msg = _build_user_message(data)
    assert "Zone 2 Ride" in msg
    assert "endurance" in msg
    assert "45min" in msg
    assert "avg=180W" in msg


def test_build_user_message_includes_feedback():
    data = {
        "workout_summary": {"workout_type": "quality"},
        "feedback": "hard",
        "perceived_effort": 8,
        "user_note": "Legs were heavy from tennis yesterday",
    }
    msg = _build_user_message(data)
    assert "hard" in msg
    assert "8/10" in msg
    assert "Legs were heavy" in msg


def test_build_user_message_includes_check_in():
    data = {
        "workout_summary": {"workout_type": "endurance"},
        "check_in": {"feel": "Good", "legs": "Normal", "motivation": "High", "time": 45},
    }
    msg = _build_user_message(data)
    assert "feel=Good" in msg
    assert "time=45min" in msg


def test_build_user_message_includes_training_memory():
    data = {
        "workout_summary": {"workout_type": "endurance"},
        "training_memory": {
            "workouts_7d": 3,
            "hard_days_7d": 1,
            "high_recent_load": True,
        },
    }
    msg = _build_user_message(data)
    assert "3 workouts in 7d" in msg
    assert "high recent load" in msg


def test_build_user_message_excludes_secrets():
    data = {
        "workout_summary": {"workout_type": "endurance"},
        "jwt": "secret-token",
        "api_key": "sk-secret",
    }
    msg = _build_user_message(data)
    assert "secret-token" not in msg
    assert "sk-secret" not in msg


def test_build_user_message_limits_steps():
    data = {
        "workout_summary": {"workout_type": "endurance"},
        "executed_steps": [
            {"name": f"Step{i}", "duration_seconds": 300, "target_power": 150, "role": "primary"}
            for i in range(15)
        ],
    }
    msg = _build_user_message(data)
    assert "Step9" in msg
    assert "Step10" not in msg


# --- Unit: _fallback_response ---


def test_fallback_response_shape():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 2700},
        "feedback": "right",
    }
    result = _fallback_response(data)
    assert result["is_fallback"] is True
    assert result["confidence"] == "low"
    assert "endurance" in result["session_evaluation"]
    assert len(result["next_two_days"]) == 2
    assert result["next_two_days"][0]["day_label"] == "Tomorrow"
    assert result["next_two_days"][1]["day_label"] == "Day after tomorrow"
    assert result["generated_at"] is not None


def test_fallback_hard_feedback_recommends_recovery():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 1800},
        "feedback": "hard",
    }
    result = _fallback_response(data)
    assert result["next_two_days"][0]["recommended_intensity"] == "recovery"


def test_fallback_quality_workout_recommends_recovery():
    data = {
        "workout_summary": {"workout_type": "quality", "duration_seconds": 2700},
        "feedback": "right",
    }
    result = _fallback_response(data)
    assert result["next_two_days"][0]["recommended_intensity"] == "recovery"


def test_fallback_easy_feedback_allows_endurance():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 1800},
        "feedback": "easy",
    }
    result = _fallback_response(data)
    assert result["next_two_days"][0]["recommended_intensity"] == "endurance"


def test_fallback_high_effort_recommends_recovery():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 1800},
        "perceived_effort": 9,
    }
    result = _fallback_response(data)
    assert result["next_two_days"][0]["recommended_intensity"] == "recovery"


# --- Integration: generate_reflection ---


@pytest.mark.asyncio
async def test_generate_reflection_fallback_when_no_api_key():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 2700},
        "feedback": "right",
    }
    with patch("app.services.ai_reflection_service.settings") as mock_settings:
        mock_settings.openai_api_key = None
        with patch("app.services.ai_reflection_service._get_client", return_value=None):
            result = await generate_reflection(data)
    assert result["is_fallback"] is True


@pytest.mark.asyncio
async def test_generate_reflection_fallback_on_timeout():
    import asyncio

    data = {
        "workout_summary": {"workout_type": "quality", "duration_seconds": 2700},
        "feedback": "hard",
    }

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(
        side_effect=asyncio.TimeoutError()
    )

    with patch("app.services.ai_reflection_service._get_client", return_value=mock_client):
        result = await generate_reflection(data)

    assert result["is_fallback"] is True
    assert len(result["next_two_days"]) == 2


@pytest.mark.asyncio
async def test_generate_reflection_fallback_on_bad_json():
    data = {
        "workout_summary": {"workout_type": "recovery", "duration_seconds": 1200},
    }

    mock_choice = AsyncMock()
    mock_choice.message.content = "not valid json"
    mock_response = AsyncMock()
    mock_response.choices = [mock_choice]

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

    with patch("app.services.ai_reflection_service._get_client", return_value=mock_client):
        result = await generate_reflection(data)

    assert result["is_fallback"] is True


@pytest.mark.asyncio
async def test_generate_reflection_fallback_on_missing_field():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 2700},
    }

    mock_choice = AsyncMock()
    mock_choice.message.content = json.dumps({"somethingElse": "no evaluation"})
    mock_response = AsyncMock()
    mock_response.choices = [mock_choice]

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

    with patch("app.services.ai_reflection_service._get_client", return_value=mock_client):
        result = await generate_reflection(data)

    assert result["is_fallback"] is True


@pytest.mark.asyncio
async def test_generate_reflection_fallback_on_wrong_day_count():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 2700},
    }

    ai_response = {
        "sessionEvaluation": "Good session.",
        "nextTwoDays": [
            {"dayLabel": "Tomorrow", "guidance": "Easy day.", "recommendedIntensity": "recovery"}
        ],
        "confidence": "high",
    }
    mock_choice = AsyncMock()
    mock_choice.message.content = json.dumps(ai_response)
    mock_response = AsyncMock()
    mock_response.choices = [mock_choice]

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

    with patch("app.services.ai_reflection_service._get_client", return_value=mock_client):
        result = await generate_reflection(data)

    assert result["is_fallback"] is True


@pytest.mark.asyncio
async def test_generate_reflection_success():
    data = {
        "workout_summary": {"workout_type": "endurance", "duration_seconds": 2700},
        "feedback": "right",
        "perceived_effort": 6,
    }

    ai_response = {
        "sessionEvaluation": "Solid endurance session. Your effort matched the intent.",
        "whatWentWell": "Consistent pacing throughout.",
        "watchOut": None,
        "nextTwoDays": [
            {
                "dayLabel": "Tomorrow",
                "guidance": "Easy spin or rest.",
                "recommendedIntensity": "recovery",
            },
            {
                "dayLabel": "Day after tomorrow",
                "guidance": "Good day for structured work.",
                "recommendedIntensity": "quality",
            },
        ],
        "confidence": "high",
    }
    mock_choice = AsyncMock()
    mock_choice.message.content = json.dumps(ai_response)
    mock_response = AsyncMock()
    mock_response.choices = [mock_choice]

    mock_client = AsyncMock()
    mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

    with patch("app.services.ai_reflection_service._get_client", return_value=mock_client):
        result = await generate_reflection(data)

    assert result["is_fallback"] is False
    assert result["session_evaluation"] == "Solid endurance session. Your effort matched the intent."
    assert result["what_went_well"] == "Consistent pacing throughout."
    assert result["confidence"] == "high"
    assert len(result["next_two_days"]) == 2
    assert result["next_two_days"][0]["day_label"] == "Tomorrow"
    assert result["next_two_days"][1]["recommended_intensity"] == "quality"


# --- Endpoint: auth required ---


@pytest.mark.asyncio
async def test_reflection_endpoint_requires_auth(async_client):
    response = await async_client.post(
        "/v1/coach/post-workout-reflection",
        json={
            "workout_summary": {"workout_type": "endurance", "duration_seconds": 2700},
            "recommendation": {"type": "endurance"},
        },
    )
    assert response.status_code == 422 or response.status_code == 401
