---
title: A local cluster
description: kind, an ingress controller, Kustomize overlays, and three real failures.
---

# A local cluster

```bash
npm run cluster:up
```

One command: creates a kind cluster, installs an ingress controller, builds and loads the
images, applies the manifests, waits for rollouts, and seeds the room.

First run takes around nine minutes — almost all of it downloading the ~1 GB node image.
After that it is cached and much faster.

```
🎉 Cluster is up. (527s)

  Open
    audience  http://localhost:18080/r/CIT22A
    presenter http://localhost:18080/present/CIT22A
```

## What kind is

kind = **K**ubernetes **in** **D**ocker. Each node is a container running a real
Kubernetes node. It is a genuine cluster — the same API, the same manifests — that you
can delete and recreate in a minute.

```yaml
# deploy/local/kind-cluster.yaml
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 18080
```

Two pieces of required plumbing:

- **`ingress-ready=true`** — the ingress-nginx manifest for kind has a node selector
  looking for this label. Without it the controller pod stays `Pending` forever with no
  obvious reason.
- **`extraPortMappings`** — a container's ports are not on your host unless published,
  and this must be set *at cluster creation*. Changing it later means recreating the
  cluster.

:::warning[Port 18080, and why it is not 8080]
`npm run cluster:up` failed on the first attempt:

```
❌ Port 8080 is in use, and the cluster needs it for ingress.
```

An unrelated kind cluster on the machine had published 80, 443 and 8080–8084. Rather
than fight it, Pulse moved to 18080/18443.

High ports are the better default for a local cluster: 80 and 8080 are the most
contested ports on any developer laptop, and a collision at cluster-creation time is
hard to spot because the failure surfaces much later as an ingress that never responds.
:::

## No registry needed

```bash
kind load docker-image pulse/poll-service:dev --name pulse
```

`kind load` copies an image straight from your local Docker into the node. No registry,
no push, no pull, no credentials — and it works with no network.

The `:dev` tag matters. Kubernetes defaults `imagePullPolicy` to `Always` for `:latest`
and `IfNotPresent` for any other tag. Tag it `:latest` and the kubelet tries to pull from
Docker Hub, fails, and your locally loaded image is ignored.

:::info[Why this matters]
A common instinct is to move image builds to CI and pull them locally. For this local
path that is strictly worse: it adds a network dependency and a registry login to the
moment you can least afford them — live, in front of people.

Local build plus `kind load` is ~13 seconds for a code change and works on a plane. CI
build plus registry push is the right answer for *cloud* deploys, where the cluster
cannot see your Docker daemon. Both exist in this repo, each where it belongs.
:::

## Kustomize: one base, several overlays

```
deploy/
  base/                  what is always true
  overlays/local/        locally built :dev images, demo credentials
  overlays/demo/         GHCR images written by CI, secrets from the cluster
```

```yaml
# deploy/overlays/local/kustomization.yaml
resources:
  - ../../base

images:
  - name: pulse/poll-service
    newTag: dev
```

```bash
# see exactly what will be applied, before applying it
kubectl kustomize deploy/overlays/local
```

Kustomize takes plain YAML and patches it. No templating language, no `{{ }}`, and the
base stays valid Kubernetes YAML you can `kubectl apply` on its own.

:::tip[Secrets are handled differently in each overlay, on purpose]
`overlays/local` contains a literal password — `pulse` — committed to git. That is
deliberate and safe: the cluster is a throwaway on your laptop and the value matches
`.env.example`.

`overlays/demo` contains **no secrets at all**. They are created once in the cluster with
`kubectl create secret`, and because they are not in the repo, ArgoCD never sees them and
never prunes them.

Copying the local pattern to a real cluster is how credentials end up in git history
forever. The overlays are separate so the convenient thing and the correct thing cannot
be confused.
:::

## Two failures worth knowing about

**The ingress-nginx URL was wrong in two ways.** It is under `kubernetes/`, not
`kubernetes-sigs/`, and the manifest path has moved on `main`:

```
error: unable to read URL ".../kubernetes-sigs/ingress-nginx/main/...", 404 Not Found
```

It is now pinned to a release tag, `controller-v1.13.1`. Pinning is the real lesson: an
unpinned `main` URL turns someone else's refactor into your broken demo.

**ArgoCD needs server-side apply.**

```
The CustomResourceDefinition "applicationsets.argoproj.io" is invalid:
metadata.annotations: Too long: may not be more than 262144 bytes
```

`kubectl apply` stores the entire manifest in a `last-applied-configuration` annotation
so it can compute diffs later. ArgoCD's ApplicationSet CRD is larger than the 256 KB
annotation limit. `--server-side` moves that bookkeeping into the API server, where it is
not an annotation:

```bash
kubectl apply -n argocd --server-side --force-conflicts -f install.yaml
```

## Useful commands

```bash
npm run cluster:status       # pods, ingress, ArgoCD app
npm run cluster:seed         # reseed the room inside the cluster
npm run cluster:down         # delete the cluster
kubectl -n pulse get pods
kubectl -n pulse logs -l app.kubernetes.io/name=poll-service --tail=50
```

---

**[GitOps →](/kubernetes/gitops)**
