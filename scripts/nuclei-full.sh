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

cat <<EOF
================================================================
 NUCLEI — VARREDURA COMPLETA

 Este modo executa o conjunto completo de templates do Nuclei
 contra o alvo. Pode levar bastante tempo e gerar um volume maior
 de tráfego do que o modo rápido.

 Use SOMENTE em ambientes próprios ou com autorização explícita
 e por escrito do responsável pelo alvo:

   Alvo: $TARGET

 Testar sistemas de terceiros sem permissão pode ser crime.
================================================================
EOF

read -r -p "Confirma que possui autorização explícita para testar este alvo? [digite 'sim' para continuar]: " CONFIRM
if [ "$CONFIRM" != "sim" ]; then
  log_warn "Operação cancelada pelo operador."
  exit 1
fi

if ! require_tool nuclei; then
  log_err "nuclei não está instalado. Instale antes de continuar."
  exit 1
fi

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/nuclei-full-${SAFE_NAME}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Alvo: $TARGET"
log_info "Relatório: $OUT_DIR"
log_info "Executando nuclei completo (rate limit conservador, limite total: 30min)..."

set +e
timeout -k 15s 1800s nuclei \
  -u "$TARGET" \
  -severity low,medium,high,critical \
  -rate-limit 10 \
  -timeout 5 \
  -retries 1 \
  -ni \
  -o "$OUT_DIR/nuclei-full.txt"
NUCLEI_EXIT=$?
set -e

if [ "$NUCLEI_EXIT" -eq 124 ]; then
  log_warn "Tempo limite de 30 minutos atingido — varredura interrompida (resultado parcial salvo)."
elif [ "$NUCLEI_EXIT" -ne 0 ]; then
  log_warn "nuclei retornou código $NUCLEI_EXIT"
fi

touch "$OUT_DIR/nuclei-full.txt"

log_ok "Finalizado."
log_ok "Relatório: $OUT_DIR/nuclei-full.txt"
log_warn "Resultados requerem validação manual antes de serem considerados achados reais."
