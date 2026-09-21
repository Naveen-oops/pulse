# AGENTS.md

Rules for coding agents (Cursor, Claude Code, Copilot) working in this repo.
**Read this before making any change.** Everything here is enforced by CI.

## What this repo is

**Pulse** — a Slido-style live audience app used as the teaching artifact in the
"Build Smarter with Agentic Engineering" session. It is demoed live in front of an
audience, so **a broken `main` is a broken talk**.

Deeper context lives in [`docs/architecture.md`](docs/architecture.md); the quality
bar and how it is enforced is in [`docs/quality.md`](docs/quality.md).

## Layout

One directory per independently deployable package. Never merge two packages.

| Package | Path | Stack |
| --- | --- | --- |
| Poll API | `packages/poll-service` | Python 3.12, FastAPI, SQLAlchemy 2, PostgreSQL |
| Q&A API | `packages/qa-service` | Python 3.12, FastAPI, SQLAlchemy 2, PostgreSQL |
| Web | `packages/web` | React 18, Vite 5, TypeScript (strict), plain CSS |
| Crew | `packages/crew` | CrewAI, YAML-configured agents, OpenAI-compatible endpoint |

Supporting directories: `deploy/` (Kustomize + ArgoCD), `docs/` (specs and standards),
`scripts/` (dev and cluster helpers), `.github/workflows/` (CI).

Both services share one PostgreSQL instance with **one schema each** (`polls`, `qa`).
A service never reads another service's tables — it goes through HTTP.

## Commands

Python packages share one virtualenv at the repo root (`.venv`), created with **uv**.

```bash
# Setup, from the repo root
uv venv --python 3.12
uv pip install -r packages/poll-service/requirements-dev.txt \
               -r packages/qa-service/requirements-dev.txt

# Test + lint a Python package (run from that package directory)
cd packages/poll-service && python -m pytest
cd packages/poll-service && ruff check . && ruff format --check .

# Web
cd packages/web && npm test && npm run lint && npm run typecheck && npm run build
```

Run the tests for every package you touched, before every commit. If you could not
run them, say so — **never report a test as passing that you did not run.**

## Hard rules

1. **Never read, print, echo, or commit `.env`, `.env.*`, kubeconfig files, or anything
   under `secrets/`.** This screen is recorded. Read names from `.env.example` and ask
   for values.
2. **Do not change `deploy/` or `.github/workflows/` unless the task explicitly says to.**
   The GitOps pipeline is demoed live; a surprise edit there breaks the deploy.
3. **Do not add services, databases, or infrastructure.** Stop and ask first.
4. **Do not introduce WebSockets.** Views refresh by polling every 2 seconds, on purpose —
   it survives venue wifi and reconnects by itself.
5. **Do not add a UI framework, CSS-in-JS, or a component library.** Plain CSS only.
6. **Do not weaken a quality gate to make it pass** — no `# type: ignore`, `eslint-disable`,
   `# noqa`, `any`, or skipped tests to get green. Fix the cause, or say why you cannot.
7. **Small commits, one logical change each.**

## Coding standards

### Both languages

- Name things for what they mean in the domain (`device_id`, `is_open`, `presenter`),
  not for their type or shape.
- A comment explains **why**, never what the line already says. Delete the rest.
- No dead code, no commented-out blocks, no `TODO` without an owner and a reason.
- Errors surface a message the audience could read. No stack traces in the UI.

### Python

- Target 3.12. Type-annotate every function signature, including `-> None`.
- `ruff` is the single source of truth for style: line length 100, rules `E,F,I,UP,B`.
- Pydantic models for every request and response body; never hand-roll validation.
- API errors are `HTTPException(status_code=..., detail="<short, friendly sentence>")`.
- Database access goes through a `Session` from the `get_db` dependency.
- Anything enforced by a business rule is **also** enforced by a database constraint
  where possible (see the unique constraint behind one-vote-per-device).

### TypeScript / React

- `strict` is on, plus `noUncheckedIndexedAccess`. Handle the `undefined`; do not cast
  it away.
- No `any`. Use `unknown` and narrow.
- Function components only. Hooks follow the rules-of-hooks lint rule.
- All HTTP goes through `packages/web/src/api.ts`. Do not scatter `fetch` calls.
- Every interactive element is reachable by keyboard and has an accessible name.

### Tests

- One acceptance criterion per test function, with the criterion in the docstring or
  test name. Test names read as sentences: `test_second_vote_from_same_device_is_rejected`.
- Test behaviour through the public interface, not private helpers.
- Assert the **message**, not just the status code, where the audience will read it.
- Python tests live in `packages/<service>/tests/`; web tests sit next to the source
  as `*.test.ts(x)`.
- No network, no real database, no sleeps. Python tests run on in-memory SQLite.

## Conventions

- **Device identity** is a random `device_id` generated in the browser and kept in
  `localStorage`. There is no login anywhere in this app.
- **Presenter actions** (create room, open/close poll, hide question, mark answered)
  require the `X-Presenter-Token` header, checked against `PULSE_PRESENTER_TOKEN`.
- **Timestamps** are UTC, ISO-8601, named `created_at`.
- **Commit messages**: `<package>: <imperative summary>`, e.g.
  `poll-service: reject votes on a closed poll`.

## When you finish a task

State plainly: what you changed, which commands you ran, what passed, and anything you
skipped or could not verify. Do not report success for work you did not run.
