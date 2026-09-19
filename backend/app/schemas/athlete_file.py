from pydantic import BaseModel


class InjuryFlag(BaseModel):
    area: str
    note: str
    active: bool


class Goal(BaseModel):
    id: str
    description: str
    kind: str  # "long_term" | "phase" | "competition"
    target_date: str | None = None
    competition_events: list[str] | None = None
    subtasks: list[str] = []


class AthleteFile(BaseModel):
    """Persistent, evolving per-user summary injected into every AI call.

    Updated after each block completes or on significant feedback events,
    not regenerated from scratch each time.
    """

    user_id: str
    training_age_years: float | None = None
    goals: list[Goal] = []
    injury_flags: list[InjuryFlag] = []
    rpe_trend_notes: str | None = None
    programming_style_notes: str | None = None
    last_updated: str
