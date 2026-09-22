"""SQLAlchemy models for questions and upvotes."""

from datetime import UTC, datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    MetaData,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

from app.config import settings


def utcnow() -> datetime:
    return datetime.now(UTC)


class Base(DeclarativeBase):
    # One schema per service on PostgreSQL; None (default) on SQLite.
    metadata = MetaData(schema=settings.db_schema)


class Question(Base):
    __tablename__ = "questions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    room_code: Mapped[str] = mapped_column(String(6), index=True)
    text: Mapped[str] = mapped_column(String(280))
    device_id: Mapped[str] = mapped_column(String(64), index=True)
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False)
    is_answered: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    votes: Mapped[list["QuestionVote"]] = relationship(
        back_populates="question",
        cascade="all, delete-orphan",
    )


class QuestionVote(Base):
    __tablename__ = "question_votes"
    # The one-upvote-per-device rule, enforced by the database as well as the API.
    __table_args__ = (UniqueConstraint("question_id", "device_id", name="uq_question_vote_device"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    question_id: Mapped[int] = mapped_column(
        ForeignKey("questions.id", ondelete="CASCADE"),
        index=True,
    )
    device_id: Mapped[str] = mapped_column(String(64), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    question: Mapped[Question] = relationship(back_populates="votes")
