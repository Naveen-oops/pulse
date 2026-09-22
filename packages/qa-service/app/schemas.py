"""Request and response shapes."""

from datetime import datetime

from pydantic import BaseModel, Field


class QuestionCreate(BaseModel):
    text: str
    device_id: str = Field(min_length=4, max_length=64)


class VoteCreate(BaseModel):
    device_id: str = Field(min_length=4, max_length=64)


class QuestionUpdate(BaseModel):
    is_hidden: bool | None = None
    is_answered: bool | None = None


class QuestionOut(BaseModel):
    id: int
    room_code: str
    text: str
    vote_count: int
    is_hidden: bool
    is_answered: bool
    created_at: datetime


class ExportOut(BaseModel):
    room_code: str
    exported_at: datetime
    questions: list[QuestionOut]
