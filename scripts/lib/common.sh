#!/usr/bin/env bash
# scripts/lib/common.sh
#
# Funções compartilhadas pelos scripts do appsec-toolbox.
# Este arquivo NÃO deve ser executado diretamente — apenas "source".
#
# Uso esperado em cada script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"

# Cores (desativadas automaticamente se a saída não for um terminal)
if [ -t 1 ]; then
  C_RED='\033[0;31m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[0;33m'
  C_BLUE='\033[0;34m'
  C_RESET='\033[0m'
else
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_RESET=''
fi

log_info() { printf '%b[*]%b %s\n' "$C_BLUE" "$C_RESET" "$1"; }
log_ok()   { printf '%b[+]%b %s\n' "$C_GREEN" "$C_RESET" "$1"; }
log_warn() { printf '%b[!]%b %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
log_err()  { printf '%b[x]%b %s\n' "$C_RED" "$C_RESET" "$1" >&2; }

# Garante que o alvo começa com http:// ou https://
require_http_target() {
  local target="${1:-}"
  if [[ ! "$target" =~ ^https?:// ]]; then
    log_err "Alvo inválido: '${target}'"
    log_err "O alvo deve começar com http:// ou https://"
    exit 1
  fi
}

# Garante que o alvo é HTTPS (usado por scripts que exigem TLS, ex.: tls-check.sh)
require_https_target() {
  local target="${1:-}"
  if [[ ! "$target" =~ ^https:// ]]; then
    log_err "Alvo inválido: '${target}'"
    log_err "Este script exige HTTPS, ex.: https://dominio-autorizado.com"
    exit 1
  fi
}

# Gera um nome de diretório seguro a partir do alvo (sem protocolo, sem caracteres especiais)
safe_target_name() {
  echo "${1:-}" | sed -E 's#https?://##; s#[^a-zA-Z0-9._-]#_#g; s#_+$##'
}

# Verifica se um comando existe no PATH
tool_available() {
  command -v "$1" >/dev/null 2>&1
}

# Verifica disponibilidade de uma ferramenta; emite aviso e retorna 1 se ausente,
# sem interromper o script (decisão de pular a etapa fica para quem chamou).
require_tool() {
  if ! tool_available "$1"; then
    log_warn "Ferramenta '$1' não encontrada — etapa será pulada."
    return 1
  fi
  return 0
}

# ============================================================================
# Perfis de execução: safe (padrão) | normal | deep
# ============================================================================

# Valida e normaliza o perfil informado (default: safe).
normalize_profile() {
  local p="${1:-safe}"
  case "$p" in
    safe|normal|deep) echo "$p" ;;
    *)
      log_err "Perfil inválido: '$p' (use: safe, normal ou deep)"
      exit 1
      ;;
  esac
}

# Exige confirmação explícita do operador antes de rodar em perfil deep.
# Use uma única vez por execução (no script orquestrador, não em cada sub-etapa).
confirm_deep_profile() {
  local target="${1:-}"
  cat <<EOF
================================================================
 PERFIL "deep" SELECIONADO

 Este perfil usa wordlists maiores, varredura mais ampla de
 templates/portas, e pode levar bastante tempo. Mesmo assim,
 NÃO realiza brute force de login, exploração ativa, bypass real,
 persistência ou qualquer ação destrutiva.

 Alvo: $target

 Use apenas em ambiente próprio ou com autorização explícita e
 por escrito do responsável pelo alvo.
================================================================
EOF
  read -r -p "Digite 'sim' para continuar em modo deep: " CONFIRM_DEEP
  if [ "$CONFIRM_DEEP" != "sim" ]; then
    log_warn "Operação cancelada pelo operador."
    exit 1
  fi
}

# ============================================================================
# Parsing de alvo (scheme / host / porta)
# ============================================================================

target_scheme() {
  if [[ "${1:-}" =~ ^https:// ]]; then echo "https"; else echo "http"; fi
}

target_host() {
  echo "${1:-}" | sed -E 's#https?://##; s#/.*##; s#:.*##'
}

target_port() {
  local target="${1:-}" port
  port="$(echo "$target" | sed -nE 's#https?://[^:/]+:([0-9]+).*#\1#p')"
  if [ -z "$port" ]; then
    if [[ "$target" =~ ^https:// ]]; then port="443"; else port="80"; fi
  fi
  echo "$port"
}

# ============================================================================
# Descoberta de conteúdo (gobuster + ffuf) por perfil
# Caminhos de wordlist e extensões podem ser sobrescritos via variáveis de
# ambiente (ver config/wordlists.env.example).
# ============================================================================

discovery_wordlist_for_profile() {
  case "$1" in
    safe)   echo "${WORDLIST_SAFE:-/usr/share/seclists/Discovery/Web-Content/common.txt}" ;;
    normal) echo "${WORDLIST_NORMAL:-/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-small.txt}" ;;
    deep)   echo "${WORDLIST_DEEP:-/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt}" ;;
  esac
}

# Executa gobuster + ffuf de acordo com o perfil. NÃO usa wordlist de senha e
# NÃO tenta autenticação — apenas descoberta de caminhos/arquivos comuns.
# Args: target profile out_dir
run_discovery_profile() {
  local target="$1" profile="$2" out_dir="$3"
  local wordlist threads rate maxtime step_timeout
  wordlist="$(discovery_wordlist_for_profile "$profile")"
  local ext_gobuster="${DISCOVERY_EXTENSIONS:-txt,html,conf,bak,old,json,xml}"
  local ext_ffuf=".${ext_gobuster//,/,.}"

  case "$profile" in
    safe)   threads="${GOBUSTER_THREADS_SAFE:-10}";   rate="${FFUF_RATE_SAFE:-20}";   maxtime=60;  step_timeout=90  ;;
    normal) threads="${GOBUSTER_THREADS_NORMAL:-20}"; rate="${FFUF_RATE_NORMAL:-50}"; maxtime=120; step_timeout=150 ;;
    deep)   threads="${GOBUSTER_THREADS_DEEP:-30}";   rate="${FFUF_RATE_DEEP:-80}";   maxtime=240; step_timeout=300 ;;
  esac

  if [ ! -f "$wordlist" ]; then
    log_warn "Wordlist não encontrada: $wordlist — descoberta de conteúdo pulada"
    return 1
  fi

  if require_tool gobuster; then
    log_info "Gobuster (perfil $profile, wordlist $(basename "$wordlist"))"
    if timeout -k 10s "$step_timeout" gobuster dir -u "$target" -w "$wordlist" \
        -x "$ext_gobuster" -t "$threads" --timeout 10s -q -o "$out_dir/gobuster.txt"; then
      log_ok "gobuster concluído"
    else
      log_warn "gobuster terminou com erro/timeout"
    fi
  fi

  if require_tool ffuf; then
    log_info "FFUF (perfil $profile, wordlist $(basename "$wordlist"))"
    if timeout -k 10s "$step_timeout" ffuf -u "${target%/}/FUZZ" -w "$wordlist" \
        -e "$ext_ffuf" -of json -o "$out_dir/ffuf.json" \
        -t "$threads" -rate "$rate" -timeout 10 -maxtime "$maxtime"; then
      log_ok "ffuf concluído"
    else
      log_warn "ffuf terminou com erro/timeout"
    fi
  fi
  return 0
}

# ============================================================================
# Nuclei por perfil. -ni desativa interactsh/OAST por padrão (evita
# depender de infraestrutura externa e qualquer interação "ativa" desnecessária).
# A confirmação do perfil deep é responsabilidade de quem chama esta função.
# Args: target profile out_file
# ============================================================================

run_nuclei_profile() {
  local target="$1" profile="$2" out_file="$3"
  local tags="" severity rate_limit req_timeout retries total_timeout

  case "$profile" in
    safe)
      tags="${NUCLEI_TAGS_SAFE:-exposure,misconfig}"
      severity="low,medium,high,critical"
      rate_limit="${NUCLEI_RATE_LIMIT_SAFE:-10}"; req_timeout=3; retries=0; total_timeout=60
      ;;
    normal)
      tags="${NUCLEI_TAGS_NORMAL:-exposure,misconfig,cve}"
      severity="low,medium,high,critical"
      rate_limit="${NUCLEI_RATE_LIMIT_NORMAL:-10}"; req_timeout=5; retries=0; total_timeout=180
      ;;
    deep)
      tags="${NUCLEI_TAGS_DEEP:-}"
      severity="low,medium,high,critical"
      rate_limit="${NUCLEI_RATE_LIMIT_DEEP:-5}"; req_timeout=8; retries=0; total_timeout=600
      ;;
  esac

  if ! require_tool nuclei; then
    return 1
  fi

  local nuclei_args=(-u "$target" -severity "$severity" -rate-limit "$rate_limit" \
      -timeout "$req_timeout" -retries "$retries" -ni -o "$out_file")
  if [ -n "$tags" ]; then
    nuclei_args=(-tags "$tags" "${nuclei_args[@]}")
  fi

  log_info "Nuclei (perfil $profile, timeout total ${total_timeout}s)"
  set +e
  timeout -k 15s "${total_timeout}s" nuclei "${nuclei_args[@]}"
  local exit_code=$?
  set -e

  touch "$out_file"

  if [ "$exit_code" -eq 124 ]; then
    log_warn "Nuclei: tempo limite de ${total_timeout}s atingido (resultado parcial salvo, se houver)"
  elif [ "$exit_code" -ne 0 ]; then
    log_warn "Nuclei retornou código $exit_code"
  else
    log_ok "Nuclei concluído"
  fi
  return 0
}

