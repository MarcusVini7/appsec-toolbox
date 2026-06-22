#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  log_err "Uso: $0 <https://alvo-autorizado>"
  log_err "Exemplo: $0 https://dominio-autorizado.com"
  exit 1
fi

require_https_target "$TARGET"

TESTSSL_BIN=""
if tool_available testssl; then
  TESTSSL_BIN="testssl"
elif tool_available testssl.sh; then
  TESTSSL_BIN="testssl.sh"
else
  log_err "testssl não encontrado no PATH."
  log_err "Instale a partir de: https://github.com/drwetter/testssl.sh"
  log_err "Alternativa via Docker: docker run --rm -ti drwetter/testssl.sh $TARGET"
  exit 1
fi

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/tls-${SAFE_NAME}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Alvo: $TARGET"
log_info "Relatório: $OUT_DIR"
log_info "Executando $TESTSSL_BIN (limite total: 5min)..."

set +e
timeout -k 10s 300s "$TESTSSL_BIN" --quiet --color 0 "$TARGET" > "$OUT_DIR/testssl.txt" 2>&1
TESTSSL_EXIT=$?
set -e

if [ "$TESTSSL_EXIT" -eq 124 ]; then
  log_warn "Tempo limite de 5 minutos atingido — resultado parcial salvo."
elif [ "$TESTSSL_EXIT" -ne 0 ]; then
  log_warn "$TESTSSL_BIN retornou código $TESTSSL_EXIT"
fi

log_ok "Finalizado."
log_ok "Relatório: $OUT_DIR/testssl.txt"
log_warn "Revise manualmente os achados antes de classificá-los como vulnerabilidade."
