from pydantic import BaseModel


class WeekPrescription(BaseModel):
    """One exercise's prescription for one week (one cell of the program sheet)."""

    sets: int | None = None
    # Reps or any work descriptor: "5", "8-10", "3RM", "MAX", "50 ft EMOM",
    # "30s on / 30s off", "15 min Zone 2". Shown as "{sets} x {reps}" when sets is set.
    reps: str | None = None
    # Effort / load cue: "RPE 8", "72-74%", "Heavier", "wk1 weight", "Top set RPE 9".
    effort: str | None = None
    note: str | None = None  # week-specific detail, e.g. "Backoff 1x3 @ 90% top set"


class Exercise(BaseModel):
    name: str
    # Exercises sharing the same non-null group (e.g. "A") are a superset.
    group: str | None = None
    cue: str | None = None  # coaching cue shown in the Notes column
    weeks: list[WeekPrescription]  # exactly one entry per week of the block


class WarmupSection(BaseModel):
    title: str  # e.g. "Core", "Isometrics", "Single Leg", "Loaded Mobility"
    prescription: str | None = None  # e.g. "1 set each", "2 sets each (superset)"
    items: list[str]  # e.g. "Bird Dog x10ea"
    notes: str | None = None


class DayPlan(BaseModel):
    day_index: int  # 1-based within the block
    title: str  # e.g. "Day 1 - Squat & Carries"
    warmup: list[WarmupSection] = []
    exercises: list[Exercise]


class DetailedBlock(BaseModel):
    phase: str
    week_start: int
    week_end: int
    # Written before the days so the model settles each day's focus before filling it in.
    weekly_split: str = ""
    days: list[DayPlan]
    coach_note: str  # plain-language reasoning shown to the athlete


class AdjustProposal(BaseModel):
    """A proposed revision of a block. Nothing is saved until the athlete applies it."""

    detail: DetailedBlock
    summary: str  # coach's explanation of what changed and why
    changes: list[str]  # factual list of edits, computed by diffing old vs new
