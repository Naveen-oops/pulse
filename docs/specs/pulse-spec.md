# Pulse: Live Audience App — Demo Spec and Build Plan

> Source of truth for the "Build Smarter with Agentic Engineering" session.
> Exported from `EventHub Demo Requirements and Build Plan.docx` (Sep 21, 2026).

## Decision and confidence

We build **Pulse**, a Slido-style live audience app: polls as the base, Q&A with
upvotes built live on stage, and a CrewAI session report from the audience's own input.

- One sentence for the audience: *"It's Slido, and we're adding a feature to it live."*
- Base in one prompt? Yes for the app code — it is small (one API service, one frontend,
  one database). The infra gets its own prompt.
- **Confidence rule:** the plan is ready when the Q&A feature has been built from scratch
  on a branch at least twice, each time in under 15 minutes, and deployed through ArgoCD.

| Segment | Time | Audience does |
| --- | --- | --- |
| Base app tour | inside the 45 min | Votes in a poll from their phones |
| Live Q&A build: Cowork, Eraser, Cursor, PR, ArgoCD | 45 min total | Posts and upvotes questions after deploy |
| CrewAI session report | 20 min | Sees their input summarized |

## Base app spec (built on `main`)

The base lets a presenter run live polls: create a poll, show a QR, audience votes from
phones, results update on screen within about 2 seconds.

### Entities

| Entity | Fields |
| --- | --- |
| Room | `id`, `code` (6 characters, e.g. `CIT22A`), `title`, `created_at` |
| Poll | `id`, `room_id`, `question`, `options` (list), `is_open`, `created_at` |
| Vote | `id`, `poll_id`, `option_index`, `device_id`, `created_at` |

### Screens

- **Presenter view** (`/present/{code}`): current poll, live bar chart, large QR code
  linking to the audience view. Protected by a presenter token from config.
- **Audience view** (`/r/{code}`): mobile-first; shows the open poll and vote buttons. No login.
- **Admin** (`/admin`): create a room, add polls, open or close a poll. Presenter token required.

### API (poll-service)

- `POST /rooms`, `GET /rooms/{code}`
- `POST /rooms/{code}/polls`, `PATCH /polls/{id}` (open or close)
- `POST /polls/{id}/votes`
- `GET /polls/{id}/results`
- `GET /rooms/{code}/export` (JSON of polls and results; CrewAI reads this)
- `GET /healthz`

### Acceptance criteria

- A device votes once per poll; `device_id` is a random id stored in the browser; a second
  vote is rejected with a friendly message.
- Votes on a closed poll are rejected.
- Presenter chart refreshes by polling every 2 seconds (no WebSockets, for reliability).
- Audience view works on a phone screen and loads in under 2 seconds on mobile data.
- Unit tests cover one-vote-per-device, closed poll and results counting; CI runs them.
- Seed: one room `CIT22A` titled "Build Smarter" with 3 polls:
  1. "Which AI coding tool have you used?"
  2. "How much of your code could AI write today?"
  3. "Biggest worry about AI in engineering education?"

## Repo layout, stack and infra

Everything lives in a personal GitHub repo and deploys to a local Kubernetes cluster on the
demo laptop, with ArgoCD syncing from the repo.

```
pulse/
  packages/web/            React + Vite + TypeScript (presenter, audience, admin)
  packages/poll-service/   FastAPI + PostgreSQL (base)
  packages/qa-service/     FastAPI skeleton: /healthz only on main (live feature lands here)
  packages/crew/           CrewAI session report
  deploy/                  Kustomize per service + ArgoCD Application
  scripts/dev.sh           every development task, one dispatcher
  .github/workflows/       CI per package, path-filtered
  docs/specs/              Cowork spec lands here live
  AGENTS.md                rules for coding agents
  .cursorignore            excludes .env, kubeconfig, secrets
```

> One directory per independently deployable package. See
> [`docs/decisions.md`](../decisions.md) for why this shape rather than `apps/` +
> `services/`.

**Key trick for the live build:** `qa-service` already exists on `main` as a deployed
hello-world, with its Dockerfile, CI workflow, manifests and ingress route. On stage the
agent only writes feature logic and UI, not plumbing. This removes the riskiest 10 minutes.

| Piece | Choice |
| --- | --- |
| Database | One PostgreSQL deployment; one schema per service |
| Images | GitHub Actions builds, pushes to GHCR, tags with the commit SHA |
| GitOps | CI commits the new tag into `deploy/`; ArgoCD auto-sync picks it up |
| Ingress | ingress-nginx on kind: `/api/polls` → poll-service, `/api/qa` → qa-service, `/` → web |
| Phone access | Cloudflare quick tunnel (`cloudflared tunnel --url`) to the ingress; HTTPS URL for the QR |
| LLM routing | LiteLLM proxy for the CrewAI crew and any AI button, with a budget cap |

> **Deviation from the original doc:** the doc specified k3d + Traefik. This build targets
> **kind + ingress-nginx** because kind is what is installed on the demo laptop. See
> [`docs/decisions.md`](../decisions.md) for the full list of deviations.

- **CI target:** merge to running pod in under 4 minutes. Slim base images and dependency
  caching help most.
- `AGENTS.md` states: stack, test command per service, "never read `.env` or kubeconfig",
  "do not change `deploy/` or CI unless asked".

## Live MVP feature: Q&A with upvotes (built on stage)

Attendees post questions from the same audience page, upvote others, and the presenter
screen shows questions ranked live.

### User stories

