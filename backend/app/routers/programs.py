from fastapi import APIRouter

from app.schemas.athlete_file import AthleteFile
from app.schemas.block import DetailedBlock
from app.schemas.macrocycle import BlockSkeleton, MacrocycleSkeleton
from app.services.ai.block_generator import generate_block
from app.services.ai.macrocycle_planner import plan_macrocycle

router = APIRouter(prefix="/programs", tags=["programs"])


@router.post("/macrocycle", response_model=MacrocycleSkeleton)
def create_macrocycle(athlete_file: AthleteFile) -> MacrocycleSkeleton:
    return plan_macrocycle(athlete_file)


@router.post("/block", response_model=DetailedBlock)
def create_block(
    skeleton: BlockSkeleton,
    athlete_file: AthleteFile,
    prior_block_summary: str | None = None,
) -> DetailedBlock:
    return generate_block(skeleton, athlete_file, prior_block_summary)
