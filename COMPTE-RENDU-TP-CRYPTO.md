# Compte rendu — TP Application de la cryptographie

## Introduction

OpenSSL est une boîte à outils permettant de manipuler TLS, X.509, les clés, les CSR, les CRL, OCSP et S/MIME. Les certificats X.509 lient une identité à une clé publique et sont validés au moyen d’une chaîne de certification. Une chaîne aboutit normalement à une autorité racine de confiance, éventuellement via une ou plusieurs autorités subordonnées. La révocation peut être publiée sous forme de CRL, liste signée de certificats révoqués, ou vérifiée en ligne avec OCSP. S/MIME applique ces mécanismes aux courriers électroniques signés et chiffrés. Le TP a aussi construit une PKI locale OpenSSL et une racine protégée par SoftHSM2 via PKCS#11.

---

# Partie 1 — Étude de certificats publics

## 1. Récupération et analyse du certificat `cyber.gouv.fr`

Sources principales : `01-public-certs/README.md`, `01-public-certs/cyber.gouv.fr.chain.txt`, `01-public-certs/cyber.gouv.fr.x509.txt`, `01-public-certs/crl.txt`.

### 1. Protocole sécurisant la connexion

Le protocole observé pour HTTPS est TLS. La connexion OpenSSL a utilisé `TLSv1.3`. SSL est l’ancien nom historique, aujourd’hui remplacé par TLS.

### 2. Longueur de la chaîne de certification

La chaîne fournie par `openssl s_client` contient 2 certificats : le certificat serveur `cyber.gouv.fr` et le certificat subordonné `GandiCert`.

Commande de comptage :

```bash
awk '/BEGIN CERTIFICATE/{c++} END{print c}' cyber.gouv.fr.chain.txt
```

Résultat : `2`.

### 3. Autorité de certification racine

L’autorité racine identifiée est `DigiCert Global Root G2`. Elle n’est pas fournie dans la chaîne TLS récupérée, mais elle est l’ancre de confiance de la chaîne `GandiCert`.

### 4. Autorité de certification subordonnée

Le certificat serveur est émis par :

```text
C=FR, O=Gandi SAS, CN=GandiCert
```

### 5. Taille de la clé publique du site

Le certificat `cyber.gouv.fr` contient une clé publique RSA de 4096 bits.

Source : `01-public-certs/cyber.gouv.fr.x509.txt`.

### 6. Type de certificat

Il s’agit d’un certificat X.509 v3 d’entité finale pour serveur TLS :

- sujet : `CN=cyber.gouv.fr` ;
- SAN : `DNS:cyber.gouv.fr`, `DNS:ssi.gouv.fr`, `DNS:www.ssi.gouv.fr`, `DNS:www.cyber.gouv.fr` ;
- Extended Key Usage : `TLS Web Server Authentication` ;
- Basic Constraints : `CA:FALSE`.

### 7. Peut-il signer d’autres certificats ?

Non. Le certificat contient `Basic Constraints: CA:FALSE`. Son Key Usage est `Digital Signature, Key Encipherment`, sans `keyCertSign`.

### 8. Peut-il signer du courrier électronique ?

Non pour l’usage S/MIME. L’Extended Key Usage contient seulement `TLS Web Server Authentication` et ne contient pas `emailProtection`.

### 9. Où trouve-t-on la CRL ?

Les CRL Distribution Points réellement présents sont :

```text
http://crl3.digicert.com/GandiCert.crl
http://crl4.digicert.com/GandiCert.crl
```

### 10. Numéro de série

Numéro de série hexadécimal :

```text
05:7e:1f:dd:c4:8e:7a:07:80:64:3a:be:eb:cc:52:a5
```

Format sans séparateurs :

```text
057E1FDDC48E7A0780643ABEEBCC52A5
```

Conversion décimale disponible :

```text
7301015708052902158374241928634716837
```

Observation : le numéro est stocké sous forme d’entier ASN.1, affiché en hexadécimal par OpenSSL.

### 11. Clé publique

La clé publique complète est longue et se trouve dans `01-public-certs/cyber.gouv.fr.x509.txt`. Extrait utile :

```text
Public Key Algorithm: rsaEncryption
Public-Key: (4096 bit)
Exponent: 65537 (0x10001)
```

Commande d’extraction :

```bash
openssl x509 -in cyber.gouv.fr.pem -pubkey -noout
```

