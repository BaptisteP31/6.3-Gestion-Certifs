#!/usr/bin/env bash
set -euo pipefail

base=/home/baptiste/tp-crypto-agents
out=$base/05-cross-cert
src=$base/02-pki-openssl

mkdir -p "$out"/{certs,csr,analysis,verify,private}

# Cross-signed EC root.
openssl req -new \
  -key "$src/EC_Root_CA_BPA/private/EC_Root_CA_BPA.key.pem" \
  -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=EC_Root_CA_BPA" \
  -out "$out/csr/EC_Root_CA_BPA.cross.csr.pem"

openssl x509 -req \
  -in "$out/csr/EC_Root_CA_BPA.cross.csr.pem" \
  -CA "$src/RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt" \
  -CAkey "$src/RSA_Root_CA_BPA/private/RSA_Root_CA_BPA.key.pem" \
  -set_serial 0x1001 \
  -days 5475 \
  -sha256 \
  -extfile "$src/EC_Root_CA_BPA/openssl-ec-root.cnf" \
  -extensions v3_root_ca \
  -out "$out/certs/EC_Root_CA_BPA.cross-signed-by-RSA_Root_CA_BPA.crt"

# Fresh EC leaf issued by Sub_EC_CA_1.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out "$out/private/Leaf_EC_1_BPA.crosspath.key.pem"
openssl req -new \
  -key "$out/private/Leaf_EC_1_BPA.crosspath.key.pem" \
  -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=Leaf_EC_1_BPA" \
  -out "$out/csr/Leaf_EC_1_BPA.crosspath.csr.pem"

openssl x509 -req \
  -in "$out/csr/Leaf_EC_1_BPA.crosspath.csr.pem" \
  -CA "$src/Sub_EC_CA_1_BPA/certs/Sub_EC_CA_1_BPA.crt" \
  -CAkey "$src/Sub_EC_CA_1_BPA/private/Sub_EC_CA_1_BPA.key.pem" \
  -set_serial 0x1002 \
  -days 365 \
  -sha256 \
  -extfile "$src/Sub_EC_CA_1_BPA/openssl-ec-sub.cnf" \
  -extensions v3_leaf \
  -out "$out/certs/Leaf_EC_1_BPA.crosspath.crt"

# Text analyses.
openssl x509 -in "$out/certs/EC_Root_CA_BPA.cross-signed-by-RSA_Root_CA_BPA.crt" -noout -text > "$out/analysis/EC_Root_CA_BPA.cross-signed-by-RSA_Root_CA_BPA.txt"
openssl x509 -in "$out/certs/Leaf_EC_1_BPA.crosspath.crt" -noout -text > "$out/analysis/Leaf_EC_1_BPA.crosspath.txt"

# Untrusted bundle for the RSA-anchored path.
awk 'FNR==1 && NR!=1 {print ""} {print}' \
  "$out/certs/EC_Root_CA_BPA.cross-signed-by-RSA_Root_CA_BPA.crt" \
  "$src/Sub_EC_CA_1_BPA/certs/Sub_EC_CA_1_BPA.crt" \
  > "$out/certs/untrusted-rsa-path.pem"

# Verification outputs with the exact commands stored alongside the results.
{
  printf '%s\n' "openssl verify -show_chain -CAfile $src/EC_Root_CA_BPA/certs/EC_Root_CA_BPA.crt -untrusted $src/Sub_EC_CA_1_BPA/certs/Sub_EC_CA_1_BPA.crt $out/certs/Leaf_EC_1_BPA.crosspath.crt"
  openssl verify -show_chain \
    -CAfile "$src/EC_Root_CA_BPA/certs/EC_Root_CA_BPA.crt" \
    -untrusted "$src/Sub_EC_CA_1_BPA/certs/Sub_EC_CA_1_BPA.crt" \
    "$out/certs/Leaf_EC_1_BPA.crosspath.crt"
} > "$out/verify/verify-ec-self.txt" 2>&1

{
  printf '%s\n' "openssl verify -show_chain -CAfile $src/RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt -untrusted $out/certs/untrusted-rsa-path.pem $out/certs/Leaf_EC_1_BPA.crosspath.crt"
  openssl verify -show_chain \
    -CAfile "$src/RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt" \
    -untrusted "$out/certs/untrusted-rsa-path.pem" \
    "$out/certs/Leaf_EC_1_BPA.crosspath.crt"
} > "$out/verify/verify-rsa-cross.txt" 2>&1

