---
title: The CI pipeline
description: Path filtering, caching, and a four-minute budget from merge to running pod.
---

# The CI pipeline

The target is stated up front: **merge to running pod in under four minutes.** Every
choice in the workflow serves that number, because a pipeline slow enough to context
switch away from is a pipeline nobody watches.

## Only build what changed

```yaml
# .github/workflows/ci.yml
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            poll-service:
              - 'packages/poll-service/**'
              - '.github/workflows/ci.yml'
            web:
              - 'packages/web/**'
              - 'package.json'
              - 'package-lock.json'
```

Every later job checks its own flag. Edit a CSS file and the Python services are not
tested, not built, not pushed.

Two details worth copying:

**The workflow file is in every filter.** Change CI itself and everything rebuilds — you
want that, because you have just changed how things are built.

**The web filter includes the root `package.json` and lockfile.** In a workspace, a
dependency change lives at the root, not in the package. Miss this and you ship a build
with stale dependencies.

:::info[Why this matters]
Path filtering is how a monorepo stays fast as it grows. Without it, every commit pays
the cost of every package, and CI time grows with the repo instead of with the change.

The failure mode to watch for is filters that are too *narrow* — a package that reads a
shared file and is not rebuilt when that file changes. Err toward rebuilding more than
you think you need; a wasted build costs minutes, a missed one ships a bug.
:::

## Caching

```yaml
- uses: astral-sh/setup-uv@v5
  with:
    enable-cache: true
    cache-dependency-glob: packages/${{ matrix.package }}/requirements*.txt
```

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 20
    cache: npm
```

```yaml
- uses: docker/build-push-action@v6
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

Three caches, three layers: Python packages, npm packages, Docker layers. The
`cache-dependency-glob` is keyed on the requirements files, so the cache invalidates
exactly when dependencies change and not when source does.

`type=gha` is GitHub's own layer cache. Without it every build reinstalls every
dependency from scratch, and four minutes is not reachable.

## Test before build

```yaml
build:
  needs: [changes, test-python, test-web]
  if: |
    always() &&
    github.ref == 'refs/heads/main' &&
    github.event_name == 'push' &&
    !contains(needs.*.result, 'failure')
```

Read that condition carefully, because it is the subtle part.

`always()` is required because a sibling test job may have been **skipped** by its path
filter. By default a skipped dependency skips the job that needs it — so a CSS-only
change would skip `test-python`, which would skip `build`, and nothing would deploy.

`!contains(needs.*.result, 'failure')` then does the actual gating: run if nothing
upstream *failed*, whether or not it ran.

:::warning[`always()` without the failure check is a trap]
`always()` on its own means *always* — including when the tests failed. You would build
and deploy a red commit.

The two clauses must travel together: `always()` to tolerate skips,
`!contains(..., 'failure')` to still respect failures.
:::

## Two tags per image

```yaml
tags: |
  ${{ env.REGISTRY }}/${{ github.repository_owner }}/pulse-${{ matrix.package }}:${{ github.sha }}
  ${{ env.REGISTRY }}/${{ github.repository_owner }}/pulse-${{ matrix.package }}:latest
```

The **SHA tag** is what the deployment references. It is immutable — that exact tag will
always be that exact image, so a rollback is a real rollback and not a guess.

The **`latest` tag** is for humans doing a quick `docker run`. Nothing in `deploy/` ever
references it.

:::tip[Never deploy a mutable tag]
`image: myapp:latest` means you cannot answer "what is running right now?" and cannot
roll back with confidence — the tag you would roll back *to* has moved too.

Deploy immutable tags. Digests are even better. It is the difference between a deployment
history and a rumour.
:::

## The build context differs per package

```yaml
- package: poll-service
  context: packages/poll-service
  dockerfile: packages/poll-service/Dockerfile
# web builds from the repo root: the npm workspace lockfile lives there.
- package: web
  context: .
  dockerfile: packages/web/Dockerfile
```

The Python services get a tiny context — just their own directory. The web build needs
the repo root because `npm ci` needs the workspace lockfile. The matrix carries both, so
the asymmetry is visible in one place rather than hidden in a script.

## What CI does not have

No cluster credentials. No `kubectl`. No cloud login.

CI's most privileged action is writing a commit. Everything that touches the cluster is
ArgoCD's job, running *inside* the cluster, pulling from git.

:::info[Why this is worth the indirection]
A pipeline with production credentials is a pipeline that can destroy production — and
CI runs third-party actions on every push. That is a large attack surface holding a large
key.

Pulling instead of pushing means the credential never leaves the cluster. It is also why
you can let people fork the repo and run CI on their own branches without handing them
anything.
:::

## Run the same checks locally

```bash
npm run verify
```

Lint, type check, tests, production build — the same set, in about two minutes. A red CI
you could have caught locally is just a slower way to find out.

---

**[Rules for your agent →](/agentic/rules)**
