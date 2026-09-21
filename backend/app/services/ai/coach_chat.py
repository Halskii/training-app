from dataclasses import dataclass, field
from datetime import date

from app.schemas.athlete_file import AthleteFile
from app.schemas.block import DetailedBlock
from app.services.ai import anthropic_client
from app.services.ai.block_generator import format_rx
from app.services.ai.coach_persona import build_system_prompt
from app.services.program_store import MacrocycleView

MAX_HISTORY_MESSAGES = 30
MAX_FEEDBACK_PER_TURN = 3
MAX_SUGGESTIONS_PER_TURN = 2

CHAT_INSTRUCTIONS = """\
You are chatting with the athlete inside their training app. This is a \
conversation, not a document.

STYLE
- Talk like a real coach messaging an athlete: direct, warm, specific. Usually \
2-5 sentences; longer only when they ask for an explanation. Plain text only: \
no headings, no bullet lists, no markdown formatting, unless they ask for a list.
- Use what you know: their goals, level, injuries, where they are in the phase, \
and the actual workouts below. Refer to specific exercises, days and numbers \
from their program instead of generalities.
- Keep explanations tight: under about 120 words unless they ask for more detail.
- When explaining why something is in their program, ground it in what you can \
actually see: the overview, the block's volume, intensity and focus, and the \
cues. If the reason is not recorded, say what the exercise does for them and \
frame it as your read; do not invent a specific rationale (for example an \
injury-related reason for choosing an exercise) as if it were documented.
- If you need a tool, call it FIRST, before writing any reply text. Text \
written before a tool call is thrown away. After the tools have run, write \
your complete reply once.
- Only mention a button, or say a note was saved, if you called that tool in \
THIS turn and it returned success. If you did not call suggest_adjustment, do \
not tell the athlete to tap anything.
- Ask one short follow-up question when you need it to help (where exactly it \
hurts, during which lift, since when). Do not interrogate.
- You have NOT seen their training logs (the app does not record them yet). \
Never invent what they lifted or how they performed; ask.

WHAT YOU CAN DO
- Answer questions about their program: why something is there, how to \
perform it, how hard an RPE should feel, what to do when a weight feels off.
- save_feedback: when they tell you something concrete that should shape \
future programming (a lift felt too easy or too hard, a stall, pain, a \
schedule or equipment limit, a strong preference), save a note. Use judgment \
about whether it is reliable and useful. Skip small talk, vague moods, \
questions, and anything that would not change programming. Save at most a \
couple of notes per message. Do not announce that you saved a note; the app \
shows it.
- suggest_adjustment: when what they tell you means the current program should \
change (pain or injury on a movement, equipment they do not have, an exercise \
they cannot do), offer a change. You cannot edit the program yourself: this \
tool shows the athlete a button to review the exact changes and approve them. \
Tell them in a sentence what you would change and that they can tap the \
button to review it. Never say you have already changed the program.
- Pain or injury: take it seriously. Ask one clarifying question if it is \
unclear, offer the plan change, and if it sounds serious (sharp pain, numbness, \
swelling, pain at night, after a fall or a pop) tell them to have it assessed by \
a doctor or physio. Do not diagnose.

ONE MESSAGE AT A TIME
- Respond to the athlete's LATEST message first and directly. Earlier messages \
in the conversation were already handled: do not re-suggest changes or re-save \
notes for them, and do not repeat what you said before.
- Earlier replies of yours may end with bracketed lines such as "[Offered the \
athlete a button ...]" or "[Saved a note: ...]". Those show what the app did at \
the time: the buttons and notes already exist. Never write bracketed lines like \
these yourself.
- Use a tool only for something new in the latest message. A single message can \
raise more than one need; handle each with its own tool call.

WHAT YOU DO NOT DO
- No advice on PEDs, steroids, SARMs, or drug dosing or cycles, and no medical \
or medication advice. Say that is outside what you can help with and suggest a \
doctor. For supplements, do not give doses; you can cover training, sleep, food \
and recovery basics.
- Goals, a brand-new plan, and the next 12-week phase are handled in the app: \
the Goals tab for goals and a new plan, the Programs tab for the next phase. \
Point them there instead of doing it in chat.
- Stay on training. If asked about something unrelated, answer briefly or steer \
back.
"""

