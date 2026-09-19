from pydantic import BaseModel

from app.schemas.athlete_file import AthleteFile
from app.schemas.block import AdjustProposal, DetailedBlock, WeekPrescription
from app.schemas.macrocycle import BlockSkeleton
from app.services.ai.anthropic_client import generate_structured
from app.services.ai.coach_persona import build_system_prompt

TASK_INSTRUCTIONS = """\
You are adjusting an existing training block for an athlete, the way a live \
coach would when something changes mid-block.

The athlete has told you what changed (a new injury or pain, missing \
equipment, an exercise they can't do or dislike). Make ONLY the changes the \
request requires. Keep every other exercise, the number and order of days, \
the warm-ups, supersets, cues, and every week's prescription exactly as they \
are. Return the complete revised block.

HOW TO ADJUST
- Injury or pain: swap or drop movements likely to aggravate it and replace \
them with pain-free alternatives that keep the training stimulus (same \
movement pattern where possible, otherwise a close substitute). Lower the \
load, range of motion or volume where that is the sensible adjustment. Keep \
training everything else. If the description sounds serious (sharp pain, \
numbness, recent trauma, pain at night), tell them to get it assessed by a \
medical professional; do not diagnose.
- Equipment or preference: substitute equivalent movements.
- Keep each day's focus intact: a replacement must fit the day it goes on (a \
swap on a squat day stays a lower-body movement; a swap on an upper day stays \
upper). Never move a day's work onto another day.
- Prescriptions for swapped exercises must cover every week of the block, in \
the same format as the rest of the program (sets, reps, effort).
- The first N weeks of the block are already completed (N is given). Do not \
change what was prescribed in completed weeks.

summary: 2-4 sentences to the athlete, in your coach voice: what you changed \
and why, and anything to watch for or tell you about. Do not list every edit; \
the app shows the exact list separately.
"""


class _LLMAdjustment(BaseModel):
    detail: DetailedBlock
    summary: str


def _key(name: str) -> str:
    return name.strip().lower()


def lock_completed_weeks(
    old: DetailedBlock, new: DetailedBlock, completed_weeks: int
) -> DetailedBlock:
    """Restore already-completed weeks so an adjustment only rewrites what's ahead."""
    if completed_weeks <= 0:
        return new
    for i, day in enumerate(new.days):
        old_by_name = (
            {_key(e.name): e for e in old.days[i].exercises} if i < len(old.days) else {}
        )
        for ex in day.exercises:
            prev = old_by_name.get(_key(ex.name))
            for w in range(min(completed_weeks, len(ex.weeks))):
                ex.weeks[w] = (
                    prev.weeks[w].model_copy()
                    if prev is not None and w < len(prev.weeks)
                    else WeekPrescription()
                )
    return new


def describe_changes(old: DetailedBlock, new: DetailedBlock) -> list[str]:
    """Factual list of edits between two versions of a block."""
    changes: list[str] = []
    for i, nd in enumerate(new.days):
        label = f"Day {i + 1}"
        if i >= len(old.days):
            changes.append(f"{label}: new day added")
            continue
        od = old.days[i]
        old_names = {_key(e.name): e.name for e in od.exercises}
        new_names = {_key(e.name): e.name for e in nd.exercises}
        removed = [n for k, n in old_names.items() if k not in new_names]
        added = [n for k, n in new_names.items() if k not in old_names]
        if removed and len(removed) == len(added):
            changes += [f"{label}: {r} -> {a}" for r, a in zip(removed, added)]
        else:
            changes += [f"{label}: removed {r}" for r in removed]
            changes += [f"{label}: added {a}" for a in added]
        old_by_name = {_key(e.name): e for e in od.exercises}
        for ex in nd.exercises:
            prev = old_by_name.get(_key(ex.name))
            if prev is None:
                continue
            if [w.model_dump() for w in prev.weeks] != [w.model_dump() for w in ex.weeks]:
                changes.append(f"{label}: adjusted {ex.name} (sets, reps or effort)")
            if (prev.cue or "").strip() != (ex.cue or "").strip():
                changes.append(f"{label}: updated cue for {ex.name}")
        if [s.model_dump() for s in od.warmup] != [s.model_dump() for s in nd.warmup]:
            changes.append(f"{label}: warm-up updated")
    for j in range(len(new.days), len(old.days)):
        changes.append(f"Day {j + 1}: removed")
    return changes or ["No exercise changes were needed."]


def adjust_block(
    current: DetailedBlock,
    skeleton: BlockSkeleton,
    athlete_file: AthleteFile,
    request: str,
    completed_weeks: int,
) -> AdjustProposal:
    system_prompt = build_system_prompt(TASK_INSTRUCTIONS)
    user_message = (
        f"Completed weeks in this block (N): {completed_weeks}\n\n"
        f"Athlete's request:\n{request.strip()}\n\n"
        f"Block skeleton:\n{skeleton.model_dump_json(indent=2)}\n\n"
        f"Athlete file:\n{athlete_file.model_dump_json(indent=2)}\n\n"
        f"Current block (revise this):\n{current.model_dump_json(indent=2)}"
    )
    result = generate_structured(
        system_prompt=system_prompt,
        user_message=user_message,
        response_schema=_LLMAdjustment,
        max_tokens=16000,
    )

    num_weeks = max(1, skeleton.week_end - skeleton.week_start + 1)
    revised = result.detail
    revised.phase = skeleton.phase
    revised.week_start = skeleton.week_start
    revised.week_end = skeleton.week_end
    for i, day in enumerate(revised.days, start=1):
        day.day_index = i
        for ex in day.exercises:
            ex.weeks = (ex.weeks + [WeekPrescription() for _ in range(num_weeks)])[
                :num_weeks
            ]
    revised = lock_completed_weeks(current, revised, completed_weeks)

    return AdjustProposal(
        detail=revised,
        summary=result.summary,
        changes=describe_changes(current, revised),
    )
