#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONTAINER_NAME="appsec-lab-nginx"
PORT="8080"

if ! require_tool docker; then
  log_err "Docker não está disponível."
  exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  log_info "Container '$CONTAINER_NAME' já existe — removendo para recriar..."
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

log_info "Iniciando '$CONTAINER_NAME' na porta $PORT..."
docker run -d --name "$CONTAINER_NAME" -p "${PORT}:80" nginx:alpine >/dev/null

log_ok "Laboratório local pronto."
log_ok "URL: http://127.0.0.1:${PORT}"
log_ok "Comando sugerido: ./scripts/web-check.sh http://127.0.0.1:${PORT} safe"
