"""poll-service: rooms, polls, votes and results for the Pulse live audience app."""

import random
from collections.abc import Iterator
from contextlib import asynccontextmanager

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.db import create_tables, get_db
from app.models import Poll, Room, Vote, utcnow
from app.schemas import (
    ExportOut,
    PollCreate,
    PollOut,
    PollUpdate,
    ResultsOut,
    RoomCreate,
    RoomOut,
    VoteCreate,
)

# Ambiguous characters left out so a room code is readable from the back row.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


@asynccontextmanager
async def lifespan(app: FastAPI) -> Iterator[None]:
    create_tables()
    yield


app = FastAPI(title="Pulse poll-service", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

router = APIRouter(prefix=settings.api_prefix)


def require_presenter(x_presenter_token: str = Header(default="")) -> None:
    """Presenter-only actions: create rooms and polls, open or close a poll."""
    if x_presenter_token != settings.presenter_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Presenter token required.",
        )


def generate_code(db: Session) -> str:
    for _ in range(20):
        code = "".join(random.choices(CODE_ALPHABET, k=6))
        if db.scalar(select(Room).where(Room.code == code)) is None:
            return code
    raise HTTPException(status_code=500, detail="Could not allocate a room code.")


def get_room_or_404(db: Session, code: str) -> Room:
    room = db.scalar(select(Room).where(Room.code == code.upper()))
    if room is None:
        raise HTTPException(status_code=404, detail=f"No room with code {code.upper()}.")
    return room


def get_poll_or_404(db: Session, poll_id: int) -> Poll:
    poll = db.get(Poll, poll_id)
    if poll is None:
        raise HTTPException(status_code=404, detail="That poll does not exist.")
    return poll


def count_votes(db: Session, poll: Poll) -> ResultsOut:
    counts = [0] * len(poll.options)
    votes = db.scalars(select(Vote).where(Vote.poll_id == poll.id)).all()
    for vote in votes:
        if 0 <= vote.option_index < len(counts):
            counts[vote.option_index] += 1
    return ResultsOut(
        poll_id=poll.id,
        question=poll.question,
        options=list(poll.options),
        is_open=poll.is_open,
        counts=counts,
        total_votes=sum(counts),
    )


@app.get("/healthz")
@router.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "poll-service"}


@router.post("/rooms", response_model=RoomOut, status_code=201)
def create_room(
    payload: RoomCreate,
    db: Session = Depends(get_db),
    _: None = Depends(require_presenter),
) -> Room:
    code = payload.code or generate_code(db)
    if db.scalar(select(Room).where(Room.code == code)) is not None:
        raise HTTPException(status_code=409, detail=f"Room {code} already exists.")
    room = Room(code=code, title=payload.title)
    db.add(room)
    db.commit()
    db.refresh(room)
    return room


@router.get("/rooms/{code}", response_model=RoomOut)
def get_room(code: str, db: Session = Depends(get_db)) -> Room:
    return get_room_or_404(db, code)


@router.post("/rooms/{code}/polls", response_model=PollOut, status_code=201)
def create_poll(
    code: str,
    payload: PollCreate,
    db: Session = Depends(get_db),
    _: None = Depends(require_presenter),
) -> Poll:
    room = get_room_or_404(db, code)
    poll = Poll(
        room_id=room.id,
        question=payload.question,
        options=payload.options,
        is_open=payload.is_open,
    )
    db.add(poll)
    db.commit()
    db.refresh(poll)
    return poll


@router.patch("/polls/{poll_id}", response_model=PollOut)
def update_poll(
    poll_id: int,
    payload: PollUpdate,
    db: Session = Depends(get_db),
    _: None = Depends(require_presenter),
) -> Poll:
    poll = get_poll_or_404(db, poll_id)

    if payload.is_open:
        # A room has one open poll at a time: the audience view shows "the open
        # poll", so opening this one closes whichever was open before.
        db.execute(
            update(Poll)
            .where(
                Poll.room_id == poll.room_id,
                Poll.id != poll.id,
                Poll.is_open.is_(True),
            )
            .values(is_open=False)
        )

    poll.is_open = payload.is_open
    db.commit()
    db.refresh(poll)
    return poll


@router.post("/polls/{poll_id}/votes", response_model=ResultsOut, status_code=201)
def cast_vote(
    poll_id: int,
    payload: VoteCreate,
    db: Session = Depends(get_db),
) -> ResultsOut:
    poll = get_poll_or_404(db, poll_id)

    if not poll.is_open:
        raise HTTPException(status_code=409, detail="This poll is closed.")

    if payload.option_index >= len(poll.options):
        raise HTTPException(status_code=400, detail="That option does not exist.")

    already_voted = db.scalar(
        select(Vote).where(Vote.poll_id == poll.id, Vote.device_id == payload.device_id)
    )
    if already_voted is not None:
        raise HTTPException(status_code=409, detail="You have already voted in this poll.")

    db.add(Vote(poll_id=poll.id, option_index=payload.option_index, device_id=payload.device_id))
    try:
        db.commit()
    except IntegrityError:
        # Two taps racing each other: the unique constraint is the real guard.
        db.rollback()
        raise HTTPException(
            status_code=409, detail="You have already voted in this poll."
        ) from None

    return count_votes(db, poll)


@router.get("/polls/{poll_id}/results", response_model=ResultsOut)
def poll_results(poll_id: int, db: Session = Depends(get_db)) -> ResultsOut:
    return count_votes(db, get_poll_or_404(db, poll_id))


@router.get("/rooms/{code}/export", response_model=ExportOut)
def export_room(code: str, db: Session = Depends(get_db)) -> ExportOut:
    """Everything the CrewAI session report needs from the polls side."""
    room = get_room_or_404(db, code)
    return ExportOut(
        room_code=room.code,
        room_title=room.title,
        exported_at=utcnow(),
        polls=[count_votes(db, poll) for poll in room.polls],
    )


app.include_router(router)
