# Revocation, OCSP, Google/YouTube, `wrong.host.badssl.com`

## 1. Certificat révoqué

Source TLS:

- `revoked-rsa-dv.ssl.com.pem`
- `revoked-rsa-dv.ssl.com.x509.txt`
- `revoked-rsa-dv.ssl.com.crl.txt`
- `revoked-rsa-dv.ssl.com.ocsp.txt`

### Valeurs extraites depuis OpenSSL

- Numéro de série: `1811B09C4BB9E179133BB9D9A9B140C5`
- Issuer: `C=US, O=SSL Corporation, CN=SSL.com TLS Issuing RSA CA R1`
- CRL Distribution Points:
  - `http://crls.ssl.com/SSL.com-TLS-I-RSA-R1.crl`
- Authority Information Access:
  - `CA Issuers - URI:http://cert.ssl.com/SSL.com-TLS-I-RSA-R1.cer`
  - `OCSP - URI:http://ocsps.ssl.com`
- URL OCSP:
  - `http://ocsps.ssl.com`

### CRL

Commande utilisée pour télécharger et lire la CRL:

```bash
openssl crl -inform DER -in revoked-rsa-dv.ssl.com.crl -noout -text
```

Le serial `1811B09C4BB9E179133BB9D9A9B140C5` est présent dans la CRL, avec:

- Revocation Date: `Jun  9 14:37:38 2026 GMT`

### Certificat intermédiaire utilisé pour OCSP

Le certificat intermédiaire récupéré via `CA Issuers` est:

- `ssl.com-tls-i-rsa-r1.pem`

### OCSP

Commande utilisée:

```bash
openssl ocsp -issuer ssl.com-tls-i-rsa-r1.pem -cert revoked-rsa-dv.ssl.com.pem -url http://ocsps.ssl.com -no_nonce -resp_text -text
```

Statut obtenu:

- `revoked-rsa-dv.ssl.com.pem: revoked`
- Revocation Time: `Jun  9 14:37:38 2026 GMT`

### Commentaire CRL vs OCSP

- La CRL est une liste publiée périodiquement; ici le serial apparaît explicitement dans `revoked-rsa-dv.ssl.com.crl.txt`.
- OCSP donne un statut par certificat, plus direct à interroger pour un client.
- Dans ce cas, les deux mécanismes convergent: le certificat est révoqué dans la CRL et l’OCSP renvoie aussi `revoked`.
- La réponse OCSP contient un `This Update` et un `Next Update`, ce qui permet d’évaluer la fraîcheur de l’état retourné.

## 2. Google et YouTube

Sources:

- `google.com.pem`
- `google.com.x509.txt`
- `google.com.serial.txt`
- `youtube.com.pem`
- `youtube.com.x509.txt`
- `youtube.com.serial.txt`

### Numéros de série

- Google:
  - `serial=139CDF29A8B5BC5212413EEEAFD18CBE`
- YouTube:
  - `serial=139CDF29A8B5BC5212413EEEAFD18CBE`

### Comparaison

- Les deux hôtes présentent le même certificat feuille.
- Le certificat contient `DNS:google.com` et `DNS:youtube.com` dans les Subject Alternative Names.
- L’explication la plus simple est que Google sert le même certificat multi-SAN sur les deux noms d’hôte.

## 3. `wrong.host.badssl.com`

Source:

- `wrong.host.badssl.com.openssl.txt`

Résultat OpenSSL:

- `verify error:num=62:hostname mismatch`
- `Verification error: hostname mismatch`

Explication:

- Le certificat présenté est pour `CN=*.badssl.com`.
- `wrong.host.badssl.com` ne correspond pas à ce nom d’hôte.
- Un navigateur doit donc refuser la connexion ou afficher une alerte de sécurité de type erreur de nom d’hôte.

## 4. Captures navigateur à insérer

Les captures visuelles n’ont pas été faites ici.

- Firefox: capture à insérer
- Chromium: capture à insérer
- Troisième navigateur: capture à insérer

