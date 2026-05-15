import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from openai import AsyncOpenAI

from app.config import settings

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
You are the coaching voice of SmarterTraining — an adaptive training companion \
for people with real lives.

Your job: evaluate a just-completed workout and provide near-term guidance for \
the next two days. Help the user feel understood, confident, and clear on \
what comes next.

ABSOLUTE RULES:
- Only reference information provided to you. Never invent history or future plans.
- No medical claims. No HRV analysis. No injury diagnosis.
- No guilt, shame, or punishment language. Never say they "failed."
- No "crush it", "no excuses", or motivational clichés.
- Do not prescribe exact future workouts. Give directional guidance only.
- Mention HR/power/cadence only if useful context, not as judgments.
- Respect the original training intent.
- Normalize appropriate recovery.

TONE: Calm. Competent. Like a thoughtful coach doing a quick post-session debrief.

FORMAT — respond with exactly this JSON:
{
  "sessionEvaluation": "2–4 sentences. How the session went, connecting performance to user feedback.",
  "whatWentWell": "1 sentence or null. Something positive and specific.",
  "watchOut": "1 sentence or null. Something to be mindful of. Only if warranted.",
  "nextTwoDays": [
    {
      "dayLabel": "Tomorrow",
      "guidance": "1–2 sentences.",
      "recommendedIntensity": "rest|recovery|endurance|quality|flexible"
    },
    {
      "dayLabel": "Day after tomorrow",
      "guidance": "1–2 sentences.",
      "recommendedIntensity": "rest|recovery|endurance|quality|flexible"
    }
  ],
  "confidence": "high | medium | low"
}

nextTwoDays MUST always contain exactly 2 items.

