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

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/discovery-${SAFE_NAME}-${PROFILE}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Alvo: $TARGET"
log_info "Perfil: $PROFILE"
log_info "Wordlist: $(discovery_wordlist_for_profile "$PROFILE")"
log_info "Relatório: $OUT_DIR"
log_warn "Apenas descoberta de conteúdo (diretórios/arquivos comuns). Sem wordlist de senha e sem tentativa de login."

run_discovery_profile "$TARGET" "$PROFILE" "$OUT_DIR"

{
  echo "# Descoberta de conteúdo"
  echo
  echo "- **Alvo:** $TARGET"
  echo "- **Perfil:** $PROFILE"
  echo "- **Wordlist:** $(discovery_wordlist_for_profile "$PROFILE")"
  echo "- **Data/hora:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  if [ -f "$OUT_DIR/gobuster.txt" ]; then
    echo "## Gobuster"
    echo
    echo '```'
    cat "$OUT_DIR/gobuster.txt"
    echo '```'
    echo
  fi
  if [ -f "$OUT_DIR/ffuf.json" ]; then
    echo "## FFUF"
    echo
    echo "Resultado em \`ffuf.json\` (formato JSON)."
    echo
  fi
  echo "## Observação"
  echo
  echo "Resultados requerem validação manual — abrir cada caminho encontrado e"
  echo "confirmar se realmente expõe algo sensível antes de reportar."
} > "$OUT_DIR/summary.md"

log_ok "Finalizado."
log_ok "Relatório: $OUT_DIR"
log_ok "Resumo: $OUT_DIR/summary.md"
