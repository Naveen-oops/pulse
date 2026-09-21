"""A room has exactly one open poll at a time.

The audience view renders "the open poll". If two were open at once the room
would be stuck on the older one, which is a dead end mid-session.
"""

from fastapi.testclient import TestClient

from tests.conftest import API


def _add_poll(client: TestClient, presenter: dict, code: str, question: str) -> dict:
    response = client.post(
        f"{API}/rooms/{code}/polls",
        json={"question": question, "options": ["Yes", "No"], "is_open": False},
        headers=presenter,
    )
    assert response.status_code == 201, response.text
    return response.json()


def _open_states(client: TestClient, code: str) -> list[bool]:
    return [poll["is_open"] for poll in client.get(f"{API}/rooms/{code}").json()["polls"]]


def test_opening_a_poll_closes_the_one_that_was_open(
    client: TestClient, presenter: dict, room: dict, open_poll: dict
) -> None:
    second = _add_poll(client, presenter, room["code"], "Second poll?")

    response = client.patch(
        f"{API}/polls/{second['id']}", json={"is_open": True}, headers=presenter
    )

    assert response.status_code == 200
    assert response.json()["is_open"] is True
    assert _open_states(client, room["code"]) == [False, True]


def test_only_one_poll_is_ever_open_across_several_switches(
    client: TestClient, presenter: dict, room: dict, open_poll: dict
) -> None:
    second = _add_poll(client, presenter, room["code"], "Second poll?")
    third = _add_poll(client, presenter, room["code"], "Third poll?")

    for target, expected in (
        (second["id"], [False, True, False]),
        (third["id"], [False, False, True]),
        (open_poll["id"], [True, False, False]),
    ):
        client.patch(f"{API}/polls/{target}", json={"is_open": True}, headers=presenter)
        states = _open_states(client, room["code"])
        assert states == expected
        assert sum(states) == 1, "exactly one poll may be open"


def test_closing_a_poll_leaves_every_other_poll_closed(
    client: TestClient, presenter: dict, room: dict, open_poll: dict
) -> None:
    _add_poll(client, presenter, room["code"], "Second poll?")

    client.patch(f"{API}/polls/{open_poll['id']}", json={"is_open": False}, headers=presenter)

    assert _open_states(client, room["code"]) == [False, False]


def test_opening_a_poll_does_not_touch_another_room(
    client: TestClient, presenter: dict, room: dict, open_poll: dict
) -> None:
    other = client.post(
        f"{API}/rooms", json={"title": "Other room", "code": "OTHER1"}, headers=presenter
    ).json()
    other_poll = _add_poll(client, presenter, other["code"], "Unrelated poll?")

    client.patch(f"{API}/polls/{other_poll['id']}", json={"is_open": True}, headers=presenter)

    assert _open_states(client, room["code"]) == [True], "the first room keeps its open poll"
    assert _open_states(client, other["code"]) == [True]


def test_reopening_the_already_open_poll_keeps_it_open(
    client: TestClient, presenter: dict, room: dict, open_poll: dict
) -> None:
    """The exclusion must not close the very poll being opened."""
    response = client.patch(
        f"{API}/polls/{open_poll['id']}", json={"is_open": True}, headers=presenter
    )

    assert response.json()["is_open"] is True
    assert _open_states(client, room["code"]) == [True]
