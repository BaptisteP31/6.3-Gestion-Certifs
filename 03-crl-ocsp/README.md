# CRL et OCSP

Travail réalisé avec la chaîne RSA du TP, en réutilisant les artefacts de `02-pki-openssl` :

- CA racine : `RSA_Root_CA_BPA`
- CA subordonnée : `Sub_RSA_CA_1_BPA`

Les fichiers bruts produits pendant l'exercice sont conservés dans ce dossier :

- [verify-before-revoke.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/verify-before-revoke.txt)
- [crl-after-revoke.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/crl-after-revoke.txt)
- [crl-after-ocsp-revoke.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/crl-after-ocsp-revoke.txt)
- [ocsp-test-cert.x509.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-test-cert.x509.txt)
- [ocsp-good.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-good.txt)
- [ocsp-revoked.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-revoked.txt)
- [ocsp-responder-good.log](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-responder-good.log)
- [ocsp-responder-revoked.log](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-responder-revoked.log)

## Commandes

Les commandes sont regroupées dans [run-crl-ocsp.sh](/home/baptiste/tp-crypto-agents/03-crl-ocsp/run-crl-ocsp.sh).

### 1. Certificat final pour la partie CRL

Émission d'un certificat final par `Sub_RSA_CA_1_BPA` :

```bash
openssl req -new \
  -config openssl-rsa-sub-ocsp.cnf \
  -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=Sub_RSA_CA_1_BPA-leaf-crl" \
  -key Sub_RSA_CA_1_BPA-leaf-crl.key.pem \
  -out Sub_RSA_CA_1_BPA-leaf-crl.csr.pem

openssl ca -batch \
  -config openssl-rsa-sub-ocsp.cnf \
  -extensions v3_leaf \
  -days 365 \
  -notext \
  -in Sub_RSA_CA_1_BPA-leaf-crl.csr.pem \
  -out Sub_RSA_CA_1_BPA-leaf-crl.crt

openssl verify \
  -CAfile ../02-pki-openssl/RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt \
  -untrusted ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  Sub_RSA_CA_1_BPA-leaf-crl.crt
```

Sortie attendue :

```text
/home/baptiste/tp-crypto-agents/03-crl-ocsp/Sub_RSA_CA_1_BPA-leaf-crl.crt: OK
```

Révocation puis génération de la CRL :

```bash
openssl ca -batch -config openssl-rsa-sub-ocsp.cnf -revoke Sub_RSA_CA_1_BPA-leaf-crl.crt -crl_reason keyCompromise
openssl ca -config openssl-rsa-sub-ocsp.cnf -gencrl -crldays 30 -out ca-work/Sub_RSA_CA_1_BPA/crl.pem
openssl crl -in ca-work/Sub_RSA_CA_1_BPA/crl.pem -text -noout > crl-after-revoke.txt
```

### 2. Certificat final pour la partie OCSP

Le deuxième certificat contient :

- une URI de CRL Distribution Point fictive ;
- une URI OCSP fictive au format attendu.

```bash
openssl req -new \
  -config openssl-rsa-sub-ocsp.cnf \
  -subj "/C=FR/O=TP Crypto Agents/OU=PKI OpenSSL/CN=Sub_RSA_CA_1_BPA-leaf-ocsp" \
  -key Sub_RSA_CA_1_BPA-leaf-ocsp.key.pem \
  -out Sub_RSA_CA_1_BPA-leaf-ocsp.csr.pem

openssl ca -batch \
  -config openssl-rsa-sub-ocsp.cnf \
  -extensions v3_leaf_ocsp \
  -days 365 \
  -notext \
  -in Sub_RSA_CA_1_BPA-leaf-ocsp.csr.pem \
  -out Sub_RSA_CA_1_BPA-leaf-ocsp.crt

openssl x509 -in Sub_RSA_CA_1_BPA-leaf-ocsp.crt -text -noout > ocsp-test-cert.x509.txt
```

### 3. Répondeur OCSP local

Le répondeur OCSP est lancé localement sur `127.0.0.1:2560` :

```bash
openssl ocsp \
  -index ca-work/Sub_RSA_CA_1_BPA/db/index.txt \
  -port 2560 \
  -rsigner ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  -rkey ../02-pki-openssl/Sub_RSA_CA_1_BPA/private/Sub_RSA_CA_1_BPA.key.pem \
  -CA ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  -nrequest 1
```

### 4. Vérification OCSP avant révocation

```bash
openssl ocsp \
  -issuer ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  -cert Sub_RSA_CA_1_BPA-leaf-ocsp.crt \
  -url http://127.0.0.1:2560 \
  -CAfile ../02-pki-openssl/RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt \
  -verify_other ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  -resp_text -text -no_nonce > ocsp-good.txt 2>&1
```

Extrait utile :

```text
/home/baptiste/tp-crypto-agents/03-crl-ocsp/Sub_RSA_CA_1_BPA-leaf-ocsp.crt: good
```

### 5. Révocation et vérification OCSP après mise à jour

```bash
openssl ca -batch -config openssl-rsa-sub-ocsp.cnf -revoke Sub_RSA_CA_1_BPA-leaf-ocsp.crt -crl_reason cessationOfOperation
openssl ca -config openssl-rsa-sub-ocsp.cnf -gencrl -crldays 30 -out ca-work/Sub_RSA_CA_1_BPA/crl-after-ocsp-revoke.pem
```

Le répondeur OCSP est relancé après mise à jour du statut, puis on refait la requête :

```bash
openssl ocsp \
  -issuer ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  -cert Sub_RSA_CA_1_BPA-leaf-ocsp.crt \
  -url http://127.0.0.1:2560 \
  -CAfile ../02-pki-openssl/RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt \
  -verify_other ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  -resp_text -text -no_nonce > ocsp-revoked.txt 2>&1
```

Extrait utile :

```text
/home/baptiste/tp-crypto-agents/03-crl-ocsp/Sub_RSA_CA_1_BPA-leaf-ocsp.crt: revoked
```

## CRL vs OCSP

### CRL

- La CRL est une liste publiée périodiquement par l'AC.
- Un client télécharge la liste et vérifie localement si le certificat y figure.
- Avantages : simple, peu de dépendance temps réel.
- Inconvénients : liste potentiellement volumineuse, information moins fraîche entre deux publications.

### OCSP

- OCSP interroge un répondeur en temps réel pour un certificat donné.
- Le client obtient un statut ciblé : `good`, `revoked` ou `unknown`.
- Avantages : réponse précise et plus à jour.
- Inconvénients : dépend d'un service en ligne et pose des questions de disponibilité/confidentialité.

## Sorties à insérer dans le compte rendu

- [verify-before-revoke.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/verify-before-revoke.txt)
- [crl-after-revoke.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/crl-after-revoke.txt)
- [crl-after-ocsp-revoke.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/crl-after-ocsp-revoke.txt)
- [ocsp-test-cert.x509.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-test-cert.x509.txt)
- [ocsp-good.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-good.txt)
- [ocsp-revoked.txt](/home/baptiste/tp-crypto-agents/03-crl-ocsp/ocsp-revoked.txt)

## Remarque

Les fichiers `ocsp-responder-*.log` sont conservés pour tracer le démarrage et les requêtes du répondeur local. Ils ne sont pas nécessaires au rendu final, mais ils documentent l'exécution du TP.