# ============================================================================
# Nmap por perfil. Nada destrutivo: apenas -sV (detecção de versão) e -sC
# (scripts padrão/seguros do nmap, categoria "safe" do NSE) em normal/deep.
# A confirmação do perfil deep (full port range) é responsabilidade de quem
# chama esta função.
# Args: host profile out_file
# ============================================================================

run_nmap_profile() {
  local host="$1" profile="$2" out_file="$3"
  case "$profile" in
    safe)
      timeout -k 10s 60 nmap -Pn -sV -T3 --top-ports "${NMAP_TOP_PORTS_SAFE:-100}" "$host" 2>&1 | tee "$out_file"
      ;;
    normal)
      timeout -k 15s 180 nmap -Pn -sV -sC -T3 --top-ports "${NMAP_TOP_PORTS_NORMAL:-1000}" "$host" 2>&1 | tee "$out_file"
      ;;
    deep)
      timeout -k 20s 1200 nmap -Pn -sV -sC -T4 -p- --max-retries 1 "$host" 2>&1 | tee "$out_file"
      ;;
  esac
}

# Varredura de nmap apenas na porta específica do alvo (usada pelo web-check.sh).
# Args: host port profile out_file
run_nmap_target_port() {
  local host="$1" port="$2" profile="$3" out_file="$4"
  case "$profile" in
    safe)
      timeout -k 10s 60 nmap -Pn -sV -T3 -p "$port" "$host" 2>&1 | tee "$out_file"
      ;;
    normal|deep)
      timeout -k 15s 120 nmap -Pn -sV -sC -T3 -p "$port" "$host" 2>&1 | tee "$out_file"
      ;;
  esac
}

