#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONTAINER_NAME="appsec-lab-nginx"

if ! require_tool docker; then
  log_err "Docker não está disponível."
  exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  docker rm -f "$CONTAINER_NAME" >/dev/null
  log_ok "Container '$CONTAINER_NAME' removido."
else
  log_info "Container '$CONTAINER_NAME' não existe — nada a fazer."
fi
