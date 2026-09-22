# Architecture

How Pulse is put together, and why. If you only read one section, read
[Why polling, not WebSockets](#why-polling-not-websockets) — it is the decision people
question most.

## The shape of the system

```
        phone                     laptop / projector
          │                              │
          ▼                              ▼
   /r/CIT22A  (audience)          /present/CIT22A  (presenter)
          │                              │
          └───────────┬──────────────────┘
                      ▼
                 packages/web              React 18 + Vite, static build
                      │
                      │  relative paths only: /api/polls, /api/qa
                      ▼
              ingress  (dev: Vite proxy)
                 │            │
       /api/polls│            │/api/qa
                 ▼            ▼
      poll-service          qa-service       FastAPI, one per concern
                 │            │
                 └─────┬──────┘
                       ▼
                  PostgreSQL              one instance, one schema each
                       │
                       │  GET /rooms/{code}/export
                       ▼
                 packages/crew             CrewAI -> report.md
                       │
                       ▼
                   LiteLLM                 -> Gemini Flash, Groq fallback
```

## Packages

Each directory under `packages/` is independently deployable: its own dependencies,
Dockerfile, CI job, and ingress route.

| Package | Responsibility | Talks to |
| --- | --- | --- |
| `poll-service` | Rooms, polls, votes, results, poll export | PostgreSQL (`polls` schema) |
| `qa-service` | Questions, upvotes, moderation, Q&A export | PostgreSQL (`qa` schema) |
| `web` | All three screens: audience, presenter, admin | Both APIs over HTTP |
| `crew` | Turns the two exports into a session report | Both export endpoints, LiteLLM |

### Why two services and not one

Because the live build depends on it. `qa-service` exists on `main` as a deployed
hello-world with its Dockerfile, CI workflow, manifests and ingress route already in
place. On stage the agent writes **only feature logic** — no plumbing. That removes the
riskiest ten minutes of the demo.

It also gives the session an honest microservice example: two deployables, one database
instance, separate schemas, no cross-service table reads.

## Key decisions

### Why polling, not WebSockets

Every view refreshes with a plain `GET` every 2 seconds.

- A dropped WebSocket needs reconnect logic, backoff, and state resync. A dropped poll
  request just... happens again in 2 seconds.
- Venue wifi and mobile data are hostile. Polling degrades gracefully; sockets fail hard.
- It is trivial to debug on stage — every refresh is one visible request in the network tab.

The cost is up to 2 seconds of staleness and some redundant requests, which is
irrelevant at the scale of one room.

**This is not a performance oversight. Do not "upgrade" it to WebSockets.**

### Why no login

The audience has 90 seconds of patience and no interest in an account. Identity is a
random `device_id` generated in the browser and stored in `localStorage`. The API enforces
one vote per device per poll.

This is deliberately weak: clearing site data or opening a private window gets you another
vote. That is an acceptable trade for a conference room, and it is a good discussion point
during the session — the honest answer is "this is a trust boundary we chose not to defend."

Presenter actions are the exception: they require an `X-Presenter-Token` header matched
against `PULSE_PRESENTER_TOKEN`.

### Why relative API paths

The web app never knows its backend's host. It calls `/api/polls/...` and `/api/qa/...`
always. In development the Vite proxy forwards those; in the cluster the ingress does.

The result: **zero code or config changes between laptop and cluster**, and no
`VITE_API_URL` to get wrong at the worst moment.

### Why rules live in the database too

The one-vote-per-device rule is enforced twice: an explicit check in the request handler
for the friendly message, and a `UNIQUE (poll_id, device_id)` constraint as the real
guard. Two phones tapping at the same millisecond race past the check; they do not race
past the constraint.

The handler catches `IntegrityError` and returns the same friendly 409.

## Data model

```
Room  ──1:N──▶  Poll  ──1:N──▶  Vote
 code           question         option_index
 title          options[]        device_id
 created_at     is_open          created_at
                created_at       UNIQUE(poll_id, device_id)

Question  ──1:N──▶  QuestionVote     (qa schema, keyed by room_code string)
 text               device_id
 device_id          UNIQUE(question_id, device_id)
 is_hidden
 is_answered
```

Room codes are six characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` — `0/O` and `1/I`
are excluded so the code is readable from the back row.

Q&A details live in [`docs/specs/qa-feature.md`](specs/qa-feature.md). `qa-service` does
not read the `rooms` table.

## Request flow: one vote

1. Audience page loads `/r/CIT22A`, polls `GET /api/polls/rooms/CIT22A` every 2s.
2. It renders the first poll where `is_open` is true.
3. Tap an option → `POST /api/polls/polls/{id}/votes` with `{option_index, device_id}`.
4. Service checks: poll exists → poll is open → option is in range → device has not voted.
5. Insert, commit (unique constraint is the backstop), return fresh counts.
6. The page switches to the results view and polls `GET .../results` every 2s.

Every rejection returns `{"detail": "<a sentence the audience can read>"}`.

## Environments

| | Local | Cluster |
| --- | --- | --- |
| Web | Vite dev server, port 5173 | Static build behind ingress |
| Routing | Vite proxy | ingress-nginx |
| poll-service | uvicorn, port 8001 | Deployment + Service |
| qa-service | uvicorn, port 8002 | Deployment + Service |
| Database | SQLite file | PostgreSQL |
| Phone access | same wifi, or tunnel | Cloudflare quick tunnel → QR |

SQLite locally is a deliberate trade: no database to start before you can run the app,
and `PULSE_DATABASE_URL` swaps it for PostgreSQL with no code change.

## What is intentionally missing

Auth beyond the presenter token · WebSockets · multiple concurrent rooms in the UI ·
email · rate limiting on votes (only on questions) · migrations (tables are created at
startup; this is a demo, not a product).
