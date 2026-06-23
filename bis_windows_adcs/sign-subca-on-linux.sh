#!/usr/bin/env bash
set -Eeuo pipefail

# TP Cryptographie - Signature de la CSR ADCS cote Linux
# Ce script ne manipule pas et n'affiche jamais de cle privee.

WORKDIR="./windows-adcs"
CSR_PATH="$WORKDIR/from-windows/sub-adcs-ca.req"
OUTPUT_CERT="$WORKDIR/to-windows/sub-adcs-ca-signed.crt"
ROOT_CA_CERT="../06-softhsm/certs/root-ca.crt"
ROOT_CA_CONFIG="../06-softhsm/openssl-root-ca.cnf"
ROOT_CA_NAME="HSM_Root_CA_BPA"
DAYS=1825

LOGDIR="$WORKDIR/logs"
EXTFILE="$WORKDIR/subca-extensions.cnf"
LOGFILE="$LOGDIR/sign-subca-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$WORKDIR/from-windows" "$WORKDIR/to-windows" "$LOGDIR"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) $*" | tee -a "$LOGFILE"; }
fatal() { log "ERREUR: $*"; exit 1; }
run() {
  log "Commande: $*"
  "$@" 2>&1 | tee -a "$LOGFILE"
}

log "Signature CSR sous-CA ADCS"
log "CSR attendue: $CSR_PATH"
log "Certificat produit: $OUTPUT_CERT"

[[ -f "$CSR_PATH" ]] || fatal "CSR absente. Copiez C:\\TP-Crypto-ADCS\\output\\sub-adcs-ca.req vers $CSR_PATH"
[[ -f "$ROOT_CA_CERT" ]] || fatal "Certificat racine introuvable: $ROOT_CA_CERT. Adaptez ROOT_CA_CERT dans le script."
[[ -f "$ROOT_CA_CONFIG" ]] || fatal "Configuration OpenSSL racine introuvable: $ROOT_CA_CONFIG. Adaptez ROOT_CA_CONFIG dans le script."
command -v openssl >/dev/null 2>&1 || fatal "openssl introuvable. Installez openssl."

cat > "$EXTFILE" <<'EOCNF'
[ v3_subca_adcs ]
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOCNF

log "Verification syntaxique de la CSR."
run openssl req -in "$CSR_PATH" -noout -subject -verify

log "Signature avec openssl ca."
log "Si votre racine utilise SoftHSM2/PKCS#11, verifiez que ROOT_CA_CONFIG charge bien le provider/engine PKCS#11."
log "Exemples de points a adapter: OPENSSL_CONF, module pkcs11, PIN via variable d'environnement, section ROOT_CA_NAME=$ROOT_CA_NAME."

# La commande ci-dessous suppose que le fichier de configuration de la racine
# contient la section d'AC nommee dans ROOT_CA_NAME et sait acceder a la cle
# privee via SoftHSM2 / PKCS#11. Aucune cle privee n'est affichee ici.
run openssl ca \
  -config "$ROOT_CA_CONFIG" \
  -name "$ROOT_CA_NAME" \
  -extensions v3_subca_adcs \
  -extfile "$EXTFILE" \
  -days "$DAYS" \
  -md sha256 \
  -notext \
  -batch \
  -in "$CSR_PATH" \
  -out "$OUTPUT_CERT"

[[ -f "$OUTPUT_CERT" ]] || fatal "Le certificat signe n'a pas ete cree."

log "Affichage du certificat signe."
run openssl x509 -in "$OUTPUT_CERT" -noout -subject -issuer -dates -serial
run openssl x509 -in "$OUTPUT_CERT" -noout -text

log "OK. Copiez vers Windows:"
log "  $OUTPUT_CERT -> C:\\TP-Crypto-ADCS\\input\\sub-adcs-ca-signed.crt"
log "  $ROOT_CA_CERT -> C:\\TP-Crypto-ADCS\\input\\root-ca.crt"
