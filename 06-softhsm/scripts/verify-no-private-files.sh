#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=/home/baptiste/tp-crypto-agents/06-softhsm

if find "$ROOT_DIR" -type f \( -name '*.key' -o -name '*.pem' \) -print -quit | grep -q .; then
  find "$ROOT_DIR" -type f \( -name '*.key' -o -name '*.pem' \) -print
  exit 1
fi

echo "No private key file (.key or private .pem) found outside SoftHSM2."
