from uuid import UUID

from fastapi import APIRouter, Depends

from app.auth import get_current_user_id
from app.schemas import (
    CoachExplanationRequest,
    CoachExplanationResponse,
    PostWorkoutReflectionRequest,
    PostWorkoutReflectionResponse,
)
from app.services.ai_coach_service import generate_explanation
from app.services.ai_reflection_service import generate_reflection

router = APIRouter(prefix="/v1/coach", tags=["coach"])


@router.post("/explanation", response_model=CoachExplanationResponse)
async def coach_explanation(
    body: CoachExplanationRequest,
    user_id: UUID = Depends(get_current_user_id),
):
    result = await generate_explanation(body.model_dump())
    return CoachExplanationResponse(**result)


@router.post("/post-workout-reflection", response_model=PostWorkoutReflectionResponse)
async def post_workout_reflection(
    body: PostWorkoutReflectionRequest,
    user_id: UUID = Depends(get_current_user_id),
):
    result = await generate_reflection(body.model_dump())
    return PostWorkoutReflectionResponse(**result)
