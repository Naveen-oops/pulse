# Decisions

Choices made while building Pulse, and what each one costs. Where this repo departs from
the original spec document, it is recorded here.

## Deviations from the original spec

| Spec said | We built | Why |
| --- | --- | --- |
| k3d + Traefik | **kind + ingress-nginx** | kind is what is installed on the demo laptop. kind ships no ingress controller, and ingress-nginx is its documented path. |
| Helm *or* Kustomize | **Kustomize** | Helm is not installed; `kubectl` already bundles Kustomize v5. One less thing to install. |
| `apps/` + `services/` | **`packages/*`** | One directory per deployable, flat. Standard pnpm/Turborepo shape; keeps every service independently deployable. |
| — | **npm workspace at the root** | `npm run web`, `npm run poll-service` from anywhere in the repo. |

## The decisions themselves

### Polling every 2 seconds, not WebSockets

A dropped socket needs reconnect logic, backoff and state resync; a dropped poll just
happens again in two seconds. Venue wifi is hostile and the room is small enough that the
redundant requests do not matter.

**Costs:** up to 2s of staleness, and steady background traffic.
**Do not "upgrade" this.** It is in `AGENTS.md` as a hard rule.

### One open poll per room

Opening a poll closes whichever was open. The audience view renders *the* open poll, so
two open at once would strand the room on the older one — a dead end mid-session.

Found by testing the real app, not by reading the spec: the spec says "the open poll"
(singular) but never states the invariant. See `tests/test_open_poll_switching.py`.

### Identity is a random `device_id` in `localStorage`

No login. The API enforces one vote per device per poll, backed by a
`UNIQUE (poll_id, device_id)` constraint.

**Cost:** clearing site data or opening a private window gets you another vote. That is
an acceptable trade for a conference room, and it is an honest discussion point during
the session — a trust boundary we chose not to defend.

### Rules enforced twice: in the handler and in the database

The handler check produces the friendly message; the unique constraint is the real guard.
Two phones tapping the same millisecond race past the check but not the constraint, and
the `IntegrityError` is caught and returned as the same 409.

### Relative API paths only

The web app calls `/api/polls/...` and never knows its backend's host. The Vite proxy
forwards it in development; the ingress does in the cluster. No `VITE_API_URL` to get
wrong at the worst possible moment.

### SQLite locally, PostgreSQL in the cluster

`PULSE_DATABASE_URL` swaps them with no code change. `npm run setup` uses PostgreSQL when
Docker is running and SQLite otherwise, so a broken Docker never blocks development.

Tests always use in-memory SQLite, pinned in `packages/<service>/conftest.py` so a local
`.env` cannot leak into a test run.

**Cost:** SQLite and PostgreSQL disagree on some edge semantics. Acceptable here because
the schema is small and CI runs the same SQLite path.

### One PostgreSQL instance, one schema per service

`polls` and `qa`. Schemas are applied only on PostgreSQL — SQLite has none, so the
setting is ignored there. A service never reads another service's tables.

### uv, and a managed Python

The demo laptop had only Python 3.8, which cannot run FastAPI 0.115 with Pydantic 2. uv
downloads a standalone CPython 3.12 into `.venv` without touching the system Python, and
installs both services' dependencies in about 17 seconds.

**Cost:** one more tool to install — handled automatically by `npm run setup`.

### Every npm script goes through `node scripts/run.mjs`

On Windows the `bash` on PATH is WSL's (`C:\Windows\system32\bash.exe`), which cannot see
the Windows toolchain, and npm's default shell is `cmd.exe`, which has no bash at all. The
launcher resolves Git Bash explicitly instead of hoping PATH is right.

### One `scripts/dev.sh`, not a script per task

Eleven small scripts is worse than one dispatcher: shared helpers stay in one place, and
`./scripts/dev.sh help` lists everything.

## Known rough edges

- **`uvicorn --reload` is unreliable on this machine.** WatchFiles logs "Reloading…" but
  sometimes never starts the new server process — seen with the repo on OneDrive. If a
  code change seems to have no effect, restart `npm run dev` rather than debugging the
  code. Confirmed during the build.
- **The repo lives in OneDrive.** `node_modules` and `.venv` generate heavy sync churn and
  can hold file locks during installs and deletes. Excluding the folder from OneDrive
  sync, or moving the repo outside it, removes a class of intermittent failures.
- **Node 18.19 is EOL** and some dependencies warn about it. Everything builds and passes,
  but Node 20 or 22 would silence the warnings.
- **Browser automation times out on clicks** because the page never reaches network-idle
  while polling every 2s. Real users are unaffected; scripted clicks need a direct
  dispatch instead.

## Not in scope

Auth beyond the presenter token · WebSockets · multiple concurrent rooms in the UI ·
email · database migrations (tables are created at startup) · rate limiting on votes
(only on questions, and that lands live).
