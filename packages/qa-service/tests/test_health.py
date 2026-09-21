"""The skeleton must stay deployable — CI gates the live build on this."""

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

API = settings.api_prefix


def test_healthz_at_the_root_for_kubernetes_probes() -> None:
    with TestClient(app) as client:
        response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "qa-service"}


def test_healthz_behind_the_ingress_prefix() -> None:
    with TestClient(app) as client:
        response = client.get(f"{API}/healthz")
    assert response.status_code == 200
    assert response.json()["service"] == "qa-service"


def test_the_service_is_mounted_under_api_qa() -> None:
    assert settings.api_prefix == "/api/qa"
