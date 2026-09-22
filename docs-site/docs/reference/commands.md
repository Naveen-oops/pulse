---
title: Every command
description: The full list. All of it runs from the repo root.
---

# Every command

Everything runs from the repo root. All of it dispatches to one file,
[`scripts/dev.sh`](https://github.com/Naveen-oops/pulse/blob/main/scripts/dev.sh), through a
small Node launcher that resolves the right bash on any OS.

```bash
npm run help     # this list, in your terminal
```

## Setup

| Command | What it does |
| --- | --- |
| `npm run setup` | One-time and idempotent: uv, Python 3.12, `.venv`, npm deps, `.env`, PostgreSQL, seed |
| `npm run doctor` | Check this machine — tools, project state, ports |
| `npm run clean` | Remove `.venv`, `node_modules`, `dist`, caches. Keeps `.env` and Docker volumes |

## Run

| Command | Port |
| --- | --- |
| `npm run dev` | All three together, colour-coded logs |
| `npm run web` | 5173 |
| `npm run poll-service` | 8001 |
| `npm run qa-service` | 8002 |
| `npm run crew` | CrewAI session report |

Override a port with an environment variable: `POLL_SERVICE_PORT`, `QA_SERVICE_PORT`.

## Data

| Command | What it does |
| --- | --- |
| `npm run db:up` | Start PostgreSQL in Docker |
| `npm run db:down` | Stop it, keep the data |
| `npm run db:reset` | Destroy the volume, restart, reseed |
| `npm run db:status` | Container status |
| `npm run seed` | Seed room `CIT22A` |
| `npm run seed:reset` | Seed and clear all votes |

`seed:reset` is the one to run between rehearsals — it clears votes without touching the
polls.

## Quality

| Command | What it does |
| --- | --- |
| `npm test` | Every suite — 82 tests |
| `npm run test:py` | Python only |
| `npm run test:web` | Web only |
| `npm run lint` | ruff + eslint |
| `npm run format` | Fix what can be fixed automatically |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run build` | Production web build |
| `npm run verify` | Everything CI runs, about two minutes |

## Kubernetes

| Command | What it does |
| --- | --- |
| `npm run cluster:up` | kind cluster + ingress-nginx + images + deploy + seed |
| `npm run cluster:argocd` | Install ArgoCD and apply the Application |
| `npm run cluster:status` | Pods, ingress, ArgoCD app |
| `npm run cluster:seed` | Reseed inside the cluster |
| `npm run cluster:down` | Delete the cluster |
| `npm run images` | Build images and load them into kind |
| `npm run tunnel` | Public HTTPS URL via Cloudflare quick tunnel |

`cluster:up` downloads `kind` into `.tools/` if you do not have it. Nothing is installed
system-wide.

## URLs

### Local dev (`npm run dev`)

| Screen | URL |
| --- | --- |
| Audience | http://localhost:5173/r/CIT22A |
| Presenter | http://localhost:5173/present/CIT22A |
| Admin | http://localhost:5173/admin |
| poll-service health | http://localhost:8001/healthz |
| poll-service API docs | http://localhost:8001/docs |
| qa-service health | http://localhost:8002/healthz |

### Cluster (`npm run cluster:up`)

| Screen | URL |
| --- | --- |
| Audience | http://localhost:18080/r/CIT22A |
| Presenter | http://localhost:18080/present/CIT22A |
| Admin | http://localhost:18080/admin |

Port 18080, not 8080 — see [A local cluster](/kubernetes/local-cluster).

### ArgoCD UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8090:443
```

Then https://localhost:8090, username `admin`. The password is printed by
`npm run cluster:argocd`, or:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

## The API, by hand

```bash
# the presenter token, from .env
T="X-Presenter-Token: demo-presenter-token"
API=http://localhost:8001/api/polls

curl $API/healthz
curl $API/rooms/CIT22A
curl $API/polls/1/results
curl $API/rooms/CIT22A/export          # what CrewAI reads

# vote
curl -X POST $API/polls/1/votes \
  -H "Content-Type: application/json" \
  -d '{"option_index":1,"device_id":"device-demo-01"}'

# open a poll (presenter only)
curl -X PATCH $API/polls/2 -H "$T" \
  -H "Content-Type: application/json" -d '{"is_open":true}'
```

## Docs site

```bash
cd docs-site
npm start        # dev server with hot reload, port 3000
npm run build    # static build into docs-site/build
npm run serve    # serve the production build
```

## Environment variables

Every one of these has a working default. `.env` is created by `npm run setup` and is
gitignored.

| Variable | Default | Used by |
| --- | --- | --- |
| `PULSE_PRESENTER_TOKEN` | `demo-presenter-token` | both services |
| `PULSE_CORS_ORIGINS` | `http://localhost:5173,...` | both services |
| `PULSE_DATABASE_URL` | SQLite file | poll-service |
| `PULSE_DB_SCHEMA` | unset (SQLite has none) | poll-service |
| `QA_DATABASE_URL` | SQLite file | qa-service |
| `QA_DB_SCHEMA` | unset | qa-service |
| `POLL_SERVICE_PORT` | `8001` | dev script |
| `QA_SERVICE_PORT` | `8002` | dev script |
| `PULSE_INGRESS_PORT` | `18080` | cluster script |

---

**[Troubleshooting →](/reference/troubleshooting)**
