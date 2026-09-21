"""Configuration for qa-service.

Mirrors poll-service on purpose: an agent implementing the Q&A feature should
find the same shapes in both services.
"""

import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class Settings:
    database_url: str
    db_schema: str | None
    presenter_token: str
    api_prefix: str
    cors_origins: list[str]


def _cors_origins() -> list[str]:
    raw = os.getenv("PULSE_CORS_ORIGINS", "http://localhost:5173,http://localhost:8080")
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


def get_settings() -> Settings:
    database_url = os.getenv("QA_DATABASE_URL", "sqlite+pysqlite:///:memory:")

    # One PostgreSQL instance, one schema per service. SQLite has no schemas.
    db_schema = os.getenv("QA_DB_SCHEMA") or None
    if database_url.startswith("sqlite"):
        db_schema = None

    return Settings(
        database_url=database_url,
        db_schema=db_schema,
        presenter_token=os.getenv("PULSE_PRESENTER_TOKEN", "demo-presenter-token"),
        api_prefix=os.getenv("QA_API_PREFIX", "/api/qa"),
        cors_origins=_cors_origins(),
    )


settings = get_settings()
