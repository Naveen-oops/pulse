"""The seed script runs between rehearsals, so it must be safe to run twice."""

from sqlalchemy import select

from app.db import SessionLocal
from app.models import Poll, Room, Vote
from app.seed import POLLS, ROOM_CODE, ROOM_TITLE, seed


def _room() -> Room:
    with SessionLocal() as db:
        room = db.scalar(select(Room).where(Room.code == ROOM_CODE))
        assert room is not None
        _ = room.polls  # load before the session closes
        return room


def test_seed_creates_the_session_room_and_polls() -> None:
    seed()
    room = _room()
    assert room.title == ROOM_TITLE
    assert len(room.polls) == len(POLLS) == 3
    assert room.polls[0].question == "Which AI coding tool have you used?"


def test_the_first_poll_is_open_and_the_rest_are_closed() -> None:
    """The presenter opens polls 2 and 3 live; only the first is ready to go."""
    seed()
    room = _room()
    assert [poll.is_open for poll in room.polls] == [True, False, False]


def test_every_seeded_poll_has_at_least_two_options() -> None:
    seed()
    for poll in _room().polls:
        assert len(poll.options) >= 2


def test_seeding_twice_does_not_duplicate_polls() -> None:
    seed()
    seed()
    assert len(_room().polls) == 3


def test_seed_without_reset_keeps_existing_votes() -> None:
    seed()
    poll_id = _room().polls[0].id
    with SessionLocal() as db:
        db.add(Vote(poll_id=poll_id, option_index=0, device_id="device-keep"))
        db.commit()

    seed()

    with SessionLocal() as db:
        assert db.scalars(select(Vote)).all() != []


def test_seed_with_reset_clears_votes_but_keeps_polls() -> None:
    seed()
    poll_id = _room().polls[0].id
    with SessionLocal() as db:
        db.add(Vote(poll_id=poll_id, option_index=0, device_id="device-clear"))
        db.commit()

    seed(reset_votes=True)

    with SessionLocal() as db:
        assert db.scalars(select(Vote)).all() == []
        assert len(db.scalars(select(Poll)).all()) == 3
