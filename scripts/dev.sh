#!/usr/bin/env bash
#
# Pulse — the single entrypoint for every development task.
#
#   ./scripts/dev.sh <command> [args]     or, from the repo root:  npm run <command>
#
# Run  ./scripts/dev.sh help  to see everything.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

COMPOSE="docker compose -f docker-compose.dev.yml"

# ============================================================================
#  setup — one-time, idempotent
# ============================================================================

cmd_setup() {
  banner "🚀 Pulse — one-time setup"

  # --- uv -------------------------------------------------------------------
  step "🔍 Looking for uv"
  if UV="$(find_uv)"; then
    ok "uv $("$UV" --version | awk '{print $2}')"
    note "$UV"
  else
    warn "uv not found — installing it now"
    if command -v winget >/dev/null 2>&1; then
      run winget install --id=astral-sh.uv -e --source winget \
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    elif command -v brew >/dev/null 2>&1; then
      run brew install uv
    elif command -v curl >/dev/null 2>&1; then
      hint "Installing from https://astral.sh/uv"
      curl -LsSf https://astral.sh/uv/install.sh | sh
    else
      die "Could not install uv automatically.
   👉 https://docs.astral.sh/uv/getting-started/installation/"
    fi
    UV="$(find_uv)" || die "uv installed but not on PATH yet.
   👉 Open a new terminal and run 'npm run setup' again."
    ok "uv installed"
  fi

  # --- python ---------------------------------------------------------------
  step "🐍 Preparing Python 3.12 and the virtualenv"
  if venv_python >/dev/null 2>&1; then
    ok "$("$(venv_python)" --version)  (.venv already exists)"
  else
    info "Downloading a managed CPython — your system Python is left untouched"
    "$UV" python install 3.12 >/dev/null 2>&1 || true
    run "$UV" venv --python 3.12 .venv \
      || die "Could not create the virtualenv.
   👉 Try: $UV python install 3.12"
    ok "$("$(venv_python)" --version) created in .venv"
  fi

  step "📦 Installing Python dependencies"
  run "$UV" pip install --python "$(venv_python)" --quiet \
    -r packages/poll-service/requirements-dev.txt \
    -r packages/qa-service/requirements-dev.txt
  ok "poll-service + qa-service ready"

  # --- node -----------------------------------------------------------------
  step "📗 Installing Node dependencies"
  run npm install --no-audit --no-fund --silent
  ok "workspace dependencies ready"

  # --- env ------------------------------------------------------------------
  step "🔐 Configuring .env"
  if [ -f .env ]; then
    ok ".env already exists — leaving your values alone"
  else
    cp .env.example .env
    ok "created .env from .env.example"
    info "Gitignored, and hidden from coding agents by .cursorignore"
  fi

  # --- stateful services ----------------------------------------------------
  step "🐘 Starting stateful services (PostgreSQL)"
  local use_postgres=0
  if docker_up; then
    run $COMPOSE up -d
    if spinner_wait 45 "waiting for PostgreSQL to accept connections" \
        $COMPOSE exec -T postgres pg_isready -U pulse -d pulse; then
      ok "PostgreSQL ready on localhost:5432"
      use_postgres=1
    else
      warn "PostgreSQL did not become ready in 45s"
      hint "Check it with: $COMPOSE logs postgres"
      warn "Falling back to SQLite so you can keep working"
    fi
  else
    warn "Docker is not running — falling back to SQLite"
    info "That is fine for development: nothing to start, same code path"
  fi

  if [ "$use_postgres" = "1" ]; then
    sed -i.bak \
      -e 's|^PULSE_DATABASE_URL=.*|PULSE_DATABASE_URL=postgresql://pulse:pulse@localhost:5432/pulse|' \
      -e 's|^QA_DATABASE_URL=.*|QA_DATABASE_URL=postgresql://pulse:pulse@localhost:5432/pulse|' \
      -e 's|^# *PULSE_DB_SCHEMA=.*|PULSE_DB_SCHEMA=polls|' \
      -e 's|^# *QA_DB_SCHEMA=.*|QA_DB_SCHEMA=qa|' \
      .env && rm -f .env.bak
    ok "both services pointed at PostgreSQL"
    note "one instance, one schema each: polls, qa"
  fi

  # --- seed -----------------------------------------------------------------
  step "🌱 Seeding room CIT22A"
  cmd_seed

  done_banner "Setup complete."
  cmd_help_short
}

# ============================================================================
#  services
# ============================================================================

cmd_poll_service() {
  require_venv; load_env
  local port="${POLL_SERVICE_PORT:-8001}"
  port_busy "$port" && die "Port $port is already in use.
   👉 Stop the other process, or set POLL_SERVICE_PORT."
  step "📊 poll-service → http://localhost:$port"
  info "docs http://localhost:$port/docs · health http://localhost:$port/healthz"
  cd packages/poll-service
  exec "$(venv_python)" -m uvicorn app.main:app --reload --host 0.0.0.0 --port "$port"
}

