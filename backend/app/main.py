from fastapi import FastAPI

from app.routes.auth import router as auth_router
from app.routes.coach import router as coach_router
from app.routes.sync import router as sync_router

app = FastAPI(title="SmarterTraining API", version="0.1.0")

app.include_router(auth_router)
app.include_router(coach_router)
app.include_router(sync_router)


@app.get("/health")
async def health():
    return {"status": "ok"}
