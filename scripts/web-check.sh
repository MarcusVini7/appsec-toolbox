#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "Uso: $0 http://127.0.0.1:8000"
  exit 1
fi

SAFE_NAME="$(echo "$TARGET" | sed -E 's#https?://##; s#[^a-zA-Z0-9._-]#_#g')"
OUT_DIR="reports/$SAFE_NAME-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUT_DIR"

echo "===================================="
echo "TARGET: $TARGET"
echo "OUTPUT: $OUT_DIR"
echo "===================================="

echo
echo "[1/6] Headers HTTP"
curl -sI --max-time 10 "$TARGET" | tee "$OUT_DIR/headers.txt" || true

echo
echo "[2/6] WhatWeb"
whatweb "$TARGET" | tee "$OUT_DIR/whatweb.txt" || true

echo
echo "[3/6] Nmap HTTP ports locais/remotos"
HOST="$(echo "$TARGET" | sed -E 's#https?://##; s#/.*##; s#:.*##')"
PORT="$(echo "$TARGET" | sed -nE 's#https?://[^:/]+:([0-9]+).*#\1#p')"

if [ -z "$PORT" ]; then
  if echo "$TARGET" | grep -q '^https://'; then
    PORT="443"
  else
    PORT="80"
  fi
fi

nmap -Pn -sV -sC -p "$PORT" "$HOST" | tee "$OUT_DIR/nmap.txt" || true

echo
echo "[4/6] Gobuster common"
gobuster dir \
  -u "$TARGET" \
  -w /usr/share/seclists/Discovery/Web-Content/common.txt \
  -t 20 \
  -o "$OUT_DIR/gobuster-common.txt" || true

echo
echo "[5/6] FFUF common"
ffuf \
  -u "$TARGET/FUZZ" \
  -w /usr/share/seclists/Discovery/Web-Content/common.txt \
  -o "$OUT_DIR/ffuf-common.json" \
  -of json || true

echo
echo "[6/6] Nuclei controlado"
nuclei \
  -u "$TARGET" \
  -severity low,medium,high,critical \
  -rate-limit 5 \
  -o "$OUT_DIR/nuclei.txt" || true

echo
echo "Finalizado."
echo "Relatórios em: $OUT_DIR"
