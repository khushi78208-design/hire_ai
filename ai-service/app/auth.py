import hmac

from fastapi import Header, HTTPException, status

from app.config import get_settings


async def require_internal_secret(
    x_internal_secret: str | None = Header(default=None),
) -> None:
    settings = get_settings()
    expected = settings.internal_secret

    if not x_internal_secret or not hmac.compare_digest(
        x_internal_secret, expected
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"message": "Invalid or missing internal secret"},
        )
