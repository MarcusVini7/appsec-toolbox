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
OUT_DIR="$ROOT_DIR/reports/headers-audit-${SAFE_NAME}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"
HEADERS_FILE="$OUT_DIR/headers.txt"
REPORT_FILE="$OUT_DIR/headers-audit.md"

log_info "Alvo: $TARGET"

if ! timeout -k 5s 15 curl -sI --max-time 10 "$TARGET" > "$HEADERS_FILE" 2>&1; then
  log_err "Não foi possível obter headers de $TARGET"
  log_err "Resposta parcial (se houver) salva em: $HEADERS_FILE"
  exit 1
fi

get_header_value() {
  local name="$1"
  # "|| true" no final é essencial: com pipefail ativo, grep sem match retorna
  # exit 1 mesmo quando isso é o resultado normal/esperado (header ausente).
  # Sem isso, "VALUE=$(get_header_value ...)" dispara set -e e mata o script
  # silenciosamente no primeiro header ausente.
  grep -i "^${name}:" "$HEADERS_FILE" 2>/dev/null | head -n1 | sed -E "s/^[^:]+:[[:space:]]*//I" | tr -d '\r' || true
}

print_result() {
  local status="$1" name="$2" detail="$3"
  case "$status" in
    OK)     log_ok   "$name: $detail" ;;
    WARN)   log_warn "$name: $detail" ;;
    REVIEW) printf '%b[?]%b %s: %s\n' "$C_YELLOW" "$C_RESET" "$name" "$detail" ;;
  esac
  echo "| $name | $status | $detail |" >> "$OUT_DIR/.rows.tmp"
}

classify_simple_presence() {
  # Para headers onde só nos importa presença/ausência (sem heurística de valor)
  local name="$1" value="$2"
  if [ -z "$value" ]; then
    echo "REVIEW|ausente — revisar se é necessário neste contexto"
  else
    echo "OK|presente ($value)"
  fi
}

: > "$OUT_DIR/.rows.tmp"

echo
echo "== Auditoria de headers de segurança =="

# Strict-Transport-Security
VALUE="$(get_header_value 'Strict-Transport-Security')"
if [ -z "$VALUE" ]; then
  print_result REVIEW "Strict-Transport-Security" "ausente — considerar se o site é servido sempre via HTTPS"
elif echo "$VALUE" | grep -qi 'max-age=0'; then
  print_result WARN "Strict-Transport-Security" "max-age=0 ($VALUE) — efetivamente desativa o HSTS"
else
  print_result OK "Strict-Transport-Security" "presente ($VALUE)"
fi

# Content-Security-Policy
VALUE="$(get_header_value 'Content-Security-Policy')"
if [ -z "$VALUE" ]; then
  print_result REVIEW "Content-Security-Policy" "ausente — avaliar necessidade conforme a aplicação"
elif echo "$VALUE" | grep -qiE "unsafe-inline|unsafe-eval|\*"; then
  print_result WARN "Content-Security-Policy" "presente mas com diretiva permissiva (unsafe-inline/unsafe-eval/wildcard)"
else
  print_result OK "Content-Security-Policy" "presente"
fi

# X-Frame-Options
VALUE="$(get_header_value 'X-Frame-Options')"
if [ -z "$VALUE" ]; then
  print_result REVIEW "X-Frame-Options" "ausente — verificar se CSP frame-ancestors cobre isso"
elif echo "$VALUE" | grep -qiE 'deny|sameorigin'; then
  print_result OK "X-Frame-Options" "presente ($VALUE)"
else
  print_result WARN "X-Frame-Options" "valor não reconhecido: $VALUE"
fi

# X-Content-Type-Options
VALUE="$(get_header_value 'X-Content-Type-Options')"
if [ -z "$VALUE" ]; then
  print_result REVIEW "X-Content-Type-Options" "ausente"
elif echo "$VALUE" | grep -qi 'nosniff'; then
  print_result OK "X-Content-Type-Options" "presente (nosniff)"
else
  print_result WARN "X-Content-Type-Options" "valor inesperado: $VALUE"
fi

