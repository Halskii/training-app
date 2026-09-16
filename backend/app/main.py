from fastapi import FastAPI

from app.routers import programs

app = FastAPI(title="Training App API")

app.include_router(programs.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