### 12. Clé privée

La clé privée ne peut pas être récupérée depuis le certificat public du site. Un certificat X.509 contient la clé publique, l’identité, les extensions et la signature de l’autorité, mais jamais la clé privée. Il est donc impossible de reconstruire ou d’obtenir la clé privée de `cyber.gouv.fr` à partir des fichiers publics collectés.

### 13. Durée de validité de la CRL

CRL consultée : `01-public-certs/GandiCert.crl`, affichée dans `01-public-certs/crl.txt`.

```text
Last Update: Jun 22 12:45:56 2026 GMT
Next Update: Jun 29 12:45:56 2026 GMT
```

Durée : 7 jours.

### 14. Raisons de révocation

Les premières entrées affichées dans `crl.txt` ne montrent que le numéro de série et la date de révocation. Des champs `X509v3 CRL Reason Code` apparaissent plus loin dans la CRL, mais pas systématiquement pour les premières entrées.

### 15. Comment être sûr que la CRL est la bonne ?

La CRL est cohérente si :

- son `Issuer` correspond à l’AC émettrice du certificat, ici `C=FR, O=Gandi SAS, CN=GandiCert` ;
- sa signature est vérifiable avec le certificat de cette AC ;
- son URL provient bien de l’extension `CRL Distribution Points` du certificat serveur.

### 16. Vérification manuelle du serial dans la CRL

Méthode utilisée :

```bash
openssl x509 -in cyber.gouv.fr.pem -noout -serial
openssl crl -inform DER -in GandiCert.crl -text -noout > crl.txt
rg "057E1FDDC48E7A0780643ABEEBCC52A5|05:7E:1F:DD:C4:8E:7A:07:80:64:3A:BE:EB:CC:52:A5" crl.txt
```

Résultat observé : aucun match. Le certificat `cyber.gouv.fr` n’apparaît pas comme révoqué dans la CRL consultée.

## 2. Révocation, OCSP et navigateurs

Sources principales : `01-public-certs/README-revocation.md`, `revoked-rsa-dv.ssl.com.*`, `google.com.*`, `youtube.com.*`, `wrong.host.badssl.com.openssl.txt`.

### Test avec `revoked-rsa-dv.ssl.com`

Les captures navigateur n’ont pas été réalisées.

[CAPTURE À INSÉRER — Firefox]

[CAPTURE À INSÉRER — Chromium]

[CAPTURE À INSÉRER — troisième navigateur]

### 17. Recherche du serial dans la CRL

Certificat testé : `01-public-certs/revoked-rsa-dv.ssl.com.pem`.

Serial :

```text
1811B09C4BB9E179133BB9D9A9B140C5
```

CRL utilisée :

```text
http://crls.ssl.com/SSL.com-TLS-I-RSA-R1.crl
```

Résultat dans `01-public-certs/revoked-rsa-dv.ssl.com.crl.txt` :

```text
Serial Number: 1811B09C4BB9E179133BB9D9A9B140C5
Revocation Date: Jun  9 14:37:38 2026 GMT
```

Le certificat est donc présent dans la CRL.

### 18. Vérification OCSP

URL OCSP :

```text
http://ocsps.ssl.com
```

Certificat du site : `revoked-rsa-dv.ssl.com.pem`.

Certificat de l’autorité : `ssl.com-tls-i-rsa-r1.pem`.

Commande utilisée :

```bash
openssl ocsp \
  -issuer ssl.com-tls-i-rsa-r1.pem \
  -cert revoked-rsa-dv.ssl.com.pem \
  -url http://ocsps.ssl.com \
  -no_nonce \
  -resp_text -text
```

Résultat observé dans `revoked-rsa-dv.ssl.com.ocsp.txt` :

```text
OCSP Response Status: successful (0x0)
Cert Status: revoked
Revocation Time: Jun  9 14:37:38 2026 GMT
revoked-rsa-dv.ssl.com.pem: revoked
```

CRL et OCSP concordent : le certificat est révoqué.

### 19. Certificats `google.com` et `youtube.com`

Serial `google.com` :

```text
139CDF29A8B5BC5212413EEEAFD18CBE
```

Serial `youtube.com` :

```text
139CDF29A8B5BC5212413EEEAFD18CBE
```