Confidence: "high" when data is clear, "medium" when incomplete, \
"low" when minimal data."""

TIMEOUT_SECONDS = 12

_client: Optional[AsyncOpenAI] = None


def _get_client() -> Optional[AsyncOpenAI]:
    global _client
    if _client is None and settings.openai_api_key:
        _client = AsyncOpenAI(api_key=settings.openai_api_key)
    return _client


def _build_user_message(data: Dict[str, Any]) -> str:
    parts = []

    ws = data.get("workout_summary", {})
    if ws:
        items = []
        if ws.get("title"):
            items.append(ws["title"])
        if ws.get("workout_type"):
            items.append(f"type={ws['workout_type']}")
        if ws.get("duration_seconds"):
            mins = ws["duration_seconds"] // 60
            items.append(f"{mins}min")
        parts.append(f"Completed workout: {', '.join(items)}")

        power_items = []
        if ws.get("average_power"):
            power_items.append(f"avg={ws['average_power']}W")
        if ws.get("max_power"):
            power_items.append(f"max={ws['max_power']}W")
        if ws.get("average_cadence"):
            power_items.append(f"cadence={ws['average_cadence']}rpm")
        if ws.get("average_heart_rate"):
            power_items.append(f"avgHR={ws['average_heart_rate']}bpm")
        if ws.get("max_heart_rate"):
            power_items.append(f"maxHR={ws['max_heart_rate']}bpm")
        if power_items:
            parts.append(f"Performance: {', '.join(power_items)}")

        if ws.get("erg_enabled") is not None:
            parts.append(f"ERG mode: {'on' if ws['erg_enabled'] else 'off'}")

    rec = data.get("recommendation", {})
    if rec:
        parts.append(f"Original recommendation: {rec.get('type', 'unknown')} — {rec.get('title', '')} ({rec.get('summary', '')})")

    steps = data.get("executed_steps") or []
    if steps:
        step_descs = []
        for s in steps[:10]:
            desc = f"{s.get('name', '?')} ({s.get('duration_seconds', 0) // 60}min, {s.get('target_power', '?')}W, {s.get('role', '?')})"
            step_descs.append(desc)
        parts.append(f"Steps: {'; '.join(step_descs)}")

    if data.get("feedback"):
        parts.append(f"User feedback: {data['feedback']}")
    if data.get("perceived_effort") is not None:
        parts.append(f"Perceived effort: {data['perceived_effort']}/10")
    if data.get("user_note"):
        parts.append(f"User note: {data['user_note'][:200]}")

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
            parts.append(f"Pre-workout check-in: {', '.join(items)}")

    context = data.get("life_context") or []
    if context:
        parts.append(f"Life context: {', '.join(context[:5])}")

    tm = data.get("training_memory")
    if tm:
        items = []
        if "workouts_7d" in tm:
            items.append(f"{tm['workouts_7d']} workouts in 7d")
        if "hard_days_7d" in tm:
            items.append(f"{tm['hard_days_7d']} hard days")
        if tm.get("days_since_last") is not None:
            items.append(f"{tm['days_since_last']}d since last")
        if tm.get("intensity_load"):
            items.append(f"load estimate: {tm['intensity_load']}")
        if tm.get("returning_after_break"):
            items.append("returning after break")
        if tm.get("high_recent_load"):
            items.append("high recent load")
        if items:
            parts.append(f"Training context: {', '.join(items)}")

    return "\n".join(parts)


_DEFAULT_NEXT_TWO_DAYS: List[Dict[str, str]] = [
    {
        "day_label": "Tomorrow",
        "guidance": "Listen to your body and adjust accordingly.",
        "recommended_intensity": "flexible",
    },
    {
        "day_label": "Day after tomorrow",
        "guidance": "Another opportunity if you're feeling good.",
        "recommended_intensity": "flexible",
    },
]


def _fallback_response(data: Dict[str, Any]) -> Dict[str, Any]:
    ws = data.get("workout_summary", {})
    feedback = data.get("feedback")
    effort = data.get("perceived_effort")
    workout_type = ws.get("workout_type", "endurance")
    duration_min = (ws.get("duration_seconds") or 0) // 60

    parts = [f"Workout complete — {duration_min} minutes of {workout_type} work."]
    if feedback == "easy":
        parts.append("You rated this as easy, which is a good sign for building consistency.")
    elif feedback == "right":
        parts.append("Felt right — exactly where you want to be.")
    elif feedback == "hard":
        parts.append("This landed on the hard side. Recovery matters tomorrow.")
    elif feedback == "tooMuch":
        parts.append("You flagged this as too much. Take it easy the next couple of days.")

    is_hard = feedback in ("hard", "tooMuch") or (effort is not None and effort >= 8)
    is_quality = workout_type == "quality"

    if is_hard or is_quality:
        next_days = [
            {
                "day_label": "Tomorrow",
                "guidance": "Keep it easy. Recovery or light endurance if you feel like moving.",
                "recommended_intensity": "recovery",
            },
            {
                "day_label": "Day after tomorrow",
                "guidance": "If your legs feel good, you can pick up intensity again.",
                "recommended_intensity": "flexible",
            },
        ]
    else:
        next_days = [
            {
                "day_label": "Tomorrow",
                "guidance": "You have room for another session if you want it.",
                "recommended_intensity": "endurance",
            },
            {
                "day_label": "Day after tomorrow",
                "guidance": "A good opportunity for structured work if you're feeling fresh.",
                "recommended_intensity": "flexible",
            },
        ]

    return {
        "session_evaluation": " ".join(parts),
        "what_went_well": None,
        "watch_out": None,
        "next_two_days": next_days,
        "confidence": "low",
        "is_fallback": True,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


async def generate_reflection(data: Dict[str, Any]) -> Dict[str, Any]:
    client = _get_client()
    if client is None:
        logger.warning("OpenAI not configured, using fallback for reflection")
        return _fallback_response(data)

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
                max_tokens=500,
                temperature=0.7,
            ),
            timeout=TIMEOUT_SECONDS,
        )

        content = response.choices[0].message.content
        result = json.loads(content)

        if "sessionEvaluation" not in result:
            logger.warning("AI reflection missing sessionEvaluation")
            return _fallback_response(data)

        raw_days = result.get("nextTwoDays") or []
        if len(raw_days) != 2:
            logger.warning("AI reflection nextTwoDays has %d items, expected 2", len(raw_days))
            return _fallback_response(data)

        next_days = []
        for d in raw_days:
            next_days.append({
                "day_label": d.get("dayLabel", ""),
                "guidance": d.get("guidance", ""),
                "recommended_intensity": d.get("recommendedIntensity", "flexible"),
            })

        return {
            "session_evaluation": result["sessionEvaluation"],
            "what_went_well": result.get("whatWentWell"),
            "watch_out": result.get("watchOut"),
            "next_two_days": next_days,
            "confidence": result.get("confidence", "medium"),
            "is_fallback": False,
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }

    except asyncio.TimeoutError:
        logger.warning("OpenAI reflection request timed out")
        return _fallback_response(data)
    except json.JSONDecodeError:
        logger.warning("Failed to parse OpenAI reflection response as JSON")
        return _fallback_response(data)
    except Exception as e:
        logger.exception("AI reflection failed: %s", e)
        return _fallback_response(data)
