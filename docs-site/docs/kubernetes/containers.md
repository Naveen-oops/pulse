---
title: Containers
description: Multi-stage builds, non-root users, and why the web image builds from the repo root.
---

# Containers

Three images. Each one is small, rebuilds fast, and runs as a non-root user.

```bash
npm run images
```

## The Python pattern

```docker
# packages/poll-service/Dockerfile
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app ./app

RUN useradd --system --uid 10001 pulse && chown -R pulse /app
USER pulse

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

Three things are doing real work here.

**`requirements.txt` is copied before the source.** Docker caches layers, and a layer is
invalidated only when its inputs change. Dependencies change rarely; source changes on
every commit. Copying them in that order means editing a Python file does not reinstall
FastAPI.

The measured difference on this repo:

| Change | Rebuild |
| --- | --- |
| Nothing (warm cache) | 22s for all three |
| One line of Python | **13s** |

**The venv is built in one stage and copied to another.** `pip` itself, its cache and
build tooling never reach the final image — only the installed packages.

**`USER pulse`.** A container process running as root is root on the host kernel if
anything escapes. Dropping to a non-root UID costs two lines.

:::info[Why this matters]
`PYTHONDONTWRITEBYTECODE=1` and `PYTHONUNBUFFERED=1` look like noise and are not.

Without the first, Python writes `.pyc` files into the image at runtime — pointless
writes to a layer that is thrown away. Without the second, stdout is block-buffered, so
your logs arrive in chunks, or not at all when a container is killed. You end up
debugging a crash with no output from the seconds before it.
:::

## The web image is different

```docker
# packages/web/Dockerfile — build from the REPO ROOT
FROM node:20-alpine AS builder

WORKDIR /build

COPY package.json package-lock.json ./
COPY packages/web/package.json packages/web/
RUN npm ci --no-audit --no-fund

COPY packages/web packages/web
RUN npm run build --workspace pulse-web

FROM nginx:1.27-alpine

COPY packages/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /build/packages/web/dist /usr/share/nginx/html

EXPOSE 8080
```

```bash
# note the -f and the trailing dot
docker build -f packages/web/Dockerfile -t pulse/web:dev .
```

:::warning[This one caught me]
My first version built from `packages/web` and ran `npm ci`. It failed immediately:
**`npm ci` requires a lockfile**, and in an npm workspace there is exactly one, at the
repo root — not in the package.

So the web build context has to be the repo root. That is what `.dockerignore` at the
root is for: it keeps `.git`, `node_modules`, `.venv`, the Python packages and — most
importantly — `.env` out of the build context.

My first `.dockerignore` also excluded `eslint.config.js`, which `tsconfig.json` lists in
`include`, so `tsc -b` failed on a missing file. Both bugs took one build each to find,
which is the argument for building the image rather than trusting the Dockerfile.
:::

## nginx serves, the ingress routes

```nginx
# packages/web/nginx.conf
location /assets/ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}

location = /index.html {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}

location / {
    try_files $uri $uri/ /index.html;
}
```

Three rules that matter for any SPA:

- **Hashed assets cache for a year.** Vite puts a content hash in each filename, so the
  URL changes when the content does. It can never be stale.
- **`index.html` is never cached.** It contains the links to those hashed files. Cache it
  and a browser will keep loading the *old* bundle names after you deploy — a 404 storm
  that clears only when the cache expires.
- **`try_files … /index.html`** makes client-side routes work. `/present/CIT22A` is not a
  file on disk; without this line, a refresh on that URL is a 404.

:::tip[The cache pair is one decision, not two]
Long-cache the hashed assets *and* no-cache the entry point. Doing only the first is the
classic broken deploy. Every SPA needs both halves.
:::

## Port 8080, not 80

The nginx container listens on 8080 because binding ports below 1024 needs privileges,
and the point of a non-root container is not to have them. The Kubernetes `Service` maps
80 to 8080, so nothing downstream notices.

---

**[A local cluster →](/kubernetes/local-cluster)**
