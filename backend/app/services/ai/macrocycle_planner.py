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

Base the shape on the athlete's goals and any active injury flags in their \
athlete file below.
"""


def plan_macrocycle(athlete_file: AthleteFile) -> MacrocycleSkeleton:
    system_prompt = build_system_prompt(TASK_INSTRUCTIONS)
    user_message = f"Athlete file:\n{athlete_file.model_dump_json(indent=2)}"

    return generate_structured(
        system_prompt=system_prompt,
        user_message=user_message,
        response_schema=MacrocycleSkeleton,
    )
