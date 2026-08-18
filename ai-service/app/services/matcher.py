import json
import logging
from typing import Any

from app.config import get_settings

logger = logging.getLogger("ai-service.matcher")

SYSTEM_PROMPT = """You are a recruitment screening assistant. You compare a \
candidate's resume against a job's requirements and return a structured \
assessment.

Rules you must follow:
- Judge only on evidence present in the resume. Never invent experience.
- A skill counts as matched if the resume shows real use of it, even when the \
exact word is absent (e.g. "built SPAs with hooks and Redux" evidences React).
- A skill listed only in an "interests" or "familiar with" section is weak \
evidence, not a match.
- Never consider name, gender, age, caste, religion, marital status, or \
photographs. If the resume contains them, ignore them entirely.
- You produce a recommendation, not a decision. A human recruiter decides.

Return ONLY valid JSON matching this exact shape, with no markdown fences:

{
  "overall_score": 0-100,
  "skill_score": 0-100,
  "experience_score": 0-100,
  "education_score": 0-100,
  "project_score": 0-100,
  "recommendation": "strong_match" | "review_required" | "low_match",
  "matched_skills": ["..."],
  "missing_skills": ["..."],
  "strengths": ["short phrase", "..."],
  "concerns": ["short phrase", "..."],
  "summary": "One or two sentences explaining the score, citing concrete \
evidence from the resume.",
  "location_note": "One short line about location fit."
}

Scoring guide:
- 80-100 strong_match: meets nearly all required skills and the experience bar
- 50-79  review_required: partial fit, worth a human look
- 0-49   low_match: missing most requirements

Keep strengths and concerns to at most 3 items each, phrased in under 12 words.
"""


def _build_user_prompt(job: dict, application: dict, resume_text: str) -> str:
    skills = ", ".join(job.get("skills") or []) or "not specified"

    exp_line = f"{job.get('experience_min', 0)}+ years"
    if job.get("experience_max"):
        exp_line = f"{job.get('experience_min', 0)}-{job['experience_max']} years"

    city = application.get("current_city") or "not stated"
    relocate = "yes" if application.get("willing_to_relocate") else "no"

    return f"""JOB
Title: {job.get('title')}
Location: {job.get('location') or 'not specified'}
Required skills: {skills}
Experience required: {exp_line}
Description:
{job.get('description') or ''}

Additional requirements:
{job.get('requirements') or 'none stated'}

CANDIDATE (self-reported on the application form)
Qualification: {application.get('qualification') or 'not stated'}
Stated experience: {application.get('experience_years', 0)} years
Current city: {city}
Willing to relocate: {relocate}

RESUME TEXT
{resume_text}
"""


def _coerce(value: Any, lo: int = 0, hi: int = 100, default: int = 0) -> int:
    """Models occasionally return "82%" or 8.2 — clamp everything to a sane int."""
    try:
        num = int(round(float(str(value).strip().rstrip("%"))))
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, num))


def _string_list(value: Any, limit: int = 12) -> list[str]:
    if not isinstance(value, list):
        return []
    out = [str(v).strip() for v in value if str(v).strip()]
    return out[:limit]


def _validate(raw: dict) -> dict:
    """
    Never trust the model's shape. Every field is coerced, so a malformed
    response degrades instead of crashing the request or poisoning the DB.
    """
    overall = _coerce(raw.get("overall_score"))

    rec = str(raw.get("recommendation", "")).strip().lower()
    if rec not in {"strong_match", "review_required", "low_match"}:
        # Derive it from the score rather than guessing.
        rec = (
            "strong_match" if overall >= 80
            else "review_required" if overall >= 50
            else "low_match"
        )

    return {
        "overall_score": overall,
        "skill_score": _coerce(raw.get("skill_score"), default=overall),
        "experience_score": _coerce(raw.get("experience_score"), default=overall),
        "education_score": _coerce(raw.get("education_score"), default=overall),
        "project_score": _coerce(raw.get("project_score"), default=overall),
        "recommendation": rec,
        "matched_skills": _string_list(raw.get("matched_skills")),
        "missing_skills": _string_list(raw.get("missing_skills")),
        "strengths": _string_list(raw.get("strengths"), limit=3),
        "concerns": _string_list(raw.get("concerns"), limit=3),
        "summary": str(raw.get("summary") or "").strip()[:800],
        "location_note": str(raw.get("location_note") or "").strip()[:300],
    }


def _parse_json(text: str) -> dict:
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


def analyse(job: dict, application: dict, resume_text: str) -> dict:
    settings = get_settings()

    if not settings.llm_api_key:
        raise RuntimeError("LLM_API_KEY is not configured")

    from google import genai
    from google.genai import types

    client = genai.Client(api_key=settings.llm_api_key)

    response = client.models.generate_content(
        model=settings.llm_model,
        contents=_build_user_prompt(job, application, resume_text),
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            response_mime_type="application/json",
            temperature=0.2,  # screening should be repeatable, not creative
        ),
    )

    text = response.text or ""

    try:
        raw = _parse_json(text)
    except json.JSONDecodeError:
        logger.error("Model returned unparseable JSON: %s", text[:500])
        raise RuntimeError("The model returned an invalid response")

    result = _validate(raw)
    result["model"] = settings.llm_model
    return result