cmd_qa_service() {
  require_venv; load_env
  local port="${QA_SERVICE_PORT:-8002}"
  port_busy "$port" && die "Port $port is already in use.
   👉 Stop the other process, or set QA_SERVICE_PORT."
  step "💬 qa-service → http://localhost:$port"
  info "Skeleton on main — the Q&A feature is built live from docs/specs/qa-feature.md"
  cd packages/qa-service
  exec "$(venv_python)" -m uvicorn app.main:app --reload --host 0.0.0.0 --port "$port"
}

cmd_web() {
  require_node_modules
  step "🖥️  web → http://localhost:5173"
  info "audience /r/CIT22A · presenter /present/CIT22A · admin /admin"
  cd packages/web
  exec npm run dev -- "$@"
}

cmd_crew() {
  require_venv; load_env
  [ -f packages/crew/main.py ] || die "The crew is not built yet.
   👉 It lands in packages/crew in phase 3 (see docs/specs/pulse-spec.md)."
  step "🤖 CrewAI session report"
  cd packages/crew
  exec "$(venv_python)" main.py "$@"
}

# ============================================================================
#  data
# ============================================================================

cmd_db() {
  docker_up || die "Docker is not running."
  case "${1:-status}" in
    up)
      step "🐘 Starting PostgreSQL"
      run $COMPOSE up -d
      spinner_wait 45 "waiting" $COMPOSE exec -T postgres pg_isready -U pulse -d pulse \
        || die "PostgreSQL did not become ready in 45s.
   👉 $COMPOSE logs postgres"
      ok "ready on localhost:5432"
      ;;
    down)
      step "🛑 Stopping PostgreSQL"
      info "Data is kept — use 'npm run db:reset' to wipe it"
      run $COMPOSE down
      ok "stopped"
      ;;
    reset)
      step "🧨 Destroying PostgreSQL and all its data"
      run $COMPOSE down -v
      cmd_db up
      cmd_seed
      ;;
    status) step "🐘 PostgreSQL"; $COMPOSE ps ;;
    logs)   $COMPOSE logs -f postgres ;;
    *) die "Usage: npm run db:up | db:down | db:reset  (also: dev.sh db status|logs)" ;;
  esac
}

cmd_seed() {
  require_venv; load_env
  ( cd packages/poll-service && "$(venv_python)" -m app.seed "$@" ) \
    | sed 's/^/   🌱 /'
  ok "room CIT22A ready"
}

# ============================================================================
#  quality gates
# ============================================================================

