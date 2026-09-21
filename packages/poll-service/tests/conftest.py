"""Shared fixtures. Tests run against in-memory SQLite — no database needed."""

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.db import engine
from app.main import app
from app.models import Base

API = settings.api_prefix


@pytest.fixture(autouse=True)
def fresh_database():
    """Every test starts from empty tables."""
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def presenter() -> dict[str, str]:
    return {"X-Presenter-Token": settings.presenter_token}


@pytest.fixture
def room(client: TestClient, presenter: dict[str, str]) -> dict:
    response = client.post(
        f"{API}/rooms",
        json={"title": "Build Smarter", "code": "CIT22A"},
        headers=presenter,
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture
def open_poll(client: TestClient, presenter: dict[str, str], room: dict) -> dict:
    response = client.post(
        f"{API}/rooms/{room['code']}/polls",
        json={
            "question": "Which AI coding tool have you used?",
            "options": ["None yet", "Copilot", "Cursor"],
            "is_open": True,
        },
        headers=presenter,
    )
    assert response.status_code == 201, response.text
    return response.json()
