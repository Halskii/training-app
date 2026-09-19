from datetime import datetime, timezone

from app.db import get_supabase
from app.schemas.athlete_file import AthleteFile, Goal, InjuryFlag


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def upsert_athlete_file(user_id: str, training_age_years: float | None) -> None:
    row: dict = {"user_id": user_id, "last_updated": _now()}
    if training_age_years is not None:
        row["training_age_years"] = training_age_years
    get_supabase().table("athlete_files").upsert(row).execute()


def add_goal(user_id: str, description: str, kind: str) -> str:
    res = (
        get_supabase()
        .table("goals")
        .insert({"user_id": user_id, "description": description, "kind": kind})
        .execute()
    )
    return res.data[0]["id"]


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
        goals=[
            Goal(
                id=g["id"],
                description=g["description"],
                kind=g["kind"],
                target_date=g.get("target_date"),
                competition_events=g.get("competition_events"),
                subtasks=g.get("subtasks") or [],
            )
            for g in goal_rows
        ],
        injury_flags=[
            InjuryFlag(area=i["area"], note=i["note"], active=i["active"])
            for i in injury_rows
        ],
        rpe_trend_notes=af.get("rpe_trend_notes"),
        programming_style_notes=af.get("programming_style_notes"),
        last_updated=af.get("last_updated") or _now(),
    )
