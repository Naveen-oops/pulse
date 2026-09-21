"""Unit tests for the logic that does not need an HTTP request."""

import pytest
from fastapi import HTTPException

from app.db import SessionLocal
from app.main import CODE_ALPHABET, count_votes, generate_code, get_poll_or_404, get_room_or_404
from app.models import Poll, Room, Vote


@pytest.fixture
def db():
    with SessionLocal() as session:
        yield session


@pytest.fixture
def poll(db) -> Poll:
    room = Room(code="UNIT01", title="Unit test room")
    db.add(room)
    db.commit()
    poll = Poll(room_id=room.id, question="Q?", options=["A", "B", "C"], is_open=True)
    db.add(poll)
    db.commit()
    db.refresh(poll)
    return poll


class TestGenerateCode:
    def test_code_is_six_characters_from_the_safe_alphabet(self, db) -> None:
        code = generate_code(db)
        assert len(code) == 6
        assert set(code) <= set(CODE_ALPHABET)

    def test_alphabet_excludes_confusable_characters(self) -> None:
        """0/O and 1/I are unreadable from the back row."""
        for confusable in "0O1I":
            assert confusable not in CODE_ALPHABET

    def test_code_does_not_collide_with_an_existing_room(self, db, monkeypatch) -> None:
        db.add(Room(code="AAAAAA", title="Taken"))
        db.commit()
        # Force the first draw to collide, then return a free code.
        draws = iter([list("AAAAAA"), list("BBBBBB")])
        monkeypatch.setattr("app.main.random.choices", lambda *a, **k: next(draws))
        assert generate_code(db) == "BBBBBB"


class TestCountVotes:
    def test_a_poll_with_no_votes_counts_zero(self, db, poll) -> None:
        results = count_votes(db, poll)
        assert results.counts == [0, 0, 0]
        assert results.total_votes == 0

    def test_counts_line_up_with_the_option_list(self, db, poll) -> None:
        db.add_all(
            [
                Vote(poll_id=poll.id, option_index=2, device_id="device-01"),
                Vote(poll_id=poll.id, option_index=2, device_id="device-02"),
                Vote(poll_id=poll.id, option_index=0, device_id="device-03"),
            ]
        )
        db.commit()
        results = count_votes(db, poll)
        assert results.counts == [1, 0, 2]
        assert results.total_votes == 3

    def test_a_vote_for_a_removed_option_is_ignored_not_crashing(self, db, poll) -> None:
        """If a poll's options were edited, stale votes must not break the chart."""
        db.add(Vote(poll_id=poll.id, option_index=7, device_id="device-stale"))
        db.commit()
        results = count_votes(db, poll)
        assert results.counts == [0, 0, 0]
        assert results.total_votes == 0

    def test_results_carry_the_question_and_open_state(self, db, poll) -> None:
        results = count_votes(db, poll)
        assert results.question == "Q?"
        assert results.options == ["A", "B", "C"]
        assert results.is_open is True


class TestLookupHelpers:
    def test_room_lookup_uppercases_the_code(self, db) -> None:
        db.add(Room(code="MIXED1", title="Mixed"))
        db.commit()
        assert get_room_or_404(db, "mixed1").code == "MIXED1"

    def test_missing_room_raises_404_naming_the_code(self, db) -> None:
        with pytest.raises(HTTPException) as exc:
            get_room_or_404(db, "nope01")
        assert exc.value.status_code == 404
        assert "NOPE01" in exc.value.detail

    def test_missing_poll_raises_404(self, db) -> None:
        with pytest.raises(HTTPException) as exc:
            get_poll_or_404(db, 999999)
        assert exc.value.status_code == 404
