#!/usr/bin/env bash
#
# aks-setup.sh — create an AKS cluster that actually fits your subscription.
#
# Why this exists: `az aks create` fails in three different ways on a new
# subscription, and each one tells you only after several minutes:
#
#   1. The VM size is not *offered* in the region.
#   2. The VM size is offered but not *allowed for your subscription*
#      (very common on free/trial), which is a different list entirely.
#   3. It is allowed, but you have no quota left in that VM family.
#
# So this script discovers all three before it creates anything, picks a size
# that satisfies them, and tells you exactly what it is doing.
#
# Usage:
#   ./scripts/aks-setup.sh                 interactive, asks before creating
#   ./scripts/aks-setup.sh --yes           no prompts
#   ./scripts/aks-setup.sh --dry-run       show the plan, create nothing
#   ./scripts/aks-setup.sh --debug         print every az command (set -x)
#   ./scripts/aks-setup.sh --size X --region Y    force a choice
#
# Environment overrides:
#   AZ_RESOURCE_GROUP  AZ_LOCATION  AZ_AKS_NAME  AZ_NODE_COUNT  AZ_ACR_NAME

set -euo pipefail

# Reuse the repo's logging helpers when present; otherwise stand alone so this
# script is useful on its own.
if [ -f "$(dirname "${BASH_SOURCE[0]}")/lib.sh" ]; then
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
else
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
  banner() { printf '\n%s%s  %s  %s\n' "$BOLD" "$CYAN" "$*" "$RESET"; }
  step()   { printf '\n%s🔹 %s%s%s\n' "$BLUE" "$BOLD" "$*" "$RESET"; }
  ok()     { printf '   %s✅ %s%s\n' "$GREEN" "$*" "$RESET"; }
  info()   { printf '   %s💡 %s%s\n' "$DIM" "$*" "$RESET"; }
  warn()   { printf '   %s⚠️  %s%s\n' "$YELLOW" "$*" "$RESET"; }
  note()   { printf '   %s   %s%s\n' "$DIM" "$*" "$RESET"; }
  hint()   { printf '   %s👉 %s%s\n' "$CYAN" "$*" "$RESET"; }
  die()    { printf '\n%s❌ %s%s\n\n' "$RED$BOLD" "$*" "$RESET" >&2; exit 1; }
  run()    { printf '   %s$ %s%s\n' "$DIM" "$*" "$RESET"; "$@"; }
fi

cd "$REPO_ROOT"

# --- configuration ----------------------------------------------------------

RESOURCE_GROUP="${AZ_RESOURCE_GROUP:-rg-pulse-demo}"
LOCATION="${AZ_LOCATION:-centralindia}"
AKS_NAME="${AZ_AKS_NAME:-pulse-aks}"
NODE_COUNT="${AZ_NODE_COUNT:-1}"

# Candidate node sizes, cheapest first. All are 2 vCPU so they fit the 4-vCPU
# regional quota that free subscriptions get. The script verifies each one is
# permitted before using it, so this is a preference list, not an assumption.
CANDIDATE_SIZES=(
  Standard_B2als_v2   # 2 vCPU,  4 GB — AMD burstable, cheapest
  Standard_B2s_v2     # 2 vCPU,  8 GB — Intel burstable
  Standard_B2ls_v2    # 2 vCPU,  4 GB
  Standard_D2as_v5    # 2 vCPU,  8 GB — AMD general purpose
  Standard_D2s_v5     # 2 vCPU,  8 GB — Intel general purpose
  Standard_B2s        # 2 vCPU,  4 GB — older gen, often not allowed
)

# Tried in order if the chosen region cannot satisfy any candidate.
FALLBACK_REGIONS=("$LOCATION" southindia eastus westeurope)

ASSUME_YES=0
DRY_RUN=0
FORCED_SIZE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)    ASSUME_YES=1; shift ;;
    --dry-run|-n) DRY_RUN=1; shift ;;
    --debug)     set -x; shift ;;
    --size)      FORCED_SIZE="${2:?--size needs a value}"; shift 2 ;;
    --region)    LOCATION="${2:?--region needs a value}"; FALLBACK_REGIONS=("$LOCATION"); shift 2 ;;
    --help|-h)   sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "Unknown argument: $1  (try --help)" ;;
  esac