cmd_test() {
  local target="${1:-all}" failed=()

  _py_tests() {
    require_venv
    for pkg in poll-service qa-service; do
      step "🧪 pytest — $pkg"
      ( cd "packages/$pkg" && "$(venv_python)" -m pytest ) || failed+=("$pkg")
    done
  }
  _web_tests() {
    require_node_modules
    step "🧪 vitest — web"
    ( cd packages/web && npm test ) || failed+=("web")
  }

  case "$target" in
    python|py) _py_tests ;;
    web)       _web_tests ;;
    all)       _py_tests; _web_tests ;;
    *) die "Usage: npm test | npm run test:py | npm run test:web" ;;
  esac

  if [ ${#failed[@]} -gt 0 ]; then
    die "Tests failed in: ${failed[*]}"
  fi
  done_banner "All tests passed."
}

cmd_lint() {
  local fix=0 failed=()
  [ "${1:-}" = "--fix" ] && fix=1
  require_venv
  local ruff; ruff="$(venv_exe ruff)" || die "ruff missing — run: npm run setup"

  if [ "$fix" = "1" ]; then
    step "🧹 ruff — fixing Python"
    run "$ruff" check --fix packages/poll-service packages/qa-service || failed+=("ruff")
    run "$ruff" format packages/poll-service packages/qa-service || failed+=("ruff-format")
    step "🧹 eslint — fixing web"
    ( cd packages/web && npx eslint . --fix ) || failed+=("eslint")
  else
    step "🔎 ruff — checking Python"
    run "$ruff" check packages/poll-service packages/qa-service || failed+=("ruff")
    run "$ruff" format --check packages/poll-service packages/qa-service || failed+=("ruff-format")
    step "🔎 eslint — checking web"
    ( cd packages/web && npm run lint ) || failed+=("eslint")
  fi

  [ ${#failed[@]} -gt 0 ] && die "Lint failed: ${failed[*]}"
  done_banner "Lint clean."
}

cmd_verify() {
  banner "🔬 Verifying everything CI will check"
  local failed=()
  require_venv; require_node_modules
  local ruff; ruff="$(venv_exe ruff)"

  step "🔎 Python lint"
  "$ruff" check packages/poll-service packages/qa-service || failed+=("ruff")
  "$ruff" format --check packages/poll-service packages/qa-service || failed+=("ruff-format")

  for pkg in poll-service qa-service; do
    step "🧪 pytest — $pkg"
    ( cd "packages/$pkg" && "$(venv_python)" -m pytest ) || failed+=("$pkg tests")
  done

  step "🔎 TypeScript"
  ( cd packages/web && npm run typecheck ) || failed+=("typecheck")
  step "🔎 eslint"
  ( cd packages/web && npm run lint ) || failed+=("eslint")
  step "🧪 vitest"
  ( cd packages/web && npm test ) || failed+=("web tests")
  step "📦 production build"
  ( cd packages/web && npm run build ) || failed+=("build")

  [ ${#failed[@]} -gt 0 ] && die "Verify failed: ${failed[*]}"
  done_banner "Everything passed. Safe to push."
}

# ============================================================================
#  kubernetes — local kind cluster, ingress, ArgoCD
# ============================================================================

KIND_CLUSTER="pulse"
# Pinned: the manifest path has moved on main before, and an unpinned URL
# turns an upstream restructure into a broken demo.
INGRESS_NGINX_VERSION="controller-v1.13.1"
INGRESS_HTTP_PORT="${PULSE_INGRESS_PORT:-18080}"

cmd_images() {
  docker_up || die "Docker is not running."
  step "🐳 Building images"
  run docker build -q -t pulse/poll-service:dev packages/poll-service
  run docker build -q -t pulse/qa-service:dev packages/qa-service
  # web builds from the repo root: the npm workspace lockfile lives there.
  run docker build -q -f packages/web/Dockerfile -t pulse/web:dev .
  ok "poll-service, qa-service and web built"

  local kind_bin; kind_bin="$(require_kind)"
  if "$kind_bin" get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
    step "📦 Loading images into the kind node"
    info "No registry needed locally — images go straight into the node"
    for image in poll-service qa-service web; do
      run "$kind_bin" load docker-image "pulse/${image}:dev" --name "$KIND_CLUSTER"
    done
    ok "images available in the cluster"
  fi
}

cmd_cluster() {
  local action="${1:-status}"
  local kind_bin; kind_bin="$(require_kind)"

  case "$action" in
    up)
      banner "☸️  Bringing up the local cluster"
      docker_up || die "Docker is not running."

      step "🔍 Checking kind"
      ok "kind $("$kind_bin" version | head -1)"

      if "$kind_bin" get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
        ok "cluster '$KIND_CLUSTER' already exists"
      else
        port_busy "$INGRESS_HTTP_PORT" \
          && die "Port $INGRESS_HTTP_PORT is in use, and the cluster needs it for ingress.
   👉 Stop whatever is listening, then retry."
        step "☸️  Creating the cluster"
        info "This pulls the node image the first time — a minute or two"
        run "$kind_bin" create cluster --config deploy/local/kind-cluster.yaml
        ok "cluster '$KIND_CLUSTER' created"
      fi

      run kubectl config use-context "kind-${KIND_CLUSTER}"

      step "🌐 Installing ingress-nginx"
      info "kind ships no ingress controller, so we add one"
      run kubectl apply -f \
        "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"
      printf '   %s⏳ waiting for the controller to be ready%s\n' "$DIM" "$RESET"
      kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=180s || die "ingress-nginx did not become ready.
   👉 kubectl -n ingress-nginx get pods"
      ok "ingress-nginx ready"

      cmd_images

      step "🚀 Applying deploy/overlays/local"
      run kubectl apply -k deploy/overlays/local
      printf '   %s⏳ waiting for rollouts%s\n' "$DIM" "$RESET"
      for deployment in postgres poll-service qa-service web; do
        kubectl -n pulse rollout status "deployment/$deployment" --timeout=180s \
          || die "$deployment did not roll out.
   👉 kubectl -n pulse describe deployment/$deployment"
      done
      ok "all four deployments are running"

      step "🌱 Seeding room CIT22A in the cluster"
      kubectl -n pulse exec deployment/poll-service -- python -m app.seed \
        2>/dev/null | sed 's/^/   🌱 /' || warn "Seeding failed — run 'npm run cluster:seed' once Postgres settles"

      done_banner "Cluster is up."
      cat <<EOF
  ${BOLD}Open${RESET}
    ${DIM}audience ${RESET} http://localhost:${INGRESS_HTTP_PORT}/r/CIT22A
    ${DIM}presenter${RESET} http://localhost:${INGRESS_HTTP_PORT}/present/CIT22A
    ${DIM}admin    ${RESET} http://localhost:${INGRESS_HTTP_PORT}/admin

  ${BOLD}Next${RESET}
    ${CYAN}npm run cluster:argocd${RESET}   install ArgoCD and the Application
    ${CYAN}npm run tunnel${RESET}           public HTTPS URL for phones

EOF
      ;;

    argocd)
      banner "🐙 Installing ArgoCD"
      step "📦 Applying the ArgoCD manifests"
      run kubectl create namespace argocd --dry-run=client -o yaml
      kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
      # --server-side is required: a client-side apply stores the whole manifest
      # in last-applied-configuration, and the ApplicationSet CRD exceeds the
      # 256KB annotation limit.
      run kubectl apply -n argocd --server-side --force-conflicts -f \
        https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
      printf '   %s⏳ waiting for the ArgoCD server%s\n' "$DIM" "$RESET"
      kubectl -n argocd rollout status deployment/argocd-server --timeout=300s \
        || die "ArgoCD did not start.
   👉 kubectl -n argocd get pods"
      ok "ArgoCD is running"

      step "🔗 Pointing the Application at this repo"
      local remote
      if remote="$(git remote get-url origin 2>/dev/null)"; then
        ok "remote: $remote"
        info "Edit deploy/argocd/app.yaml if the URL or overlay path differs"
      else
        warn "No git remote yet — ArgoCD cannot sync from a repo that is not pushed"
        hint "Create the GitHub repo, push, then: npm run cluster:argocd"
        hint "The app is already running from 'npm run cluster:up' meanwhile"
        return 0
      fi
      # Substitute the real repo URL at apply time, so the committed manifest
      # never carries a stale placeholder.
      info "Applying the Application with repoURL=$remote"
      sed "s|https://github.com/Naveen-oops/Pulse.git|${remote}|" deploy/argocd/app.yaml         | kubectl apply -f -

      step "🔑 Admin password"
      printf '   %s' "$DIM"
      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
      printf '%s\n' "$RESET"
      info "Username is 'admin'. Port-forward the UI with:"
      note "kubectl -n argocd port-forward svc/argocd-server 8090:443"
      done_banner "ArgoCD ready."
      ;;

    down)
      banner "🧨 Deleting the cluster"
      run "$kind_bin" delete cluster --name "$KIND_CLUSTER"
      ok "cluster '$KIND_CLUSTER' deleted"
      ;;

    seed)
      step "🌱 Seeding room CIT22A in the cluster"
      kubectl -n pulse exec deployment/poll-service -- python -m app.seed "${@:2}" \
        | sed 's/^/   🌱 /'
      ok "seeded"
      ;;

    status)
      banner "☸️  Cluster status"
      if ! "$kind_bin" get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
        info "No cluster named '$KIND_CLUSTER'"
        hint "npm run cluster:up"
        return 0
      fi
      step "Pods"; kubectl -n pulse get pods -o wide 2>&1 || true
      step "Ingress"; kubectl -n pulse get ingress 2>&1 || true
      step "ArgoCD"; kubectl -n argocd get application 2>&1 || info "ArgoCD not installed"
      ;;

    logs)
      kubectl -n pulse logs -l "app.kubernetes.io/name=${2:-poll-service}" --tail=100 -f
      ;;

    *)
      die "Usage: npm run cluster:up | cluster:down | cluster:argocd | cluster:status
   also: dev.sh cluster seed | dev.sh cluster logs <service>"
      ;;
  esac
}

