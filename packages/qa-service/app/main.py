"""qa-service — skeleton.

On `main` this service only answers /healthz. The Q&A feature (post a question,
upvote once per device, presenter hide/answer, export) is built live on stage from
`docs/specs/qa-feature.md`.

Do not implement Q&A here ahead of the session.
"""

from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings

app = FastAPI(title="Pulse qa-service", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

router = APIRouter(prefix=settings.api_prefix)


@app.get("/healthz")
@router.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "qa-service"}


app.include_router(router)
