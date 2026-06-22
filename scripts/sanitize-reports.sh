#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

REPORT_DIR="${1:-}"

if [ -z "$REPORT_DIR" ] || [ ! -d "$REPORT_DIR" ]; then
  log_err "Uso: $0 reports/<pasta-do-relatorio>"
  log_err "Exemplo: $0 reports/example.com-safe-20260101-120000"
  exit 1
fi

REPORT_DIR="$(cd "$REPORT_DIR" && pwd)"
FINDINGS_FILE="$REPORT_DIR/sensitive-findings.txt"

log_info "Varrendo $REPORT_DIR por padrões sensíveis..."
log_warn "Este script só ALERTA — não remove nem redige nada automaticamente."

: > "$FINDINGS_FILE"

scan_pattern() {
  local label="$1" pattern="$2"
  local matches
  matches="$(grep -rInE "$pattern" "$REPORT_DIR" \
      --exclude="sensitive-findings.txt" 2>/dev/null || true)"
  if [ -n "$matches" ]; then
    {
      echo "## $label"
      echo
      echo '```'
      echo "$matches"
      echo '```'
      echo
    } >> "$FINDINGS_FILE"
    log_warn "Possível ocorrência: $label"
  fi
}

{
  echo "# Alertas de dados sensíveis"
  echo
  echo "Pasta analisada: $REPORT_DIR"
  echo "Gerado em: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  echo "Este arquivo lista padrões que PODEM indicar dados sensíveis nos"
  echo "relatórios. Pode haver falsos positivos. Revise manualmente cada"
  echo "ocorrência antes de decidir o que remover/redigir/manter."
  echo
} > "$FINDINGS_FILE"

# Caracteres de aspas isolados em variáveis para evitar quoting frágil dentro
# das regex abaixo (aspas literais dentro de string single-quoted no bash).
dq='"'
sq="'"

scan_pattern "JWT (JSON Web Token)" 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
scan_pattern "Authorization: Bearer" 'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]+'
scan_pattern "Cookies de sessão (sessionid/PHPSESSID/JSESSIONID/etc.)" '(sessionid|phpsessid|jsessionid|sid)=[A-Za-z0-9._-]{8,}'
scan_pattern "csrftoken" 'csrftoken=[A-Za-z0-9._-]{8,}'
scan_pattern "Set-Cookie genérico com valor longo" 'set-cookie:[[:space:]]*[A-Za-z0-9_-]+=[A-Za-z0-9._%-]{16,}'
scan_pattern "Chave privada (PEM)" '-----BEGIN (RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----'
scan_pattern "AWS Access Key ID" 'AKIA[0-9A-Z]{16}'
scan_pattern "Token genérico tipo API key" "(api[_-]?key|secret|token)[${dq}${sq}]?[[:space:]]*[:=][[:space:]]*[${dq}${sq}]?[A-Za-z0-9._-]{16,}"
scan_pattern "E-mail" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
scan_pattern "IP privado/interno (RFC1918)" '\b(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3})\b'
scan_pattern "Possível senha em texto (password=/pwd=/senha=)" "(password|pwd|senha)[${dq}${sq}]?[[:space:]]*[:=][[:space:]]*[${dq}${sq}]?[^${dq}${sq}[:space:]]{4,}"

if [ ! -s "$FINDINGS_FILE" ] || ! grep -q '^## ' "$FINDINGS_FILE"; then
  echo "Nenhum padrão sensível conhecido encontrado nesta varredura simples." >> "$FINDINGS_FILE"
  log_ok "Nenhum padrão sensível encontrado (varredura heurística — não é garantia)."
else
  log_warn "Possíveis dados sensíveis encontrados — revise: $FINDINGS_FILE"
fi

log_ok "Resultado: $FINDINGS_FILE"
