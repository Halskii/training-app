from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth import current_user_id
from app.db import get_supabase
from app.schemas.athlete_file import AthleteFile
from app.schemas.block import DetailedBlock
from app.schemas.macrocycle import BlockSkeleton, MacrocycleSkeleton
from app.services import athlete_file_store
from app.services.ai.block_generator import generate_block
from app.services.ai.macrocycle_planner import plan_macrocycle

router = APIRouter(prefix="/programs", tags=["programs"])


class PlanRequest(BaseModel):
    goal_description: str
    goal_kind: Literal["long_term", "phase", "competition"]
    training_age_years: float | None = None


@router.post("/macrocycle", response_model=MacrocycleSkeleton)
def create_macrocycle(
    req: PlanRequest, user_id: str = Depends(current_user_id)
) -> MacrocycleSkeleton:
    athlete_file_store.upsert_athlete_file(user_id, req.training_age_years)
    goal_id = athlete_file_store.add_goal(user_id, req.goal_description, req.goal_kind)
    athlete_file = athlete_file_store.build_athlete_file(user_id)

    skeleton = plan_macrocycle(athlete_file)

    sb = get_supabase()
    macro = (
        sb.table("macrocycles")
        .insert(
            {
                "user_id": user_id,
                "skeleton": skeleton.model_dump(mode="json"),
                "goal_ids": [goal_id],
            }
        )
        .execute()
        .data[0]
    )
    sb.table("blocks").insert(
        [
            {
                "macrocycle_id": macro["id"],
                "phase": b.phase,
                "week_start": b.week_start,
                "week_end": b.week_end,
            }
            for b in skeleton.blocks
        ]
    ).execute()

    return skeleton.model_copy(
        update={
            "user_id": user_id,
            "macrocycle_id": macro["id"],
            "goal_ids": [goal_id],
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
    )


@router.get("/macrocycle/latest", response_model=MacrocycleSkeleton)
def latest_macrocycle(user_id: str = Depends(current_user_id)) -> MacrocycleSkeleton:
    rows = (
        get_supabase()
        .table("macrocycles")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
        .data
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No macrocycle yet")
    row = rows[0]
    skeleton = MacrocycleSkeleton.model_validate(row["skeleton"])
    return skeleton.model_copy(
        update={
            "user_id": user_id,
            "macrocycle_id": row["id"],
            "goal_ids": row.get("goal_ids") or [],
        }
    )


@router.post("/block", response_model=DetailedBlock)
def create_block(
    skeleton: BlockSkeleton,
    athlete_file: AthleteFile,
    prior_block_summary: str | None = None,
    _user_id: str = Depends(current_user_id),
) -> DetailedBlock:
    return generate_block(skeleton, athlete_file, prior_block_summary)
