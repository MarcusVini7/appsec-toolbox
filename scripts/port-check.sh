#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

HOST_ARG="${1:-}"

if [ -z "$HOST_ARG" ]; then
  log_err "Uso: $0 <host-ou-ip-autorizado> [safe|normal|deep]"
  log_err "Exemplo: $0 127.0.0.1 safe"
  exit 1
fi

PROFILE="$(normalize_profile "${2:-safe}")"

print_authorization_banner

if [ "$PROFILE" = "deep" ]; then
  log_warn "Perfil deep faz varredura de TODAS as portas (1-65535). Pode levar bastante tempo."
  confirm_deep_profile "$HOST_ARG"
fi

if ! require_tool nmap; then
  log_err "nmap não está instalado. Instale antes de continuar."
  exit 1
fi

SAFE_NAME="$(safe_target_name "$HOST_ARG")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/port-check-${SAFE_NAME}-${PROFILE}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Host: $HOST_ARG"
log_info "Perfil: $PROFILE"
log_info "Relatório: $OUT_DIR"
log_warn "Apenas detecção de serviços/versão — nenhuma exploração é executada."

run_nmap_profile "$HOST_ARG" "$PROFILE" "$OUT_DIR/nmap.txt"

{
  echo "# Varredura de portas"
  echo
  echo "- **Host:** $HOST_ARG"
  echo "- **Perfil:** $PROFILE"
  echo "- **Data/hora:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  echo "## Portas abertas"
  echo
  OPEN_PORTS="$(grep -E '^[0-9]+/tcp\s+open' "$OUT_DIR/nmap.txt" 2>/dev/null || true)"
  if [ -n "$OPEN_PORTS" ]; then
    echo '```'
    echo "$OPEN_PORTS"
    echo '```'
  else
    echo "Nenhuma porta aberta encontrada (ou nmap não retornou resultado utilizável)."
  fi
  echo
  echo "## Observação"
  echo
  echo "Esta varredura identifica serviços expostos — não interage além da"
  echo "detecção padrão de versão/scripts seguros do nmap. Avalie manualmente"
  echo "se a exposição encontrada é esperada (firewall/segmentação de rede)."
} > "$OUT_DIR/summary.md"

log_ok "Finalizado."
log_ok "Relatório: $OUT_DIR/nmap.txt"
log_ok "Resumo: $OUT_DIR/summary.md"
