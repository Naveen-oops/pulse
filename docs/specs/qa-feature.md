# Q&A with upvotes

> **This is the feature built live on stage.** It is deliberately not implemented on
> `main` — `qa-service` there answers `/healthz` and nothing else.
>
> On the day, this file is replaced by whatever the Cowork brainstorm produces. This
> version exists so rehearsals have a real spec to run against.

Attendees post questions from the same audience page, upvote each other's, and the
presenter screen shows them ranked live.

## User stories

- As an attendee, I post a question in the room without logging in.
- As an attendee, I upvote a question once.
- As the presenter, I see questions sorted by votes, refreshed every 2 seconds, and I can
  mark one answered or hide it.

## Acceptance criteria

Each one needs a test that names it.

| # | Rule |
| --- | --- |
| 1 | Question text is 5 to 280 characters. Shorter, longer or empty is rejected with a message. |
| 2 | One upvote per device per question. A second upvote is ignored, not counted. |
| 3 | A device cannot upvote its own question. |
| 4 | Hidden questions disappear from both the audience and presenter views. |
| 5 | Only the presenter token can hide a question or mark it answered. |
| 6 | At most 5 questions per device per minute. The 6th is rejected with a message. |
| 7 | `GET /rooms/{code}/questions/export` returns every question with votes and status. |
| 8 | Questions are returned sorted by votes descending, then newest first. |

Rule 3 is the one agents skip most often. Check for it in the review moment.

## Data model

```
Question                          QuestionVote
  id                                id
  room_code   (6 chars, indexed)    question_id  -> Question
  text        (5..280)              device_id
  device_id   (author)              created_at
  is_hidden   (default false)       UNIQUE (question_id, device_id)
  is_answered (default false)
  created_at
```

`qa-service` owns the `qa` schema. It stores `room_code` as a plain string — it does
**not** read poll-service's `rooms` table. Services talk over HTTP, never through each
other's tables.

## API — `packages/qa-service`

All routes sit under the `/api/qa` prefix, matching the ingress route.

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| `POST` | `/rooms/{code}/questions` | none | Body `{text, device_id}`. Rules 1, 6. |
| `GET` | `/rooms/{code}/questions` | none | Visible questions only, sorted by rule 8. |
| `POST` | `/questions/{id}/votes` | none | Body `{device_id}`. Rules 2, 3. |
| `PATCH` | `/questions/{id}` | presenter | Body `{is_hidden?, is_answered?}`. Rule 5. |
| `GET` | `/rooms/{code}/questions/export` | none | Everything, hidden included. Rule 7. |

Errors return `{"detail": "<a sentence the audience can read>"}`:

- `"Your question needs to be at least 5 characters."`
- `"Questions are limited to 280 characters."`
- `"You are posting too quickly — try again in a moment."`
- `"You cannot upvote your own question."`

## Web — `packages/web`

**Audience** (`/r/{code}`) — an "Ask" tab beside the poll:
a text box with a live character counter, a submit button, and the ranked question list
with an upvote button on each. The viewer's own questions are marked; already-upvoted
questions show as voted. Refreshes every 2 seconds.

**Presenter** (`/present/{code}`) — a ranked question panel beside the poll chart:
question text, vote count, and **Hide** / **Answered** buttons. Answered questions move
to the bottom, greyed. Refreshes every 2 seconds.

Reuse what exists: all HTTP goes through `src/api.ts`, polling through
`src/hooks/usePolling.ts`, device identity through `src/device.ts`. Plain CSS in
`src/styles.css` — no UI framework.

## Out of scope

Editing or deleting a question · threading and replies · profanity filtering ·
notifications · the AI "Group questions" stretch.

## The rehearsal prompt

Use in Cursor agent mode, not Claude Code:

```
Implement docs/specs/qa-feature.md in packages/qa-service and packages/web.
Follow AGENTS.md. Add a test for every acceptance criterion.
Do not change deploy/ or .github/workflows/.
```

**The review moment.** Before merging, check the diff for:

1. The rate limit (rule 6) and self-upvote rule (rule 3) — the two most often skipped.
2. A `UNIQUE (question_id, device_id)` constraint, not just an `if` — rule 2 must survive
   two taps in the same millisecond.
3. Tests that assert the **message**, not only the status code.
4. Weakened gates: `noqa`, `eslint-disable`, `any`, skipped tests.
5. Invented scope: new endpoints, new tables, caching nobody asked for.

If a rule is missing, the prompt is *"add the rate limit and a test for it"* — name the
rule and demand the test in the same breath.