TOOLS = [
    {
        "name": "save_feedback",
        "description": (
            "Save a concise note about the athlete for future programming. Only for "
            "concrete, useful information."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "content": {
                    "type": "string",
                    "description": (
                        "One or two self-contained sentences in the third person, e.g. "
                        "'Front squat felt too easy at RPE 6 in week 2; wants heavier loads.'"
                    ),
                },
                "kind": {
                    "type": "string",
                    "enum": ["note", "injury"],
                    "description": "'injury' for pain or injury reports, otherwise 'note'.",
                },
            },
            "required": ["content", "kind"],
        },
    },
    {
        "name": "suggest_adjustment",
        "description": (
            "Offer the athlete a button to review a change to one built block. This does "
            "NOT change the program."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "block_number": {
                    "type": "integer",
                    "description": (
                        "Which block (1-3). Use the current block unless the change is "
                        "about another built block."
                    ),
                },
                "request": {
                    "type": "string",
                    "description": (
                        "What should change, written the way the athlete would tell a "
                        "coach and self-contained, e.g. 'My left shoulder hurts on "
                        "overhead pressing; keep training but avoid it.'"
                    ),
                },
                "is_injury": {
                    "type": "boolean",
                    "description": "True if this is a new injury or pain.",
                },
            },
            "required": ["block_number", "request", "is_injury"],
        },
    },
]


def current_week(start_date: str | None, today: date) -> int:
    """1-based week of the phase on `today`. Before the start date counts as week 1."""
    if not start_date:
        return 1
    days = (today - date.fromisoformat(start_date[:10])).days
    return 1 if days < 0 else days // 7 + 1


def _workouts_text(detail: DetailedBlock) -> str:
    lines = []
    for day in detail.days:
        lines.append(f"  {day.title}")
        for ex in day.exercises:
            group = f"[{ex.group}] " if ex.group else ""
            weeks = " | ".join(
                f"W{i}: {format_rx(w)}" for i, w in enumerate(ex.weeks, start=1)
            )
            cue = f"   (cue: {ex.cue})" if ex.cue else ""
            lines.append(f"    {group}{ex.name}: {weeks}{cue}")
    return "\n".join(lines)


def current_block_index(view: MacrocycleView | None, today: date) -> int | None:
    if view is None or not view.blocks:
        return None
    total = view.blocks[-1].week_end
    week = min(current_week(view.start_date, today), total)
    for i, b in enumerate(view.blocks):
        if b.week_start <= week <= b.week_end:
            return i
    return len(view.blocks) - 1


def program_text(view: MacrocycleView | None, today: date) -> str:
    if view is None:
        return "The athlete has no training plan yet."

    total = view.blocks[-1].week_end if view.blocks else 12
    week = current_week(view.start_date, today)
    status = (
        f"Week {week} of {total}"
        if week <= total
        else f"The {total}-week phase is finished (it has been {week} weeks)"
    )
    lines = [
        f"Today is {today.isoformat()}. Phase {view.phase_number}, {status}; "
        f"started {view.start_date or 'unknown'}.",
    ]
    if view.coach_note:
        lines.append(f"Overview you gave them: {view.coach_note}")

    current = current_block_index(view, today)
    for i, b in enumerate(view.blocks):
        marker = "  <- CURRENT BLOCK" if week <= total and i == current else ""
        lines.append(
            f"\nBlock {i + 1} ({b.phase}, weeks {b.week_start}-{b.week_end}){marker}\n"
            f"  Volume: {b.volume_trend}. Intensity: {b.intensity_trend}. "
            f"Focus: {', '.join(b.movement_focus)}."
        )
        if b.detail is None:
            lines.append("  Workouts are not built yet.")
        elif i == current:
            lines.append("  Workouts:\n" + _workouts_text(b.detail))
        else:
            titles = "; ".join(d.title for d in b.detail.days)
            lines.append(f"  Workouts built ({titles}).")
    return "\n".join(lines)


@dataclass
class CoachReply:
    text: str
    actions: list[dict]
    feedback: list[dict]  # notes to persist once the whole reply has succeeded


