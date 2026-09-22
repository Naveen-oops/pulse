---
title: Troubleshooting
description: Real failures hit while building this, and what fixed them.
---

# Troubleshooting

Every entry here is something that actually broke during the build, not a hypothetical.

## Start here

```bash
npm run doctor
```

Tools, project state, and what is holding each port. Most "it does not work" is a missing
tool or a busy port, and this finds both in two seconds.

## A code change seems to have no effect

**Symptom.** You edit a Python file, the log says the server reloaded, and the behaviour
is unchanged.

```
WARNING:  WatchFiles detected changes in 'app\main.py'. Reloading...
```

…and then no `Started server process` line ever follows.

**Cause.** `uvicorn --reload` logged the intent and never actually restarted the worker.
Seen on Windows with the repo inside OneDrive — the file watcher and the sync client
interact badly.

**Fix.** Restart it.

```bash
# Ctrl+C, then
npm run dev
```

:::warning[This one cost real time]
I spent a debugging cycle convinced a database write was failing, because the API kept
returning old behaviour while the tests passed on the new code.

The tell: count the `Started server process` lines in the log. One per service means the
reload never completed. **If a change seems to do nothing, restart before you doubt the
code.**
:::

## Port already in use

```
❌ Port 8080 is in use, and the cluster needs it for ingress.
```

Find the owner:

```bash
# Windows
netstat -ano | findstr :8080
# macOS / Linux
lsof -i :8080
```

Common culprits are other local Kubernetes clusters — they often publish 80, 443 and
8080–8084.

```bash
docker ps --format "{{.Names}} | {{.Ports}}"
```

Either stop it, or move Pulse:

```bash
PULSE_INGRESS_PORT=19080 npm run cluster:up
```

Note that the ingress port is baked in at cluster creation, so changing it means
`npm run cluster:down` first.

## The API says the room does not exist

```json
{"detail":"No room with code CIT22A."}
```

The service and the seed are talking to different databases. Usually the service was
started before `.env` pointed at PostgreSQL.

```bash
# where is the data?
docker exec pulse-postgres psql -U pulse -d pulse -c "select code from polls.rooms;"

# a stray SQLite file means the service fell back
ls packages/poll-service/*.db
```

**Fix.** Restart the services so they pick up the current `.env`, then reseed:

```bash
npm run dev
npm run seed
```

## Python tests fail with a syntax error

```
SyntaxError: invalid syntax
```

You are on the wrong Python. The code targets 3.12 and uses syntax that 3.8 cannot parse.

```bash
.venv/Scripts/python.exe --version    # Windows
.venv/bin/python --version            # macOS / Linux
```

Should say 3.12.x. If not:

```bash
npm run clean && npm run setup
```

Always run tests through `npm test`, which uses the venv. A bare `pytest` may find your
system Python.

## ArgoCD install fails on a CRD

```
The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
metadata.annotations: Too long: may not be more than 262144 bytes
```

`kubectl apply` stores the whole manifest in an annotation, and this CRD exceeds the
256 KB limit.

**Fix.** Server-side apply — already in the script:

```bash
kubectl apply -n argocd --server-side --force-conflicts -f install.yaml
```

## ArgoCD will not sync

```
⚠️  No git remote yet — ArgoCD cannot sync from a repo that is not pushed
```

Not a bug. ArgoCD polls a **git URL**; it cannot see your working directory or an unpushed
commit.

```bash
git remote add origin https://github.com/<you>/Pulse.git
git push -u origin main
npm run cluster:argocd
```

## An upstream manifest 404s

```
error: unable to read URL "...", server reported 404 Not Found
```

Someone restructured a repo. This happened twice here: ingress-nginx is under
`kubernetes/`, not `kubernetes-sigs/`, and the path moved on `main`.

**Fix.** Pin a release tag rather than tracking `main`:

```bash
INGRESS_NGINX_VERSION="controller-v1.13.1"
```

Then verify before you rely on it:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "<the url>"
```

## `npm ci` fails inside the web Docker build

```
npm ci can only install packages when your package.json and package-lock.json are in sync
```

Or it cannot find a lockfile at all. In an npm workspace there is exactly one lockfile, at
the repo root — not in `packages/web`.

**Fix.** Build from the repo root:

```bash
docker build -f packages/web/Dockerfile -t pulse/web:dev .
```

Note the `-f` and the trailing dot.

## Pods stay Pending

```bash
kubectl -n pulse get pods
kubectl -n pulse describe pod <name>
```

Read the `Events` at the bottom — it almost always says exactly what is wrong.

| Message | Cause |
| --- | --- |
| `ImagePullBackOff` | Image not loaded into kind, or tagged `:latest` |
| `didn't match Pod's node affinity` | Missing `ingress-ready=true` label on the node |
| `pod has unbound immediate PersistentVolumeClaims` | Storage class still provisioning; wait |

For the image case:

```bash
npm run images     # rebuild and load into the node
```

Remember: a `:latest` tag makes Kubernetes try to pull from a registry and ignore your
locally loaded image. Use `:dev`.

## Browser automation times out clicking

If you script the UI with Playwright, Puppeteer or similar, clicks may time out even
though the page works.

**Cause.** The page polls every two seconds, so it never reaches network-idle, and tools
that wait for idle before acting wait forever.

**Fix.** Dispatch the click directly rather than using the idle-waiting helper, or
configure the tool not to wait for network idle. Real users are entirely unaffected.

## OneDrive file locks

```
rm: cannot remove 'apps/web': Device or resource busy
```

OneDrive holds handles while syncing. `node_modules` and `.venv` generate a lot of churn.

**Fix.** Retry after a few seconds, or on Windows:

```powershell
Remove-Item -LiteralPath "<path>" -Recurse -Force
```

**Better fix.** Exclude the repo from OneDrive sync, or keep it outside OneDrive
entirely. This removes a whole class of intermittent failures during installs.

## Shell scripts fail with `\r: command not found`

Line endings. The scripts must stay LF, which `.gitattributes` enforces:

```
*.sh text eol=lf
```

If you hit it, renormalise:

```bash
git rm --cached -r . && git reset --hard
```

## Still stuck

```bash
npm run doctor
npm run cluster:status
kubectl -n pulse logs -l app.kubernetes.io/name=poll-service --tail=100
docker compose -f docker-compose.dev.yml logs postgres
```

And the reset that fixes most local mysteries:

```bash
npm run clean && npm run setup
```