Les deux hôtes ont présenté le même certificat feuille, émis par `C=US, O=Google Trust Services, CN=WR2`, avec `CN=*.google.com`. Les SAN contiennent à la fois `DNS:google.com` et `DNS:youtube.com`. L’interprétation cohérente est l’utilisation d’un certificat multi-SAN partagé par l’infrastructure Google.

### 20. `wrong.host.badssl.com`

Observation navigateur : à compléter.

Observation OpenSSL dans `wrong.host.badssl.com.openssl.txt` :

```text
verify error:num=62:hostname mismatch
Verification error: hostname mismatch
```

L’alerte est cohérente : le nom demandé `wrong.host.badssl.com` ne correspond pas au certificat présenté. La validation du nom d’hôte repose sur les SAN, ou à défaut le CN, selon la logique de la RFC 6125.

### 21. `isrg-1.crt` et `isrg-2.crt`

Non réalisé : aucun fichier `isrg-1.crt` ou `isrg-2.crt` n’a été trouvé dans l’arborescence de travail.

---

# Partie 2 — Création et exploitation d’une PKI OpenSSL

## 1. Mise en place des autorités

Sources principales : `02-pki-openssl/README.md`, `02-pki-openssl/generate-pki.sh`, configurations `openssl-*.cnf`, certificats et fichiers `analysis/*.txt`.

Méthode observée :

- arborescence dédiée par AC : `private/`, `certs/`, `csr/`, `db/`, `newcerts/` ;
- fichiers de configuration OpenSSL séparés par AC ;
- bases `openssl ca` : `index.txt`, `serial`, `crlnumber` ;
- racines autosignées avec `openssl req -x509` ;
- subordonnées signées par leur racine avec `openssl ca` ;
- certificats finaux signés par les AC subordonnées ;
- extensions explicites : `CA:TRUE` pour les AC, `CA:FALSE` pour les entités finales, `pathlen:0` pour les subordonnées.

Commande de génération :

```bash
./generate-pki.sh
```

### Autorités créées

| Autorité | Algorithme | Taille/courbe | Validité | Extensions importantes | Fichier associé | Vérification |
|---|---:|---:|---|---|---|---|
| `RSA_Root_CA_APV` | RSA / SHA-256 | 4096 bits | 2026-06-23 à 2041-06-19 | `CA:TRUE`, `Certificate Sign`, `CRL Sign` | `RSA_Root_CA_APV/openssl-rsa-root.cnf` | `OK` |
| `Sub_RSA_CA_1_APV` | RSA / SHA-256 | 3072 bits | 2026-06-23 à 2036-06-20 | `CA:TRUE, pathlen:0`, `Certificate Sign`, `CRL Sign` | `Sub_RSA_CA_1_APV/openssl-rsa-sub.cnf` | `OK` |
| `EC_Root_CA_APV` | ECDSA / SHA-256 | P-384 | 2026-06-23 à 2041-06-19 | `CA:TRUE`, `Certificate Sign`, `CRL Sign` | `EC_Root_CA_APV/openssl-ec-root.cnf` | `OK` |
| `Sub_EC_CA_1_APV` | ECDSA / SHA-256 | P-384 | 2026-06-23 à 2036-06-20 | `CA:TRUE, pathlen:0`, `Certificate Sign`, `CRL Sign` | `Sub_EC_CA_1_APV/openssl-ec-sub.cnf` | `OK` |

Commandes de vérification représentatives :

```bash
openssl verify -CAfile RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt
openssl verify -CAfile RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt
openssl verify -CAfile RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt -untrusted Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt Sub_RSA_CA_1_APV/certs/Leaf_RSA_1_APV.crt
openssl verify -CAfile EC_Root_CA_APV/certs/EC_Root_CA_APV.crt -untrusted Sub_EC_CA_1_APV/certs/Sub_EC_CA_1_APV.crt Sub_EC_CA_1_APV/certs/Leaf_EC_1_APV.crt
```

Résultats observés : tous `OK`.

Extrait d’arborescence utile :

```text
02-pki-openssl/
  RSA_Root_CA_APV/
    certs/RSA_Root_CA_APV.crt
    db/index.txt
    openssl-rsa-root.cnf
  Sub_RSA_CA_1_APV/
    certs/Sub_RSA_CA_1_APV.crt
    certs/Leaf_RSA_1_APV.crt
    openssl-rsa-sub.cnf
  EC_Root_CA_APV/
    certs/EC_Root_CA_APV.crt
    openssl-ec-root.cnf
  Sub_EC_CA_1_APV/
    certs/Sub_EC_CA_1_APV.crt
    certs/Leaf_EC_1_APV.crt
    openssl-ec-sub.cnf
```

