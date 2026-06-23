# PKI OpenSSL

Cette arborescence construit deux chaînes d'autorité de certification séparées :

- une chaîne RSA : `RSA_Root_CA_BPA` -> `Sub_RSA_CA_1_BPA`
- une chaîne EC : `EC_Root_CA_BPA` -> `Sub_EC_CA_1_BPA`

Le préfixe `BPA` est utilisé par défaut. Si un fichier `TRI.txt` est présent dans ce dossier, sa première ligne non vide remplace `BPA`.

## Méthode

La génération suit une structure OpenSSL classique par AC :

- `private/` pour les clés privées
- `certs/` pour les certificats émis
- `csr/` pour les demandes de signature
- `db/` pour la base `openssl ca`
- `newcerts/` pour les certificats nouvellement signés

Les AC racines sont créées en autosigné avec `openssl req -x509`.
Les AC subordonnées sont signées par leur racine avec `openssl ca`.
Les certificats finaux sont signés par leur AC subordonnée avec `openssl ca`.

## Choix des extensions

Les extensions X509 sont définies explicitement dans les fichiers `openssl-*.cnf`.

### AC racines

- `basicConstraints = critical, CA:TRUE`
- `keyUsage = critical, keyCertSign, cRLSign`
- `subjectKeyIdentifier = hash`
- `authorityKeyIdentifier = keyid:always,issuer`

### AC subordonnées

- `basicConstraints = critical, CA:TRUE, pathlen:0`
- `keyUsage = critical, keyCertSign, cRLSign`
- `subjectKeyIdentifier = hash`
- `authorityKeyIdentifier = keyid:always,issuer`

Le `pathlen:0` interdit à une AC subordonnée d’émettre elle-même d’autres AC.

### Certificats finaux

- `basicConstraints = critical, CA:FALSE`
- `keyUsage` adapté au type de clé
- `extendedKeyUsage = serverAuth, clientAuth`
- `subjectAltName` explicite
- `subjectKeyIdentifier = hash`
- `authorityKeyIdentifier = keyid,issuer`

## Durées

- Racines : `15 ans` = `5475` jours
- Subordonnées : `10 ans` = `3650` jours
- Certificats finaux : `1 an` = `365` jours

## Contraintes de chaîne

Les contraintes de chaîne reposent sur :

- `CA:TRUE` pour toutes les AC
- `CA:FALSE` pour les certificats finaux
- `pathlen:0` pour empêcher toute subordonnée d’émettre une autre AC

Les vérifications ont été faites avec `openssl verify` pour :

- chaque racine
- chaque AC subordonnée
- chaque certificat final avec la chaîne complète

## Commandes utilisées

### Génération

```bash
./generate-pki.sh
```

### Vérification

```bash
openssl verify -CAfile RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt
openssl verify -CAfile RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt
openssl verify -CAfile RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt -untrusted Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt Sub_RSA_CA_1_BPA/certs/Leaf_RSA_1_BPA.crt

openssl verify -CAfile EC_Root_CA_BPA/certs/EC_Root_CA_BPA.crt EC_Root_CA_BPA/certs/EC_Root_CA_BPA.crt
openssl verify -CAfile EC_Root_CA_BPA/certs/EC_Root_CA_BPA.crt Sub_EC_CA_1_BPA/certs/Sub_EC_CA_1_BPA.crt
openssl verify -CAfile EC_Root_CA_BPA/certs/EC_Root_CA_BPA.crt -untrusted Sub_EC_CA_1_BPA/certs/Sub_EC_CA_1_BPA.crt Sub_EC_CA_1_BPA/certs/Leaf_EC_1_BPA.crt
```

## Sorties d’analyse

Chaque certificat possède un fichier texte d’analyse généré par :

```bash
openssl x509 -in <certificat.crt> -text -noout > <fichier>.txt
```