# Banner de aviso de autorização, reutilizado pelos scripts de scan.
print_authorization_banner() {
  cat <<'EOF'
================================================================
 AVISO: use apenas em ambientes próprios ou com autorização
 explícita e por escrito do responsável pelo alvo.
 Testar sistemas de terceiros sem permissão pode ser crime.
================================================================
EOF
}

# Analisa um arquivo de headers HTTP já coletado (ex.: headers.txt) em busca de
# assinaturas conhecidas de WAF/CDN/proteção de borda. NÃO faz nenhuma
# requisição adicional nem envia payload — é puramente heurístico e passivo.
# Ausência de indício não comprova ausência de proteção.
analyze_edge_protection() {
  local headers_file="$1"
  local out_file="$2"
  local found=0

  {
    echo "# Indícios de WAF / CDN / proteção de borda"
    echo
    echo "Análise heurística baseada apenas nos headers HTTP já coletados."
    echo "Ausência de indício NÃO significa ausência de proteção — apenas que"
    echo "nenhuma assinatura conhecida foi observada nestes headers."
    echo
  } > "$out_file"

  if [ ! -f "$headers_file" ]; then
    echo "- [!] headers indisponíveis para análise." >> "$out_file"
    return 0
  fi

  local label
  local pattern
  local entries=(
    "Cloudflare|cf-ray|cf-cache-status|cloudflare"
    "Akamai|akamaighost|akamai"
    "Sucuri|x-sucuri-id|sucuri"
    "Imperva/Incapsula|incap_ses|visid_incap|x-iinfo"
    "AWS CloudFront/ELB|x-amz-cf-id|cloudfront|x-amzn-requestid|awselb"
    "Fastly|x-fastly-request-id|fastly"
    "F5 BIG-IP/ASM|bigipserver|x-waf-event"
    "Fortinet FortiWeb|fortiweb|x-fortiweb"
    "Barracuda|barra_counter_session|x-barracuda"
    "Citrix NetScaler|ns_af|citrix_ns_id|netscaler"
    "Varnish (cache, não é WAF)|x-varnish"
  )

  for entry in "${entries[@]}"; do
    label="${entry%%|*}"
    pattern="${entry#*|}"
    pattern="${pattern//|/\\|}"
    if grep -qiE "$pattern" "$headers_file" 2>/dev/null; then
      echo "- [+] Indício de '$label' encontrado nos headers." >> "$out_file"
      found=1
    fi
  done

  if [ "$found" -eq 0 ]; then
    {
      echo "- [!] Nenhuma assinatura conhecida de WAF/CDN encontrada nos headers."
      echo "      Isso NÃO confirma ausência de proteção — apenas que não há"
      echo "      indício visível nestes headers específicos."
    } >> "$out_file"
  fi

  return 0
}
