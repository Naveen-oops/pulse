"""Seed room CIT22A with the three session polls.

Idempotent: re-running it resets votes and restores the three polls, which is
exactly what you want between rehearsals.

    python -m app.seed             # seed, keep existing votes
    python -m app.seed --reset     # seed and clear all votes
"""

import sys

from sqlalchemy import delete, select

from app.db import SessionLocal, create_tables
from app.models import Poll, Room, Vote

ROOM_CODE = "CIT22A"
ROOM_TITLE = "Build Smarter"

POLLS: list[dict] = [
    {
        "question": "Which AI coding tool have you used?",
        "options": [
            "None yet",
            "ChatGPT / Claude chat",
            "Copilot in the IDE",
            "Cursor / Claude Code",
        ],
        "is_open": True,
    },
    {
        "question": "How much of your code could AI write today?",
        "options": ["Almost none", "About a quarter", "About half", "Most of it"],
        "is_open": False,
    },
    {
        "question": "Biggest worry about AI in engineering education?",
        "options": [
            "Students stop learning fundamentals",
            "Wrong code that looks right",
            "Grading and academic integrity",
            "Falling behind industry",
        ],
        "is_open": False,
    },
]


def seed(reset_votes: bool = False) -> None:
    create_tables()
    with SessionLocal() as db:
        room = db.scalar(select(Room).where(Room.code == ROOM_CODE))
        if room is None:
            room = Room(code=ROOM_CODE, title=ROOM_TITLE)
            db.add(room)
            db.commit()
            db.refresh(room)
            print(f"Created room {ROOM_CODE}")
        else:
            print(f"Room {ROOM_CODE} already exists (id={room.id})")

        existing = {poll.question for poll in room.polls}
        for spec in POLLS:
            if spec["question"] in existing:
                continue
            db.add(Poll(room_id=room.id, **spec))
            print(f"Added poll: {spec['question']}")
        db.commit()

        if reset_votes:
            poll_ids = [poll.id for poll in room.polls]
            if poll_ids:
                db.execute(delete(Vote).where(Vote.poll_id.in_(poll_ids)))
                db.commit()
            print("Cleared all votes for this room")

        db.refresh(room)
        print(f"Room {room.code} '{room.title}' now has {len(room.polls)} polls")


if __name__ == "__main__":
    seed(reset_votes="--reset" in sys.argv)
