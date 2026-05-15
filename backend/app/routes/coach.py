from uuid import UUID

from fastapi import APIRouter, Depends

from app.routes.sync import get_current_user_id
from app.schemas import CoachExplanationRequest, CoachExplanationResponse
from app.services.ai_coach_service import generate_explanation

router = APIRouter(prefix="/v1/coach", tags=["coach"])


@router.post("/explanation", response_model=CoachExplanationResponse)
async def coach_explanation(
    body: CoachExplanationRequest,
    user_id: UUID = Depends(get_current_user_id),
):
    result = await generate_explanation(body.model_dump())
    return CoachExplanationResponse(**result)
