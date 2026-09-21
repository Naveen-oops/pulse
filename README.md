# Pulse

A Slido-style live audience app: the presenter runs polls, the room votes from their
phones, and results update on screen within about two seconds.

Built as the teaching artifact for the **Build Smarter with Agentic Engineering**
session. The Q&A feature is deliberately *not* built — it is written live on stage by a
coding agent from [`docs/specs/qa-feature.md`](docs/specs/qa-feature.md).

## Quick start

```bash
npm run setup
npm run dev
```

`setup` is one command and idempotent. It installs uv, downloads a managed Python 3.12,
creates `.venv`, installs every dependency, starts PostgreSQL in Docker, writes `.env`,
and seeds room `CIT22A`. It falls back to SQLite if Docker is not running.

Then open:

| Screen | URL |
| --- | --- |
| Audience | http://localhost:5173/r/CIT22A |
| Presenter | http://localhost:5173/present/CIT22A |
| Admin | http://localhost:5173/admin |

The presenter and admin screens ask for a token — it is `demo-presenter-token` from `.env`.

## Commands

Everything runs from the repo root.

```bash
npm run dev              # all three services together
npm run web              # web only            (5173)
npm run poll-service     # poll API only       (8001)
npm run qa-service       # Q&A API only        (8002)

npm run db:up            # start PostgreSQL
npm run db:reset         # wipe it, restart, reseed
npm run seed:reset       # reseed and clear all votes

npm test                 # every test suite    (test:py, test:web)
npm run lint             # ruff + eslint
npm run format           # fix what can be fixed
npm run verify           # everything CI runs
npm run doctor           # check this machine's toolchain
npm run clean            # remove .venv, node_modules, dist, caches
```

All of it is one bash file — [`scripts/dev.sh`](scripts/dev.sh). The npm scripts are thin
wrappers so `npm run <thing>` works from anywhere.

## Layout

One directory per independently deployable package.

```
packages/
  web/              React 18 + Vite 5 + TypeScript — audience, presenter, admin
  poll-service/     FastAPI — rooms, polls, votes, results, export
  qa-service/       FastAPI — /healthz only; the live-build target
  crew/             CrewAI session report (phase 3)
deploy/             Kustomize + ArgoCD (phase 2)
docs/               specs and standards
scripts/            dev.sh — every development task
```

`qa-service` exists on `main` as a deployed hello-world with its own Dockerfile, CI
workflow and ingress route. That is deliberate: on stage the agent writes only feature
logic, never plumbing.

## Docs

| Document | What it covers |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | Rules coding agents must follow. Read first. |
| [`docs/architecture.md`](docs/architecture.md) | How it fits together and why |
| [`docs/quality.md`](docs/quality.md) | The quality bar and what enforces it |
| [`docs/decisions.md`](docs/decisions.md) | Decisions made, with their trade-offs |
| [`docs/specs/pulse-spec.md`](docs/specs/pulse-spec.md) | The full session spec |
| [`docs/specs/qa-feature.md`](docs/specs/qa-feature.md) | The feature built live on stage |

## Requirements

Node 18.18+, Git, and Docker (optional — SQLite is the fallback). Python is **not**
required: `npm run setup` downloads a managed CPython 3.12 through uv and leaves your
system Python untouched.

Run `npm run doctor` to check this machine.
