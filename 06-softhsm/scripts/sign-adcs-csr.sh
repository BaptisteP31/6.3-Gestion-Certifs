#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <csr.pem|csr.der> <output.crt>" >&2
  exit 1
fi

ROOT_DIR=/home/baptiste/tp-crypto-agents/06-softhsm
CSR_IN=$1
OUT_CRT=$2

export SOFTHSM2_CONF="$ROOT_DIR/softhsm2.conf"
export OPENSSL_MODULES=/usr/lib/ossl-modules
export PKCS11_MODULE_PATH=/usr/lib/softhsm/libsofthsm2.so
export CA_DIR="$ROOT_DIR/state"
export CA_CERT="$ROOT_DIR/state/certs/HSM_Root_CA_TRI.crt"
export NEWCERTS_DIR="$ROOT_DIR/state/newcerts"
export CA_INDEX="$ROOT_DIR/state/index.txt"
export CA_SERIAL="$ROOT_DIR/state/serial"
export CA_CRLNUMBER="$ROOT_DIR/state/crlnumber"
export TOKEN_LABEL=TP_SOFTHSM_TRI
export KEY_LABEL=HSM_Root_CA_TRI
export USER_PIN=12345678

case "$CSR_IN" in
  *.der|*.cer|*.req)
    TMP_CSR=$(mktemp /tmp/adcs-csr.XXXXXX.pem)
    trap 'rm -f "$TMP_CSR"' EXIT
    openssl req -inform DER -in "$CSR_IN" -out "$TMP_CSR"
    CSR_IN="$TMP_CSR"
    ;;
esac

mkdir -p "$(dirname "$OUT_CRT")"

openssl ca \
  -provider default \
  -provider pkcs11prov \
  -config "$ROOT_DIR/openssl-hsm-root.cnf" \
  -extensions v3_subca \
  -in "$CSR_IN" \
  -out "$OUT_CRT" \
  -batch
