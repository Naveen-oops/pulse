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
  seed)                 cmd_seed "$@" ;;
  test)                 cmd_test "$@" ;;
  lint)                 cmd_lint "$@" ;;
  verify)               cmd_verify "$@" ;;
  doctor)               cmd_doctor "$@" ;;
  clean)                cmd_clean "$@" ;;
  help|--help|-h)       cmd_help ;;
  *) printf '\n%s❌ Unknown command: %s%s\n' "$RED" "$COMMAND" "$RESET"; cmd_help; exit 1 ;;
esac