Les clés privées existent dans les répertoires `private/`, mais elles ne sont pas affichées dans ce compte rendu.

## 2. Révocation par CRL

Sources : `03-crl-ocsp/README.md`, `verify-before-revoke.txt`, `crl-after-revoke.txt`, `openssl-rsa-sub-ocsp.cnf`.

### 2. Émission d’un certificat final par `Sub_RSA_CA_1_APV`

Certificat généré : `03-crl-ocsp/Sub_RSA_CA_1_APV-leaf-crl.crt`.

Commande :

```bash
openssl ca -batch \
  -config openssl-rsa-sub-ocsp.cnf \
  -extensions v3_leaf \
  -days 365 \
  -notext \
  -in Sub_RSA_CA_1_APV-leaf-crl.csr.pem \
  -out Sub_RSA_CA_1_APV-leaf-crl.crt
```

### 3. Validation du certificat face à la chaîne d’autorité

Commande :

```bash
openssl verify \
  -CAfile ../02-pki-openssl/RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt \
  -untrusted ../02-pki-openssl/Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt \
  Sub_RSA_CA_1_APV-leaf-crl.crt
```

Résultat dans `verify-before-revoke.txt` :

```text
/home/baptiste/tp-crypto-agents/03-crl-ocsp/Sub_RSA_CA_1_APV-leaf-crl.crt: OK
```

### 4. Révocation du certificat et émission de la CRL

Commandes :

```bash
openssl ca -batch -config openssl-rsa-sub-ocsp.cnf \
  -revoke Sub_RSA_CA_1_APV-leaf-crl.crt \
  -crl_reason keyCompromise

openssl ca -config openssl-rsa-sub-ocsp.cnf \
  -gencrl -crldays 30 \
  -out ca-work/Sub_RSA_CA_1_APV/crl.pem

openssl crl -in ca-work/Sub_RSA_CA_1_APV/crl.pem -text -noout > crl-after-revoke.txt
```

Résultat dans `crl-after-revoke.txt` :

```text
Issuer: C=FR, O=TP Crypto Agents, OU=PKI OpenSSL, CN=Sub_RSA_CA_1_APV
Last Update: Jun 23 07:18:21 2026 GMT
Next Update: Jul 23 07:18:21 2026 GMT
Serial Number: 1000
Revocation Date: Jun 23 07:18:21 2026 GMT
X509v3 CRL Reason Code: Key Compromise
```

## 3. Signature et chiffrement S/MIME

Sources : `04-smime/README.md`, `smime-openssl.cnf`, `smime-cert.x509.txt`, `verified-message.txt`.

### 5. Émission d’un certificat S/MIME

Certificat : `04-smime/smime-user.crt`, émis par `Sub_RSA_CA_1_APV`.

Extensions observées :

- `Basic Constraints: CA:FALSE` ;
- `Key Usage: Digital Signature, Key Encipherment` ;
- `Extended Key Usage: E-mail Protection` ;
- SAN email : `smime-user@APV.local`.

Commande de signature :

```bash
openssl ca -batch \
  -config Sub_RSA_CA_1_APV/openssl-rsa-sub.cnf \
  -extfile ../04-smime/smime-openssl.cnf \
  -extensions v3_smime_signer \
  -days 365 \
  -notext \
  -in ../04-smime/smime-user.csr.pem \
  -out ../04-smime/smime-user.crt
```

### 6. Échange du certificat et envoi d’un message signé/chiffré

L’échange réel avec un autre groupe est à compléter. Une démonstration locale a été réalisée avec un certificat destinataire de test : `04-smime/recipient-test.crt`.

Commandes préparées et utilisées en local :

```bash
openssl smime -sign -binary -nodetach \
  -in message.txt \
  -signer smime-user.crt \
  -inkey smime-user.key.pem \
  -certfile ../02-pki-openssl/Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt \
| openssl smime -encrypt -aes256 \
  -out signed-encrypted-message.pem \
  recipient-test.crt
```

### 7. Réception, déchiffrement et vérification

Commandes :

