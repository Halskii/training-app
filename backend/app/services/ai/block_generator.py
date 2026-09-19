from app.schemas.athlete_file import MAX_TRAINING_DAYS, MIN_TRAINING_DAYS, AthleteFile
from app.schemas.block import DetailedBlock, WeekPrescription
from app.schemas.macrocycle import BlockSkeleton
from app.services.ai.anthropic_client import generate_structured
from app.services.ai.coach_persona import build_system_prompt

DEFAULT_DAYS_PER_WEEK = 4

TASK_INSTRUCTIONS = """\
Write the complete training block as a spreadsheet-style program: a set of \
training days, each day a table of exercises, and every exercise has its own \
prescription for EVERY week of the block. The athlete will read this on a \
phone and edit it, so be concrete and consistent.

WEEKLY SPLIT (decide this FIRST, and write it in weekly_split)
- Number of days: the athlete's training_days_per_week (use 4 if unknown).
- Design a real training split before choosing any exercise. Give every day \
ONE primary focus and spread the movement patterns across the week; do NOT \
cover every pattern every day. Typical splits:
  2 days: Full Body A / Full Body B.
  3 days: Full Body x3 with a different lift emphasized each day, or Lower / \
Upper / Full Body.
  4 days: Lower (squat focus) / Upper (press focus) / Lower (hinge focus) / \
Upper (pull focus, plus carries or conditioning).
  5 days: the 4-day split plus a day for events, carries/conditioning, or weak \
points.
- For strongman or other implement goals, give event and carry work a home: \
on the lower-body days, or on its own day when there are 5 days.
- weekly_split: one line per day naming its focus and the movement patterns \
allowed on it, e.g. "Day 1: Lower, squat focus - squat, single-leg, core. Day \
2: Upper, press focus - horizontal/vertical press, upper back, triceps."

DAY RULES (the most important rule in this task)
- Every exercise on a day MUST serve that day's focus. A squat or lower-body \
day contains NO bench press, rows, pulldowns or other upper-body pressing or \
pulling (core, carries, grip, calves and prehab are fine). An upper-body day \
contains NO squats or deadlifts. Only days explicitly titled "Full Body" mix \
upper and lower work.
- The title must describe what is actually on the day. Check each day against \
its title before you finish; if an exercise doesn't belong, replace it with one \
that does.
- The main lift for the day's focus comes first.

STRUCTURE
- Each day gets a short title naming its focus (e.g. "Day 1 - Squat & Core", \
"Day 2 - Upper Push").
- warmup: 2-4 sections per day chosen to suit that day (e.g. "Core", \
we always want the McGill Big 3 in warmups, and copenhagen planks at least on one workout per week for anyone over beginner level (injury permitting), \
"Isometrics", "Single Leg", "Loaded Mobility", "Shoulder Prep"). Each section \
has a prescription ("1 set each", "2 sets each (superset)") and concrete \
items with reps or time (e.g. "Bird Dog x10ea", "Copenhagen Plank 2x20sec each").
- exercises: typically 5-8 per day, in the order they are performed: main \
lift(s) first, then secondary lifts, then accessories, then optional \
carries/conditioning. Never more than 8 per day.
- Use specific, real movement names ("Front Squat", "Trap Bar Deadlift", \
"Seated Cable Row", "Sandbag Front Carry"), never categories like "squat \
variation".
- Supersets: give paired exercises the same group letter ("A" for the first \
pair, "B" for the next). Standalone exercises have group null.
- cue: one short, specific execution note (tempo, setup, what to feel). Keep \
the words the athlete needs, drop filler.

PRESCRIPTIONS (weeks list)
- weeks must contain EXACTLY one entry per week of the block, in order.
- sets: integer number of sets (or rounds). reps: a string - "5", "8-10", \
"3RM", "MAX", "50 ft EMOM", "30s on / 30s off", "15 min Zone 2". If work has \
no sets (steady cardio), leave sets null.
- effort: how hard or how heavy. Prefer RPE ("RPE 8"). Use % of 1RM only for \
main barbell lifts ("72-74%"), and when you do, say in that exercise's cue to \
use a conservative 1RM estimate. Accessories use RPE or progression cues \
("Add 5-10 lb", "Same weight as week 1", "Heavier").
- note: only for week-specific detail, e.g. "Backoff 1x3 @ 90% of top set".
- Progress sensibly across the weeks according to the block's phase and its \
volume/intensity trend from the skeleton: accumulation builds volume at \
moderate effort, intensification trades volume for heavier loads, realization \
tapers volume and peaks or tests. The final week may be a top set, a rep-max \
test, or a back-off week - whichever fits the phase.

ATHLETE FIT
- Respect the athlete's training level: beginners get simple, well-established \
exercise selections and conservative progression; seasoned athletes can take \
more specificity and intensity.
- Respect active injury flags: avoid or substitute movements likely to \
aggravate them, and mention how you adjusted in coach_note.
- If the athlete's goal involves strongman or another implement sport, work in \
carries, sandbag, or implement work appropriate to their level.
- If a prior block summary is provided, keep useful movements for continuity, \
progress the loading, and explain the change in coach_note. Otherwise this is \
the first block.

coach_note: 2-4 plain sentences to the athlete on the key decisions in this \
block (what it builds, what to watch for, injury adjustments). Always include it.
"""


