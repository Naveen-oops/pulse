"""Request and response shapes."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class RoomCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    code: str | None = Field(default=None, min_length=6, max_length=6)

    @field_validator("code")
    @classmethod
    def uppercase_code(cls, value: str | None) -> str | None:
        return value.upper() if value else value


class PollCreate(BaseModel):
    question: str = Field(min_length=1, max_length=300)
    options: list[str] = Field(min_length=2, max_length=8)
    is_open: bool = False


class PollUpdate(BaseModel):
    is_open: bool


class VoteCreate(BaseModel):
    option_index: int = Field(ge=0)
    device_id: str = Field(min_length=4, max_length=64)


class PollOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    room_id: int
    question: str
    options: list[str]
    is_open: bool
    created_at: datetime


class RoomOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    code: str
    title: str
    created_at: datetime
    polls: list[PollOut] = []


class ResultsOut(BaseModel):
    poll_id: int
    question: str
    options: list[str]
    is_open: bool
    counts: list[int]
    total_votes: int


class ExportOut(BaseModel):
    room_code: str
    room_title: str
    exported_at: datetime
    polls: list[ResultsOut]
