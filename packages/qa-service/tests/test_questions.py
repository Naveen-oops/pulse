"""Acceptance criteria for posting questions, upvotes, moderation and export."""

from fastapi.testclient import TestClient

from tests.conftest import API

ROOM = "CIT22A"


def post_question(
    client: TestClient,
    text: str,
    device_id: str = "device-author",
    code: str = ROOM,
) -> dict:
    response = client.post(
        f"{API}/rooms/{code}/questions",
        json={"text": text, "device_id": device_id},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_question_shorter_than_five_characters_is_rejected(client: TestClient) -> None:
    """Rule 1: shorter or empty text is rejected with a readable message."""
    response = client.post(
        f"{API}/rooms/{ROOM}/questions",
        json={"text": "hey", "device_id": "device-author"},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Your question needs to be at least 5 characters."


def test_question_longer_than_280_characters_is_rejected(client: TestClient) -> None:
    """Rule 1: longer than 280 characters is rejected with a readable message."""
    response = client.post(
        f"{API}/rooms/{ROOM}/questions",
        json={"text": "x" * 281, "device_id": "device-author"},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Questions are limited to 280 characters."


def test_second_upvote_from_same_device_is_ignored(client: TestClient) -> None:
    """Rule 2: a second upvote from the same device is not counted."""
    question = post_question(client, "How does polling survive venue wifi?")
    first = client.post(
        f"{API}/questions/{question['id']}/votes",
        json={"device_id": "device-voter"},
    )
    assert first.status_code == 201
    assert first.json()["vote_count"] == 1

    second = client.post(
        f"{API}/questions/{question['id']}/votes",
        json={"device_id": "device-voter"},
    )
    assert second.status_code == 409
    assert second.json()["detail"] == "You have already upvoted this question."
    listed = client.get(f"{API}/rooms/{ROOM}/questions").json()
    assert listed[0]["vote_count"] == 1


def test_device_cannot_upvote_its_own_question(client: TestClient) -> None:
    """Rule 3: a device cannot upvote its own question."""
    question = post_question(client, "What is on the agenda?", device_id="device-author")
    response = client.post(
        f"{API}/questions/{question['id']}/votes",
        json={"device_id": "device-author"},
    )
    assert response.status_code == 409
    assert response.json()["detail"] == "You cannot upvote your own question."
    listed = client.get(f"{API}/rooms/{ROOM}/questions").json()
    assert listed[0]["vote_count"] == 0


def test_hidden_questions_are_omitted_from_the_live_list(
    client: TestClient, presenter: dict[str, str]
) -> None:
    """Rule 4: hidden questions disappear from the live list."""
    visible = post_question(client, "Will this stay visible?")
    hidden = post_question(client, "Should this be hidden now?", device_id="device-other")
    patched = client.patch(
        f"{API}/questions/{hidden['id']}",
        json={"is_hidden": True},
        headers=presenter,
    )
    assert patched.status_code == 200
    listed = client.get(f"{API}/rooms/{ROOM}/questions").json()
    ids = [item["id"] for item in listed]
    assert visible["id"] in ids
    assert hidden["id"] not in ids


def test_hide_and_answer_require_presenter_token(client: TestClient) -> None:
    """Rule 5: only the presenter token can hide a question or mark it answered."""
    question = post_question(client, "Who can moderate this?")
    missing = client.patch(f"{API}/questions/{question['id']}", json={"is_hidden": True})
    assert missing.status_code == 401
    assert missing.json()["detail"] == "Presenter token required."

    wrong = client.patch(
        f"{API}/questions/{question['id']}",
        json={"is_answered": True},
        headers={"X-Presenter-Token": "not-the-token"},
    )
    assert wrong.status_code == 401
    assert wrong.json()["detail"] == "Presenter token required."


def test_sixth_question_in_one_minute_is_rejected(client: TestClient) -> None:
    """Rule 6: at most five questions per device per minute."""
    for index in range(5):
        post_question(client, f"Question number {index} here", device_id="device-speedy")
    sixth = client.post(
        f"{API}/rooms/{ROOM}/questions",
        json={"text": "This one should be blocked now", "device_id": "device-speedy"},
    )
    assert sixth.status_code == 429
    assert sixth.json()["detail"] == "You are posting too quickly — try again in a moment."


def test_export_includes_hidden_questions_with_votes_and_status(
    client: TestClient, presenter: dict[str, str]
) -> None:
    """Rule 7: export returns every question with votes and status."""
    shown = post_question(client, "What should export include?")
    hidden = post_question(client, "And does it keep hidden ones?", device_id="device-other")
    client.post(f"{API}/questions/{shown['id']}/votes", json={"device_id": "device-voter"})
    client.patch(
        f"{API}/questions/{hidden['id']}",
        json={"is_hidden": True, "is_answered": True},
        headers=presenter,
    )

    exported = client.get(f"{API}/rooms/{ROOM}/questions/export")
    assert exported.status_code == 200
    body = exported.json()
    assert body["room_code"] == ROOM
    assert "device_id" not in body
    by_id = {item["id"]: item for item in body["questions"]}
    assert by_id[shown["id"]]["vote_count"] == 1
    assert by_id[shown["id"]]["is_hidden"] is False
    assert by_id[hidden["id"]]["is_hidden"] is True
    assert by_id[hidden["id"]]["is_answered"] is True
    assert "device_id" not in by_id[shown["id"]]


def test_questions_are_sorted_by_votes_then_newest(client: TestClient) -> None:
    """Rule 8: live list is votes descending, then newest first."""
    older_tied = post_question(client, "This is older with one vote", device_id="device-c")
    older_top = post_question(client, "This will get two votes later")
    newer_tied = post_question(client, "This is newer with one vote", device_id="device-b")

    client.post(f"{API}/questions/{older_top['id']}/votes", json={"device_id": "device-v1"})
    client.post(f"{API}/questions/{older_top['id']}/votes", json={"device_id": "device-v2"})
    client.post(f"{API}/questions/{newer_tied['id']}/votes", json={"device_id": "device-v1"})
    client.post(f"{API}/questions/{older_tied['id']}/votes", json={"device_id": "device-v1"})

    listed = client.get(f"{API}/rooms/{ROOM}/questions").json()
    assert [item["id"] for item in listed] == [
        older_top["id"],
        newer_tied["id"],
        older_tied["id"],
    ]


def test_unknown_room_live_list_is_empty(client: TestClient) -> None:
    response = client.get(f"{API}/rooms/ZZZZZZ/questions")
    assert response.status_code == 200
    assert response.json() == []


def test_upvote_on_a_hidden_question_is_a_404(
    client: TestClient, presenter: dict[str, str]
) -> None:
    question = post_question(client, "Please hide this question")
    client.patch(
        f"{API}/questions/{question['id']}",
        json={"is_hidden": True},
        headers=presenter,
    )
    response = client.post(
        f"{API}/questions/{question['id']}/votes",
        json={"device_id": "device-voter"},
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "That question does not exist."
