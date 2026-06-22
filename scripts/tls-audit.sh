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
OUT_DIR="$ROOT_DIR/reports/tls-audit-${SAFE_NAME}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"
RAW_FILE="$OUT_DIR/testssl.txt"
SUMMARY_FILE="$OUT_DIR/tls-summary.md"

log_info "Alvo: $TARGET"
log_info "Relatório: $OUT_DIR"
log_info "Executando $TESTSSL_BIN (limite total: 5min)..."

set +e
timeout -k 10s 300s "$TESTSSL_BIN" --quiet --color 0 "$TARGET" > "$RAW_FILE" 2>&1
TESTSSL_EXIT=$?
set -e

if [ "$TESTSSL_EXIT" -eq 124 ]; then
  log_warn "Tempo limite de 5 minutos atingido — resultado parcial salvo."
elif [ "$TESTSSL_EXIT" -ne 0 ]; then
  log_warn "$TESTSSL_BIN retornou código $TESTSSL_EXIT"
fi

PROTOCOLS="$(grep -iE 'SSLv2|SSLv3|TLS ?1(\.[0-3])?' "$RAW_FILE" 2>/dev/null | grep -iE 'offered|not offered' || true)"
CERT_INFO="$(grep -iE 'subject|issuer|expir|valid|signature algorithm|common name|cert\. validity' "$RAW_FILE" 2>/dev/null || true)"
WEAK_CIPHERS="$(grep -iE 'weak|NULL|EXPORT|RC4|3DES|MD5|anon|low' "$RAW_FILE" 2>/dev/null || true)"

{
  echo "# Resumo TLS/SSL"
  echo
  echo "- **Alvo:** $TARGET"
  echo "- **Data/hora:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "- **Ferramenta:** $TESTSSL_BIN"
  echo "- **Saída completa:** \`testssl.txt\`"
  echo
  echo "## Protocolos aceitos"
  echo
  if [ -n "$PROTOCOLS" ]; then
    echo '```'
    echo "$PROTOCOLS"
    echo '```'
  else
    echo "Não foi possível extrair automaticamente — verifique \`testssl.txt\`."
  fi
  echo
  echo "## Certificado"
  echo
  if [ -n "$CERT_INFO" ]; then
    echo '```'
    echo "$CERT_INFO"
    echo '```'
  else
    echo "Não foi possível extrair automaticamente — verifique \`testssl.txt\`."
  fi
  echo
  echo "## Ciphers potencialmente fracos"
  echo
  if [ -n "$WEAK_CIPHERS" ]; then
    echo '```'
    echo "$WEAK_CIPHERS"
    echo '```'
  else
    echo "Nenhum indício óbvio de cipher fraco encontrado por esta busca simples."
    echo "Isso NÃO substitui a leitura completa de \`testssl.txt\`."
  fi
  echo
  echo "## Observações manuais"
  echo
  echo "- Confirme manualmente a validade e a cadeia completa do certificado."
  echo "- Avalie se protocolos legados (SSLv2/SSLv3/TLS1.0/TLS1.1) realmente"
  echo "  precisam estar habilitados para algum cliente legado conhecido."
  echo "- Esta extração de resumo é heurística (baseada em \`grep\`); a saída"
  echo "  completa em \`testssl.txt\` é a fonte de verdade."
} > "$SUMMARY_FILE"

log_ok "Finalizado."
log_ok "Relatório bruto: $RAW_FILE"
log_ok "Resumo: $SUMMARY_FILE"
log_warn "Revise manualmente os achados antes de classificá-los como vulnerabilidade."