```bash
openssl smime -decrypt \
  -in signed-encrypted-message.pem \
  -recip recipient-test.crt \
  -inkey recipient-test.key.pem \
  -out decrypted-signed-message.pem

openssl smime -verify \
  -in decrypted-signed-message.pem \
  -CAfile ../02-pki-openssl/RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt \
  -out verified-message.txt
```

Résultat : `verified-message.txt` contient le message clair attendu. La démonstration locale signature + chiffrement + déchiffrement + vérification est donc réalisée. L’échange inter-groupe reste à compléter.

## 4. Révocation par OCSP

Sources : `03-crl-ocsp/README.md`, `ocsp-test-cert.x509.txt`, `ocsp-good.txt`, `ocsp-revoked.txt`.

### 8. Certificat contenant URL CRL et URL OCSP

Certificat testé : `03-crl-ocsp/Sub_RSA_CA_1_APV-leaf-ocsp.crt`.

Extensions observées :

```text
CRL Distribution Points:
  URI:http://crl.localhost:2560/Sub_RSA_CA_1_APV.crl
Authority Information Access:
  OCSP - URI:http://ocsp.localhost:2560
```

### 9. Mise en place du répondeur OCSP

Répondeur local lancé sur `127.0.0.1:2560`.

Commande :

```bash
openssl ocsp \
  -index ca-work/Sub_RSA_CA_1_APV/db/index.txt \
  -port 2560 \
  -rsigner ../02-pki-openssl/Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt \
  -rkey ../02-pki-openssl/Sub_RSA_CA_1_APV/private/Sub_RSA_CA_1_APV.key.pem \
  -CA ../02-pki-openssl/Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt \
  -nrequest 1
```

### 10. Vérification OCSP avant révocation

Commande :

```bash
openssl ocsp \
  -issuer ../02-pki-openssl/Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt \
  -cert Sub_RSA_CA_1_APV-leaf-ocsp.crt \
  -url http://127.0.0.1:2560 \
  -CAfile ../02-pki-openssl/RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt \
  -verify_other ../02-pki-openssl/Sub_RSA_CA_1_APV/certs/Sub_RSA_CA_1_APV.crt \
  -resp_text -text -no_nonce
```

Résultat dans `ocsp-good.txt` :

```text
Cert Status: good
Response verify OK
Sub_RSA_CA_1_APV-leaf-ocsp.crt: good
```

### 11. Révocation

Commande :

```bash
openssl ca -batch -config openssl-rsa-sub-ocsp.cnf \
  -revoke Sub_RSA_CA_1_APV-leaf-ocsp.crt \
  -crl_reason cessationOfOperation
```

### 12. Vérification OCSP après révocation

Résultat dans `ocsp-revoked.txt` :

```text
Cert Status: revoked
Revocation Time: Jun 23 07:18:22 2026 GMT
Response verify OK
Sub_RSA_CA_1_APV-leaf-ocsp.crt: revoked
```

Le statut passe bien de `good` à `revoked`.

## 5. Certification croisée

Sources : `05-cross-cert/README.md`, `verify/verify-ec-self.txt`, `verify/verify-rsa-cross.txt`, `analysis/*.txt`.

Une certification croisée dans un seul sens n’est pas symétrique. Ici, `RSA_Root_CA_APV` signe un certificat croisé pour `EC_Root_CA_APV`. Un validateur qui fait confiance à la racine RSA peut donc valider une chaîne EC via ce certificat croisé. L’inverse n’est pas vrai sans certificat miroir `RSA_Root_CA_APV` signé par `EC_Root_CA_APV`.

Exemple concret :

```text
RSA_Root_CA_APV
  -> EC_Root_CA_APV (certificat croisé signé par RSA_Root_CA_APV)
  -> Sub_EC_CA_1_APV
  -> Leaf_EC_1_APV.crosspath
```

Schéma conceptuel pour une certification croisée dans les deux sens :

```text
RSA_Root_CA_APV -> EC_Root_CA_APV
EC_Root_CA_APV  -> RSA_Root_CA_APV
```

Il faudrait donc émettre un second certificat croisé, cette fois avec la racine EC comme émetteur et la clé publique de la racine RSA comme sujet.

Certificat final émis par `Sub_EC_CA_1_APV` : `05-cross-cert/certs/Leaf_EC_1_APV.crosspath.crt`.

### Chaîne 1 : jusqu’à `EC_Root_CA_APV` autosignée

Commande :

