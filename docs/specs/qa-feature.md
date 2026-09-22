# Q&A with upvotes

Attendees post questions from the same audience page, upvote each other's, and the
presenter screen shows them ranked live.

This spec is the contract for `packages/qa-service` and the Q&A UI in `packages/web`.
Each numbered rule has a test that names it.

## User stories

- As an attendee, I post a question in the room without logging in.
- As an attendee, I upvote a question once.
- As the presenter, I see questions sorted by votes, refreshed every 2 seconds, and I can
  mark one answered or hide it.

## Acceptance criteria

| # | Rule |
| --- | --- |
| 1 | Question text is 5 to 280 characters after trimming. Shorter, longer or empty is rejected with a message. |
| 2 | One upvote per device per question. A second upvote is not counted. |
| 3 | A device cannot upvote its own question. |
| 4 | Hidden questions disappear from both the audience and presenter views. |
| 5 | Only the presenter token can hide a question or mark it answered. |
| 6 | At most 5 questions per device per minute. The 6th is rejected with a message. |
| 7 | `GET /rooms/{code}/questions/export` returns every question with votes and status. |
| 8 | Questions are returned sorted by votes descending, then newest first. |

Rule 3 is the one to check first in review.

## Locked decisions

These close the gaps the original rehearsal spec left open. Do not reopen them in the
implementation without changing this file.

| Topic | Decision |
| --- | --- |
| Answered questions on the audience list | Still visible. Only `is_hidden` removes a question from live lists. |
| Presenter "answered" presentation | Answered rows stay on the presenter list, greyed, and sink to the bottom. That extra sort is UI-only; the API keeps rule 8. |
| Second upvote | `409` and `"You have already upvoted this question."` Count stays the same. |
| Self-upvote | `409` and `"You cannot upvote your own question."` |
| Rate limit | Count is **per device across rooms**, last 60 seconds. `429` and `"You are posting too quickly — try again in a moment."` |
| Text validation | `400` with the two length messages below. Do not rely on Pydantic's 422 array for rule 1 — the audience reads the sentence. |
| Missing question | `404` `"That question does not exist."` |
| Unknown room on live GET | `200` with `[]`. qa-service has no rooms table. |
| POST to an unknown code | Allowed. `room_code` is a string; the service does not call poll-service. |
| Votes on a hidden question | `404` `"That question does not exist."` |
| PATCH hide / un-hide / un-answer | Idempotent. Presenter may set `is_hidden` or `is_answered` back to `false`. |
| Author identity on live JSON | Never return `device_id` on live or export payloads. The client remembers "mine" and "upvoted" in `localStorage`. |
| Live GET query params | None. No `device_id` on GET. |
| Q&A vs open poll | Asking does not require an open poll. |
| Audience chrome | Two tabs, `Poll` and `Ask`. Tab choice is component state so a 2s refresh does not reset it. |
| Room codes | Uppercased. qa-service does not validate the poll-service alphabet. |

## Data model

```
Question                          QuestionVote
  id                                id
  room_code   (indexed, uppercase)  question_id  -> Question  ON DELETE CASCADE
  text        (5..280, stored trimmed)
  device_id   (author)              device_id
  is_hidden   (default false)       created_at
  is_answered (default false)       UNIQUE (question_id, device_id)
  created_at
```

`qa-service` owns the `qa` schema. It stores `room_code` as a plain string — it does
**not** read poll-service's `rooms` table. Services talk over HTTP, never through each
other's tables.

Vote counts are derived from `QuestionVote`, never stored on `Question`.

The unique constraint is the real one-upvote guard. The handler also checks first so the
audience gets a sentence instead of a 500. Catch `IntegrityError` and return the same 409.

## API — `packages/qa-service`

All routes sit under the `/api/qa` prefix, matching the ingress route.

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| `POST` | `/rooms/{code}/questions` | none | Body `{text, device_id}`. Rules 1, 6. `201`. |
| `GET` | `/rooms/{code}/questions` | none | Visible questions only (`is_hidden = false`), sorted by rule 8. |
| `POST` | `/questions/{id}/votes` | none | Body `{device_id}`. Rules 2, 3. `201`. |
| `PATCH` | `/questions/{id}` | presenter | Body `{is_hidden?, is_answered?}`. Rule 5. Missing token → `401` `"Presenter token required."` |
| `GET` | `/rooms/{code}/questions/export` | none | Everything, hidden included, same sort as rule 8. Rule 7. |

`device_id` is 4 to 64 characters (same bound as poll votes).

### Response shape (`QuestionOut`)

Used by POST, GET (item), PATCH, votes, and export items:

```json
{
  "id": 12,
  "room_code": "CIT22A",
  "text": "How does polling survive venue wifi?",
  "vote_count": 7,
  "is_hidden": false,
  "is_answered": false,
  "created_at": "2026-09-22T06:30:00+00:00"
}
```

Export wrapper:

```json
{
  "room_code": "CIT22A",
  "exported_at": "2026-09-22T06:35:00+00:00",
  "questions": []
}
```

Errors return `{"detail": "<a sentence the audience can read>"}`:

- `"Your question needs to be at least 5 characters."`
- `"Questions are limited to 280 characters."`
- `"You are posting too quickly — try again in a moment."`
- `"You cannot upvote your own question."`
- `"You have already upvoted this question."`
- `"Presenter token required."`
- `"That question does not exist."`

## Web — `packages/web`

Reuse what exists: all HTTP goes through `src/api.ts`, polling through
`src/hooks/usePolling.ts`, device identity through `src/device.ts`. Plain CSS in
`src/styles.css` — no UI framework.

**Audience** (`/r/{code}`) — `Poll` and `Ask` tabs. Ask is available while waiting for a
poll. Ask has a text box with a live character counter (`n/280`), a submit button, and
the ranked question list with an upvote button on each. The viewer's own questions are
marked and cannot be upvoted. Already-upvoted questions show as voted. Refreshes every 2
seconds. Surface `ApiError.message` in the page.

**Presenter** (`/present/{code}`) — a ranked question panel beside the poll chart:
question text, vote count, and **Hide** / **Answered** buttons. Answered questions move
to the bottom, greyed. Hidden questions are absent (the live GET already dropped them).
Refreshes every 2 seconds. Presenter actions send `X-Presenter-Token`.

Every interactive element is reachable by keyboard and has an accessible name.

## Out of scope

Editing or deleting a question · threading and replies · profanity filtering ·
notifications · the AI "Group questions" stretch · WebSockets · calling poll-service to
verify a room exists.

## Review checklist

1. The rate limit (rule 6) and self-upvote rule (rule 3).
2. A `UNIQUE (question_id, device_id)` constraint, not just an `if`.
3. Tests that assert the **message**, not only the status code.
4. Weakened gates: `noqa`, `eslint-disable`, `any`, skipped tests.
5. Invented scope: new endpoints, new tables, caching nobody asked for.
6. `device_id` leaking on list/export JSON.
