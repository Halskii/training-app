from datetime import date
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.auth import current_user_id
from app.db import get_supabase
from app.services import athlete_file_store
from app.services.ai.coach_chat import MAX_HISTORY_MESSAGES, coach_reply
from app.services.program_store import latest_macrocycle_view

router = APIRouter(prefix="/coach", tags=["coach"])


class SendRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    today: date | None = None  # the athlete's local date, so "week 3" matches their calendar


class ChatMessage(BaseModel):
    id: str
    role: Literal["user", "coach"]
    content: str
    actions: list[dict[str, Any]] = []
    created_at: str


class SendResponse(BaseModel):
    user_message: ChatMessage
    coach_message: ChatMessage


def _to_message(row: dict) -> ChatMessage:
    return ChatMessage(
        id=row["id"],
        role=row["role"],
        content=row["content"],
        actions=row.get("actions") or [],
        created_at=str(row["created_at"]),
    )


def _recent_rows(user_id: str, limit: int) -> list[dict]:
    """The user's latest `limit` messages, oldest first."""
    rows = (
        get_supabase()
        .table("chat_messages")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
        .data
    )
    return list(reversed(rows))


def _local_today(claimed: date | None) -> date:
    server_today = date.today()
    if claimed is None or abs((claimed - server_today).days) > 2:
        return server_today
    return claimed


@router.get("/messages", response_model=list[ChatMessage])
def list_messages(
    limit: int = Query(default=50, ge=1, le=200),
    user_id: str = Depends(current_user_id),
) -> list[ChatMessage]:
    return [_to_message(r) for r in _recent_rows(user_id, limit)]


@router.post("/messages", response_model=SendResponse)
def send_message(
    req: SendRequest, user_id: str = Depends(current_user_id)
) -> SendResponse:
    text = req.message.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Message is empty")

    reply = coach_reply(
        athlete_file=athlete_file_store.build_athlete_file(user_id),
        view=latest_macrocycle_view(user_id),
        history=_recent_rows(user_id, MAX_HISTORY_MESSAGES),
        user_text=text,
        today=_local_today(req.today),
    )

    # Persist only after the whole reply succeeded, so a failed turn leaves nothing behind
    # and the athlete can simply retry.
    for note in reply.feedback:
        athlete_file_store.add_feedback(user_id, note["kind"], note["content"], note["block_id"])
    sb = get_supabase()
    user_row = (
        sb.table("chat_messages")
        .insert({"user_id": user_id, "role": "user", "content": text})
        .execute()
        .data[0]
    )
    coach_row = (
        sb.table("chat_messages")
        .insert(
            {
                "user_id": user_id,
                "role": "coach",
                "content": reply.text,
                "actions": reply.actions,
            }
        )
        .execute()
        .data[0]
    )
    return SendResponse(user_message=_to_message(user_row), coach_message=_to_message(coach_row))


@router.delete("/messages")
def clear_messages(user_id: str = Depends(current_user_id)) -> dict[str, int]:
    rows = get_supabase().table("chat_messages").delete().eq("user_id", user_id).execute().data
    return {"deleted": len(rows)}