done

# --- azure cli --------------------------------------------------------------

find_az_bin() {
  if command -v az >/dev/null 2>&1; then command -v az; return 0; fi
  local msi="/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin/az.cmd"
  [ -f "$msi" ] && { echo "$msi"; return 0; }
  return 1
}

AZ="$(find_az_bin)" || die "Azure CLI not found.
   👉 winget install --id Microsoft.AzureCLI -e --source winget"

"$AZ" account show >/dev/null 2>&1 || die "Not logged in to Azure.
   👉 Run: az login   (or: az login --use-device-code)"

# --- discovery --------------------------------------------------------------

# Sizes your subscription may actually use here. `az vm list-skus` reports a
# `restrictions` array when a SKU is blocked for the subscription — that is the
# authoritative answer, and it differs from "is it offered in the region".
allowed_sizes_in() {
  local region="$1"
  "$AZ" vm list-skus \
    --location "$region" \
    --resource-type virtualMachines \
    --query "[?length(restrictions)==\`0\`].name" \
    -o tsv 2>/dev/null || true
}

# Remaining vCPU headroom for a given size's family, and for the region overall.
quota_for_size() {
  local region="$1" size="$2"
  local family cores_used cores_limit
  family="$("$AZ" vm list-skus --location "$region" --resource-type virtualMachines \
    --query "[?name=='${size}'].family | [0]" -o tsv 2>/dev/null)"
  [ -z "$family" ] && { echo "unknown 0 0"; return; }
  read -r cores_used cores_limit <<<"$(
    "$AZ" vm list-usage -l "$region" \
      --query "[?name.value=='${family}'].[currentValue,limit] | [0]" -o tsv 2>/dev/null
  )"
  echo "${family} ${cores_used:-0} ${cores_limit:-0}"
}

cores_for_size() {
  local region="$1" size="$2"
  "$AZ" vm list-skus --location "$region" --resource-type virtualMachines \
    --query "[?name=='${size}'].capabilities[?name=='vCPUs'].value | [0] | [0]" \
    -o tsv 2>/dev/null
}

banner "☸️  AKS setup — discovering what your subscription allows"

SUB_NAME="$("$AZ" account show --query name -o tsv)"
SUB_ID="$("$AZ" account show --query id -o tsv)"
ok "subscription: $SUB_NAME"
note "$SUB_ID"

CHOSEN_SIZE=""
CHOSEN_REGION=""

for region in "${FALLBACK_REGIONS[@]}"; do
  step "🔍 Checking $region"

  regional_quota="$("$AZ" vm list-usage -l "$region" \
    --query "[?contains(localName,'Total Regional vCPUs')].[currentValue,limit] | [0]" -o tsv 2>/dev/null || true)"
  if [ -n "$regional_quota" ]; then
    read -r used limit <<<"$regional_quota"
    info "regional vCPUs: ${used:-?} used of ${limit:-?}"
  fi

  mapfile -t allowed < <(allowed_sizes_in "$region")
  if [ "${#allowed[@]}" -eq 0 ]; then
    warn "could not list permitted sizes here — skipping"
    continue
  fi
  info "${#allowed[@]} VM sizes permitted for this subscription"

  # If the caller forced a size, only consider that one.
  local_candidates=("${CANDIDATE_SIZES[@]}")
  [ -n "$FORCED_SIZE" ] && local_candidates=("$FORCED_SIZE")

  for size in "${local_candidates[@]}"; do
    # 1. permitted for this subscription?
    if ! printf '%s\n' "${allowed[@]}" | grep -qix "$size"; then
      note "$size — not permitted here"
      continue
    fi

    # 2. enough quota in its family?
    read -r family used limit <<<"$(quota_for_size "$region" "$size")"
    cores="$(cores_for_size "$region" "$size")"
    cores="${cores:-2}"
    needed=$(( cores * NODE_COUNT ))
    available=$(( ${limit:-0} - ${used:-0} ))

    if [ "$limit" = "0" ]; then
      note "$size — family '$family' reports no quota"
      continue
    fi
    if [ "$available" -lt "$needed" ]; then
      note "$size — needs ${needed} vCPU, only ${available} free in '$family'"
      continue
    fi

    ok "$size is permitted and has quota"
    note "family $family · ${cores} vCPU x ${NODE_COUNT} node(s) = ${needed} of ${available} free"
    CHOSEN_SIZE="$size"
    CHOSEN_REGION="$region"
    break 2
  done

  warn "no candidate size works in $region"