cmd_tunnel() {
  banner "🌍 Public HTTPS URL for phones"
  local target="http://localhost:${INGRESS_HTTP_PORT}"
  if ! command -v cloudflared >/dev/null 2>&1; then
    warn "cloudflared is not installed"
    hint "winget install --id Cloudflare.cloudflared -e --source winget"
    hint "or: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
    die "Install cloudflared, then run 'npm run tunnel' again."
  fi
  info "Serving $target over a Cloudflare quick tunnel"
  info "The *.trycloudflare.com URL it prints is what the QR code should point at"
  warn "Quick tunnels are ephemeral — the URL changes every restart"
  exec cloudflared tunnel --url "$target"
}

# ============================================================================
#  azure — AKS deployment for audience participation
# ============================================================================
#
# Everything lands in ONE resource group so teardown is one command. That is the
# only cost control that actually works:  npm run azure:down
#
# Cost for a two-day session, in the region below:
#   AKS control plane (Free tier)   $0
#   1x Standard_B2s node            ~$0.04/hr  -> ~$2 for 48h
#   ACR Basic                       ~$0.17/day -> ~$0.34
#   PostgreSQL (in-cluster)         $0
# A new Azure account's $200 credit covers this many times over.

AZ_RESOURCE_GROUP="${AZ_RESOURCE_GROUP:-rg-pulse-demo}"
AZ_LOCATION="${AZ_LOCATION:-centralindia}"
AZ_AKS_NAME="${AZ_AKS_NAME:-pulse-aks}"
AZ_NODE_SIZE="${AZ_NODE_SIZE:-Standard_B2s}"
AZ_NODE_COUNT="${AZ_NODE_COUNT:-1}"