```bash
openssl verify -show_chain \
  -CAfile /home/baptiste/tp-crypto-agents/02-pki-openssl/EC_Root_CA_APV/certs/EC_Root_CA_APV.crt \
  -untrusted /home/baptiste/tp-crypto-agents/02-pki-openssl/Sub_EC_CA_1_APV/certs/Sub_EC_CA_1_APV.crt \
  /home/baptiste/tp-crypto-agents/05-cross-cert/certs/Leaf_EC_1_APV.crosspath.crt
```

Résultat :

```text
/home/baptiste/tp-crypto-agents/05-cross-cert/certs/Leaf_EC_1_APV.crosspath.crt: OK
depth=0: CN=Leaf_EC_1_APV
depth=1: CN=Sub_EC_CA_1_APV
depth=2: CN=EC_Root_CA_APV
```

### Chaîne 2 : via certification croisée jusqu’à `RSA_Root_CA_APV`

Commande :

```bash
openssl verify -show_chain \
  -CAfile /home/baptiste/tp-crypto-agents/02-pki-openssl/RSA_Root_CA_APV/certs/RSA_Root_CA_APV.crt \
  -untrusted /home/baptiste/tp-crypto-agents/05-cross-cert/certs/untrusted-rsa-path.pem \
  /home/baptiste/tp-crypto-agents/05-cross-cert/certs/Leaf_EC_1_APV.crosspath.crt
```

Résultat :

```text
/home/baptiste/tp-crypto-agents/05-cross-cert/certs/Leaf_EC_1_APV.crosspath.crt: OK
depth=0: CN=Leaf_EC_1_APV
depth=1: CN=Sub_EC_CA_1_APV
depth=2: CN=EC_Root_CA_APV
depth=3: CN=RSA_Root_CA_APV
```

## 6. Magasin de certificats Windows

Question 15 de la partie 2 : non réalisée sur Windows. Une procédure a été préparée dans `07-windows-handoff/README.md`.

Certificats à exporter/importer :

- racine : certificat racine de confiance, par exemple `RSA_Root_CA_APV.crt` ou `HSM_Root_CA_TRI.crt` selon la chaîne testée ;
- intermédiaire : certificat d’AC subordonnée, par exemple `Sub_RSA_CA_1_APV.crt` ou l’AC ADCS subordonnée une fois émise.

Magasins Windows visés :

- racine : `Autorités de certification racines de confiance` / `Cert:\LocalMachine\Root` ;
- intermédiaire : `Autorités de certification intermédiaires` / `Cert:\LocalMachine\CA`.

Commandes indicatives :

```powershell
Import-Certificate -FilePath C:\PKI\HSM_Root_CA_TRI.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath C:\PKI\HSM_Sub_CA_TRI.cer  -CertStoreLocation Cert:\LocalMachine\CA
```

Validation attendue : ouverture du certificat dans Windows et vérification de l’onglet `Certification Path`.

Captures à compléter : magasin racine, magasin intermédiaire, chaîne validée.

---

# Partie 3 — SoftHSM2 et ADCS

## 1. Autorité racine Linux avec SoftHSM2

Sources : `06-softhsm/README.md`, `06-softhsm/openssl-hsm-root.cnf`, `state/certs/HSM_Root_CA_TRI.crt`, `state/crl/HSM_Root_CA_TRI.crl`, `scripts/verify-no-private-files.sh`.

Travail réalisé sous Linux :

- configuration locale SoftHSM2 ;
- initialisation d’un token dédié ;
- génération d’une clé RSA 4096 bits dans le token ;
- émission d’un certificat racine autosigné ;
- génération d’une CRL/ARL valable environ un mois ;
- utilisation d’OpenSSL via PKCS#11 ;
- vérification de l’absence de fichier de clé privée exporté hors SoftHSM2.

Commande de bootstrap :

```bash
./scripts/bootstrap-hsm-root-ca.sh
```

Certificat racine :

```text
Subject: C=FR, O=TP Crypto, OU=06-softhsm, CN=HSM_Root_CA_TRI
Issuer:  C=FR, O=TP Crypto, OU=06-softhsm, CN=HSM_Root_CA_TRI
Clé: RSA 4096 bits
Validité: Jun 23 07:17:04 2026 GMT -> Jun 20 07:17:04 2036 GMT
Extensions: CA:TRUE, pathlen:1, Certificate Sign, CRL Sign
```

