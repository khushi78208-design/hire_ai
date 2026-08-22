import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.auth import require_internal_secret
from app.services import assessment

logger = logging.getLogger("ai-service.assessment")

router = APIRouter(
    prefix="/assessment",
    tags=["assessment"],
    dependencies=[Depends(require_internal_secret)],
)


class GenerateRequest(BaseModel):
    job_title: str = Field(..., min_length=2, max_length=200)
    skills: list[str] = Field(default_factory=list)
    count: int = Field(default=10, ge=3, le=25)
    experience_min: int = Field(default=0, ge=0, le=30)


@router.post("/generate")
async def generate(req: GenerateRequest) -> dict:
    try:
        questions = assessment.generate(
            req.job_title,
            req.skills,
            req.count,
            req.experience_min,
        )
    except RuntimeError as exc:
        logger.error("Generation failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"message": str(exc)},
        )
    except Exception:
        logger.exception("Unexpected generation failure")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"message": "Could not generate questions"},
        )

    return {"success": True, "data": {"questions": questions}}