# Azure CLI is installed by an MSI that may not be on this shell's PATH yet.
find_az() {
  if command -v az >/dev/null 2>&1; then command -v az; return 0; fi
  local msi="/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin/az.cmd"
  if [ -f "$msi" ]; then echo "$msi"; return 0; fi
  return 1
}

require_az() {
  local az_bin
  az_bin="$(find_az)" || die "Azure CLI not found.
   👉 winget install --id Microsoft.AzureCLI -e --source winget"
  if ! "$az_bin" account show >/dev/null 2>&1; then
    die "Not logged in to Azure, or the cached credential is stale.
   👉 Run: az login"
  fi
  echo "$az_bin"
}

# ACR names are globally unique and alphanumeric only, so one is derived from
# the subscription id rather than guessed.
acr_name_for() {
  local az_bin="$1" sub
  sub="$("$az_bin" account show --query id -o tsv 2>/dev/null | tr -d '-' | tail -c 8)"
  echo "${AZ_ACR_NAME:-pulseacr${sub}}"
}

cmd_azure() {
  local action="${1:-status}"
  local AZ; AZ="$(require_az)"
  local ACR; ACR="$(acr_name_for "$AZ")"

  case "$action" in
    up)
      banner "☁️  Deploying Pulse to AKS"
      local sub_name
      sub_name="$("$AZ" account show --query name -o tsv)"
      ok "subscription: $sub_name"
      note "resource group: $AZ_RESOURCE_GROUP · region: $AZ_LOCATION"
      info "Everything goes in one resource group. 'npm run azure:down' deletes all of it."

      step "📋 Registering resource providers"
      for provider in Microsoft.ContainerService Microsoft.ContainerRegistry; do
        local state
        state="$("$AZ" provider show -n "$provider" --query registrationState -o tsv 2>/dev/null || echo NotRegistered)"
        if [ "$state" = "Registered" ]; then
          ok "$provider"
        else
          info "$provider is $state — registering (can take a few minutes)"
          "$AZ" provider register -n "$provider" --wait
          ok "$provider registered"
        fi
      done

      step "📦 Creating the resource group"
      "$AZ" group create -n "$AZ_RESOURCE_GROUP" -l "$AZ_LOCATION" --output none
      ok "$AZ_RESOURCE_GROUP in $AZ_LOCATION"

      step "🗄️  Creating the container registry"
      if "$AZ" acr show -n "$ACR" -g "$AZ_RESOURCE_GROUP" >/dev/null 2>&1; then
        ok "$ACR already exists"
      else
        "$AZ" acr create -n "$ACR" -g "$AZ_RESOURCE_GROUP" --sku Basic --output none \
          || die "Could not create the registry. The name '$ACR' may be taken globally.
   👉 Set a different one: AZ_ACR_NAME=<name> npm run azure:up"
        ok "$ACR.azurecr.io"
      fi

      step "🐳 Building images in the cloud"
      info "az acr build compiles inside Azure — no local Docker push, no slow upload"
      "$AZ" acr build -r "$ACR" -t "pulse-poll-service:latest" packages/poll-service --output none
      ok "pulse-poll-service"
      "$AZ" acr build -r "$ACR" -t "pulse-qa-service:latest" packages/qa-service --output none
      ok "pulse-qa-service"
      # web builds from the repo root: the npm workspace lockfile lives there.
      "$AZ" acr build -r "$ACR" -t "pulse-web:latest" -f packages/web/Dockerfile . --output none
      ok "pulse-web"

      step "☸️  Creating the AKS cluster"
      if "$AZ" aks show -n "$AZ_AKS_NAME" -g "$AZ_RESOURCE_GROUP" >/dev/null 2>&1; then
        ok "$AZ_AKS_NAME already exists"
      else
        info "$AZ_NODE_COUNT x $AZ_NODE_SIZE, Free control plane — this takes 5-10 minutes"
        "$AZ" aks create \
          -n "$AZ_AKS_NAME" -g "$AZ_RESOURCE_GROUP" \
          --tier free \
          --node-count "$AZ_NODE_COUNT" \
          --node-vm-size "$AZ_NODE_SIZE" \
          --attach-acr "$ACR" \
          --no-ssh-key \
          --output none \
        || die "AKS creation failed.
   👉 Often a quota limit on a new subscription. Check with:
      az vm list-usage -l $AZ_LOCATION -o table | grep -i vcpu"
        ok "$AZ_AKS_NAME created"
      fi

      step "🔑 Fetching kubectl credentials"
      "$AZ" aks get-credentials -n "$AZ_AKS_NAME" -g "$AZ_RESOURCE_GROUP" --overwrite-existing
      ok "kubectl context is now $AZ_AKS_NAME"
      warn "Your kubectl context changed — 'kubectl config use-context kind-pulse' to go back"

      step "🌐 Installing ingress-nginx (cloud LoadBalancer)"
      run kubectl apply -f \
        "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/cloud/deploy.yaml"
      printf '   %s⏳ waiting for the controller%s\n' "$DIM" "$RESET"
      kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s || die "ingress-nginx did not become ready.
   👉 kubectl -n ingress-nginx get pods"
      ok "ingress-nginx ready"

      step "🔐 Creating secrets in the cluster (never in git)"
      kubectl create namespace pulse --dry-run=client -o yaml | kubectl apply -f -
      if kubectl -n pulse get secret pulse-db >/dev/null 2>&1; then
        ok "secrets already exist — leaving them alone"
      else
        local pg_pass presenter_token
        pg_pass="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
        presenter_token="$(openssl rand -hex 16)"
        kubectl -n pulse create secret generic pulse-db \
          --from-literal=username=pulse \
          --from-literal=password="$pg_pass" \
          --from-literal=poll-service-url="postgresql://pulse:${pg_pass}@postgres:5432/pulse" \
          --from-literal=qa-service-url="postgresql://pulse:${pg_pass}@postgres:5432/pulse"
        kubectl -n pulse create secret generic pulse-app \
          --from-literal=presenter-token="$presenter_token"
        ok "generated a random database password and presenter token"
        printf '\n   %s🔑 PRESENTER TOKEN: %s%s%s\n\n' "$CYAN$BOLD" "$presenter_token" "$RESET" ""
        info "Write that down — it is only shown once. Retrieve it later with:"
        note "kubectl -n pulse get secret pulse-app -o jsonpath='{.data.presenter-token}' | base64 -d"
      fi

      step "🚀 Pointing the overlay at the registry and deploying"
      # kubectl renders kustomize but has no `kustomize edit`, so the images
      # block is written directly rather than adding a second binary.
      _write_azure_images "$ACR"
      run kubectl apply -k deploy/overlays/azure

      printf '   %s⏳ waiting for rollouts%s\n' "$DIM" "$RESET"
      for deployment in postgres poll-service qa-service web; do
        kubectl -n pulse rollout status "deployment/$deployment" --timeout=300s \
          || die "$deployment did not roll out.
   👉 kubectl -n pulse describe deployment/$deployment"
      done
      ok "all four deployments are running"

      step "🌱 Seeding room CIT22A"
      kubectl -n pulse exec deployment/poll-service -- python -m app.seed 2>/dev/null \
        | sed 's/^/   🌱 /' || warn "Seeding failed — retry with 'npm run azure:seed'"

      cmd_azure url
      ;;

    url)
      step "🌍 Public address"
      local ip
      ip="$(kubectl -n ingress-nginx get service ingress-nginx-controller \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)"
      if [ -z "$ip" ]; then
        warn "The LoadBalancer has no external IP yet — Azure usually takes 1-3 minutes"
        hint "Watch it: kubectl -n ingress-nginx get svc ingress-nginx-controller -w"
        return 0
      fi
      done_banner "Pulse is live."
      cat <<EOF
  ${BOLD}Share with the audience${RESET}
    ${CYAN}http://${ip}/r/CIT22A${RESET}

  ${BOLD}For you${RESET}
    presenter  http://${ip}/present/CIT22A
    admin      http://${ip}/admin

  ${BOLD}When the session is over${RESET}
    ${CYAN}npm run azure:down${RESET}   ${DIM}deletes the whole resource group${RESET}

