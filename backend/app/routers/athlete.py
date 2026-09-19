from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException

from app.auth import current_user_id
from app.schemas.athlete_file import AthleteFile
from app.services import athlete_file_store

router = APIRouter(prefix="/athlete", tags=["athlete"])


@router.get("/me", response_model=AthleteFile)
def get_me(user_id: str = Depends(current_user_id)) -> AthleteFile:
    return athlete_file_store.build_athlete_file(user_id)


@router.post("/injuries/{injury_id}/resolve")
def resolve_injury(
    injury_id: UUID, user_id: str = Depends(current_user_id)
) -> dict[str, bool]:
    if not athlete_file_store.resolve_injury(user_id, str(injury_id)):
        raise HTTPException(status_code=404, detail="Injury not found")
    return {"resolved": True}
