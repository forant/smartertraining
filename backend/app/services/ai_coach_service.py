import asyncio
import json
import logging
from typing import Any, Dict, Optional

from openai import AsyncOpenAI

from app.config import settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
You are the coaching voice of SmarterTraining — an adaptive training companion \
for people with real lives.

Your job: explain why today's workout was chosen, connecting it to the user's \
current state and recent patterns. Help them feel understood, supported, and \
confident in the plan.

ABSOLUTE RULES:
- The workout is already decided. Never suggest changing it.
- Only reference information provided to you. Never invent history or plans.
- No medical claims. No HRV analysis. No injury diagnosis.
- No guilt, shame, or punishment language.
- No "crush it", "no excuses", or motivational clichés.

TONE: Calm. Competent. Like a thoughtful coach who knows your situation.

FORMAT — respond with exactly this JSON:
{
  "coachExplanation": "1–3 sentences. Why this workout, given today's context.",
  "continuityNote": "One sentence connecting today to recent days. Null if not useful.",
  "tomorrowImplication": "One sentence about what this sets up. Null if not useful.",
  "confidence": "high | medium | low"
}

Confidence: "high" when context is clear, "medium" when incomplete, \
"low" when minimal data."""

TIMEOUT_SECONDS = 10

_client: Optional[AsyncOpenAI] = None


def _get_client() -> Optional[AsyncOpenAI]:
    global _client
    if _client is None and settings.openai_api_key:
        _client = AsyncOpenAI(api_key=settings.openai_api_key)
    return _client


def _build_user_message(data: Dict[str, Any]) -> str:
    parts = []

    rec = data.get("recommendation", {})
    if rec:
        parts.append(f"Recommendation: {rec.get('type', 'unknown')} — {rec.get('title', '')}")
        if rec.get("summary"):
            parts.append(f"Summary: {rec['summary']}")

    ci = data.get("check_in")
    if ci:
        items = []
        if ci.get("feel"):
            items.append(f"feel={ci['feel']}")
        if ci.get("legs"):
            items.append(f"legs={ci['legs']}")
        if ci.get("motivation"):
            items.append(f"motivation={ci['motivation']}")
        if ci.get("time"):
            items.append(f"time={ci['time']}min")
        if items:
            parts.append(f"Check-in: {', '.join(items)}")

    tm = data.get("training_memory")
    if tm:
        items = []
        if "workouts_7d" in tm:
            items.append(f"{tm['workouts_7d']} workouts in 7d")
        if "hard_days_7d" in tm:
            items.append(f"{tm['hard_days_7d']} hard days")
        if tm.get("days_since_last") is not None:
            items.append(f"{tm['days_since_last']}d since last")
        if tm.get("last_feedback"):
            items.append(f"last feedback: {tm['last_feedback']}")
        if tm.get("intensity_load"):
            items.append(f"load estimate: {tm['intensity_load']}")
        if tm.get("returning_after_break"):
            items.append("returning after break")
        if tm.get("high_recent_load"):
            items.append("high recent load")
        if items:
            parts.append(f"Training: {', '.join(items)}")

    activities = data.get("recent_activities") or []
    if activities:
        descs = []
        for a in activities[:5]:
            desc = a.get("type", "activity")
            if a.get("timing"):
                desc += f" ({a['timing']})"
            if a.get("intensity"):
                desc += f" [{a['intensity']}]"
            descs.append(desc)
        parts.append(f"Recent activities: {', '.join(descs)}")

    context = data.get("life_context") or []
    if context:
        parts.append(f"Life context: {', '.join(context[:5])}")

    if data.get("last_feedback"):
        parts.append(f"Last session feedback: {data['last_feedback']}")

    if data.get("edited_workout"):
        parts.append("User edited the workout from the recommendation.")

    return "\n".join(parts)


def _fallback_response(reason: str) -> Dict[str, Any]:
    return {
        "coach_explanation": reason,
        "continuity_note": None,
        "tomorrow_implication": None,
        "confidence": "low",
        "is_fallback": True,
    }


async def generate_explanation(data: Dict[str, Any]) -> Dict[str, Any]:
    deterministic_reason = data.get("recommendation", {}).get("reason", "")

    client = _get_client()
    if client is None:
        logger.warning("OpenAI not configured, using fallback")
        return _fallback_response(deterministic_reason)

    user_message = _build_user_message(data)

    try:
        response = await asyncio.wait_for(
            client.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_message},
                ],
                response_format={"type": "json_object"},
                max_tokens=300,
                temperature=0.7,
            ),
            timeout=TIMEOUT_SECONDS,
        )

        content = response.choices[0].message.content
        result = json.loads(content)

        if "coachExplanation" not in result:
            logger.warning("AI response missing coachExplanation")
            return _fallback_response(deterministic_reason)

        return {
            "coach_explanation": result["coachExplanation"],
            "continuity_note": result.get("continuityNote"),
            "tomorrow_implication": result.get("tomorrowImplication"),
            "confidence": result.get("confidence", "medium"),
            "is_fallback": False,
        }

    except asyncio.TimeoutError:
        logger.warning("OpenAI request timed out")
        return _fallback_response(deterministic_reason)
    except json.JSONDecodeError:
        logger.warning("Failed to parse OpenAI response as JSON")
        return _fallback_response(deterministic_reason)
    except Exception as e:
        logger.exception("AI coach explanation failed: %s", e)
        return _fallback_response(deterministic_reason)
