#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  log_err "Uso: $0 <http://ou-https://alvo-autorizado>"
  log_err "Exemplo: $0 https://dominio-autorizado.com"
  exit 1
fi

require_http_target "$TARGET"
print_authorization_banner

if ! require_tool nuclei; then
  log_err "nuclei não está instalado. Instale antes de continuar."
  exit 1
fi

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/nuclei-quick-${SAFE_NAME}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Alvo: $TARGET"
log_info "Relatório: $OUT_DIR"
log_info "Executando nuclei em modo rápido (limite total: 60s)..."

set +e
timeout -k 10s 60s nuclei \
  -u "$TARGET" \
  -tags exposure,misconfig \
  -severity low,medium,high,critical \
  -rate-limit 30 \
  -timeout 3 \
  -retries 0 \
  -ni \
  -o "$OUT_DIR/nuclei.txt"
NUCLEI_EXIT=$?
set -e

if [ "$NUCLEI_EXIT" -eq 124 ]; then
  log_warn "Tempo limite de 60s atingido — varredura interrompida (resultado parcial salvo, se houver)."
elif [ "$NUCLEI_EXIT" -ne 0 ]; then
  log_warn "nuclei retornou código $NUCLEI_EXIT"
fi

touch "$OUT_DIR/nuclei.txt"

log_ok "Finalizado."
log_ok "Relatório: $OUT_DIR/nuclei.txt"
log_warn "Resultados requerem validação manual antes de serem considerados achados reais."
