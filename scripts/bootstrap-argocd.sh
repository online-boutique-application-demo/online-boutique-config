#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <env> [--dry-run]"
  echo "       $0 [--dry-run] <env>"
  exit 1
}

DRY_RUN=false
TARGET_ENV=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    -*)
      usage
      ;;
    *)
      if [ -z "$TARGET_ENV" ]; then
        TARGET_ENV="$arg"
      else
        usage
      fi
      ;;
  esac
done

if [ -z "$TARGET_ENV" ]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPS_DIR="${REPO_ROOT}/argocd/apps/${TARGET_ENV}"

if [ ! -d "$APPS_DIR" ]; then
  echo "Error: Directory not found: ${APPS_DIR}" >&2
  exit 1
fi

# Required environment variables
if [ -z "${GITHUB_ORG:-}" ]; then
  echo "Error: Required environment variable GITHUB_ORG is not set" >&2
  exit 1
fi
if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
  echo "Error: Required environment variable AWS_ACCOUNT_ID is not set" >&2
  exit 1
fi
if [ -z "${AWS_REGION:-}" ]; then
  echo "Error: Required environment variable AWS_REGION is not set" >&2
  exit 1
fi

# Default variables
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-online-boutique-${TARGET_ENV}}"
export CONFIG_REVISION="${CONFIG_REVISION:-deploy/${TARGET_ENV}}"

# Grafana Admin Password
if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  if [ -t 0 ]; then
    read -rsp "Enter Grafana Admin Password: " GRAFANA_ADMIN_PASSWORD
    echo
  else
    echo "Error: GRAFANA_ADMIN_PASSWORD is required in non-interactive mode" >&2
    exit 1
  fi
fi

if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  echo "Error: GRAFANA_ADMIN_PASSWORD cannot be empty" >&2
  exit 1
fi

export GITHUB_ORG AWS_ACCOUNT_ID AWS_REGION EKS_CLUSTER_NAME CONFIG_REVISION GRAFANA_ADMIN_PASSWORD

# Detect kubectl binary
if command -v kubectl >/dev/null 2>&1; then
  KUBECTL=kubectl
elif command -v kubectl.exe >/dev/null 2>&1; then
  KUBECTL=kubectl.exe
else
  echo "Error: kubectl not found in PATH" >&2
  exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo "# --- Namespace: monitoring ---"
  "$KUBECTL" create namespace monitoring --dry-run=client -o yaml
  echo "---"
  echo "# --- Secret: grafana-admin ---"
  "$KUBECTL" create secret generic grafana-admin \
    --namespace monitoring \
    --from-literal=admin-user=admin \
    --from-literal=admin-password=REDACTED \
    --dry-run=client -o yaml
else
  "$KUBECTL" create namespace monitoring --dry-run=client -o yaml | "$KUBECTL" apply -f -
  "$KUBECTL" create secret generic grafana-admin \
    --namespace monitoring \
    --from-literal=admin-user=admin \
    --from-literal="admin-password=${GRAFANA_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | "$KUBECTL" apply -f -
fi

ENVSUBST_VARS='$GITHUB_ORG $AWS_ACCOUNT_ID $AWS_REGION $EKS_CLUSTER_NAME $CONFIG_REVISION'

for file in "${APPS_DIR}"/*.yaml; do
  [ -f "$file" ] || continue
  if [ "$DRY_RUN" = true ]; then
    echo "---"
    echo "# --- Rendered from $(basename "$file") ---"
    envsubst "$ENVSUBST_VARS" < "$file"
  else
    envsubst "$ENVSUBST_VARS" < "$file" | "$KUBECTL" apply -f -
  fi
done
