#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  log_err "Uso: $0 <http://ou-https://alvo-autorizado> [safe|normal|deep]"
  log_err "Exemplo: $0 http://127.0.0.1:8080 safe"
  exit 1
fi

require_http_target "$TARGET"
PROFILE="$(normalize_profile "${2:-safe}")"

print_authorization_banner

if [ "$PROFILE" = "deep" ]; then
  confirm_deep_profile "$TARGET"
fi

SCHEME="$(target_scheme "$TARGET")"
HOST="$(target_host "$TARGET")"
PORT="$(target_port "$TARGET")"

SAFE_NAME="$(safe_target_name "$TARGET")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/reports/${SAFE_NAME}-${PROFILE}-${TIMESTAMP}"
mkdir -p "$OUT_DIR"

log_info "Alvo: $TARGET"
log_info "Perfil: $PROFILE"
log_info "Relatório: $OUT_DIR"

TOOLS_RUN=()
FILES_GENERATED=()
COMMANDS=()

# 1. Headers HTTP
log_info "==> Headers HTTP (curl)"
COMMANDS+=("curl -sI --max-time 10 \"$TARGET\"")
if timeout -k 5s 15 curl -sI --max-time 10 "$TARGET" 2>&1 | tee "$OUT_DIR/headers.txt"; then
  TOOLS_RUN+=("curl -sI")
else
  log_warn "Não foi possível obter headers (alvo pode estar fora do ar) — ver $OUT_DIR/headers.txt"
fi
FILES_GENERATED+=("headers.txt")

# 2. Indícios de WAF/CDN (heurística passiva sobre os headers já coletados)
log_info "==> Indícios de proteção de borda (WAF/CDN) — heurística passiva"
analyze_edge_protection "$OUT_DIR/headers.txt" "$OUT_DIR/edge-protection.txt"
cat "$OUT_DIR/edge-protection.txt"
TOOLS_RUN+=("análise heurística de WAF/CDN")
FILES_GENERATED+=("edge-protection.txt")

# 3. WhatWeb
log_info "==> Fingerprint (whatweb)"
if require_tool whatweb; then
  COMMANDS+=("whatweb -a 1 \"$TARGET\"")
  if timeout -k 10s 60 whatweb -a 1 "$TARGET" 2>&1 | tee "$OUT_DIR/whatweb.txt"; then
    TOOLS_RUN+=("whatweb")
  else
    log_warn "whatweb terminou com erro/timeout"
  fi
  FILES_GENERATED+=("whatweb.txt")
fi

# 4. Nmap na porta do alvo (safe: -sV | normal/deep: -sV -sC)
log_info "==> Nmap (porta $PORT, perfil $PROFILE)"
if require_tool nmap; then
  COMMANDS+=("nmap -Pn -sV [-sC] -p $PORT $HOST")
  if run_nmap_target_port "$HOST" "$PORT" "$PROFILE" "$OUT_DIR/nmap.txt"; then
    TOOLS_RUN+=("nmap -p $PORT")
  else
    log_warn "nmap terminou com erro/timeout"
  fi
  FILES_GENERATED+=("nmap.txt")
fi

# 5. Nmap - perfil de exposição (top-ports varia por perfil; deep usa portas completas)
log_info "==> Nmap - perfil de exposição (perfil $PROFILE)"
if require_tool nmap; then
  COMMANDS+=("nmap -Pn -sV [-sC] [--top-ports N | -p-] $HOST")
  if run_nmap_profile "$HOST" "$PROFILE" "$OUT_DIR/nmap-exposure.txt"; then
    TOOLS_RUN+=("nmap (perfil de exposição: $PROFILE)")
  else
    log_warn "nmap (perfil de exposição) terminou com erro/timeout"
  fi
  FILES_GENERATED+=("nmap-exposure.txt")
  log_warn "Este scan apenas observa portas/serviços abertos — não tenta explorar nada encontrado."
fi

