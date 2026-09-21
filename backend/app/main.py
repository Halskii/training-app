import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.routers import athlete, coach, goals, programs

logger = logging.getLogger("app")

app = FastAPI(title="Training App API")


# Added before CORS so it sits inside it: unhandled errors then still get CORS
# headers, and the browser shows the real error instead of "Failed to fetch".
@app.middleware("http")
async def catch_unhandled_errors(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception as e:
        logger.exception("Unhandled error on %s %s", request.method, request.url.path)
        detail = (
            f"{type(e).__name__}: {e}"
            if settings.environment == "development"
            else "Internal server error"
        )
        return JSONResponse(status_code=500, content={"detail": detail})


# Dev only: lets Flutter web (Chrome, random localhost port) call the API.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(programs.router)
app.include_router(athlete.router)
app.include_router(goals.router)
app.include_router(coach.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
