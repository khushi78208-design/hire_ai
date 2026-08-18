import base64
import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.auth import require_internal_secret
from app.services import matcher
from app.services.resume_parser import extract_text

logger = logging.getLogger("ai-service.analysis")

router = APIRouter(
    prefix="/analysis",
    tags=["analysis"],
    dependencies=[Depends(require_internal_secret)],
)


class AnalyseRequest(BaseModel):
    job: dict = Field(..., description="Job row: title, description, skills, ...")
    application: dict = Field(..., description="Application row from the form")
    resume_base64: str = Field(..., description="Raw resume file, base64 encoded")
    resume_filename: str = Field(default="resume.pdf")


@router.post("/match")
async def match(req: AnalyseRequest) -> dict:
    try:
        file_bytes = base64.b64decode(req.resume_base64)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"message": "Resume could not be decoded"},
        )

    resume_text = extract_text(file_bytes, req.resume_filename)

    # A scanned-image PDF extracts to nothing. Say so plainly rather than
    # asking the model to score an empty document.
    if len(resume_text) < 100:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "message": "Could not read text from this resume. "
                "It may be a scanned image or an unsupported format."
            },
        )

    try:
        result = matcher.analyse(req.job, req.application, resume_text)
    except RuntimeError as exc:
        logger.error("Analysis failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"message": str(exc)},
        )
    except Exception:
        logger.exception("Unexpected analysis failure")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"message": "The analysis service failed"},
        )

    return {"success": True, "data": result}