# 6. Descoberta de conteúdo (gobuster + ffuf), wordlist conforme perfil
log_info "==> Descoberta de conteúdo (gobuster + ffuf, perfil $PROFILE)"
COMMANDS+=("gobuster dir -u $TARGET -w <wordlist-$PROFILE> ...")
COMMANDS+=("ffuf -u $TARGET/FUZZ -w <wordlist-$PROFILE> ...")
run_discovery_profile "$TARGET" "$PROFILE" "$OUT_DIR" || true
if [ -f "$OUT_DIR/gobuster.txt" ]; then
  TOOLS_RUN+=("gobuster dir")
  FILES_GENERATED+=("gobuster.txt")
fi
if [ -f "$OUT_DIR/ffuf.json" ]; then
  TOOLS_RUN+=("ffuf")
  FILES_GENERATED+=("ffuf.json")
fi

# 7. Nuclei (tags e severidade conforme perfil)
log_info "==> Nuclei (perfil $PROFILE)"
COMMANDS+=("nuclei -u $TARGET [-tags ...] -severity ... -rate-limit ... -ni")
if run_nuclei_profile "$TARGET" "$PROFILE" "$OUT_DIR/nuclei.txt"; then
  TOOLS_RUN+=("nuclei (perfil $PROFILE)")
fi
FILES_GENERATED+=("nuclei.txt")
if [ "$PROFILE" != "deep" ]; then
  log_info "Para mais cobertura, use: scripts/web-check.sh \"$TARGET\" $([ "$PROFILE" = "safe" ] && echo normal || echo deep)"
fi

# 8. Nikto — apenas em normal/deep (mais lento, mais abrangente)
if [ "$PROFILE" != "safe" ]; then
  log_info "==> Nikto (perfil $PROFILE)"
  if require_tool nikto; then
    COMMANDS+=("nikto -h \"$TARGET\" -maxtime 120s")
    if timeout -k 15s 150 nikto -h "$TARGET" -maxtime 120s 2>&1 | tee "$OUT_DIR/nikto.txt"; then
      TOOLS_RUN+=("nikto")
    else
      log_warn "nikto terminou com erro/timeout"
    fi
    FILES_GENERATED+=("nikto.txt")
  fi
fi

# metadata.txt
{
  echo "target: $TARGET"
  echo "profile: $PROFILE"
  echo "date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "host: $HOST"
  echo "port: $PORT"
  echo "scheme: $SCHEME"
  echo "commands_executed:"
  for c in "${COMMANDS[@]}"; do
    echo "  - $c"
  done
} > "$OUT_DIR/metadata.txt"

