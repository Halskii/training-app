from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.auth import current_user_id
from app.db import get_supabase
from app.schemas.athlete_file import MAX_TRAINING_DAYS, MIN_TRAINING_DAYS
from app.schemas.block import AdjustProposal, DetailedBlock
from app.schemas.macrocycle import MacrocycleSkeleton
from app.services import athlete_file_store
from app.services.ai.block_adjuster import adjust_block
from app.services.ai.block_generator import generate_block, summarize_block
from app.services.ai.macrocycle_planner import plan_macrocycle
from app.services.program_store import (
    BlockView,
    MacrocycleView,
    block_view,
    latest_macro_row,
    macrocycle_view,
    owned_block,
    sorted_block_rows,
    summarize_macrocycle,
)

router = APIRouter(prefix="/programs", tags=["programs"])

MAX_DAYS = MAX_TRAINING_DAYS
MAX_EXERCISES_PER_DAY = 30
MAX_WEEKS = 8


class PlanRequest(BaseModel):
    training_level: Literal["beginner", "intermediate", "seasoned"]
    training_age_years: float | None = Field(default=None, ge=0, le=80)
    training_days_per_week: int | None = Field(
        default=None, ge=MIN_TRAINING_DAYS, le=MAX_TRAINING_DAYS
    )
    # None leaves the saved injury note alone; "" clears it.
    injuries: str | None = Field(default=None, max_length=2000)


class AdjustRequest(BaseModel):
    request: str = Field(min_length=1, max_length=2000)
    is_injury: bool = True
    completed_weeks: int = Field(default=0, ge=0, le=MAX_WEEKS)


def _build_plan(
    user_id: str,
    req: PlanRequest,
    phase_number: int,
    previous_phase_summary: str | None,
) -> MacrocycleView:
    athlete_file_store.upsert_athlete_file(
        user_id, req.training_age_years, req.training_level, req.training_days_per_week
    )
    if req.injuries is not None:
        athlete_file_store.set_reported_injuries(user_id, req.injuries)
    athlete_file = athlete_file_store.build_athlete_file(user_id)
    if not athlete_file.goals:
        raise HTTPException(
            status_code=400, detail="Add at least one goal before creating a plan."
        )

    skeleton = plan_macrocycle(
        athlete_file,
        phase_number=phase_number,
        previous_phase_summary=previous_phase_summary,
    )

    sb = get_supabase()
    macro = (
        sb.table("macrocycles")
        .insert(
            {
                "user_id": user_id,
                "skeleton": skeleton.model_dump(mode="json"),
                "goal_ids": [g.id for g in athlete_file.goals],
                "phase_number": phase_number,
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

    return macrocycle_view(macro, sorted_block_rows(macro["id"]))


@router.post("/macrocycle", response_model=MacrocycleView)
def create_macrocycle(
    req: PlanRequest, user_id: str = Depends(current_user_id)
) -> MacrocycleView:
    """Start a brand-new plan from the athlete's saved goals (replaces the current one)."""
    return _build_plan(user_id, req, phase_number=1, previous_phase_summary=None)


@router.post("/macrocycle/next", response_model=MacrocycleView)
def create_next_phase(
    req: PlanRequest, user_id: str = Depends(current_user_id)
) -> MacrocycleView:
    """Plan the next 12-week phase, building on the latest one."""
    latest = latest_macro_row(user_id)
    if latest is None:
        raise HTTPException(status_code=404, detail="No existing plan to continue from")
    previous = macrocycle_view(latest, sorted_block_rows(latest["id"]))
    return _build_plan(
        user_id,
        req,
        phase_number=(latest.get("phase_number") or 1) + 1,
        previous_phase_summary=summarize_macrocycle(previous),
    )


@router.get("/macrocycle/latest", response_model=MacrocycleView)
def latest_macrocycle(user_id: str = Depends(current_user_id)) -> MacrocycleView:
    row = latest_macro_row(user_id)
    if row is None:
        raise HTTPException(status_code=404, detail="No macrocycle yet")
    return macrocycle_view(row, sorted_block_rows(row["id"]))


@router.post("/blocks/{block_id}/generate", response_model=BlockView)
def generate_block_detail(
    block_id: UUID,
    regenerate: bool = False,
    user_id: str = Depends(current_user_id),
) -> BlockView:
    block_row, macro_row, all_rows, index = owned_block(block_id, user_id)
    if block_row.get("detail") and not regenerate:
        raise HTTPException(
            status_code=409, detail="This block is already built (edits would be lost)"
        )

    skeleton = MacrocycleSkeleton.model_validate(macro_row["skeleton"])
    block_skeleton = skeleton.blocks[index]

    prior_summary = None
    if index > 0 and all_rows[index - 1].get("detail"):
        prior_summary = summarize_block(
            DetailedBlock.model_validate(all_rows[index - 1]["detail"])
        )

    detail = generate_block(
        block_skeleton,
        athlete_file_store.build_athlete_file(user_id),
        block_number=index + 1,
        prior_block_summary=prior_summary,
    )

    get_supabase().table("blocks").update(
        {"detail": detail.model_dump(mode="json"), "coach_note": detail.coach_note}
    ).eq("id", str(block_id)).execute()

    return block_view(block_skeleton, {**block_row, "detail": detail.model_dump()})


@router.post("/blocks/{block_id}/adjust", response_model=AdjustProposal)
def adjust_block_detail(
    block_id: UUID,
    req: AdjustRequest,
    user_id: str = Depends(current_user_id),
) -> AdjustProposal:
    """Propose a revision of a built block. Returns a preview; nothing is saved here."""
    block_row, macro_row, _all_rows, index = owned_block(block_id, user_id)
    if not block_row.get("detail"):
        raise HTTPException(
            status_code=409, detail="Build this block's workouts before adjusting them"
        )

    if req.is_injury:
        # Recorded up front: the injury is real even if the athlete discards the proposal.
        athlete_file_store.add_injury(user_id, req.request)

    skeleton = MacrocycleSkeleton.model_validate(macro_row["skeleton"])
    return adjust_block(
        current=DetailedBlock.model_validate(block_row["detail"]),
        skeleton=skeleton.blocks[index],
        athlete_file=athlete_file_store.build_athlete_file(user_id),
        request=req.request,
        completed_weeks=req.completed_weeks,
    )


@router.put("/blocks/{block_id}/detail", response_model=BlockView)
def save_block_detail(
    block_id: UUID,
    detail: DetailedBlock,
    user_id: str = Depends(current_user_id),
) -> BlockView:
    block_row, macro_row, _all_rows, index = owned_block(block_id, user_id)

    if (
        len(detail.days) > MAX_DAYS
        or any(len(d.exercises) > MAX_EXERCISES_PER_DAY for d in detail.days)
        or any(len(e.weeks) > MAX_WEEKS for d in detail.days for e in d.exercises)
    ):
        raise HTTPException(status_code=422, detail="Program is too large")

    get_supabase().table("blocks").update(
        {"detail": detail.model_dump(mode="json"), "coach_note": detail.coach_note}
    ).eq("id", str(block_id)).execute()

    skeleton = MacrocycleSkeleton.model_validate(macro_row["skeleton"])
    return block_view(skeleton.blocks[index], {**block_row, "detail": detail.model_dump()})
