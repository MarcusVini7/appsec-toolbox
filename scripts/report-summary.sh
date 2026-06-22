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
SUMMARY_FILE="$REPORT_DIR/summary.md"

log_info "Consolidando relatório em: $REPORT_DIR"

TARGET="(desconhecido — sem metadata.txt)"
PROFILE="(desconhecido)"
REPORT_DATE="(desconhecido)"

if [ -f "$REPORT_DIR/metadata.txt" ]; then
  TARGET="$(grep -m1 '^target:' "$REPORT_DIR/metadata.txt" | sed 's/^target:[[:space:]]*//')"
  PROFILE="$(grep -m1 '^profile:' "$REPORT_DIR/metadata.txt" | sed 's/^profile:[[:space:]]*//')"
  REPORT_DATE="$(grep -m1 '^date:' "$REPORT_DIR/metadata.txt" | sed 's/^date:[[:space:]]*//')"
fi

FILES_FOUND=()
while IFS= read -r -d '' f; do
  FILES_FOUND+=("$(basename "$f")")
done < <(find "$REPORT_DIR" -maxdepth 1 -type f -not -name "summary.md" -not -name "sensitive-findings.txt" -print0 | sort -z)

TOOLS_DETECTED=()
[ -f "$REPORT_DIR/headers.txt" ] && TOOLS_DETECTED+=("curl (headers)") || true
[ -f "$REPORT_DIR/whatweb.txt" ] && TOOLS_DETECTED+=("whatweb") || true
[ -f "$REPORT_DIR/httpx.txt" ] && TOOLS_DETECTED+=("httpx") || true
[ -f "$REPORT_DIR/nmap.txt" ] && TOOLS_DETECTED+=("nmap") || true
[ -f "$REPORT_DIR/nmap-exposure.txt" ] && TOOLS_DETECTED+=("nmap (perfil de exposição)") || true
if [ -f "$REPORT_DIR/gobuster.txt" ] || [ -f "$REPORT_DIR/gobuster-common.txt" ]; then
  TOOLS_DETECTED+=("gobuster")
fi
if [ -f "$REPORT_DIR/ffuf.json" ] || [ -f "$REPORT_DIR/ffuf-common.json" ]; then
  TOOLS_DETECTED+=("ffuf")
fi
[ -f "$REPORT_DIR/nuclei.txt" ] && TOOLS_DETECTED+=("nuclei") || true
[ -f "$REPORT_DIR/nikto.txt" ] && TOOLS_DETECTED+=("nikto") || true
[ -f "$REPORT_DIR/testssl.txt" ] && TOOLS_DETECTED+=("testssl") || true
[ -f "$REPORT_DIR/edge-protection.txt" ] && TOOLS_DETECTED+=("heurística WAF/CDN") || true

NUCLEI_FINDINGS=""
if [ -f "$REPORT_DIR/nuclei.txt" ]; then
  NUCLEI_FINDINGS="$(cat "$REPORT_DIR/nuclei.txt")"
fi

GOBUSTER_FINDINGS=""
if [ -f "$REPORT_DIR/gobuster.txt" ]; then
  GOBUSTER_FINDINGS="$(cat "$REPORT_DIR/gobuster.txt")"
elif [ -f "$REPORT_DIR/gobuster-common.txt" ]; then
  GOBUSTER_FINDINGS="$(cat "$REPORT_DIR/gobuster-common.txt")"
fi

{
  echo "# Resumo consolidado do relatório"
  echo
  echo "- **Pasta:** $REPORT_DIR"
  echo "- **Alvo:** $TARGET"
  echo "- **Perfil:** $PROFILE"
  echo "- **Data/hora original:** $REPORT_DATE"
  echo "- **Consolidado em:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  echo "## Ferramentas com saída disponível"
  echo
  if [ "${#TOOLS_DETECTED[@]}" -eq 0 ]; then
    echo "Nenhuma saída de ferramenta reconhecida nesta pasta."
  else
    for t in "${TOOLS_DETECTED[@]}"; do
      echo "- $t"
    done
  fi
  echo
  echo "## Arquivos analisados"
  echo
  for f in "${FILES_FOUND[@]}"; do
    echo "- $f"
  done
  echo
  echo "## Achados relevantes"
  echo
  if [ -n "$NUCLEI_FINDINGS" ]; then
    echo "### Nuclei"
    echo
    echo '```'
    echo "$NUCLEI_FINDINGS"
    echo '```'
    echo
  fi
  if [ -n "$GOBUSTER_FINDINGS" ]; then
    echo "### Gobuster"
    echo
    echo '```'
    echo "$GOBUSTER_FINDINGS"
    echo '```'
    echo
  fi
  if [ -z "$NUCLEI_FINDINGS" ] && [ -z "$GOBUSTER_FINDINGS" ]; then
    echo "Nenhum achado automático relevante identificado nos arquivos padrão"
    echo "(nuclei.txt / gobuster.txt). Revise manualmente os demais arquivos."
  fi
  echo
  echo "## Possíveis falsos positivos"
  echo
  echo "Toda detecção automática (Nuclei, Nikto, gobuster/ffuf, whatweb,"
  echo "heurística de WAF/CDN) pode conter falsos positivos. Não reporte nada"
  echo "deste resumo sem reprodução/validação manual — ver \`docs/REPORTING.md\`."
  echo
  echo "## Recomendações defensivas"
  echo
  echo "- Revisar headers de segurança ausentes (ver \`headers-audit.sh\`/\`headers.txt\`)."
  echo "- Confirmar se a exposição de portas/serviços corresponde ao esperado"
  echo "  (firewall/segmentação de rede)."
  echo "- Avaliar achados do Nuclei manualmente antes de qualquer correção."
  echo "- Garantir que dados sensíveis não fiquem versionados (ver"
  echo "  \`scripts/sanitize-reports.sh\` e \`docs/OPSEC.md\`)."
  echo
  echo "## Próximos passos"
  echo
  echo "1. Validar manualmente os achados listados acima."
  echo "2. Rodar \`scripts/sanitize-reports.sh $REPORT_DIR\` antes de compartilhar."
  echo "3. Se necessário, repetir a coleta com perfil mais profundo (normal/deep)"
  echo "   nos pontos de maior interesse."
  echo "4. Registrar o achado validado e remediação sugerida no relatório final"
  echo "   para o responsável pelo ambiente."
} > "$SUMMARY_FILE"

log_ok "summary.md gerado/atualizado em: $SUMMARY_FILE"
