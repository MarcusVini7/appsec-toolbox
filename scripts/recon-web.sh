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

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/recon-${SAFE_NAME}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Alvo: $TARGET"
log_info "Relatório: $OUT_DIR"

# 1. curl -I seguindo redirecionamentos (mostra a cadeia completa)
log_info "==> curl -I (com redirecionamentos)"
if ! timeout -k 5s 20 curl -sIL --max-time 15 "$TARGET" 2>&1 | tee "$OUT_DIR/curl-redirects.txt"; then
  log_warn "curl (com redirecionamento) terminou com erro/timeout"
fi

# 2. headers da resposta direta (sem seguir redirecionamento)
log_info "==> curl -I (sem seguir redirecionamento)"
if ! timeout -k 5s 15 curl -sI --max-time 10 "$TARGET" 2>&1 | tee "$OUT_DIR/headers.txt"; then
  log_warn "curl terminou com erro/timeout"
fi

# 3. WhatWeb — fingerprint de tecnologia/servidor/framework
log_info "==> WhatWeb (fingerprint de tecnologia)"
if require_tool whatweb; then
  if ! timeout -k 10s 60 whatweb -a 3 "$TARGET" 2>&1 | tee "$OUT_DIR/whatweb.txt"; then
    log_warn "whatweb terminou com erro/timeout"
  fi
fi

# 4. httpx — probing rápido com detecção de tecnologia, status, título, CDN
log_info "==> httpx (probing/fingerprint)"
if require_tool httpx; then
  if ! echo "$TARGET" | timeout -k 10s 30 httpx -silent -title -status-code -tech-detect -location -cdn -server 2>&1 \
      | tee "$OUT_DIR/httpx.txt"; then
    log_warn "httpx terminou com erro/timeout"
  fi
fi

# 5. Indícios de WAF/CDN (reaproveita heurística passiva já existente)
log_info "==> Indícios de proteção de borda (WAF/CDN)"
analyze_edge_protection "$OUT_DIR/headers.txt" "$OUT_DIR/edge-protection.txt"
cat "$OUT_DIR/edge-protection.txt"

# 6. Headers de segurança (presença simples — auditoria completa fica em headers-audit.sh)
log_info "==> Headers de segurança (resumo simples)"
{
  echo "# Headers de segurança — resumo"
  echo
  for h in "Strict-Transport-Security" "Content-Security-Policy" "X-Frame-Options" \
           "X-Content-Type-Options" "Referrer-Policy" "Permissions-Policy"; do
    if grep -qi "^${h}:" "$OUT_DIR/headers.txt" 2>/dev/null; then
      echo "- $h: presente"
    else
      echo "- $h: ausente"
    fi
  done
  echo
  echo "Para auditoria completa com classificação OK/WARN/REVIEW, use:"
  echo "  scripts/headers-audit.sh \"$TARGET\""
} | tee "$OUT_DIR/security-headers-summary.txt"

# 7. Cookies
log_info "==> Cookies"
{
  echo "# Cookies observados"
  echo
  COOKIE_LINES="$(grep -i '^set-cookie:' "$OUT_DIR/headers.txt" 2>/dev/null || true)"
  if [ -z "$COOKIE_LINES" ]; then
    echo "Nenhum cookie definido na resposta inicial."
  else
    echo "$COOKIE_LINES"
  fi
} | tee "$OUT_DIR/cookies.txt"

log_ok "Finalizado."
log_ok "Relatório: $OUT_DIR"
log_warn "Resultados requerem validação manual antes de qualquer conclusão."
