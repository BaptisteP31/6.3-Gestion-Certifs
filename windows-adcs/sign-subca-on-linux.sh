#!/usr/bin/env bash
set -euo pipefail

WORKDIR="./windows-adcs"
CSR_PATH="$WORKDIR/from-windows/sub-adcs-ca.req"
OUTPUT_CERT="$WORKDIR/to-windows/sub-adcs-ca-signed.crt"
ROOT_CA_CERT="../06-softhsm/certs/root-ca.crt"
ROOT_CA_CONFIG="../06-softhsm/openssl-root-ca.cnf"
ROOT_CA_NAME="HSM_Root_CA_BPA"
DAYS=1825
LOGDIR="$WORKDIR/logs"
LOGFILE="$LOGDIR/sign-subca-on-linux.log"

mkdir -p "$WORKDIR/from-windows" "$WORKDIR/to-windows" "$WORKDIR/logs"
: > "$LOGFILE"

log() {
  printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOGFILE"
}

fail() {
  log "ERREUR: $*"
  exit 1
}

log "Debut de la signature de la CSR Windows du sous-CA."
log "CSR attendue: $CSR_PATH"
log "Certificat de sortie: $OUTPUT_CERT"

[[ -f "$CSR_PATH" ]] || fail "CSR absente. Copiez d'abord la requete Windows vers $CSR_PATH"
[[ -f "$ROOT_CA_CERT" ]] || log "Avertissement: le certificat racine indique n'existe pas a cet emplacement: $ROOT_CA_CERT"
[[ -f "$ROOT_CA_CONFIG" ]] || fail "Fichier de configuration OpenSSL racine introuvable: $ROOT_CA_CONFIG"

if [[ ! -f "$ROOT_CA_CERT" ]]; then
  cat <<MSG
Chemins a adapter avant execution:
- ROOT_CA_CERT=$ROOT_CA_CERT
- ROOT_CA_CONFIG=$ROOT_CA_CONFIG
- Si votre AC racine utilise PKCS#11/SoftHSM2, adaptez la section [ ca ] et la section du moteur/provider dans $ROOT_CA_CONFIG.
MSG
fi

if grep -qi 'pkcs11\|softhsm\|engine' "$ROOT_CA_CONFIG"; then
  log "Configuration racine PKCS#11/SoftHSM2 detectee. Utilisation du profil existant."
else
  log "La configuration ne mentionne pas explicitement PKCS#11/SoftHSM2. Verifiez qu'elle correspond bien a votre AC racine."
fi

TMP_EXTFILE="$WORKDIR/logs/subca-ext.cnf"
cat > "$TMP_EXTFILE" <<'EXT'
[v3_subca]
basicConstraints = critical,CA:true,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EXT

log "Signature de la CSR avec OpenSSL."
log "Commande attendue: openssl x509 -req -in <CSR> -CA <CA> -CAkey <KEY> -out <OUT> -days $DAYS -sha256 -extfile $TMP_EXTFILE -extensions v3_subca"

if [[ -n "${OPENSSL_ROOT_CA_KEY:-}" ]]; then
  log "Utilisation de OPENSSL_ROOT_CA_KEY depuis l'environnement."
  openssl x509 -req \
    -in "$CSR_PATH" \
    -CA "$ROOT_CA_CERT" \
    -CAkey "$OPENSSL_ROOT_CA_KEY" \
    -CAcreateserial \
    -out "$OUTPUT_CERT" \
    -days "$DAYS" \
    -sha256 \
    -extfile "$TMP_EXTFILE" \
    -extensions v3_subca 2>&1 | tee -a "$LOGFILE"
else
  cat <<MSG
A faire manuellement si votre cle racine est dans SoftHSM2 / PKCS#11:
- Exporter ou cibler le bon provider OpenSSL pour signer.
- Adapter la commande au format de votre environnement.
- Ne pas afficher ni copier la cle privee.
- Exemple general a adapter: openssl ca -config "$ROOT_CA_CONFIG" -extensions v3_subca -in "$CSR_PATH" -out "$OUTPUT_CERT" -days "$DAYS" -batch -notext -md sha256
MSG
  fail "Aucune cle racine exploitable n'a ete fournie. Definissez OPENSSL_ROOT_CA_KEY ou adaptez la commande a votre environnement PKCS#11."
fi

[[ -f "$OUTPUT_CERT" ]] || fail "Le certificat signe n'a pas ete produit: $OUTPUT_CERT"
log "Signature terminee: $OUTPUT_CERT"
log "Verification du certificat signe."
openssl x509 -in "$OUTPUT_CERT" -noout -text 2>&1 | tee -a "$LOGFILE"
log "Termine. Copiez $OUTPUT_CERT vers la VM Windows dans C:\\TP-Crypto-ADCS\\input\\sub-adcs-ca-signed.crt"
