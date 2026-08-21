import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.auth import require_internal_secret
from app.services import agent

logger = logging.getLogger("ai-service.agent")

router = APIRouter(
    prefix="/agent",
    tags=["agent"],
    dependencies=[Depends(require_internal_secret)],
)


class DraftRequest(BaseModel):
    message: str = Field(..., min_length=3, max_length=2000)


class RefineRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    draft: dict = Field(...)


class AnswerRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    context: dict = Field(default_factory=dict)


def _guard(fn, *args):
    try:
        return fn(*args)
    except RuntimeError as exc:
        logger.error("Agent call failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"message": str(exc)},
        )
    except Exception:
        logger.exception("Unexpected agent failure")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"message": "The assistant is unavailable"},
        )


@router.post("/draft-job")
async def draft_job(req: DraftRequest) -> dict:
    return {"success": True, "data": _guard(agent.draft_job, req.message)}


@router.post("/refine-job")
async def refine_job(req: RefineRequest) -> dict:
    return {
        "success": True,
        "data": _guard(agent.refine_job, req.draft, req.message),
    }


@router.post("/answer")
async def answer(req: AnswerRequest) -> dict:
    text = _guard(agent.answer, req.message, req.context)
    return {"success": True, "data": {"answer": text}}