# Pulse

A Slido-style live audience app: the presenter runs polls, the room votes from their
phones, and results update on screen within about two seconds.

Built as the teaching artifact for the **Build Smarter with Agentic Engineering**
session. The Q&A feature is deliberately *not* built — it is written live on stage by a
coding agent from [`docs/specs/qa-feature.md`](docs/specs/qa-feature.md).

## Session resources

Material from the **Build Smarter with Agentic Engineering** session. Start here.

| Resource | Where |
| --- | --- |
| **Tutorial** — setup, architecture, Kubernetes, CI/CD, agentic engineering | [`docs-site/`](docs-site/docs) — run `cd docs-site && npm start` |
| **Run sheet** — how the session was delivered, beat by beat | [`docs-site/docs/runsheet.md`](docs-site/docs/runsheet.md) |
| **Participant assessment** — 10 MCQs with answer key | [`docs/assessment/`](docs/assessment) |
| **Agent rules** — what a coding agent must follow here | [`AGENTS.md`](AGENTS.md) |
| **The live-build spec** — what the agent implemented on stage | [`docs/specs/qa-feature.md`](docs/specs/qa-feature.md) |
| **Design decisions** — every trade-off, with its cost | [`docs/decisions.md`](docs/decisions.md) |

### Live deployment

The session ran on Azure Container Apps. While that deployment is up, these work with no
setup at all — just open them:

| | |
| --- | --- |
| **Tutorial site** | https://pulse-docs.victoriouscliff-b6c1062a.centralindia.azurecontainerapps.io/docs/ |
| **Audience** (vote from your phone) | https://pulse-web.victoriouscliff-b6c1062a.centralindia.azurecontainerapps.io/r/CIT22A |
| **Presenter** (QR + live chart) | https://pulse-web.victoriouscliff-b6c1062a.centralindia.azurecontainerapps.io/present/CIT22A |
| **Admin** (create rooms and polls) | https://pulse-web.victoriouscliff-b6c1062a.centralindia.azurecontainerapps.io/admin |

The presenter and admin screens ask for a token, which is not published here — ask the
session facilitator if you need it. The audience view needs nothing.

> These URLs are a temporary demo deployment and will be taken down. If they are unreachable,
> run it locally instead — that path is permanent and takes one command.

**Reproduce the whole thing locally:**

```bash
git clone https://github.com/Naveen-oops/pulse && cd pulse && npm run setup
```

No prior Python, Docker or Kubernetes knowledge required — setup fetches its own toolchain
and leaves your system Python untouched.

### The path through the material

1. **[Set up and tour the app](docs-site/docs/setup.md)** — get it running, vote from your phone
2. **[Why it is built this way](docs-site/docs/concepts/polling.md)** — four decisions with real
   trade-offs, including two that look wrong until you hear the reason
3. **[Ship it](docs-site/docs/kubernetes/containers.md)** — containers, a local cluster, and a
   commit that deploys itself
4. **[Agentic engineering](docs-site/docs/agentic/rules.md)** — constrain the agent, write the
   spec, build the feature, then **review what it actually wrote**

Step 4 is the point. Writing code stopped being the bottleneck; knowing whether the code is
right is the durable skill.

---

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
