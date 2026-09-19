from datetime import date, datetime, timezone

from app.db import get_supabase
from app.schemas.athlete_file import AthleteFile, Goal, InjuryFlag


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


REPORTED_INJURY_AREA = "Athlete-reported"
NEW_INJURY_AREA = "New injury"


def upsert_athlete_file(
    user_id: str,
    training_age_years: float | None,
    training_level: str | None,
    training_days_per_week: int | None,
) -> None:
    row: dict = {"user_id": user_id, "last_updated": _now()}
    if training_age_years is not None:
        row["training_age_years"] = training_age_years
    if training_level is not None:
        row["training_level"] = training_level
    if training_days_per_week is not None:
        row["training_days_per_week"] = training_days_per_week
    get_supabase().table("athlete_files").upsert(row).execute()


def set_reported_injuries(user_id: str, text: str | None) -> None:
    """Replace the athlete's plan-setup injury note (empty text clears it)."""
    sb = get_supabase()
    (
        sb.table("injury_flags")
        .update({"active": False})
        .eq("user_id", user_id)
        .eq("area", REPORTED_INJURY_AREA)
        .eq("active", True)
        .execute()
    )
    if text and text.strip():
        sb.table("injury_flags").insert(
            {
                "user_id": user_id,
                "area": REPORTED_INJURY_AREA,
                "note": text.strip(),
                "active": True,
            }
        ).execute()


def add_injury(user_id: str, note: str) -> None:
    """Record a new injury reported mid-plan. Identical active notes aren't duplicated."""
    note = note.strip()
    sb = get_supabase()
    existing = (
        sb.table("injury_flags")
        .select("id")
        .eq("user_id", user_id)
        .eq("note", note)
        .eq("active", True)
        .limit(1)
        .execute()
        .data
    )
    if existing:
        return
    sb.table("injury_flags").insert(
        {"user_id": user_id, "area": NEW_INJURY_AREA, "note": note, "active": True}
    ).execute()


def resolve_injury(user_id: str, injury_id: str) -> bool:
    rows = (
        get_supabase()
        .table("injury_flags")
        .update({"active": False})
        .eq("id", injury_id)
        .eq("user_id", user_id)
        .execute()
        .data
    )
    return bool(rows)


def _goal_from_row(g: dict) -> Goal:
    return Goal(
        id=g["id"],
        description=g["description"],
        kind=g["kind"],
        target_date=g.get("target_date"),
        competition_events=g.get("competition_events"),
        subtasks=g.get("subtasks") or [],
    )


def _goal_fields(
    description: str,
    kind: str,
    target_date: date | None,
    competition_events: list[str] | None,
) -> dict:
    return {
        "description": description.strip(),
        "kind": kind,
        "target_date": target_date.isoformat() if target_date else None,
        "competition_events": (
            [e.strip() for e in competition_events if e.strip()][:20]
            if kind == "competition" and competition_events
            else None
        ),
    }


def add_goal(
    user_id: str,
    description: str,
    kind: str,
    target_date: date | None = None,
    competition_events: list[str] | None = None,
) -> Goal:
    row = (
        get_supabase()
        .table("goals")
        .insert(
            {
                "user_id": user_id,
                **_goal_fields(description, kind, target_date, competition_events),
            }
        )
        .execute()
        .data[0]
    )
    return _goal_from_row(row)


def update_goal(
    user_id: str,
    goal_id: str,
    description: str,
    kind: str,
    target_date: date | None,
    competition_events: list[str] | None,
) -> Goal | None:
    rows = (
        get_supabase()
        .table("goals")
        .update(_goal_fields(description, kind, target_date, competition_events))
        .eq("id", goal_id)
        .eq("user_id", user_id)
        .execute()
        .data
    )
    return _goal_from_row(rows[0]) if rows else None


def delete_goal(user_id: str, goal_id: str) -> bool:
    rows = (
        get_supabase()
        .table("goals")
        .delete()
        .eq("id", goal_id)
        .eq("user_id", user_id)
        .execute()
        .data
    )
    return bool(rows)


def build_athlete_file(user_id: str) -> AthleteFile:
    sb = get_supabase()
    af_rows = sb.table("athlete_files").select("*").eq("user_id", user_id).limit(1).execute().data
    af = af_rows[0] if af_rows else {}

    goal_rows = (
        sb.table("goals")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
        .data
    )
    injury_rows = (
        sb.table("injury_flags")
        .select("*")
        .eq("user_id", user_id)
        .eq("active", True)
        .execute()
        .data
    )

    return AthleteFile(
        user_id=user_id,
        training_age_years=af.get("training_age_years"),
        training_level=af.get("training_level"),
        training_days_per_week=af.get("training_days_per_week"),
        goals=[_goal_from_row(g) for g in goal_rows],
        injury_flags=[
            InjuryFlag(id=i["id"], area=i["area"], note=i["note"], active=i["active"])
            for i in injury_rows
        ],
        rpe_trend_notes=af.get("rpe_trend_notes"),
        programming_style_notes=af.get("programming_style_notes"),
        last_updated=af.get("last_updated") or _now(),
    )
