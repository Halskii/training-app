from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import programs

app = FastAPI(title="Training App API")

# Dev only: lets Flutter web (Chrome, random localhost port) call the API.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(programs.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
