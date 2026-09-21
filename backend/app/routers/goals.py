from datetime import date
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.auth import current_user_id
from app.schemas.athlete_file import Goal
from app.services import athlete_file_store

router = APIRouter(prefix="/goals", tags=["goals"])


class GoalIn(BaseModel):
    description: str = Field(min_length=1, max_length=500)
    kind: Literal["long_term", "phase", "competition"]
    target_date: date | None = None
    competition_events: list[str] | None = Field(default=None, max_length=20)


@router.post("", response_model=Goal)
def create_goal(body: GoalIn, user_id: str = Depends(current_user_id)) -> Goal:
    return athlete_file_store.add_goal(
        user_id, body.description, body.kind, body.target_date, body.competition_events
    )


@router.put("/{goal_id}", response_model=Goal)
def update_goal(
    goal_id: UUID, body: GoalIn, user_id: str = Depends(current_user_id)
) -> Goal:
    goal = athlete_file_store.update_goal(
        user_id,
        str(goal_id),
        body.description,
        body.kind,
        body.target_date,
        body.competition_events,
    )
    if goal is None:
        raise HTTPException(status_code=404, detail="Goal not found")
    return goal


@router.delete("/{goal_id}")
def delete_goal(goal_id: UUID, user_id: str = Depends(current_user_id)) -> dict[str, bool]:
    if not athlete_file_store.delete_goal(user_id, str(goal_id)):
        raise HTTPException(status_code=404, detail="Goal not found")
    return {"deleted": True}
