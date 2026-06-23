#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

read_tri() {
  local tri_file="$SCRIPT_DIR/TRI.txt"
  if [[ -f "$tri_file" ]]; then
    awk 'NF { print; exit }' "$tri_file"
  fi
}

TRI="$(read_tri)"
TRI="${TRI:-BPA}"

rsa_root="RSA_Root_CA_${TRI}"
rsa_sub="Sub_RSA_CA_1_${TRI}"
ec_root="EC_Root_CA_${TRI}"
ec_sub="Sub_EC_CA_1_${TRI}"

init_ca() {
  local ca_dir="$1"
  mkdir -p \
    "$ca_dir/certs" \
    "$ca_dir/csr" \
    "$ca_dir/db" \
    "$ca_dir/newcerts" \
    "$ca_dir/private" \
    "$ca_dir/analysis"
  chmod 700 "$ca_dir/private"
  : > "$ca_dir/db/index.txt"
  printf '1000\n' > "$ca_dir/db/serial"
  printf '1000\n' > "$ca_dir/db/crlnumber"
  printf 'unique_subject = no\n' > "$ca_dir/db/index.txt.attr"
}

make_analysis() {
  local cert="$1"
  local out="$2"
  openssl x509 -in "$cert" -text -noout > "$out"
}

init_ca "$rsa_root"
init_ca "$rsa_sub"
init_ca "$ec_root"
init_ca "$ec_sub"

