#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=/home/baptiste/tp-crypto-agents/06-softhsm
STATE_DIR="$ROOT_DIR/state"
TOKEN_DIR="$STATE_DIR/tokens"
CERT_DIR="$STATE_DIR/certs"
CRL_DIR="$STATE_DIR/crl"
NEWCERTS_DIR="$STATE_DIR/newcerts"
TOKEN_LABEL=TP_SOFTHSM_TRI
KEY_LABEL=HSM_Root_CA_TRI
USER_PIN=12345678
SO_PIN=87654321
MODULE=/usr/lib/softhsm/libsofthsm2.so

export SOFTHSM2_CONF="$ROOT_DIR/softhsm2.conf"
export OPENSSL_MODULES=/usr/lib/ossl-modules
export PKCS11_MODULE_PATH="$MODULE"
export CA_DIR="$STATE_DIR"
export CA_CERT="$CERT_DIR/HSM_Root_CA_TRI.crt"
export NEWCERTS_DIR="$NEWCERTS_DIR"
export CA_INDEX="$STATE_DIR/index.txt"
export CA_SERIAL="$STATE_DIR/serial"
export CA_CRLNUMBER="$STATE_DIR/crlnumber"
export TOKEN_LABEL
export KEY_LABEL
export USER_PIN

mkdir -p "$TOKEN_DIR" "$CERT_DIR" "$CRL_DIR" "$NEWCERTS_DIR"
: > "$STATE_DIR/index.txt"
printf '%s\n' 01 > "$STATE_DIR/serial"
printf '%s\n' 1000 > "$STATE_DIR/crlnumber"

if ! softhsm2-util --show-slots | grep -q "Label:            $TOKEN_LABEL"; then
  softhsm2-util --init-token --free --label "$TOKEN_LABEL" --so-pin "$SO_PIN" --pin "$USER_PIN"
fi

if ! pkcs11-tool --module "$MODULE" --login --pin "$USER_PIN" -O | grep -q "label:      $KEY_LABEL"; then
  pkcs11-tool \
    --module "$MODULE" \
    --login \
    --pin "$USER_PIN" \
    --keypairgen \
    --key-type rsa:4096 \
    --id 01 \
    --label "$KEY_LABEL" \
    --usage-sign \
    --usage-decrypt
fi

pkcs11-tool --module "$MODULE" --login --pin "$USER_PIN" -O | sed -n "/Private Key Object; RSA  4096 bits/,+14p"

ROOT_KEY_URI="pkcs11:token=$TOKEN_LABEL;object=$KEY_LABEL;type=private;id=%01;pin-value=$USER_PIN"

openssl req \
  -provider default \
  -provider pkcs11prov \
  -new -x509 \
  -sha256 \
  -days 3650 \
  -key "$ROOT_KEY_URI" \
  -subj "/C=FR/O=TP Crypto/OU=06-softhsm/CN=HSM_Root_CA_TRI" \
  -out "$CERT_DIR/HSM_Root_CA_TRI.crt" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash" \
  -addext "authorityKeyIdentifier=keyid:always"

openssl ca \
  -provider default \
  -provider pkcs11prov \
  -config "$ROOT_DIR/openssl-hsm-root.cnf" \
  -gencrl \
  -out "$CRL_DIR/HSM_Root_CA_TRI.crl"

openssl x509 -in "$CERT_DIR/HSM_Root_CA_TRI.crt" -noout -subject -issuer -dates
openssl crl -in "$CRL_DIR/HSM_Root_CA_TRI.crl" -noout -issuer -lastupdate -nextupdate

echo "Root CA ready:"
echo "  cert: $CERT_DIR/HSM_Root_CA_TRI.crt"
echo "  crl : $CRL_DIR/HSM_Root_CA_TRI.crl"
