import logging

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.requests import Request

from app.config import get_settings
from app.routers import health, analysis

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("ai-service")

settings = get_settings()

app = FastAPI(
    title="HireAI AI Service",
    description="Internal AI service: resume parsing, matching, RAG, agents.",
    version="0.1.0",
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None,
)

# No CORS middleware on purpose: the only client is the Node backend,
# which is server-side and therefore not subject to CORS.

app.include_router(health.router)
app.include_router(analysis.router)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={"detail": {"message": "Validation failed", "errors": exc.errors()}},
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(
    request: Request, exc: Exception
) -> JSONResponse:
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": {"message": "Internal AI service error"}},
    )