def _fmt(rx: WeekPrescription) -> str:
    if rx.sets and rx.reps:
        scheme = f"{rx.sets}x{rx.reps}"
    else:
        scheme = rx.reps or (str(rx.sets) if rx.sets else "")
    return " ".join(p for p in (scheme, rx.effort) if p) or "-"


def summarize_block(detail: DetailedBlock) -> str:
    """Compact text of what a block programmed, fed to the next block's generator."""
    lines = [f"{detail.phase} block, weeks {detail.week_start}-{detail.week_end}"]
    for day in detail.days:
        lines.append(f"{day.title}:")
        for ex in day.exercises:
            if ex.weeks:
                first, last = _fmt(ex.weeks[0]), _fmt(ex.weeks[-1])
                lines.append(f"  - {ex.name}: week 1 {first} -> last week {last}")
    return "\n".join(lines)


def _normalize(
    block: DetailedBlock, skeleton: BlockSkeleton, num_weeks: int
) -> DetailedBlock:
    block.phase = skeleton.phase
    block.week_start = skeleton.week_start
    block.week_end = skeleton.week_end
    for i, day in enumerate(block.days, start=1):
        day.day_index = i
        for ex in day.exercises:
            ex.weeks = (ex.weeks + [WeekPrescription() for _ in range(num_weeks)])[
                :num_weeks
            ]
    return block


def generate_block(
    skeleton: BlockSkeleton,
    athlete_file: AthleteFile,
    block_number: int,
    prior_block_summary: str | None = None,
) -> DetailedBlock:
    num_weeks = max(1, skeleton.week_end - skeleton.week_start + 1)
    # Clamp so athletes saved before the 5-day cap still get a valid schedule.
    days = min(
        max(athlete_file.training_days_per_week or DEFAULT_DAYS_PER_WEEK, MIN_TRAINING_DAYS),
        MAX_TRAINING_DAYS,
    )

    system_prompt = build_system_prompt(TASK_INSTRUCTIONS)
    user_message = (
        f"Write block {block_number} of 3. It has {num_weeks} weeks and "
        f"{days} training days per week.\n\n"
        f"Block skeleton:\n{skeleton.model_dump_json(indent=2)}\n\n"
        f"Athlete file:\n{athlete_file.model_dump_json(indent=2)}\n\n"
        f"Prior block summary:\n{prior_block_summary or 'None - this is the first block.'}"
    )

    block = generate_structured(
        system_prompt=system_prompt,
        user_message=user_message,
        response_schema=DetailedBlock,
        max_tokens=16000,
    )
    return _normalize(block, skeleton, num_weeks)