EOF
      ;;

    seed)
      kubectl -n pulse exec deployment/poll-service -- python -m app.seed "${@:2}" \
        | sed 's/^/   🌱 /'
      ok "seeded"
      ;;

    status)
      banner "☁️  Azure status"
      if ! "$AZ" group exists -n "$AZ_RESOURCE_GROUP" --output tsv | grep -q true; then
        info "Resource group '$AZ_RESOURCE_GROUP' does not exist"
        hint "npm run azure:up"
        return 0
      fi
      step "Resources in $AZ_RESOURCE_GROUP"
      "$AZ" resource list -g "$AZ_RESOURCE_GROUP" \
        --query "[].{name:name,type:type,location:location}" -o table 2>&1 || true
      step "Cluster"
      kubectl -n pulse get pods -o wide 2>&1 || info "kubectl is not pointed at AKS"
      cmd_azure url
      ;;

    cost)
      step "💰 What is running, and roughly what it costs"
      "$AZ" resource list -g "$AZ_RESOURCE_GROUP" --query "[].{name:name,type:type}" -o table 2>&1 || true
      cat <<EOF

   ${DIM}AKS control plane (Free tier)   \$0
   ${AZ_NODE_COUNT}x ${AZ_NODE_SIZE}                  ~\$0.04/hr each
   ACR Basic                       ~\$0.17/day
   PostgreSQL (in-cluster)         \$0${RESET}

   ${BOLD}Billing is per-second while it exists. 'npm run azure:down' is the off switch.${RESET}

