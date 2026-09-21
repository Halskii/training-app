"""Loading plans and blocks from the database, shared by the programs and coach routers."""

from uuid import UUID

from fastapi import HTTPException
from pydantic import BaseModel

from app.db import get_supabase
from app.schemas.block import DetailedBlock
from app.schemas.macrocycle import BlockSkeleton, MacrocycleSkeleton
from app.services.ai.block_generator import summarize_block


class BlockView(BlockSkeleton):
    block_id: str
    detail: DetailedBlock | None = None


class MacrocycleView(BaseModel):
    macrocycle_id: str
    coach_note: str = ""
    phase_number: int = 1
    start_date: str | None = None
    goal_ids: list[str] = []
    blocks: list[BlockView]


def sorted_block_rows(macrocycle_id: str) -> list[dict]:
    rows = (
        get_supabase()
        .table("blocks")
        .select("*")
        .eq("macrocycle_id", macrocycle_id)
        .execute()
        .data
    )
    return sorted(rows, key=lambda r: r["week_start"])


def block_view(skeleton: BlockSkeleton, row: dict) -> BlockView:
    detail = DetailedBlock.model_validate(row["detail"]) if row.get("detail") else None
    return BlockView(**skeleton.model_dump(), block_id=row["id"], detail=detail)


def macrocycle_view(macro_row: dict, block_rows: list[dict]) -> MacrocycleView:
    skeleton = MacrocycleSkeleton.model_validate(macro_row["skeleton"])
    return MacrocycleView(
        macrocycle_id=macro_row["id"],
        coach_note=skeleton.coach_note,
        phase_number=macro_row.get("phase_number") or 1,
        start_date=macro_row.get("start_date"),
        goal_ids=macro_row.get("goal_ids") or [],
        blocks=[block_view(sk, row) for sk, row in zip(skeleton.blocks, block_rows)],
    )


def latest_macro_row(user_id: str) -> dict | None:
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
    return rows[0] if rows else None


def latest_macrocycle_view(user_id: str) -> MacrocycleView | None:
    row = latest_macro_row(user_id)
    return macrocycle_view(row, sorted_block_rows(row["id"])) if row else None


def owned_block(block_id: UUID, user_id: str) -> tuple[dict, dict, list[dict], int]:
    """Load a block the user owns. Returns (block_row, macro_row, all_block_rows, index)."""
    sb = get_supabase()
    rows = sb.table("blocks").select("*").eq("id", str(block_id)).limit(1).execute().data
    macro_rows = (
        sb.table("macrocycles")
        .select("*")
        .eq("id", rows[0]["macrocycle_id"])
        .limit(1)
        .execute()
        .data
        if rows
        else []
    )
    # Same 404 for "missing" and "not yours" so block ids can't be probed.
    if not rows or not macro_rows or macro_rows[0]["user_id"] != user_id:
        raise HTTPException(status_code=404, detail="Block not found")
    all_rows = sorted_block_rows(macro_rows[0]["id"])
    index = next(i for i, r in enumerate(all_rows) if r["id"] == rows[0]["id"])
    return rows[0], macro_rows[0], all_rows, index


def summarize_macrocycle(view: MacrocycleView) -> str:
    parts = []
    for i, b in enumerate(view.blocks, start=1):
        if b.detail:
            parts.append(f"Block {i}: {summarize_block(b.detail)}")
        else:
            parts.append(
                f"Block {i}: {b.phase} block, weeks {b.week_start}-{b.week_end} "
                f"(workouts were never built). Volume: {b.volume_trend}. "
                f"Intensity: {b.intensity_trend}. Focus: {', '.join(b.movement_focus)}."
            )
    return "\n\n".join(parts)
