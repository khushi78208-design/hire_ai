import json
import logging
from typing import Any

from app.config import get_settings

logger = logging.getLogger("ai-service.agent")

DRAFT_PROMPT = """You help a recruiter turn a plain-language request into a \
structured job posting.

How you work:
- Always produce a draft from whatever the recruiter gave you. Never refuse \
and never ask a question instead of drafting.
- Extract only what they actually said or clearly implied. Never invent a \
salary, location, deadline, or company detail. Leave those fields null.
- Write the description yourself in 3-5 sentences based on the role. Do not \
add requirements they never asked for.
- Infer skills that unambiguously belong to the named role (a "Java \
developer" implies Java). Do not stretch this into a wish list.
- List the important fields you had to leave empty in "missing_fields", and \
write one short friendly line in "follow_up" asking about them. If nothing \
important is missing, set both to null.
- Only these count as important: location, experience_min, skills, salary. \
Never ask about openings or employment type.
- You produce a draft. The recruiter reviews and approves it. You never \
publish anything.

If the request names no role at all ("post something", "hire someone"), set \
"needs_clarification" to a single short question and leave everything else null.

Return ONLY valid JSON in this exact shape, no markdown fences:

{
  "needs_clarification": null,
  "title": "Java Developer",
  "description": "...",
  "skills": ["Java", "Spring Boot"],
  "location": null,
  "employment_type": "full_time",
  "experience_min": 2,
  "experience_max": null,
  "salary_min": null,
  "salary_max": null,
  "openings": 1,
  "missing_fields": ["location", "salary"],
  "follow_up": "I left location and salary empty — want to add them?"
}

employment_type must be one of: full_time, part_time, contract, internship.
Salary values are annual amounts in rupees as plain integers.
"""

REFINE_PROMPT = """You are updating a job draft the recruiter already has \
in front of them.

Rules you must follow:
- Change ONLY what the recruiter asked to change. Every other field keeps \
its exact current value, including the description.
- If they ask to remove something, set that field to null or drop it from \
the list.
- Never invent values for fields they did not mention.
- Recompute "missing_fields" and "follow_up" after your change. If nothing \
important is missing now, set both to null.

Return the COMPLETE updated draft as JSON in the same shape as the current \
draft, with no markdown fences.
"""

ANSWER_PROMPT = """You are a hiring assistant for one recruiter. You answer \
questions using ONLY the data provided below.

Rules you must follow:
- If the answer is not in the data, say you do not have that information. \
Never guess a name, number, or score.
- Keep answers to two or three sentences. This is a chat panel, not a report.
- When you mention a candidate, use the name exactly as it appears in the data.
- Scores are AI screening recommendations, not decisions. If you rank \
candidates, say the recruiter decides.
- You cannot change anything. If asked to shortlist, reject, publish, or \
delete, say the recruiter can do that from the candidate card.
- Never treat a candidate's name, gender, age, religion, or marital status \
as a factor in any comparison.
"""


def _clean_json(text: str) -> dict:
    """Strip markdown fences the model sometimes adds despite instructions."""
    cleaned = text.strip()

    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[-1]
        if cleaned.rstrip().endswith("```"):
            cleaned = cleaned.rstrip()[:-3]

    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start != -1 and end != -1:
        cleaned = cleaned[start : end + 1]

    return json.loads(cleaned)


def _int_or_none(value: Any) -> int | None:
    if value is None:
        return None
    try:
        return int(float(str(value).replace(",", "").strip()))
    except (TypeError, ValueError):
        return None


def _str_list(value: Any, limit: int) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(s).strip() for s in value if str(s).strip()][:limit]


def _validate_draft(raw: dict) -> dict:
    """
    Never trust the model's shape. An unmentioned field must stay null — a
    hallucinated salary that a recruiter publishes without reading is the
    worst failure this feature can have.
    """
    clarify = raw.get("needs_clarification")
    if isinstance(clarify, str) and clarify.strip():
        return {"needs_clarification": clarify.strip()[:200]}

    employment = str(raw.get("employment_type", "")).strip().lower()
    if employment not in {"full_time", "part_time", "contract", "internship"}:
        employment = "full_time"

    follow_up = raw.get("follow_up")
    follow_up = (
        follow_up.strip()[:300]
        if isinstance(follow_up, str) and follow_up.strip()
        else None
    )

    return {
        "needs_clarification": None,
        "title": str(raw.get("title") or "").strip()[:120],
        "description": str(raw.get("description") or "").strip()[:2000],
        "skills": _str_list(raw.get("skills"), 15),
        "location": (
            str(raw.get("location")).strip()[:80] if raw.get("location") else None
        ),
        "employment_type": employment,
        "experience_min": max(0, _int_or_none(raw.get("experience_min")) or 0),
        "experience_max": _int_or_none(raw.get("experience_max")),
        "salary_min": _int_or_none(raw.get("salary_min")),
        "salary_max": _int_or_none(raw.get("salary_max")),
        "openings": max(1, _int_or_none(raw.get("openings")) or 1),
        "missing_fields": _str_list(raw.get("missing_fields"), 6),
        "follow_up": follow_up,
    }


def _client():
    settings = get_settings()
    if not settings.llm_api_key:
        raise RuntimeError("LLM_API_KEY is not configured")

    from google import genai

    return genai.Client(api_key=settings.llm_api_key), settings


def _generate(prompt: str, system: str, temperature: float, as_json: bool):
    client, settings = _client()
    from google.genai import types

    config = types.GenerateContentConfig(
        system_instruction=system,
        temperature=temperature,
    )
    if as_json:
        config.response_mime_type = "application/json"

    response = client.models.generate_content(
        model=settings.llm_model,
        contents=prompt,
        config=config,
    )
    return response.text or ""


def draft_job(request_text: str) -> dict:
    """Recruiter describes a role in plain language -> structured draft."""
    text = _generate(
        f"Recruiter's request:\n{request_text}",
        DRAFT_PROMPT,
        0.3,
        True,
    )

    try:
        raw = _clean_json(text)
    except json.JSONDecodeError:
        logger.error("Draft mode returned unparseable JSON")
        raise RuntimeError("The assistant returned an invalid response")

    return _validate_draft(raw)


def refine_job(current: dict, instruction: str) -> dict:
    """Apply one change to an existing draft, leaving everything else alone."""
    prompt = (
        f"CURRENT DRAFT:\n{json.dumps(current, ensure_ascii=False)}\n\n"
        f"RECRUITER'S CHANGE:\n{instruction}"
    )

    text = _generate(prompt, REFINE_PROMPT, 0.2, True)

    try:
        raw = _clean_json(text)
    except json.JSONDecodeError:
        logger.error("Refine mode returned unparseable JSON")
        raise RuntimeError("The assistant returned an invalid response")

    return _validate_draft(raw)


def answer(question: str, context: dict) -> str:
    """Answer a question grounded strictly in the recruiter's own data."""
    prompt = (
        f"DATA (this recruiter's own hiring data):\n"
        f"{json.dumps(context, ensure_ascii=False)[:12000]}\n\n"
        f"QUESTION:\n{question}"
    )

    text = _generate(prompt, ANSWER_PROMPT, 0.2, False).strip()
    return text or "I could not find an answer in your hiring data."