EOF
      info "Exact figures: https://portal.azure.com -> Cost Management"
      ;;

    down)
      banner "🧨 Deleting every Azure resource for Pulse"
      warn "This deletes resource group '$AZ_RESOURCE_GROUP' and everything in it:"
      note "the AKS cluster, the registry and its images, the load balancer, and the database"
      printf '\n   %sType the resource group name to confirm:%s ' "$BOLD" "$RESET"
      read -r confirm
      [ "$confirm" = "$AZ_RESOURCE_GROUP" ] || die "Did not match. Nothing was deleted."
      info "Deleting in the background — Azure takes a few minutes to finish"
      "$AZ" group delete -n "$AZ_RESOURCE_GROUP" --yes --no-wait
      ok "deletion started"
      hint "Confirm it is gone: az group exists -n $AZ_RESOURCE_GROUP"
      ;;

    *)
      die "Usage: npm run azure:up | azure:down | azure:status | azure:url | azure:cost" ;;
  esac
}

# Writes the images block of the azure overlay. Done in shell because `kubectl
# kustomize` can render but cannot edit, and we do not want a second binary.
_write_azure_images() {
  local acr="$1"
  local file="deploy/overlays/azure/kustomization.yaml"
  # Drop any previous images block, then append a fresh one.
  sed -i '/^images:/,/^$/d' "$file"
  cat >> "$file" <<EOF

images:
  - name: pulse/poll-service
    newName: ${acr}.azurecr.io/pulse-poll-service
    newTag: latest
  - name: pulse/qa-service
    newName: ${acr}.azurecr.io/pulse-qa-service
    newTag: latest
  - name: pulse/web
    newName: ${acr}.azurecr.io/pulse-web
    newTag: latest
EOF
  ok "overlay points at ${acr}.azurecr.io"
}

# ============================================================================
#  utilities
# ============================================================================

cmd_doctor() {
  banner "🩺 Toolchain check"
  local missing=0

  _check() { # _check <label> <command> <required|optional> <hint>
    local label="$1" cmd="$2" req="$3" hint_text="${4:-}"
    if out="$(eval "$cmd" 2>/dev/null | head -1)" && [ -n "$out" ]; then
      ok "$label — $out"
    elif [ "$req" = "required" ]; then
      warn "$label — MISSING"; [ -n "$hint_text" ] && hint "$hint_text"; missing=$((missing+1))
    else
      info "$label — not installed (optional)"; [ -n "$hint_text" ] && note "$hint_text"
    fi
  }

  step "Core"
  _check "node"   "node --version"   required "https://nodejs.org (18.18+)"
  _check "npm"    "npm --version"    required
  _check "git"    "git --version"    required
  _check "uv"     "$(find_uv 2>/dev/null || echo false) --version" required \
    "winget install astral-sh.uv"

  step "Project"
  if venv_python >/dev/null 2>&1; then ok ".venv — $("$(venv_python)" --version)"
  else warn ".venv — MISSING"; hint "npm run setup"; missing=$((missing+1)); fi
  if [ -d node_modules ]; then ok "node_modules — installed"
  else warn "node_modules — MISSING"; hint "npm run setup"; missing=$((missing+1)); fi
  if [ -f .env ]; then ok ".env — present"
  else warn ".env — MISSING"; hint "npm run setup"; fi

  step "Containers"
  if docker_up; then
    ok "docker — $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    if $COMPOSE ps --status running 2>/dev/null | grep -q postgres; then
      ok "postgres — running"
    else
      info "postgres — not running (SQLite will be used)"
      note "npm run db:up"
    fi
  else
    info "docker — not running (optional; SQLite will be used)"
  fi

  step "Ports"
  for p in 5173:web 8001:poll-service 8002:qa-service 5432:postgres; do
    local port="${p%%:*}" who="${p##*:}"
    if port_busy "$port"; then info "$port ($who) — in use"; else ok "$port ($who) — free"; fi
  done

  if [ "$missing" -gt 0 ]; then
    die "$missing required item(s) missing. Run: npm run setup"
  fi
  done_banner "Toolchain looks good."
}

