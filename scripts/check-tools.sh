#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MISSING_ESSENTIAL=()

print_status() {
  local label="$1" status="$2" extra="${3:-}"
  case "$status" in
    OK)      printf '  %-16s %bOK%b      %s\n' "$label" "$C_GREEN" "$C_RESET" "$extra" ;;
    MISSING) printf '  %-16s %bMISSING%b %s\n' "$label" "$C_RED" "$C_RESET" "$extra" ;;
    WARN)    printf '  %-16s %bWARN%b    %s\n' "$label" "$C_YELLOW" "$C_RESET" "$extra" ;;
  esac
}

check_cmd() {
  local label="$1" cmd="$2" essential="${3:-no}"
  if command -v "$cmd" >/dev/null 2>&1; then
    print_status "$label" OK
  elif [ "$essential" = "yes" ]; then
    print_status "$label" MISSING
    MISSING_ESSENTIAL+=("$label")
  else
    print_status "$label" WARN "(opcional)"
  fi
}

check_dir() {
  local label="$1" dir="$2" essential="${3:-no}"
  if [ -d "$dir" ]; then
    print_status "$label" OK
  elif [ "$essential" = "yes" ]; then
    print_status "$label" MISSING "($dir)"
    MISSING_ESSENTIAL+=("$label")
  else
    print_status "$label" WARN "($dir não encontrado)"
  fi
}

echo "===== Ferramentas essenciais ====="
check_cmd "Git"      git      yes
check_cmd "Nmap"     nmap     yes
check_cmd "WhatWeb"  whatweb  yes
check_cmd "Gobuster" gobuster yes
check_cmd "FFUF"     ffuf     yes
check_cmd "Nuclei"   nuclei   yes
check_cmd "Curl"     curl     yes
check_dir "SecLists" /usr/share/seclists yes

echo
echo "===== Ferramentas opcionais ====="
check_cmd "Docker" docker no
if command -v docker >/dev/null 2>&1 && timeout -k 3s 5 docker info >/dev/null 2>&1; then
  if timeout -k 3s 5 docker compose version >/dev/null 2>&1; then
    print_status "Docker Compose" OK
  else
    print_status "Docker Compose" WARN "(plugin não encontrado)"
  fi
else
  print_status "Docker Compose" WARN "(docker ausente ou daemon não respondeu em 5s)"
fi
check_cmd "Node"       node      no
check_cmd "NPM"        npm       no
check_cmd "NPX"        npx       no
check_cmd "Python3"    python3   no
check_cmd "Pipx"       pipx      no
check_cmd "Go"         go        no
check_cmd "Httpx"      httpx     no
check_cmd "Subfinder"  subfinder no
check_cmd "Nikto"      nikto     no
if command -v testssl >/dev/null 2>&1 || command -v testssl.sh >/dev/null 2>&1; then
  print_status "Testssl" OK
else
  print_status "Testssl" WARN "(opcional)"
fi
check_dir "Nuclei templates" "$HOME/nuclei-templates" no

echo
if [ "${#MISSING_ESSENTIAL[@]}" -eq 0 ]; then
  log_ok "Todas as ferramentas essenciais estão presentes."
  exit 0
else
  log_err "Ferramentas essenciais faltando: ${MISSING_ESSENTIAL[*]}"
  exit 1
fi
