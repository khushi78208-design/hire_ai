import json
import logging
import uuid
from typing import Any

from app.config import get_settings

logger = logging.getLogger("ai-service.assessment")

SYSTEM_PROMPT = """You write multiple-choice screening tests for a recruiter.

Rules you must follow:
- Every question has exactly 4 options and exactly one correct answer.
- Test practical, job-relevant knowledge. No trick questions, no trivia about \
version numbers or release dates.
- Wrong options must be plausible to someone who half-knows the topic. \
Obviously absurd options make the question worthless.
- Vary difficulty: roughly a third easy, a third moderate, a third harder.
- Keep each question under 30 words and each option under 12 words.
- Write a one-line explanation of why the correct answer is correct. The \
recruiter reads it while reviewing; the candidate never sees it.
- Never reference the company, the candidate, or anything outside the skills \
you were given.
- Cover the listed skills evenly rather than crowding around one of them.

Return ONLY valid JSON in this exact shape, no markdown fences:

{
  "questions": [
    {
      "question": "Which keyword prevents a class from being inherited in Java?",
      "options": ["static", "final", "abstract", "sealed"],
      "correct": 1,
      "topic": "Java",
      "explanation": "A final class cannot be extended."
    }
  ]
}

"correct" is the zero-based index of the right option.
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


def _validate_question(raw: Any) -> dict | None:
    """
    A malformed question is dropped rather than repaired. Guessing at a
    correct answer would silently mark candidates wrong.
    """
    if not isinstance(raw, dict):
        return None

    text = str(raw.get("question") or "").strip()
    options = raw.get("options")

    if not text or not isinstance(options, list) or len(options) != 4:
        return None

    options = [str(o).strip() for o in options]
    if any(not o for o in options) or len(set(options)) != 4:
        return None

    try:
        correct = int(raw.get("correct"))
    except (TypeError, ValueError):
        return None

    if correct < 0 or correct > 3:
        return None

    return {
        "id": uuid.uuid4().hex[:8],
        "question": text[:400],
        "options": [o[:120] for o in options],
        "correct": correct,
        "topic": str(raw.get("topic") or "").strip()[:60],
        "explanation": str(raw.get("explanation") or "").strip()[:300],
    }


def generate(
    job_title: str,
    skills: list[str],
    count: int = 10,
    experience_min: int = 0,
) -> list[dict]:
    settings = get_settings()

    if not settings.llm_api_key:
        raise RuntimeError("LLM_API_KEY is not configured")

    from google import genai
    from google.genai import types

    client = genai.Client(api_key=settings.llm_api_key)

    skill_line = ", ".join(skills) if skills else "general skills for this role"
    level = (
        "entry level"
        if experience_min <= 1
        else "mid level"
        if experience_min <= 4
        else "senior level"
    )

    prompt = (
        f"Role: {job_title}\n"
        f"Skills to test: {skill_line}\n"
        f"Candidate level: {level} ({experience_min}+ years)\n"
        f"Number of questions: {count}"
    )

    response = client.models.generate_content(
        model=settings.llm_model,
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            response_mime_type="application/json",
            # Some variety is wanted here — an identical test every time is
            # easy to leak between candidates.
            temperature=0.7,
        ),
    )

    try:
        raw = _clean_json(response.text or "")
    except json.JSONDecodeError:
        logger.error("Question generation returned unparseable JSON")
        raise RuntimeError("The assistant returned an invalid response")

    items = raw.get("questions")
    if not isinstance(items, list):
        raise RuntimeError("The assistant returned no questions")

    questions = [q for q in (_validate_question(i) for i in items) if q]

    if len(questions) < 3:
        raise RuntimeError("Could not generate enough valid questions")

    return questions[:count]