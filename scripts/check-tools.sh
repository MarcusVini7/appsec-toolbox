#!/usr/bin/env bash

echo "===== DEV ====="
git --version
gh --version | head -n 1
node -v
npm -v
pnpm -v
python3 --version
pipx --version
go version

echo
echo "===== DOCKER ====="
docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}' 2>/dev/null || echo "Docker sem permissão ou daemon parado"
docker compose version 2>/dev/null || true

echo
echo "===== SECURITY ====="
nmap --version | head -n 1
whatweb --version
gobuster version
ffuf -V
httpx -version
subfinder -version
nuclei -version
nikto -Version | head -n 8
timeout 10 testssl --help | head -n 1 || echo "testssl não respondeu no timeout"

echo
echo "===== WORDLISTS ====="
test -d /usr/share/seclists && echo "SecLists OK" || echo "SecLists ausente"
test -d ~/nuclei-templates && echo "Nuclei templates OK" || echo "Nuclei templates ausente"
