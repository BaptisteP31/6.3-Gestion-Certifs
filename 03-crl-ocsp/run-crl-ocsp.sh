#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TRI="${TRI:-BPA}"
RSA_ROOT="RSA_Root_CA_${TRI}"
RSA_SUB="Sub_RSA_CA_1_${TRI}"

ROOT_CERT="../02-pki-openssl/${RSA_ROOT}/certs/${RSA_ROOT}.crt"
SUB_CERT="../02-pki-openssl/${RSA_SUB}/certs/${RSA_SUB}.crt"
SUB_KEY="../02-pki-openssl/${RSA_SUB}/private/${RSA_SUB}.key.pem"
CONFIG="$SCRIPT_DIR/openssl-rsa-sub-ocsp.cnf"
WORK_DIR="$SCRIPT_DIR/ca-work/${RSA_SUB}"

LEAF1_KEY="$SCRIPT_DIR/${RSA_SUB}-leaf-crl.key.pem"
LEAF1_CSR="$SCRIPT_DIR/${RSA_SUB}-leaf-crl.csr.pem"
LEAF1_CERT="$SCRIPT_DIR/${RSA_SUB}-leaf-crl.crt"

LEAF2_KEY="$SCRIPT_DIR/${RSA_SUB}-leaf-ocsp.key.pem"
LEAF2_CSR="$SCRIPT_DIR/${RSA_SUB}-leaf-ocsp.csr.pem"
LEAF2_CERT="$SCRIPT_DIR/${RSA_SUB}-leaf-ocsp.crt"

mkdir -p \
  "$WORK_DIR/certs" \
  "$WORK_DIR/csr" \
  "$WORK_DIR/db" \
  "$WORK_DIR/newcerts" \
  "$WORK_DIR/private"
chmod 700 "$WORK_DIR/private"

: > "$WORK_DIR/db/index.txt"
printf '1000\n' > "$WORK_DIR/db/serial"
printf '1000\n' > "$WORK_DIR/db/crlnumber"
printf 'unique_subject = no\n' > "$WORK_DIR/db/index.txt.attr"

if [[ ! -f "$LEAF1_KEY" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$LEAF1_KEY"
fi

openssl req -new \
  -config "$CONFIG" \
  -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=${RSA_SUB}-leaf-crl" \
  -key "$LEAF1_KEY" \
  -out "$LEAF1_CSR"

openssl ca -batch \
  -config "$CONFIG" \
  -extensions v3_leaf \
  -days 365 \
  -notext \
  -in "$LEAF1_CSR" \
  -out "$LEAF1_CERT"

openssl verify \
  -CAfile "$ROOT_CERT" \
  -untrusted "$SUB_CERT" \
  "$LEAF1_CERT" > "$SCRIPT_DIR/verify-before-revoke.txt"

openssl ca -batch -config "$CONFIG" -revoke "$LEAF1_CERT" -crl_reason keyCompromise
openssl ca -config "$CONFIG" -gencrl -crldays 30 -out "$WORK_DIR/crl.pem"
openssl crl -in "$WORK_DIR/crl.pem" -text -noout > "$SCRIPT_DIR/crl-after-revoke.txt"

if [[ ! -f "$LEAF2_KEY" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$LEAF2_KEY"
fi

openssl req -new \
  -config "$CONFIG" \
  -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=${RSA_SUB}-leaf-ocsp" \
  -key "$LEAF2_KEY" \
  -out "$LEAF2_CSR"

openssl ca -batch \
  -config "$CONFIG" \
  -extensions v3_leaf_ocsp \
  -days 365 \
  -notext \
  -in "$LEAF2_CSR" \
  -out "$LEAF2_CERT"

openssl x509 -in "$LEAF2_CERT" -text -noout > "$SCRIPT_DIR/ocsp-test-cert.x509.txt"

start_responder() {
  local log_file="$1"
  openssl ocsp \
    -index "$WORK_DIR/db/index.txt" \
    -port 2560 \
    -rsigner "$SUB_CERT" \
    -rkey "$SUB_KEY" \
    -CA "$SUB_CERT" \
    -nrequest 1 \
    > "$log_file" 2>&1 &
  RESPONDER_PID=$!
  sleep 1
}

start_responder "$SCRIPT_DIR/ocsp-responder-good.log"
OCSP_PID="$RESPONDER_PID"
openssl ocsp \
  -issuer "$SUB_CERT" \
  -cert "$LEAF2_CERT" \
  -url http://127.0.0.1:2560 \
  -CAfile "$ROOT_CERT" \
  -verify_other "$SUB_CERT" \
  -resp_text \
  -text \
  -no_nonce \
  > "$SCRIPT_DIR/ocsp-good.txt" 2>&1
wait "$OCSP_PID" || true

openssl ca -batch -config "$CONFIG" -revoke "$LEAF2_CERT" -crl_reason cessationOfOperation
openssl ca -config "$CONFIG" -gencrl -crldays 30 -out "$WORK_DIR/crl-after-ocsp-revoke.pem"
openssl crl -in "$WORK_DIR/crl-after-ocsp-revoke.pem" -text -noout > "$SCRIPT_DIR/crl-after-ocsp-revoke.txt"

start_responder "$SCRIPT_DIR/ocsp-responder-revoked.log"
OCSP_PID="$RESPONDER_PID"
openssl ocsp \
  -issuer "$SUB_CERT" \
  -cert "$LEAF2_CERT" \
  -url http://127.0.0.1:2560 \
  -CAfile "$ROOT_CERT" \
  -verify_other "$SUB_CERT" \
  -resp_text \
  -text \
  -no_nonce \
  > "$SCRIPT_DIR/ocsp-revoked.txt" 2>&1
wait "$OCSP_PID" || true

printf 'CRL/OCSP exercise complete for TRI=%s\n' "$TRI"
