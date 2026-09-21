"""Configuration for poll-service.

Plain ``os.getenv`` on purpose: this file is shown on screen during the session,
so it should be readable without knowing a settings library.
"""

import os
from dataclasses import dataclass

from dotenv import load_dotenv

# Reads .env at the repo root when running locally; a no-op in the container,
# where the values come from the environment.
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
    # Unset -> in-memory SQLite, so tests and a bare `uvicorn app.main:app` both
    # work without a database running.
    database_url = os.getenv("PULSE_DATABASE_URL", "sqlite+pysqlite:///:memory:")

    # One PostgreSQL instance, one schema per service. SQLite has no schemas,
    # so it is ignored there.
    db_schema = os.getenv("PULSE_DB_SCHEMA") or None
    if database_url.startswith("sqlite"):
        db_schema = None

    return Settings(
        database_url=database_url,
        db_schema=db_schema,
        presenter_token=os.getenv("PULSE_PRESENTER_TOKEN", "demo-presenter-token"),
        # The ingress routes /api/polls to this service without rewriting, so the
        # app itself serves that prefix.
        api_prefix=os.getenv("PULSE_API_PREFIX", "/api/polls"),
        cors_origins=_cors_origins(),
    )


settings = get_settings()