done

[ -n "$CHOSEN_SIZE" ] || die "No usable VM size found in: ${FALLBACK_REGIONS[*]}
   👉 See what is permitted:
      az vm list-skus -l $LOCATION --resource-type virtualMachines \\
        --query \"[?length(restrictions)==\\\`0\\\`].name\" -o tsv | sort | head -40
   👉 Or request a quota increase in the portal under Subscriptions > Usage + quotas."

# --- plan -------------------------------------------------------------------

ACR_NAME="${AZ_ACR_NAME:-pulseacr$(echo "$SUB_ID" | tr -d '-' | tail -c 8)}"

step "📋 Plan"
cat <<EOF
   ${BOLD}resource group${RESET}  $RESOURCE_GROUP
   ${BOLD}region${RESET}          $CHOSEN_REGION
   ${BOLD}cluster${RESET}         $AKS_NAME
   ${BOLD}node size${RESET}       $CHOSEN_SIZE  x $NODE_COUNT
   ${BOLD}registry${RESET}        $ACR_NAME.azurecr.io
   ${BOLD}control plane${RESET}   Free tier (\$0)
EOF

if [ "$DRY_RUN" = "1" ]; then
  info "--dry-run: nothing was created"
  exit 0
fi

if [ "$ASSUME_YES" != "1" ]; then
  printf '\n   %sCreate this? [y/N]%s ' "$BOLD" "$RESET"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) die "Cancelled. Nothing was created." ;;
  esac
fi

# --- create -----------------------------------------------------------------

step "📦 Resource group"
if "$AZ" group exists -n "$RESOURCE_GROUP" -o tsv | grep -q true; then
  ok "$RESOURCE_GROUP already exists"
else
  run "$AZ" group create -n "$RESOURCE_GROUP" -l "$CHOSEN_REGION" -o none
  ok "created"
fi

step "🗄️  Container registry"
if "$AZ" acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  ok "$ACR_NAME already exists"
else
  run "$AZ" acr create -n "$ACR_NAME" -g "$RESOURCE_GROUP" --sku Basic -o none \
    || die "Registry creation failed — '$ACR_NAME' may be taken globally.
   👉 Retry with: AZ_ACR_NAME=<unique-name> ./scripts/aks-setup.sh"
  ok "$ACR_NAME.azurecr.io"
fi

step "☸️  AKS cluster"
if "$AZ" aks show -n "$AKS_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  ok "$AKS_NAME already exists"
else
  info "This takes 5-10 minutes. Azure is provisioning a control plane and a node."
  run "$AZ" aks create \
    -n "$AKS_NAME" -g "$RESOURCE_GROUP" \
    --location "$CHOSEN_REGION" \
    --tier free \
    --node-count "$NODE_COUNT" \
    --node-vm-size "$CHOSEN_SIZE" \
    --attach-acr "$ACR_NAME" \
    --no-ssh-key \
    --output none \
  || die "AKS creation failed even though the size passed every precheck.
   👉 Read the real reason:
      az aks create ... (rerun with --debug), or check the portal activity log."
  ok "$AKS_NAME created"
fi

step "🔑 kubectl credentials"
run "$AZ" aks get-credentials -n "$AKS_NAME" -g "$RESOURCE_GROUP" --overwrite-existing
kubectl get nodes -o wide 2>&1 | sed 's/^/   /'
warn "kubectl now points at AKS — 'kubectl config use-context kind-pulse' to go back"

printf '\n%s%s🎉 Cluster is ready.%s\n\n' "$GREEN" "$BOLD" "$RESET"
cat <<EOF
  ${BOLD}Next${RESET}
    ${CYAN}npm run azure:up${RESET}     build, push, deploy and seed onto this cluster
    ${CYAN}npm run azure:url${RESET}    the public URL once the LoadBalancer has an IP

  ${BOLD}Chosen for you${RESET}  ${DIM}(export these to make it explicit next time)${RESET}
    AZ_LOCATION=$CHOSEN_REGION
    AZ_NODE_SIZE=$CHOSEN_SIZE

EOF
