"""qa-service: questions, upvotes, moderation and export."""

from collections.abc import Iterator
from contextlib import asynccontextmanager
from datetime import timedelta

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import Select, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.db import create_tables, get_db
from app.models import Question, QuestionVote, utcnow
from app.schemas import ExportOut, QuestionCreate, QuestionOut, QuestionUpdate, VoteCreate

RATE_LIMIT = 5
RATE_WINDOW = timedelta(minutes=1)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> Iterator[None]:
    create_tables()
    yield


app = FastAPI(title="Pulse qa-service", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

router = APIRouter(prefix=settings.api_prefix)


def require_presenter(x_presenter_token: str = Header(default="")) -> None:
    """Presenter-only actions: hide a question or mark it answered."""
    if x_presenter_token != settings.presenter_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Presenter token required.",
        )


def _vote_count_column() -> Select[tuple[int]]:
    return (
        select(func.count())
        .where(QuestionVote.question_id == Question.id)
        .correlate(Question)
        .scalar_subquery()
    )


def sorted_questions(db: Session, room_code: str, *, include_hidden: bool) -> list[Question]:
    stmt = select(Question).where(Question.room_code == room_code)
    if not include_hidden:
        stmt = stmt.where(Question.is_hidden.is_(False))
    stmt = stmt.order_by(_vote_count_column().desc(), Question.created_at.desc())
    return list(db.scalars(stmt).all())


def to_out(db: Session, question: Question) -> QuestionOut:
    count = db.scalar(
        select(func.count())
        .select_from(QuestionVote)
        .where(QuestionVote.question_id == question.id)
    )
    return QuestionOut(
        id=question.id,
        room_code=question.room_code,
        text=question.text,
        vote_count=count or 0,
        is_hidden=question.is_hidden,
        is_answered=question.is_answered,
        created_at=question.created_at,
    )


def get_question_or_404(db: Session, question_id: int, *, visible_only: bool) -> Question:
    question = db.get(Question, question_id)
    if question is None or (visible_only and question.is_hidden):
        raise HTTPException(status_code=404, detail="That question does not exist.")
    return question


def validate_text(text: str) -> str:
    trimmed = text.strip()
    if len(trimmed) < 5:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Your question needs to be at least 5 characters.",
        )
    if len(trimmed) > 280:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Questions are limited to 280 characters.",
        )
    return trimmed


@app.get("/healthz")
@router.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "qa-service"}


@router.post("/rooms/{code}/questions", response_model=QuestionOut, status_code=201)
def create_question(
    code: str,
    payload: QuestionCreate,
    db: Session = Depends(get_db),
) -> QuestionOut:
    text = validate_text(payload.text)
    room_code = code.upper()
    cutoff = utcnow() - RATE_WINDOW
    recent = db.scalar(
        select(func.count())
        .select_from(Question)
        .where(Question.device_id == payload.device_id, Question.created_at >= cutoff)
    )
    if recent is not None and recent >= RATE_LIMIT:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="You are posting too quickly — try again in a moment.",
        )

    question = Question(room_code=room_code, text=text, device_id=payload.device_id)
    db.add(question)
    db.commit()
    db.refresh(question)
    return to_out(db, question)


@router.get("/rooms/{code}/questions", response_model=list[QuestionOut])
def list_questions(code: str, db: Session = Depends(get_db)) -> list[QuestionOut]:
    questions = sorted_questions(db, code.upper(), include_hidden=False)
    return [to_out(db, question) for question in questions]


@router.post("/questions/{question_id}/votes", response_model=QuestionOut, status_code=201)
def upvote_question(
    question_id: int,
    payload: VoteCreate,
    db: Session = Depends(get_db),
) -> QuestionOut:
    question = get_question_or_404(db, question_id, visible_only=True)

    if question.device_id == payload.device_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You cannot upvote your own question.",
        )

    already = db.scalar(
        select(QuestionVote).where(
            QuestionVote.question_id == question.id,
            QuestionVote.device_id == payload.device_id,
        )
    )
    if already is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You have already upvoted this question.",
        )

    db.add(QuestionVote(question_id=question.id, device_id=payload.device_id))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You have already upvoted this question.",
        ) from None

    db.refresh(question)
    return to_out(db, question)


@router.patch("/questions/{question_id}", response_model=QuestionOut)
def update_question(
    question_id: int,
    payload: QuestionUpdate,
    db: Session = Depends(get_db),
    _: None = Depends(require_presenter),
) -> QuestionOut:
    question = get_question_or_404(db, question_id, visible_only=False)
    if payload.is_hidden is not None:
        question.is_hidden = payload.is_hidden
    if payload.is_answered is not None:
        question.is_answered = payload.is_answered
    db.commit()
    db.refresh(question)
    return to_out(db, question)


@router.get("/rooms/{code}/questions/export", response_model=ExportOut)
def export_questions(code: str, db: Session = Depends(get_db)) -> ExportOut:
    room_code = code.upper()
    questions = sorted_questions(db, room_code, include_hidden=True)
    return ExportOut(
        room_code=room_code,
        exported_at=utcnow(),
        questions=[to_out(db, question) for question in questions],
    )


app.include_router(router)
