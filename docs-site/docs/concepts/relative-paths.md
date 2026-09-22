---
title: Relative paths only
description: How the same build runs on a laptop and in a cluster with no config change.
---

# Relative paths only

The web app never knows what host its backend is on. Every call looks like this:

```ts
// packages/web/src/api.ts
const POLLS = '/api/polls'

export function getRoom(code: string): Promise<Room> {
  return request<Room>(`${POLLS}/rooms/${encodeURIComponent(code)}`)
}
```

No `VITE_API_URL`. No `import.meta.env`. No environment-specific build. The same
JavaScript bundle runs on your laptop, in a Kubernetes cluster, and behind a public
tunnel.

## Who resolves the path

Something in front always routes it — a different something in each environment, and the
app cannot tell:

| Environment | Router | How |
| --- | --- | --- |
| Local dev | Vite dev server | `server.proxy` in `vite.config.ts` |
| Docker / Kubernetes | ingress-nginx | `Ingress` rules in `deploy/base/ingress.yaml` |
| Azure Container Apps | nginx in the web image | `proxy_pass` to the internal FQDNs |

```ts
// packages/web/vite.config.ts
proxy: {
  '/api/polls': { target: 'http://127.0.0.1:8001', changeOrigin: true },
  '/api/qa': { target: 'http://127.0.0.1:8002', changeOrigin: true },
}
```

```yaml
# deploy/base/ingress.yaml
- path: /api/polls
  pathType: Prefix
  backend:
    service:
      name: poll-service
```

:::info[Why this matters]
The usual approach is a build-time environment variable: `VITE_API_URL` baked into the
bundle. It works, and it fails in a specific, recognisable way — you rebuild for each
environment, and one day you ship the staging bundle to production and every request
goes to the wrong host.

Relative paths remove the variable, and with it the whole failure mode. There is no
value to set wrong because there is no value.

The cost is that you need a router in front in every environment. That is not really a
cost — you already have one. In development it is the dev server you are running anyway;
in production it is the ingress you need regardless.
:::

## The prefix is real, not rewritten

Notice there is no rewrite rule anywhere. The ingress does **not** strip `/api/polls`
before forwarding. Instead, the service genuinely serves that prefix:

```python
# packages/poll-service/app/config.py
api_prefix=os.getenv("PULSE_API_PREFIX", "/api/polls")
```

```python
# packages/poll-service/app/main.py
router = APIRouter(prefix=settings.api_prefix)
```

So the path the browser sends is the path the service expects, unchanged, end to end.

:::tip[Why avoid rewrites]
Rewrite rules are a classic source of "works locally, 404s in the cluster". They are
invisible in the application, configured in a different system, and they interact badly
with redirects, generated links and OpenAPI docs.

Making the prefix part of the service's own identity means there is one path, and you
can `curl` it identically at every layer:

```bash
curl http://localhost:8001/api/polls/healthz        # direct
curl http://localhost:18080/api/polls/healthz       # through the ingress
```

Same path. Same response. Nothing in between is lying to you.
:::

## `/healthz` twice, on purpose

```python
@app.get("/healthz")       # for Kubernetes probes
@router.get("/healthz")    # for the ingress path
def healthz() -> dict[str, str]:
    return {"status": "ok", "service": "poll-service"}
```

Kubernetes probes the pod directly at `/healthz` — no ingress involved, so no prefix.
Anything coming through the ingress arrives at `/api/polls/healthz`. Registering both
costs one line and means neither caller needs a special case.

---

**[Tests as the spec →](/concepts/tests)**
