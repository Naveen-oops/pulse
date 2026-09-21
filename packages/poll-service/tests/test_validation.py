"""Input validation — the audience sees these messages, so they must fire."""

import pytest
from fastapi.testclient import TestClient

from tests.conftest import API


class TestPollValidation:
    @pytest.mark.parametrize(
        "options",
        [
            pytest.param([], id="no-options"),
            pytest.param(["Only one"], id="one-option"),
            pytest.param([f"Option {i}" for i in range(9)], id="nine-options"),
        ],
    )
    def test_option_count_is_bounded(
        self, client: TestClient, presenter: dict, room: dict, options: list
    ) -> None:
        response = client.post(
            f"{API}/rooms/{room['code']}/polls",
            json={"question": "Q?", "options": options},
            headers=presenter,
        )
        assert response.status_code == 422

    def test_question_longer_than_300_characters_is_rejected(
        self, client: TestClient, presenter: dict, room: dict
    ) -> None:
        response = client.post(
            f"{API}/rooms/{room['code']}/polls",
            json={"question": "x" * 301, "options": ["A", "B"]},
            headers=presenter,
        )
        assert response.status_code == 422

    def test_empty_question_is_rejected(
        self, client: TestClient, presenter: dict, room: dict
    ) -> None:
        response = client.post(
            f"{API}/rooms/{room['code']}/polls",
            json={"question": "", "options": ["A", "B"]},
            headers=presenter,
        )
        assert response.status_code == 422

    def test_a_poll_for_an_unknown_room_is_a_404(self, client: TestClient, presenter: dict) -> None:
        response = client.post(
            f"{API}/rooms/ZZZZZZ/polls",
            json={"question": "Q?", "options": ["A", "B"]},
            headers=presenter,
        )
        assert response.status_code == 404


class TestRoomValidation:
    def test_empty_title_is_rejected(self, client: TestClient, presenter: dict) -> None:
        response = client.post(f"{API}/rooms", json={"title": ""}, headers=presenter)
        assert response.status_code == 422

    @pytest.mark.parametrize("code", ["ABC", "TOOLONG1"], ids=["too-short", "too-long"])
    def test_a_supplied_code_must_be_six_characters(
        self, client: TestClient, presenter: dict, code: str
    ) -> None:
        response = client.post(f"{API}/rooms", json={"title": "T", "code": code}, headers=presenter)
        assert response.status_code == 422

    def test_a_supplied_code_is_stored_uppercase(self, client: TestClient, presenter: dict) -> None:
        response = client.post(
            f"{API}/rooms", json={"title": "T", "code": "cit99z"}, headers=presenter
        )
        assert response.status_code == 201
        assert response.json()["code"] == "CIT99Z"

    def test_a_wrong_presenter_token_is_rejected(self, client: TestClient) -> None:
        response = client.post(
            f"{API}/rooms",
            json={"title": "T"},
            headers={"X-Presenter-Token": "not-the-token"},
        )
        assert response.status_code == 401


class TestVoteValidation:
    @pytest.mark.parametrize("device_id", ["", "ab"], ids=["empty", "too-short"])
    def test_device_id_must_be_present_and_long_enough(
        self, client: TestClient, open_poll: dict, device_id: str
    ) -> None:
        response = client.post(
            f"{API}/polls/{open_poll['id']}/votes",
            json={"option_index": 0, "device_id": device_id},
        )
        assert response.status_code == 422

    def test_a_negative_option_index_is_rejected(self, client: TestClient, open_poll: dict) -> None:
        response = client.post(
            f"{API}/polls/{open_poll['id']}/votes",
            json={"option_index": -1, "device_id": "device-neg"},
        )
        assert response.status_code == 422