CRL :

```text
Issuer: C=FR, O=TP Crypto, OU=06-softhsm, CN=HSM_Root_CA_TRI
Last Update: Jun 23 07:17:04 2026 GMT
Next Update: Jul 23 07:17:04 2026 GMT
No Revoked Certificates.
```

Preuve d’absence de fichier clé privée exporté :

```bash
sh scripts/verify-no-private-files.sh
```

Résultat :

```text
No private key file (.key or private .pem) found outside SoftHSM2.
```

Point important : aucun PIN, mot de passe, secret de token ou contenu de clé privée n’est inclus dans ce compte rendu.

Problème rencontré et correction documentée : la tentative avec le provider `pkcs11` a échoué car le module attendu n’existait pas sous ce nom. La solution utilisée est le provider OpenSSL 3 `pkcs11prov` avec le module SoftHSM2 configuré.

## 2. Autorité subordonnée ADCS Windows

À réaliser sur Windows Server 2019. Le dossier `07-windows-handoff/README.md` contient une procédure de préparation, mais pas de preuve d’exécution.

Procédure attendue :

1. Installer ADCS en mode Standalone CA :

```powershell
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
```

2. Créer une AC subordonnée autonome avec clé RSA 4096 bits, SHA-256 et validité 5 ans :

```powershell
Install-AdcsCertificationAuthority `
  -CAType StandaloneSubordinateCA `
  -CACommonName "HSM_Sub_CA_TRI" `
  -KeyLength 4096 `
  -HashAlgorithmName SHA256 `
  -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
  -OutputCertRequestFile C:\PKI\HSM_Sub_CA_TRI.req `
  -ValidityPeriod Years `
  -ValidityPeriodUnits 5
