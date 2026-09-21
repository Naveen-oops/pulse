"""Database engine and session handling.

PostgreSQL in production, in-memory SQLite when ``PULSE_DATABASE_URL`` is unset so
that ``pytest`` needs no running database.
"""

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool
from sqlalchemy.schema import CreateSchema

from app.config import settings
from app.models import Base

_is_sqlite = settings.database_url.startswith("sqlite")

engine = create_engine(
    settings.database_url,
    # A single shared connection, otherwise each in-memory SQLite connection gets
    # its own empty database.
    connect_args={"check_same_thread": False} if _is_sqlite else {},
    poolclass=StaticPool if _is_sqlite else None,
    pool_pre_ping=not _is_sqlite,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def create_tables() -> None:
    if settings.db_schema:
        with engine.begin() as connection:
            connection.execute(CreateSchema(settings.db_schema, if_not_exists=True))
    Base.metadata.create_all(bind=engine)


def get_db() -> Iterator[Session]:
    """FastAPI dependency: one session per request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
