"""Acceptance criteria for voting."""

from fastapi.testclient import TestClient

from tests.conftest import API


def test_a_device_can_vote_once(client: TestClient, open_poll: dict) -> None:
    """Spec: A device votes once per poll."""
    response = client.post(
        f"{API}/polls/{open_poll['id']}/votes",
        json={"option_index": 1, "device_id": "device-aaa"},
    )
    assert response.status_code == 201, response.text
    assert response.json()["counts"] == [0, 1, 0]
    assert response.json()["total_votes"] == 1


def test_second_vote_from_same_device_is_rejected(client: TestClient, open_poll: dict) -> None:
    """Spec: A second vote is rejected with a friendly message."""
    client.post(
        f"{API}/polls/{open_poll['id']}/votes",
        json={"option_index": 0, "device_id": "device-aaa"},
    )
    second = client.post(
        f"{API}/polls/{open_poll['id']}/votes",
        json={"option_index": 2, "device_id": "device-aaa"},
    )
    assert second.status_code == 409
    assert second.json()["detail"] == "You have already voted in this poll."

    results = client.get(f"{API}/polls/{open_poll['id']}/results").json()
    assert results["total_votes"] == 1, "the rejected vote must not be counted"


def test_different_devices_each_get_a_vote(client: TestClient, open_poll: dict) -> None:
    for index, device in enumerate(["device-a", "device-b", "device-c"]):
        response = client.post(
            f"{API}/polls/{open_poll['id']}/votes",
            json={"option_index": index % 3, "device_id": device},
        )
        assert response.status_code == 201
    results = client.get(f"{API}/polls/{open_poll['id']}/results").json()
    assert results["counts"] == [1, 1, 1]
    assert results["total_votes"] == 3


def test_votes_on_a_closed_poll_are_rejected(
    client: TestClient, presenter: dict, open_poll: dict
) -> None:
    """Spec: Votes on a closed poll are rejected."""
    closed = client.patch(
        f"{API}/polls/{open_poll['id']}", json={"is_open": False}, headers=presenter
    )
    assert closed.status_code == 200
    assert closed.json()["is_open"] is False

    response = client.post(
        f"{API}/polls/{open_poll['id']}/votes",
        json={"option_index": 0, "device_id": "device-late"},
    )
    assert response.status_code == 409
    assert response.json()["detail"] == "This poll is closed."


def test_option_index_out_of_range_is_rejected(client: TestClient, open_poll: dict) -> None:
    response = client.post(
        f"{API}/polls/{open_poll['id']}/votes",
        json={"option_index": 99, "device_id": "device-aaa"},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "That option does not exist."


def test_voting_on_a_missing_poll_is_a_404(client: TestClient) -> None:
    response = client.post(
        f"{API}/polls/4242/votes",
        json={"option_index": 0, "device_id": "device-aaa"},
    )
    assert response.status_code == 404