# summary.md
log_info "Gerando summary.md"
{
  echo "# Relatório de auditoria web"
  echo
  echo "- **Alvo:** $TARGET"
  echo "- **Perfil:** $PROFILE"
  echo "- **Data/hora:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "- **Host:** $HOST  |  **Porta:** $PORT  |  **Scheme:** $SCHEME"
  echo "- **Diretório do relatório:** $OUT_DIR"
  echo
  echo "## Visão geral"
  echo
  echo "Ferramentas executadas com sucesso:"
  echo
  if [ "${#TOOLS_RUN[@]}" -eq 0 ]; then
    echo "Nenhuma ferramenta concluiu execução com sucesso."
  else
    for t in "${TOOLS_RUN[@]}"; do
      echo "- $t"
    done
  fi
  echo
  echo "Arquivos gerados:"
  echo
  if [ "${#FILES_GENERATED[@]}" -eq 0 ]; then
    echo "Nenhum arquivo gerado."
  else
    for f in "${FILES_GENERATED[@]}"; do
      echo "- $f"
    done
  fi
  echo
  echo "## Tecnologias detectadas"
  echo
  if [ -f "$OUT_DIR/whatweb.txt" ]; then
    echo '```'
    cat "$OUT_DIR/whatweb.txt"
    echo '```'
  else
    echo "whatweb não executado."
  fi
  echo
  echo "## Headers ausentes / indícios de borda"
  echo
  if [ -f "$OUT_DIR/headers.txt" ]; then
    STATUS_LINE="$(head -n 1 "$OUT_DIR/headers.txt" 2>/dev/null || true)"
    echo "- Resposta HTTP inicial: \`${STATUS_LINE:-sem resposta}\`"
  fi
  for h in "Strict-Transport-Security" "Content-Security-Policy" "X-Frame-Options" "X-Content-Type-Options"; do
    if [ -f "$OUT_DIR/headers.txt" ] && grep -qi "^${h}:" "$OUT_DIR/headers.txt"; then
      echo "- $h: presente"
    else
      echo "- $h: ausente (revisar manualmente)"
    fi
  done
  if [ -f "$OUT_DIR/edge-protection.txt" ]; then
    echo
    echo "Indícios de WAF/CDN (ver \`edge-protection.txt\`):"
    echo '```'
    tail -n +6 "$OUT_DIR/edge-protection.txt"
    echo '```'
  fi
  echo
  echo "## Portas / exposição"
  echo
  if [ -f "$OUT_DIR/nmap.txt" ]; then
    OPEN_PORTS="$(grep -E '^[0-9]+/tcp' "$OUT_DIR/nmap.txt" 2>/dev/null || true)"
    if [ -n "$OPEN_PORTS" ]; then
      echo '```'
      echo "$OPEN_PORTS"
      echo '```'
    fi
  fi
  if [ -f "$OUT_DIR/nmap-exposure.txt" ]; then
    EXPOSED_PORTS="$(grep -E '^[0-9]+/tcp\s+open' "$OUT_DIR/nmap-exposure.txt" 2>/dev/null || true)"
    if [ -n "$EXPOSED_PORTS" ]; then
      echo "Perfil de exposição — portas abertas encontradas:"
      echo '```'
      echo "$EXPOSED_PORTS"
      echo '```'
    else
      echo "Perfil de exposição: nenhuma porta adicional aberta encontrada."
    fi
  fi
  echo
  echo "## Diretórios/arquivos encontrados"
  echo
  if [ -f "$OUT_DIR/gobuster.txt" ]; then
    GOBUSTER_HITS="$(grep -c '^/' "$OUT_DIR/gobuster.txt" 2>/dev/null || echo 0)"
    echo "- Gobuster: $GOBUSTER_HITS caminho(s) encontrados."
  fi
  if [ -f "$OUT_DIR/ffuf.json" ]; then
    echo "- FFUF: resultado em \`ffuf.json\` (formato JSON)."
  fi
  echo
  echo "## Achados do Nuclei"
  echo
  if [ -f "$OUT_DIR/nuclei.txt" ]; then
    NUCLEI_HITS="$(grep -c . "$OUT_DIR/nuclei.txt" 2>/dev/null || echo 0)"
    echo "$NUCLEI_HITS linha(s) de saída. Conteúdo:"
    echo '```'
    cat "$OUT_DIR/nuclei.txt"
    echo '```'
  else
    echo "Nuclei não executado ou sem saída."
  fi
  echo
  echo "## Observações de falso positivo"
  echo
  echo "Detecções automáticas (Nuclei, Nikto, gobuster/ffuf, whatweb) podem"
  echo "conter falsos positivos. Confirme manualmente antes de reportar."
  echo
  echo "## Próximos passos manuais"
  echo
  echo "1. Validar manualmente cada achado relevante (ver \`docs/REPORTING.md\`)."
  echo "2. Se o perfil usado foi \`safe\` ou \`normal\`, considerar rodar um perfil"
  echo "   mais profundo (\`normal\` ou \`deep\`) sobre os pontos de interesse."
  echo "3. Avaliar contexto de negócio/impacto antes de classificar severidade."
  echo "4. Rodar \`scripts/sanitize-reports.sh $OUT_DIR\` antes de compartilhar o"
  echo "   relatório, para identificar dados sensíveis acidentalmente capturados."
} > "$OUT_DIR/summary.md"

log_ok "Finalizado."
log_ok "Relatório completo em: $OUT_DIR"
log_ok "Metadados: $OUT_DIR/metadata.txt"
log_ok "Resumo: $OUT_DIR/summary.md"
