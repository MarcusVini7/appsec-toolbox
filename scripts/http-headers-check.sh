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

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/headers-${SAFE_NAME}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"
HEADERS_FILE="$OUT_DIR/headers.txt"

log_info "Alvo: $TARGET"

if ! timeout -k 5s 15 curl -sI --max-time 10 "$TARGET" > "$HEADERS_FILE" 2>&1; then
  log_err "Não foi possível obter headers de $TARGET"
  log_err "Resposta parcial (se houver) salva em: $HEADERS_FILE"
  exit 1
fi

check_header() {
  local name="$1"
  if grep -qi "^${name}:" "$HEADERS_FILE"; then
    log_ok "$name: presente"
  else
    log_warn "$name: ausente"
  fi
}

echo
echo "== Headers de segurança =="
check_header "Strict-Transport-Security"
check_header "Content-Security-Policy"
check_header "X-Frame-Options"
check_header "X-Content-Type-Options"
check_header "Referrer-Policy"
check_header "Permissions-Policy"

echo
echo "== Cookies (revisão manual recomendada) =="
COOKIE_LINES="$(grep -i '^set-cookie:' "$HEADERS_FILE" || true)"
if [ -z "$COOKIE_LINES" ]; then
  log_info "Nenhum cookie definido nesta resposta."
else
  while IFS= read -r line; do
    echo "$line"
    if echo "$line" | grep -qi 'httponly'; then
      log_ok "  HttpOnly: presente"
    else
      log_warn "  HttpOnly: ausente — revisar manualmente"
    fi
    if echo "$line" | grep -qi 'secure'; then
      log_ok "  Secure: presente"
    else
      log_warn "  Secure: ausente — revisar manualmente"
    fi
    if echo "$line" | grep -qi 'samesite'; then
      log_ok "  SameSite: presente"
    else
      log_warn "  SameSite: ausente — revisar manualmente"
    fi
  done <<< "$COOKIE_LINES"
fi

echo
echo "== Indícios de WAF/CDN (heurística passiva, sem requisição extra) =="
analyze_edge_protection "$HEADERS_FILE" "$OUT_DIR/edge-protection.txt"
tail -n +6 "$OUT_DIR/edge-protection.txt"

echo
log_info "Headers completos salvos em: $HEADERS_FILE"
log_info "Análise de WAF/CDN salva em: $OUT_DIR/edge-protection.txt"
log_warn "Verificação heurística: ausência de um header não significa vulnerabilidade automática."
log_warn "Valide o contexto da aplicação manualmente antes de registrar qualquer achado."
