from app.schemas.athlete_file import AthleteFile
from app.schemas.block import DetailedBlock
from app.schemas.macrocycle import BlockSkeleton
from app.services.ai.anthropic_client import generate_structured
from app.services.ai.coach_persona import build_system_prompt

TASK_INSTRUCTIONS = """\
Generate the full day-by-day program for ONE training block, given its \
skeleton (phase, volume/intensity trend, movement focus) and the athlete's \
current file (goals, injury flags, programming history).

Write specific exercises, sets, reps, and load guidance (RPE or %1RM). \
Include a short coach_note explaining the key decisions in plain language, \
e.g. referencing what changed since the last block and why.
"""


def generate_block(
    skeleton: BlockSkeleton,
    athlete_file: AthleteFile,
    prior_block_summary: str | None = None,
) -> DetailedBlock:
    system_prompt = build_system_prompt(TASK_INSTRUCTIONS)
    user_message = (
        f"Block skeleton:\n{skeleton.model_dump_json(indent=2)}\n\n"
        f"Athlete file:\n{athlete_file.model_dump_json(indent=2)}\n\n"
        f"Prior block summary:\n{prior_block_summary or 'None - this is the first block.'}"
    )

    return generate_structured(
        system_prompt=system_prompt,
        user_message=user_message,
        response_schema=DetailedBlock,
    )
