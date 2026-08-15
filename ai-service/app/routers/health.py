from fastapi import APIRouter, Depends

from app.auth import require_internal_secret
from app.config import get_settings

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "ai-service"}


@router.get("/health/ready", dependencies=[Depends(require_internal_secret)])
async def ready() -> dict:
    settings = get_settings()
    return {
        "status": "ready",
        "environment": settings.environment,
        "llm_configured": settings.llm_api_key is not None,
        "model": settings.llm_model,
    }
