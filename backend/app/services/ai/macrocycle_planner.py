from datetime import date

from app.schemas.athlete_file import AthleteFile
from app.schemas.macrocycle import MacrocycleSkeleton
from app.services.ai.anthropic_client import generate_structured
from app.services.ai.coach_persona import build_system_prompt

TASK_INSTRUCTIONS = """\
Plan a 12-week macrocycle split into exactly 3 blocks of 4 weeks each: \
accumulation, intensification, realization.

For each block, decide only the SHAPE of the plan: volume/intensity trend and \
movement focus areas. Do NOT prescribe specific exercises, sets, or reps here \
- that happens later, one block at a time, using real logged performance.

Base the shape on the athlete's goals, training level, and any active injury \
flags in their athlete file below.

TRAINING LEVEL (beginner / intermediate / seasoned) scopes what this 12 weeks \
can honestly accomplish, regardless of how ambitious the goal is:
- beginner: build the foundation first. Prioritize movement quality, general \
strength on the basic barbell/bodyweight patterns, and work capacity. Keep \
intensity moderate and progression conservative. Do NOT include \
sport-specific peaking or competition simulation, even if the goal is \
competitive - the realization block should be a controlled test of the \
foundational lifts, not a peak.
- intermediate: a mix of general and goal-specific work. Introduce \
goal-specific movements progressively; the realization block may include a \
modest, well-prepared test of goal-specific lifts.
- seasoned: can handle high specificity, higher intensities, and true \
peaking toward the goal.
If years of training conflicts with the stated level, trust the more \
conservative of the two.

If the goal is far beyond what the athlete's level allows in 12 weeks (e.g. a \
beginner aiming to win an elite competition), say so kindly and plainly in \
coach_note: frame these 12 weeks as the foundation stage of a longer road, \
and say what the next stage would be. Do not pretend the goal is achievable \
in this cycle, and do not shrink the goal itself.

INJURIES: the athlete may describe injuries or concerns in free text. \
Interpret them sensibly: steer the movement focus away from patterns likely \
to aggravate them, prefer substitutions, and mention how you adjusted in the \
relevant block's rationale. You are not diagnosing anything - if the \
description sounds serious (sharp pain, numbness, recent trauma), advise \
seeing a medical professional before training that area.

FEEDBACK: recent_feedback in the athlete file holds notes the athlete shared \
with their coach in chat, newest first (how training felt, stalls, pain, \
schedule or equipment limits, preferences). Let them shape the cycle and \
mention in coach_note when you acted on one.

GOALS: the athlete may have several goals (long-term, this phase, competition). \
Plan a cycle that serves them together, prioritizing goals that have a target \
date or are marked as this phase. If a goal has a target_date, use today's date \
to work out how many weeks remain and shape the cycle around it where a 12-week \
cycle allows; if the date is far beyond or well inside 12 weeks, say what that \
means for this cycle in coach_note.

NEXT PHASE: if a previous phase summary is provided, this cycle is a \
continuation, not a fresh start. Build on what was programmed: carry forward \
what suits the goals, progress toward more goal-specific work as the athlete's \
level allows, and don't simply repeat the last plan. Say in coach_note how this \
phase follows the last one.

coach_note: 2-4 plain sentences addressed to the athlete summarizing the \
overall approach for this cycle (including any level/goal realism framing and \
injury adjustments). Always include it.
"""


def plan_macrocycle(
    athlete_file: AthleteFile,
    phase_number: int = 1,
    previous_phase_summary: str | None = None,
) -> MacrocycleSkeleton:
    system_prompt = build_system_prompt(TASK_INSTRUCTIONS)
    parts = [
        f"Today's date: {date.today().isoformat()}",
        f"This is training phase number {phase_number}.",
        f"Athlete file:\n{athlete_file.model_dump_json(indent=2)}",
    ]
    if previous_phase_summary:
        parts.append(
            "Previous phase (as programmed, including any edits by the athlete):\n"
            f"{previous_phase_summary}"
        )
    user_message = "\n\n".join(parts)

    return generate_structured(
        system_prompt=system_prompt,
        user_message=user_message,
        response_schema=MacrocycleSkeleton,
    )