- As an attendee, I post a question in the room without logging in.
- As an attendee, I upvote a question once.
- As the presenter, I see questions sorted by votes, refreshed every 2 seconds, and can
  mark one answered or hide it.

### Acceptance criteria

- Question text 5 to 280 characters; empty or too long is rejected with a message.
- One upvote per device per question; a second upvote is ignored.
- Hidden questions disappear from audience and presenter views; only the presenter token
  can hide or mark answered.
- Basic rate limit: at most 5 questions per device per minute.
- `GET /rooms/{code}/questions/export` returns questions with votes and status
  (CrewAI reads it).
- Tests cover length limits, duplicate upvote, hide and rate limit.

### Where it lands

| Part | Location |
| --- | --- |
| Question and upvote logic, export | `packages/qa-service` |
| "Ask" tab on audience page | `packages/web` |
| Ranked question panel beside the poll chart | `packages/web` |

### Stage beats

1. **Cowork:** brainstorm requirements; save as `docs/specs/qa-feature.md`.
2. **Eraser:** one flow diagram — audience posts, qa-service stores, presenter panel polls.
3. **Cursor agent mode:** "Implement `docs/specs/qa-feature.md`."
4. **Review moment:** check the diff for the upvote and rate-limit rules. If the agent
   skipped either, ask for it plus a test. This is the human-in-the-loop point.
5. **PR, merge, ArgoCD sync,** then: *"Scan the QR and ask me anything."*

Stretch, only if ahead of time: a "Group questions" button that sends the list through
LiteLLM and returns 3 to 5 themes. Leave it off the critical path.

## CrewAI: session report crew

A three-agent sequential crew turns the room's poll results and questions into a one-page
session report; it runs on a free LLM tier through LiteLLM.

| Agent | Task | Output |
| --- | --- | --- |
| Audience analyst | Read poll results and questions; find what the audience knew, asked most and was unsure about | Findings |
| Report writer | Write the report: audience snapshot, top questions, confusion points, follow-up topics | Draft |
| Reviewer | Check every number against the export; flag any claim not backed by data | Final report + flags |

- **Layout:** `crew/` with `agents.yaml`, `tasks.yaml`, `main.py` (CrewAI's standard project structure).
- **Input:** `export.json` built from the two export endpoints. Live, run a small script that
  fetches both; offline, use a saved file.
- **Output:** `report.md`, opened on screen.
- **LLM:** `OPENAI_API_BASE` pointed at LiteLLM, routing to Gemini Flash (free), with Groq
  as the fallback route.
- **Acceptance:** one command, under 2 minutes, numbers match the export, fixed section order.

20-minute flow: why this is a workflow, not a coding task (2) · walk through the YAML roles (5)
· run it on the live room data (5) · open the report, point at a reviewer flag (4) · where this
pattern fits and breaks, and cost per run (4).

Mention n8n in one line as the same category: config-driven automation for repeatable work.

## Build plan

Five phases. Stop once phase 4 passes twice.

| Phase | Goal | Est. time | Done when |
| --- | --- | --- | --- |
| 1. Base app | Prompt 1 in Claude Code | 60–90 min | Polls work locally; tests pass |
| 2. Infra | Prompt 2 | 60–90 min | Push to main, ArgoCD deploys, phone opens the tunnel URL |
| 3. CrewAI | Prompt 3 | 30–45 min | `report.md` generated from a saved export |
| 4. MVP rehearsal | Build Q&A in Cursor from scratch on a branch | 2 runs, 20 min each | Deployed and working, under 15 min of agent time |
| 5. Freeze | Tag and prepare fallbacks | 20 min | Branches below exist; `main` is clean |

### Branches

- `main` — base app + qa-service skeleton, deployed. **This is what you demo from.**
- `rehearsal/qa-1`, `rehearsal/qa-2` — practice runs; keep them to compare what the agent did.
- `demo/qa-done` — best finished Q&A feature, ready to merge if the live build stalls.
- `demo/crew-output` — saved `export.json` and `report.md` in case the LLM is throttled.

After each rehearsal, reset the cluster to `main` (ArgoCD sync to the main commit) so you
practise the real starting state.

### Morning-of checklist

- [ ] Cluster up, ArgoCD synced to `main`, tunnel running, QR opens on your phone over mobile data
- [ ] Room `CIT22A` seeded with 3 polls; votes cleared
- [ ] LiteLLM running with budget set; one test call succeeds
- [ ] Cursor, Claude (Cowork) and Eraser signed in; Eraser credit count checked
- [ ] `.env`, kubeconfig and personal tabs closed before screen share

## Risks and fallbacks

Every live step has a fallback reachable in under 30 seconds. If one fires, say so openly —
that is part of the lesson.

| Risk | Fallback |
| --- | --- |
| Infra not working by midnight | Demo from docker-compose locally and show ArgoCD from a screenshot |
| Cursor agent stalls or drifts on stage | Merge `demo/qa-done` and review that diff instead |
| CI slower than 4 minutes | Explain the pipeline and ArgoCD while it builds |
| Tunnel or venue network blocks phones | Scan from your own phone on camera; vote from a second browser window |
| Audience spams the Q&A | Presenter hide button and rate limit; this becomes a live security point |
| Eraser generation fails or credits run out | Show a pre-generated diagram |
| Free LLM tier throttled during CrewAI | Switch the LiteLLM route to Groq; last resort, `demo/crew-output` |
| Secrets on a recorded screen | `.cursorignore`, `AGENTS.md` rule, and close files before sharing |

**Not in scope:** auth beyond a presenter token, WebSockets, multiple concurrent rooms in the
UI, email, and the AI "Group questions" stretch.
