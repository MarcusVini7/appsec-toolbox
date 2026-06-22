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

log_info "Aguardando o serviço responder em http://127.0.0.1:${PORT}..."
READY=0
for _ in $(seq 1 20); do
  if curl -sf --max-time 1 "http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.5
done

if [ "$READY" -eq 1 ]; then
  log_ok "Laboratório local pronto."
else
  log_warn "Container iniciado, mas o serviço ainda não respondeu após 10s."
  log_warn "Verifique com: docker logs $CONTAINER_NAME"
fi
log_ok "URL: http://127.0.0.1:${PORT}"
log_ok "Comando sugerido: ./scripts/web-check.sh http://127.0.0.1:${PORT} safe"
