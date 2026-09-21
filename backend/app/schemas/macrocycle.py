from pydantic import BaseModel


class BlockSkeleton(BaseModel):
    """High-level shape of one 4-week block. No exercises yet."""

    phase: str  # "accumulation" | "intensification" | "realization"
    week_start: int
    week_end: int
    volume_trend: str  # e.g. "high, stable"
    intensity_trend: str  # e.g. "moderate, rising"
    movement_focus: list[str]  # e.g. ["squat pattern", "horizontal push"]
    rationale: str


class MacrocycleSkeleton(BaseModel):
    user_id: str
    macrocycle_id: str
    blocks: list[BlockSkeleton]  # exactly 3
    goal_ids: list[str]
    generated_at: str
    # Overall coach framing shown above the blocks (e.g. how realistic the goal is
    # for this athlete's level). Defaults to "" so older saved plans still load.
    coach_note: str = ""
