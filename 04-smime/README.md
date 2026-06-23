# S/MIME avec OpenSSL

## Méthodologie

Le certificat d'entité finale est émis par la CA subordonnée RSA `Sub_RSA_CA_1_BPA` de la PKI fournie dans `../02-pki-openssl`.

Le profil S/MIME utilise :

- `extendedKeyUsage = emailProtection`
- `keyUsage = digitalSignature, keyEncipherment`

Ces usages sont cohérents avec :

- la signature de messages, via `digitalSignature`
- le chiffrement à destination du destinataire, via `keyEncipherment`

J'ai aussi ajouté un `subjectAltName` de type email pour rendre le certificat exploitable dans un contexte S/MIME.

## Commandes utilisées

Les commandes ci-dessous sont celles utilisées pour produire les fichiers du dossier.

### 1. Créer la clé et la CSR du certificat S/MIME

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out smime-user.key.pem

openssl req -new \
  -key smime-user.key.pem \
  -subj "/C=FR/O=TP Crypto Agents/OU=SMIME/CN=SMIME Test User/emailAddress=smime-user@bpa.local" \
  -out smime-user.csr.pem
```

### 2. Signer le certificat avec `Sub_RSA_CA_1_BPA`

```bash
cd ../02-pki-openssl

openssl ca -batch \
  -config Sub_RSA_CA_1_BPA/openssl-rsa-sub.cnf \
  -extfile ../04-smime/smime-openssl.cnf \
  -extensions v3_smime_signer \
  -days 365 \
  -notext \
  -in ../04-smime/smime-user.csr.pem \
  -out ../04-smime/smime-user.crt
```

### 3. Afficher le certificat

```bash
openssl x509 -in smime-user.crt -text -noout > smime-cert.x509.txt
```

### 4. Créer le message texte

```bash
cat > message.txt <<'EOF'
Bonjour,

Ceci est un message de test S/MIME.
Il servira pour la signature, le chiffrement, puis la vérification de bout en bout.

-- TP Crypto Agents
EOF
```

### 5. Préparer les commandes OpenSSL

Signer :

```bash
openssl smime -sign -binary -nodetach \
  -in message.txt \
  -signer smime-user.crt \
  -inkey smime-user.key.pem \
  -certfile ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
  -out signed-message.pem \
  -outform SMIME
```

Chiffrer pour un autre groupe :

```bash
openssl smime -encrypt -aes256 \
  -in message.txt \
  -out encrypted-message.pem \
  recipient-test.crt
```

Signer puis chiffrer :

```bash
openssl smime -sign -binary -nodetach \
  -in message.txt \
  -signer smime-user.crt \
  -inkey smime-user.key.pem \
  -certfile ../02-pki-openssl/Sub_RSA_CA_1_BPA/certs/Sub_RSA_CA_1_BPA.crt \
| openssl smime -encrypt -aes256 \
  -out signed-encrypted-message.pem \
  recipient-test.crt
```

### 6. Générer un certificat destinataire de test

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out recipient-test.key.pem

openssl req -new \
  -key recipient-test.key.pem \
  -subj "/C=FR/O=TP Crypto Agents/OU=SMIME/CN=Recipient Test/emailAddress=recipient-test@bpa.local" \
  -out recipient-test.csr.pem

cd ../02-pki-openssl

openssl ca -batch \
  -config Sub_RSA_CA_1_BPA/openssl-rsa-sub.cnf \
  -extfile ../04-smime/smime-openssl.cnf \
  -extensions v3_smime_recipient \
  -days 365 \
  -notext \
  -in ../04-smime/recipient-test.csr.pem \
  -out ../04-smime/recipient-test.crt
```

### 7. Déchiffrer et vérifier

Déchiffrer :

```bash
openssl smime -decrypt \
  -in signed-encrypted-message.pem \
  -recip recipient-test.crt \
  -inkey recipient-test.key.pem \
  -out decrypted-signed-message.pem
```

Vérifier la signature après déchiffrement :

```bash
openssl smime -verify \
  -in decrypted-signed-message.pem \
  -CAfile ../02-pki-openssl/RSA_Root_CA_BPA/certs/RSA_Root_CA_BPA.crt \
  -out verified-message.txt
```

## Fichiers produits

- `smime-openssl.cnf`
- `message.txt`
- `smime-user.key.pem`
- `smime-user.csr.pem`
- `smime-user.crt`
- `smime-cert.x509.txt`
- `recipient-test.key.pem`
- `recipient-test.csr.pem`
- `recipient-test.crt`
- `signed-message.pem`
- `encrypted-message.pem`
- `signed-encrypted-message.pem`
- `decrypted-signed-message.pem`
- `verified-message.txt`

## À faire en séance : remplacer `recipient-test.crt` par le certificat de l'autre groupe

Le certificat `recipient-test.crt` sert uniquement de démonstration locale.

En séance, il faut remplacer :

- `recipient-test.crt` dans la commande de chiffrement
- `recipient-test.crt` et `recipient-test.key.pem` dans la commande de déchiffrement

par le certificat public réel du groupe destinataire et, pour la phase de déchiffrement locale, la clé privée correspondante du destinataire de test n'est plus utilisée.

## Remarque

Je ne prétends pas avoir échangé avec un autre groupe. La démonstration ci-dessus repose uniquement sur un certificat destinataire de test généré localement.