```

3. Transférer la CSR PKCS#10 vers Linux et la signer avec la racine OpenSSL/SoftHSM2 :

```bash
./scripts/sign-adcs-csr.sh HSM_Sub_CA_TRI.req issued/HSM_Sub_CA_TRI.crt
```

4. Renvoyer le certificat signé sur Windows et finaliser ADCS :

```powershell
certreq -accept C:\PKI\HSM_Sub_CA_TRI.cer
```

5. Générer une requête TLS avec `certreq` :

```powershell
certreq -new C:\PKI\tls.inf C:\PKI\tls.req
```

6. Soumettre la requête TLS à l’AC ADCS :

```powershell
certutil -config "NomServeur\HSM_Sub_CA_TRI" -submit C:\PKI\tls.req C:\PKI\tls.cer
```

Captures nécessaires : rôle ADCS installé, AC subordonnée configurée, certificat racine importé, certificat subordonné valide, certificat TLS émis, chaîne visible dans Windows.

---

# Conclusion

Sous Linux, le TP a permis d’analyser des certificats publics, de vérifier CRL et OCSP, de construire deux PKI OpenSSL, de révoquer des certificats, de simuler S/MIME localement, de tester une certification croisée et de créer une racine protégée par SoftHSM2. Les éléments dépendant d’un navigateur graphique, d’un autre groupe ou de Windows Server restent à compléter : captures navigateur, échange S/MIME réel, magasin Windows et ADCS.

Les mécanismes étudiés illustrent le fonctionnement pratique de la chaîne de confiance, de la révocation, d’OCSP, de S/MIME et de la protection des clés d’autorité par HSM.

---

# Annexes

## Annexes — Fichiers produits

### `01-public-certs`

- Certificats et chaînes : `cyber.gouv.fr.pem`, `cyber.gouv.fr.chain.txt`, `revoked-rsa-dv.ssl.com.pem`, `google.com.pem`, `youtube.com.pem`.
- Analyses X.509 : `cyber.gouv.fr.x509.txt`, `revoked-rsa-dv.ssl.com.x509.txt`, `google.com.x509.txt`, `youtube.com.x509.txt`.
- CRL/OCSP : `GandiCert.crl`, `crl.txt`, `revoked-rsa-dv.ssl.com.crl`, `revoked-rsa-dv.ssl.com.crl.txt`, `revoked-rsa-dv.ssl.com.ocsp.txt`.
- Rapports intermédiaires : `README.md`, `README-revocation.md`.

### `02-pki-openssl`

- Configurations : `openssl-rsa-root.cnf`, `openssl-ec-root.cnf`, `openssl-rsa-sub.cnf`, `openssl-ec-sub.cnf`.
- Certificats : `RSA_Root_CA_APV.crt`, `Sub_RSA_CA_1_APV.crt`, `Leaf_RSA_1_APV.crt`, `EC_Root_CA_APV.crt`, `Sub_EC_CA_1_APV.crt`, `Leaf_EC_1_APV.crt`.
- Bases OpenSSL : `db/index.txt`, `db/serial`, `db/crlnumber`.
- Analyses : dossiers `analysis/`.

### `03-crl-ocsp`

- Certificats : `Sub_RSA_CA_1_APV-leaf-crl.crt`, `Sub_RSA_CA_1_APV-leaf-ocsp.crt`.
- Configuration : `openssl-rsa-sub-ocsp.cnf`.
- Sorties : `verify-before-revoke.txt`, `crl-after-revoke.txt`, `crl-after-ocsp-revoke.txt`, `ocsp-good.txt`, `ocsp-revoked.txt`, `ocsp-test-cert.x509.txt`.
- Script : `run-crl-ocsp.sh`.

### `04-smime`

- Configuration : `smime-openssl.cnf`.
- Certificats/CSR : `smime-user.csr.pem`, `smime-user.crt`, `recipient-test.csr.pem`, `recipient-test.crt`.
- Messages : `message.txt`, `signed-message.pem`, `encrypted-message.pem`, `signed-encrypted-message.pem`, `decrypted-signed-message.pem`, `verified-message.txt`.

### `05-cross-cert`

- Certificat croisé : `certs/EC_Root_CA_APV.cross-signed-by-RSA_Root_CA_APV.crt`.
- Certificat final : `certs/Leaf_EC_1_APV.crosspath.crt`.
- Chaîne non fiable : `certs/untrusted-rsa-path.pem`.
- Vérifications : `verify/verify-ec-self.txt`, `verify/verify-rsa-cross.txt`.
- Analyses : `analysis/*.txt`.

### `06-softhsm`

- Configuration : `softhsm2.conf`, `openssl-hsm-root.cnf`.
- Certificat : `state/certs/HSM_Root_CA_TRI.crt`.
- CRL : `state/crl/HSM_Root_CA_TRI.crl`.
- État CA : `state/index.txt`, `state/serial`, `state/crlnumber`.
- Scripts : `bootstrap-hsm-root-ca.sh`, `sign-adcs-csr.sh`, `verify-no-private-files.sh`.

### `07-windows-handoff`

- Procédure Windows : `README.md`.

## Annexes — Captures restantes à insérer

- Navigateurs sur `revoked-rsa-dv.ssl.com` : Firefox, Chromium, troisième navigateur.
- Navigateur sur `wrong.host.badssl.com`.
- Magasin de certificats Windows.
- Installation et configuration ADCS.
- Certificat TLS Windows.
- Échange S/MIME réel avec un autre groupe.

## Annexes — Checklist finale

- [x] Analyse du certificat `cyber.gouv.fr`.
- [x] Téléchargement et analyse de la CRL GandiCert.
- [x] Recherche du serial `cyber.gouv.fr` dans la CRL.
- [x] Vérification CRL du certificat révoqué SSL.com.
- [x] Vérification OCSP du certificat révoqué SSL.com.
- [x] Comparaison des certificats `google.com` et `youtube.com`.
- [x] Test OpenSSL de `wrong.host.badssl.com`.
- [ ] Captures navigateur de révocation.
- [ ] Capture navigateur de mismatch de nom d’hôte.
- [ ] Analyse de `isrg-1.crt` et `isrg-2.crt`.
- [x] Création des AC RSA et EC OpenSSL.
- [x] Vérification des chaînes OpenSSL.
- [x] Révocation CRL locale.
- [x] Démonstration S/MIME locale.
- [ ] Échange S/MIME réel avec un autre groupe.
- [x] Répondeur OCSP local et changement `good` vers `revoked`.
- [x] Certification croisée dans un sens.
- [x] Vérification des deux chemins pour le certificat EC final.
- [ ] Import et validation dans le magasin Windows.
- [x] Racine Linux SoftHSM2.
- [x] CRL/ARL SoftHSM2 valable environ un mois.
- [ ] AC subordonnée ADCS Windows Server 2019.
- [ ] Certificat TLS émis par ADCS.
