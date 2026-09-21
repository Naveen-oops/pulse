"""Rooms, presenter auth, results counting and the CrewAI export."""

from fastapi.testclient import TestClient

from tests.conftest import API


def test_healthz(client: TestClient) -> None:
    assert client.get("/healthz").json()["status"] == "ok"
    assert client.get(f"{API}/healthz").json()["service"] == "poll-service"


def test_creating_a_room_requires_the_presenter_token(client: TestClient) -> None:
    response = client.post(f"{API}/rooms", json={"title": "Build Smarter"})
    assert response.status_code == 401
    assert response.json()["detail"] == "Presenter token required."


def test_room_code_is_generated_when_not_supplied(client: TestClient, presenter: dict) -> None:
    response = client.post(f"{API}/rooms", json={"title": "Ad hoc"}, headers=presenter)
    assert response.status_code == 201
    assert len(response.json()["code"]) == 6


def test_duplicate_room_code_is_rejected(client: TestClient, presenter: dict, room: dict) -> None:
    response = client.post(
        f"{API}/rooms", json={"title": "Again", "code": "CIT22A"}, headers=presenter
    )
    assert response.status_code == 409


def test_room_lookup_is_case_insensitive(client: TestClient, room: dict) -> None:
    assert client.get(f"{API}/rooms/cit22a").json()["code"] == "CIT22A"


def test_unknown_room_is_a_404(client: TestClient) -> None:
    response = client.get(f"{API}/rooms/ZZZZZZ")
    assert response.status_code == 404
    assert "ZZZZZZ" in response.json()["detail"]


def test_opening_a_poll_requires_the_presenter_token(client: TestClient, open_poll: dict) -> None:
    response = client.patch(f"{API}/polls/{open_poll['id']}", json={"is_open": False})
    assert response.status_code == 401


def test_results_count_votes_per_option(client: TestClient, open_poll: dict) -> None:
    """Spec: Results counting."""
    votes = {"device-01": 0, "device-02": 2, "device-03": 2, "device-04": 2, "device-05": 1}
    for device, option in votes.items():
        response = client.post(
            f"{API}/polls/{open_poll['id']}/votes",
            json={"option_index": option, "device_id": device},
        )
        assert response.status_code == 201, response.text
    results = client.get(f"{API}/polls/{open_poll['id']}/results").json()
    assert results["counts"] == [1, 1, 3]
    assert results["total_votes"] == 5
    assert results["question"] == open_poll["question"]


def test_export_contains_every_poll_with_counts(
    client: TestClient, presenter: dict, room: dict, open_poll: dict
) -> None:
    """Spec: GET /rooms/{code}/export — CrewAI reads this."""
    client.post(
        f"{API}/rooms/{room['code']}/polls",
        json={"question": "Second poll?", "options": ["Yes", "No"], "is_open": False},
        headers=presenter,
    )
    voted = client.post(
        f"{API}/polls/{open_poll['id']}/votes",
        json={"option_index": 0, "device_id": "device-01"},
    )
    assert voted.status_code == 201, voted.text

    export = client.get(f"{API}/rooms/{room['code']}/export").json()
    assert export["room_code"] == "CIT22A"
    assert export["room_title"] == "Build Smarter"
    assert len(export["polls"]) == 2
    assert export["polls"][0]["counts"] == [1, 0, 0]
    assert export["polls"][1]["total_votes"] == 0
    assert "exported_at" in export