cmd_clean() {
  banner "🧹 Cleaning generated files"
  step "Removing build output and caches"
  run rm -rf packages/web/dist packages/web/node_modules node_modules
  run rm -rf .venv .ruff_cache
  find . -type d \( -name __pycache__ -o -name .pytest_cache -o -name .ruff_cache \) \
    -not -path "./.git/*" -prune -exec rm -rf {} + 2>/dev/null || true
  ok "removed .venv, node_modules, dist and caches"
  info ".env and Docker volumes are kept — use 'npm run db:reset' to wipe the database"
  done_banner "Clean. Run 'npm run setup' to start again."
}

cmd_help_short() {
  cat <<EOF
  ${BOLD}Run it${RESET}
    ${CYAN}npm run dev${RESET}             ${DIM}everything at once${RESET}
    ${CYAN}npm run web${RESET}             ${DIM}→ http://localhost:5173${RESET}
    ${CYAN}npm run poll-service${RESET}    ${DIM}→ http://localhost:8001/healthz${RESET}
    ${CYAN}npm run qa-service${RESET}      ${DIM}→ http://localhost:8002/healthz${RESET}

  ${BOLD}Check it${RESET}
    ${CYAN}npm test${RESET}                ${DIM}every test suite${RESET}
    ${CYAN}npm run verify${RESET}          ${DIM}what CI runs${RESET}
    ${CYAN}npm run doctor${RESET}          ${DIM}check this machine${RESET}

  ${BOLD}Then open${RESET}
    ${DIM}audience ${RESET} http://localhost:5173/r/CIT22A
    ${DIM}presenter${RESET} http://localhost:5173/present/CIT22A
    ${DIM}admin    ${RESET} http://localhost:5173/admin

EOF
}

cmd_help() {
  banner "Pulse — development commands"
  cat <<EOF
  ${BOLD}Setup${RESET}
    npm run setup            one-time: venv, deps, PostgreSQL, .env, seed

  ${BOLD}Run${RESET}
    npm run dev              all three services together
    npm run web              web only          (5173)
    npm run poll-service     poll API only     (8001)
    npm run qa-service       Q&A API only      (8002)
    npm run crew             CrewAI session report

  ${BOLD}Data${RESET}
    npm run db:up            start PostgreSQL
    npm run db:down          stop it, keep the data
    npm run db:reset         wipe it, restart, reseed
    npm run seed             seed room CIT22A
    npm run seed:reset       seed and clear all votes

  ${BOLD}Kubernetes${RESET}
    npm run cluster:up       kind cluster + ingress-nginx + deploy + seed
    npm run cluster:argocd   install ArgoCD and the Application
    npm run cluster:status   pods, ingress, ArgoCD app
    npm run cluster:down     delete the cluster
    npm run images           build images and load them into kind
    npm run tunnel           public HTTPS URL for phones

  ${BOLD}Azure (AKS)${RESET}
    npm run azure:up         resource group + ACR + AKS + ingress + deploy + seed
    npm run azure:url        the public URL to share with the audience
    npm run azure:status     what exists, and the pods
    npm run azure:cost       what is running and roughly what it costs
    npm run azure:down       DELETE the whole resource group

  ${BOLD}Quality${RESET}
    npm test                 all tests        (test:py, test:web)
    npm run lint             ruff + eslint
    npm run format           fix what can be fixed
    npm run typecheck        tsc --noEmit
    npm run verify           everything CI runs
    npm run build            production web build

  ${BOLD}Utility${RESET}
    npm run doctor           check the toolchain on this machine
    npm run clean            remove .venv, node_modules, dist, caches

EOF
}

# ============================================================================

COMMAND="${1:-help}"; shift || true

case "$COMMAND" in
  setup)                cmd_setup "$@" ;;
  web)                  cmd_web "$@" ;;
  poll-service|poll)    cmd_poll_service "$@" ;;
  qa-service|qa)        cmd_qa_service "$@" ;;
  crew)                 cmd_crew "$@" ;;
  db)                   cmd_db "$@" ;;
  cluster)              cmd_cluster "$@" ;;
  images)               cmd_images "$@" ;;
  tunnel)               cmd_tunnel "$@" ;;
  azure)                cmd_azure "$@" ;;
  seed)                 cmd_seed "$@" ;;
  test)                 cmd_test "$@" ;;
  lint)                 cmd_lint "$@" ;;
  verify)               cmd_verify "$@" ;;
  doctor)               cmd_doctor "$@" ;;
  clean)                cmd_clean "$@" ;;
  help|--help|-h)       cmd_help ;;
  *) printf '\n%s❌ Unknown command: %s%s\n' "$RED" "$COMMAND" "$RESET"; cmd_help; exit 1 ;;
esac