# Referrer-Policy
VALUE="$(get_header_value 'Referrer-Policy')"
RESULT="$(classify_simple_presence "Referrer-Policy" "$VALUE")"
print_result "${RESULT%%|*}" "Referrer-Policy" "${RESULT#*|}"

# Permissions-Policy
VALUE="$(get_header_value 'Permissions-Policy')"
RESULT="$(classify_simple_presence "Permissions-Policy" "$VALUE")"
print_result "${RESULT%%|*}" "Permissions-Policy" "${RESULT#*|}"

# Cross-Origin-Opener-Policy
VALUE="$(get_header_value 'Cross-Origin-Opener-Policy')"
RESULT="$(classify_simple_presence "Cross-Origin-Opener-Policy" "$VALUE")"
print_result "${RESULT%%|*}" "Cross-Origin-Opener-Policy" "${RESULT#*|}"

# Cross-Origin-Resource-Policy
VALUE="$(get_header_value 'Cross-Origin-Resource-Policy')"
RESULT="$(classify_simple_presence "Cross-Origin-Resource-Policy" "$VALUE")"
print_result "${RESULT%%|*}" "Cross-Origin-Resource-Policy" "${RESULT#*|}"

# Cross-Origin-Embedder-Policy
VALUE="$(get_header_value 'Cross-Origin-Embedder-Policy')"
RESULT="$(classify_simple_presence "Cross-Origin-Embedder-Policy" "$VALUE")"
print_result "${RESULT%%|*}" "Cross-Origin-Embedder-Policy" "${RESULT#*|}"

echo
echo "== Cookies (revisão manual recomendada) =="
COOKIE_ROWS=""
COOKIE_LINES="$(grep -i '^set-cookie:' "$HEADERS_FILE" || true)"
if [ -z "$COOKIE_LINES" ]; then
  log_info "Nenhum cookie definido nesta resposta."
else
  while IFS= read -r line; do
    echo "$line"
    cookie_name="$(echo "$line" | sed -E 's/^[Ss]et-[Cc]ookie:[[:space:]]*([^=]+)=.*/\1/')"
    for flag in HttpOnly Secure SameSite; do
      if echo "$line" | grep -qi "$flag"; then
        log_ok "  $flag: presente"
        COOKIE_ROWS="${COOKIE_ROWS}| $cookie_name | $flag | OK | presente |\n"
      else
        log_warn "  $flag: ausente — revisar manualmente"
        COOKIE_ROWS="${COOKIE_ROWS}| $cookie_name | $flag | REVIEW | ausente |\n"
      fi
    done
  done <<< "$COOKIE_LINES"
fi

# Relatório .md
{
  echo "# Auditoria de headers HTTP"
  echo
  echo "- **Alvo:** $TARGET"
  echo "- **Data/hora:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  echo "Classificação: \`OK\` (presente/adequado), \`WARN\` (presente mas com"
  echo "configuração permissiva/atenção), \`REVIEW\` (ausente — requer avaliação"
  echo "manual do contexto; ausência não é vulnerabilidade automática)."
  echo
  echo "## Headers"
  echo
  echo "| Header | Status | Detalhe |"
  echo "|---|---|---|"
  cat "$OUT_DIR/.rows.tmp"
  echo
  echo "## Cookies"
  echo
  if [ -n "$COOKIE_ROWS" ]; then
    echo "| Cookie | Flag | Status | Detalhe |"
    echo "|---|---|---|---|"
    printf '%b' "$COOKIE_ROWS"
  else
    echo "Nenhum cookie definido na resposta analisada."
  fi
  echo
  echo "## Observação"
  echo
  echo "Esta é uma verificação heurística sobre uma única resposta HTTP."
  echo "Ausência de header não é, por si só, uma vulnerabilidade confirmada —"
  echo "valide o contexto da aplicação antes de registrar qualquer achado."
} > "$REPORT_FILE"

rm -f "$OUT_DIR/.rows.tmp"

echo
log_info "Headers completos salvos em: $HEADERS_FILE"
log_ok "Relatório: $REPORT_FILE"
