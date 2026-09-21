#!/usr/bin/env bash
# Shared helpers. Every script sources this first.
# shellcheck disable=SC2034

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- colours ----------------------------------------------------------------

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

# --- logging ----------------------------------------------------------------

_started_at=$(date +%s)

banner() {
  printf '\n%s%s  %s  %s\n' "$BOLD" "$CYAN" "$*" "$RESET"
  printf '%s  %s%s\n' "$DIM" "$(printf '─%.0s' $(seq 1 56))" "$RESET"
}

step()  { printf '\n%s🔹 %s%s%s\n' "$BLUE" "$BOLD" "$*" "$RESET"; }
ok()    { printf '   %s✅ %s%s\n' "$GREEN" "$*" "$RESET"; }
info()  { printf '   %s💡 %s%s\n' "$DIM" "$*" "$RESET"; }
warn()  { printf '   %s⚠️  %s%s\n' "$YELLOW" "$*" "$RESET"; }
note()  { printf '   %s   %s%s\n' "$DIM" "$*" "$RESET"; }

die() {
  printf '\n%s❌ %s%s\n' "$RED$BOLD" "$*" "$RESET" >&2
  [ $# -gt 1 ] || true
  printf '\n' >&2
  exit 1
}

hint() { printf '   %s👉 %s%s\n' "$CYAN" "$*" "$RESET"; }

# Shows the command before running it, so nothing happens invisibly.
run() {
  printf '   %s$ %s%s\n' "$DIM" "$*" "$RESET"
  "$@"
}

done_banner() {
  local elapsed=$(( $(date +%s) - _started_at ))
  printf '\n%s%s🎉 %s%s %s(%ss)%s\n\n' "$GREEN" "$BOLD" "$*" "$RESET" "$DIM" "$elapsed" "$RESET"
}

spinner_wait() {
  # spinner_wait <seconds> <label> <command...>
  local limit="$1" label="$2"; shift 2
  printf '   %s⏳ %s' "$DIM" "$label"
  for _ in $(seq 1 "$limit"); do
    if "$@" >/dev/null 2>&1; then printf '%s\n' "$RESET"; return 0; fi
    printf '.'; sleep 1
  done
  printf '%s\n' "$RESET"
  return 1
}

# --- tool resolution --------------------------------------------------------

UV_WINGET_DIR="${LOCALAPPDATA:-}/Microsoft/WinGet/Packages/astral-sh.uv_Microsoft.Winget.Source_8wekyb3d8bbwe"

# uv may be freshly installed and not yet on this shell's PATH.
find_uv() {
  if command -v uv >/dev/null 2>&1; then command -v uv; return 0; fi
  if [ -x "$UV_WINGET_DIR/uv.exe" ]; then echo "$UV_WINGET_DIR/uv.exe"; return 0; fi
  if [ -x "$HOME/.local/bin/uv" ]; then echo "$HOME/.local/bin/uv"; return 0; fi
  if [ -x "$HOME/.cargo/bin/uv" ]; then echo "$HOME/.cargo/bin/uv"; return 0; fi
  return 1
}

# The venv interpreter: Scripts/ on Windows, bin/ elsewhere.
venv_python() {
  if [ -x "$REPO_ROOT/.venv/Scripts/python.exe" ]; then
    echo "$REPO_ROOT/.venv/Scripts/python.exe"
  elif [ -x "$REPO_ROOT/.venv/bin/python" ]; then
    echo "$REPO_ROOT/.venv/bin/python"
  else
    return 1
  fi
}

venv_exe() {
  # venv_exe ruff  ->  absolute path to the venv's ruff
  local name="$1"
  if [ -x "$REPO_ROOT/.venv/Scripts/$name.exe" ]; then echo "$REPO_ROOT/.venv/Scripts/$name.exe"
  elif [ -x "$REPO_ROOT/.venv/bin/$name" ]; then echo "$REPO_ROOT/.venv/bin/$name"
  else return 1; fi
}

require_venv() {
  venv_python >/dev/null 2>&1 || die "No virtualenv found.
   👉 Run: npm run setup"
}

require_node_modules() {
  [ -d "$REPO_ROOT/node_modules" ] || die "Node dependencies are not installed.
   👉 Run: npm run setup"
}

docker_up() { docker info >/dev/null 2>&1; }

port_busy() {
  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | grep -Eq "[:.]$1[[:space:]]+.*LISTEN"
  else
    return 1
  fi
}

load_env() {
  if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_ROOT/.env"
    set +a
  fi
}
