#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  log_err "Uso: $0 <http://ou-https://alvo-autorizado> [safe|normal|deep]"
  log_err "Exemplo: $0 https://dominio-autorizado.com normal"
  exit 1
fi

require_http_target "$TARGET"
PROFILE="$(normalize_profile "${2:-safe}")"

print_authorization_banner

if [ "$PROFILE" = "deep" ]; then
  confirm_deep_profile "$TARGET"
fi

if ! require_tool nuclei; then
  log_err "nuclei não está instalado. Instale antes de continuar."
  exit 1
fi

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/nuclei-${SAFE_NAME}-${PROFILE}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Alvo: $TARGET"
log_info "Perfil: $PROFILE"
log_info "Relatório: $OUT_DIR"
log_warn "-ni ativo: sem interactsh/OAST por padrão (evita depender de infraestrutura externa)."

run_nuclei_profile "$TARGET" "$PROFILE" "$OUT_DIR/nuclei.txt"

log_ok "Finalizado."
log_ok "Relatório: $OUT_DIR/nuclei.txt"
log_warn "Resultados requerem validação manual antes de serem considerados achados reais."
