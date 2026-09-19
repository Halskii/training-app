from pydantic import BaseModel


class ExercisePrescription(BaseModel):
    name: str
    sets: int
    reps: str  # e.g. "5" or "8-10"
    load_guidance: str  # e.g. "RPE 7" or "70% 1RM"
    notes: str | None = None


class DayPlan(BaseModel):
    day_index: int  # 1-based within the block
    focus: str
    exercises: list[ExercisePrescription]


class DetailedBlock(BaseModel):
    block_id: str
    macrocycle_id: str
    phase: str
    week_start: int
    week_end: int
    days: list[DayPlan]
    coach_note: str  # natural-language reasoning shown to the user