@dataclass
class _Toolbox:
    view: MacrocycleView | None
    current_index: int | None
    actions: list[dict] = field(default_factory=list)
    feedback: list[dict] = field(default_factory=list)

    def handle(self, name: str, args: dict) -> str:
        if name == "save_feedback":
            return self._save_feedback(args)
        if name == "suggest_adjustment":
            return self._suggest_adjustment(args)
        return f"Unknown tool {name}."

    def _save_feedback(self, args: dict) -> str:
        content = str(args.get("content", "")).strip()
        kind = "injury" if args.get("kind") == "injury" else "note"
        if not content:
            return "Nothing to save."
        if len(self.feedback) >= MAX_FEEDBACK_PER_TURN:
            return "Enough notes saved for this message."
        block_id = None
        if self.view and self.current_index is not None:
            block_id = self.view.blocks[self.current_index].block_id
        self.feedback.append({"kind": kind, "content": content[:500], "block_id": block_id})
        self.actions.append({"type": "feedback_saved", "kind": kind, "content": content[:500]})
        return "Saved."

    def _suggest_adjustment(self, args: dict) -> str:
        if self.view is None:
            return (
                "The athlete has no plan yet, so there is nothing to adjust. Suggest "
                "creating one in the Goals tab."
            )
        number = args.get("block_number")
        request = str(args.get("request", "")).strip()[:2000]
        if not isinstance(number, int) or not 1 <= number <= len(self.view.blocks):
            return "There is no such block."
        if not request:
            return "Missing request."
        block = self.view.blocks[number - 1]
        if block.detail is None:
            return (
                f"Block {number} has no workouts built yet, so it cannot be adjusted. "
                "Tell the athlete you will account for it when that block is built."
            )
        offered = [a for a in self.actions if a["type"] == "adjust_suggestion"]
        if any(a["block_id"] == block.block_id and a["request"] == request for a in offered):
            return "You already offered exactly that change in this reply."
        if len(offered) >= MAX_SUGGESTIONS_PER_TURN:
            return (
                "Enough changes offered for one message. Mention that they can bring "
                "up the rest next."
            )
        self.actions.append(
            {
                "type": "adjust_suggestion",
                "block_id": block.block_id,
                "block_number": number,
                "request": request,
                "is_injury": bool(args.get("is_injury")),
            }
        )
        return (
            f"Done: the athlete will see a button to review and approve your suggested "
            f"change to Block {number}. You have NOT changed the program. Tell them "
            "briefly what you would change and that they can tap the button."
        )


def _content_with_action_notes(row: dict) -> str:
    """A coach message plus bracketed notes on what the app did with it, so the model
    knows those buttons and notes already exist instead of re-issuing them."""
    notes = []
    for a in row.get("actions") or []:
        if a.get("type") == "adjust_suggestion":
            notes.append(
                f"[Offered the athlete a button to review a change to Block "
                f"{a.get('block_number')}: {a.get('request')}]"
            )
        elif a.get("type") == "feedback_saved":
            notes.append(f"[Saved a note: {a.get('content')}]")
    return "\n\n".join([row["content"], *notes])


def to_api_messages(history: list[dict]) -> list[dict]:
    """Stored chat rows -> API messages: must start with a user turn and alternate roles."""
    messages: list[dict] = []
    for row in history[-MAX_HISTORY_MESSAGES:]:
        role = "assistant" if row["role"] == "coach" else "user"
        content = _content_with_action_notes(row) if role == "assistant" else row["content"]
        if not messages and role == "assistant":
            continue
        if messages and messages[-1]["role"] == role:
            messages[-1]["content"] += "\n\n" + content
        else:
            messages.append({"role": role, "content": content})
    return messages


def coach_reply(
    *,
    athlete_file: AthleteFile,
    view: MacrocycleView | None,
    history: list[dict],
    user_text: str,
    today: date,
) -> CoachReply:
    toolbox = _Toolbox(view=view, current_index=current_block_index(view, today))
    system_prompt = (
        build_system_prompt(CHAT_INSTRUCTIONS)
        + "\n\nATHLETE FILE\n"
        + athlete_file.model_dump_json(indent=2)
        + "\n\nTHEIR PROGRAM\n"
        + program_text(view, today)
    )
    messages = to_api_messages(history)
    if messages and messages[-1]["role"] == "user":
        # Can't happen with pairs saved together, but the API requires alternation.
        messages[-1]["content"] += "\n\n" + user_text
    else:
        messages.append({"role": "user", "content": user_text})

    text = anthropic_client.chat_with_tools(
        system_prompt=system_prompt,
        messages=messages,
        tools=TOOLS,
        handle_tool=toolbox.handle,
    )
    if not text:
        text = (
            "I'd suggest a change to your program. Tap below to review it."
            if any(a["type"] == "adjust_suggestion" for a in toolbox.actions)
            else "Got it."
        )
    return CoachReply(text=text, actions=toolbox.actions, feedback=toolbox.feedback)