if [[ ! -f "$rsa_root/private/${rsa_root}.key.pem" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$rsa_root/private/${rsa_root}.key.pem"
fi

if [[ ! -f "$rsa_sub/private/${rsa_sub}.key.pem" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$rsa_sub/private/${rsa_sub}.key.pem"
fi

if [[ ! -f "$ec_root/private/${ec_root}.key.pem" ]]; then
  openssl ecparam -name secp384r1 -genkey -noout -out "$ec_root/private/${ec_root}.key.pem"
fi

if [[ ! -f "$ec_sub/private/${ec_sub}.key.pem" ]]; then
  openssl ecparam -name secp384r1 -genkey -noout -out "$ec_sub/private/${ec_sub}.key.pem"
fi

if [[ ! -f "$rsa_root/certs/${rsa_root}.crt" ]]; then
  openssl req -new -x509 \
    -config "$rsa_root/openssl-rsa-root.cnf" \
    -extensions v3_root_ca \
    -days 5475 \
    -sha256 \
    -key "$rsa_root/private/${rsa_root}.key.pem" \
    -out "$rsa_root/certs/${rsa_root}.crt"
fi

if [[ ! -f "$ec_root/certs/${ec_root}.crt" ]]; then
  openssl req -new -x509 \
    -config "$ec_root/openssl-ec-root.cnf" \
    -extensions v3_root_ca \
    -days 5475 \
    -sha256 \
    -key "$ec_root/private/${ec_root}.key.pem" \
    -out "$ec_root/certs/${ec_root}.crt"
fi

if [[ ! -f "$rsa_sub/csr/${rsa_sub}.csr.pem" ]]; then
  openssl req -new \
    -config "$rsa_sub/openssl-rsa-sub.cnf" \
    -key "$rsa_sub/private/${rsa_sub}.key.pem" \
    -out "$rsa_sub/csr/${rsa_sub}.csr.pem"
fi

if [[ ! -f "$ec_sub/csr/${ec_sub}.csr.pem" ]]; then
  openssl req -new \
    -config "$ec_sub/openssl-ec-sub.cnf" \
    -key "$ec_sub/private/${ec_sub}.key.pem" \
    -out "$ec_sub/csr/${ec_sub}.csr.pem"
fi

if [[ ! -f "$rsa_sub/certs/${rsa_sub}.crt" ]]; then
  openssl ca -batch \
    -config "$rsa_root/openssl-rsa-root.cnf" \
    -extensions v3_sub_ca \
    -days 3650 \
    -notext \
    -in "$rsa_sub/csr/${rsa_sub}.csr.pem" \
    -out "$rsa_sub/certs/${rsa_sub}.crt"
fi

if [[ ! -f "$ec_sub/certs/${ec_sub}.crt" ]]; then
  openssl ca -batch \
    -config "$ec_root/openssl-ec-root.cnf" \
    -extensions v3_sub_ca \
    -days 3650 \
    -notext \
    -in "$ec_sub/csr/${ec_sub}.csr.pem" \
    -out "$ec_sub/certs/${ec_sub}.crt"
fi

if [[ ! -f "$rsa_sub/private/Leaf_RSA_1_${TRI}.key.pem" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$rsa_sub/private/Leaf_RSA_1_${TRI}.key.pem"
fi

if [[ ! -f "$ec_sub/private/Leaf_EC_1_${TRI}.key.pem" ]]; then
  openssl ecparam -name secp384r1 -genkey -noout -out "$ec_sub/private/Leaf_EC_1_${TRI}.key.pem"
fi

if [[ ! -f "$rsa_sub/csr/Leaf_RSA_1_${TRI}.csr.pem" ]]; then
  openssl req -new \
    -config "$rsa_sub/openssl-rsa-sub.cnf" \
    -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=Leaf_RSA_1_${TRI}" \
    -key "$rsa_sub/private/Leaf_RSA_1_${TRI}.key.pem" \
    -out "$rsa_sub/csr/Leaf_RSA_1_${TRI}.csr.pem"
fi

if [[ ! -f "$ec_sub/csr/Leaf_EC_1_${TRI}.csr.pem" ]]; then
  openssl req -new \
    -config "$ec_sub/openssl-ec-sub.cnf" \
    -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=Leaf_EC_1_${TRI}" \
    -key "$ec_sub/private/Leaf_EC_1_${TRI}.key.pem" \
    -out "$ec_sub/csr/Leaf_EC_1_${TRI}.csr.pem"
fi

if [[ ! -f "$rsa_sub/certs/Leaf_RSA_1_${TRI}.crt" ]]; then
  openssl ca -batch \
    -config "$rsa_sub/openssl-rsa-sub.cnf" \
    -extensions v3_leaf \
    -days 365 \
    -notext \
    -in "$rsa_sub/csr/Leaf_RSA_1_${TRI}.csr.pem" \
    -out "$rsa_sub/certs/Leaf_RSA_1_${TRI}.crt"
fi

if [[ ! -f "$ec_sub/certs/Leaf_EC_1_${TRI}.crt" ]]; then
  openssl ca -batch \
    -config "$ec_sub/openssl-ec-sub.cnf" \
    -extensions v3_leaf \
    -days 365 \
    -notext \
    -in "$ec_sub/csr/Leaf_EC_1_${TRI}.csr.pem" \
    -out "$ec_sub/certs/Leaf_EC_1_${TRI}.crt"
fi

make_analysis "$rsa_root/certs/${rsa_root}.crt" "$rsa_root/analysis/${rsa_root}.txt"
make_analysis "$rsa_sub/certs/${rsa_sub}.crt" "$rsa_sub/analysis/${rsa_sub}.txt"
make_analysis "$rsa_sub/certs/Leaf_RSA_1_${TRI}.crt" "$rsa_sub/analysis/Leaf_RSA_1_${TRI}.txt"
make_analysis "$ec_root/certs/${ec_root}.crt" "$ec_root/analysis/${ec_root}.txt"
make_analysis "$ec_sub/certs/${ec_sub}.crt" "$ec_sub/analysis/${ec_sub}.txt"
make_analysis "$ec_sub/certs/Leaf_EC_1_${TRI}.crt" "$ec_sub/analysis/Leaf_EC_1_${TRI}.txt"

openssl verify -CAfile "$rsa_root/certs/${rsa_root}.crt" "$rsa_root/certs/${rsa_root}.crt"
openssl verify -CAfile "$rsa_root/certs/${rsa_root}.crt" "$rsa_sub/certs/${rsa_sub}.crt"
openssl verify -CAfile "$rsa_root/certs/${rsa_root}.crt" -untrusted "$rsa_sub/certs/${rsa_sub}.crt" "$rsa_sub/certs/Leaf_RSA_1_${TRI}.crt"

openssl verify -CAfile "$ec_root/certs/${ec_root}.crt" "$ec_root/certs/${ec_root}.crt"
openssl verify -CAfile "$ec_root/certs/${ec_root}.crt" "$ec_sub/certs/${ec_sub}.crt"
openssl verify -CAfile "$ec_root/certs/${ec_root}.crt" -untrusted "$ec_sub/certs/${ec_sub}.crt" "$ec_sub/certs/Leaf_EC_1_${TRI}.crt"

printf 'Generated PKI for TRI=%s\n' "$TRI"
