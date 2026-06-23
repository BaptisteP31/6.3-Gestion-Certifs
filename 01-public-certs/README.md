# TP 1 - Certificats publics

Fichiers produits:
- `cyber.gouv.fr.chain.txt`
- `cyber.gouv.fr.pem`
- `cyber.gouv.fr.x509.txt`
- `GandiCert.crl`
- `crl.txt`

## Reponses

- Protocole utilise par HTTPS: `TLSv1.3`
- Longueur de chaine: `2` certificats dans la chaine fournie par `s_client` (`cyber.gouv.fr` + `GandiCert`)
- Autorite racine: `DigiCert Global Root G2`
- Autorite subordonnee: `GandiCert`
- Taille de cle publique: `4096 bits`
- Type de certificat: `X.509 v3`, certificat serveur TLS
- Peut signer d'autres certificats: `non` (`Basic Constraints: CA:FALSE`)
- Peut signer du courrier electronique: `non` (`Extended Key Usage: TLS Web Server Authentication` seulement)
- Emplacements CRL:
  - `http://crl3.digicert.com/GandiCert.crl`
  - `http://crl4.digicert.com/GandiCert.crl`
- Numero de serie:
  - Format lu dans le certificat: `05:7e:1f:dd:c4:8e:7a:07:80:64:3a:be:eb:cc:52:a5`
  - Format sans deux-points: `057E1FDDC48E7A0780643ABEEBCC52A5`
  - Conversion decimale: `7301015708052902158374241928634716837`
- Cle publique:
  - Algorithme: `RSA`
  - Taille: `4096 bits`
  - Exposant: `65537 (0x10001)`
  - Extraction PEM: `openssl x509 -in cyber.gouv.fr.pem -pubkey -noout`
- Impossible d'obtenir la cle privee:
  - Le certificat ne contient que la cle publique et la signature de l'autorite.
  - La cle privee n'est pas incluse dans un certificat X.509 et ne peut pas etre reconstruite a partir du certificat seul.

## CRL

- CRL telechargee: `http://crl3.digicert.com/GandiCert.crl`
- Validite de la CRL:
  - `Last Update: Jun 22 12:45:56 2026 GMT`
  - `Next Update: Jun 29 12:45:56 2026 GMT`
  - Duree: `7 days`
- Raisons de revocation dans les premieres entrees:
  - Non, les premieres entrees listees affichent seulement le numero de serie et la date de revocation.
  - Des champs `X509v3 CRL Reason Code` apparaissent plus loin dans la liste.
- Presence du serial de `cyber.gouv.fr.pem` dans la CRL:
  - Aucun match trouve pour `057E1FDDC48E7A0780643ABEEBCC52A5`.

## Commandes utilisees

```bash
rtk sh -lc 'openssl s_client -showcerts -servername cyber.gouv.fr -connect cyber.gouv.fr:443 </dev/null 2>&1'
rtk sh -lc 'openssl s_client -showcerts -servername cyber.gouv.fr -connect cyber.gouv.fr:443 </dev/null 2>&1 | tee cyber.gouv.fr.chain.txt'
```

```bash
rtk sh -lc 'awk "BEGIN{c=0} /-----BEGIN CERTIFICATE-----/{c++; if(c==1) p=1} p{print} /-----END CERTIFICATE-----/{if(p){exit}}" cyber.gouv.fr.chain.txt > cyber.gouv.fr.pem'
```

```bash
rtk sh -lc 'openssl x509 -in cyber.gouv.fr.pem -text -noout > cyber.gouv.fr.x509.txt'
```

```bash
rtk openssl x509 -in cyber.gouv.fr.pem -noout -serial
rtk openssl x509 -in cyber.gouv.fr.pem -noout -subject -issuer -dates
rtk openssl x509 -in cyber.gouv.fr.pem -pubkey -noout
rtk python3 -c 'print(int("057E1FDDC48E7A0780643ABEEBCC52A5", 16))'
```

```bash
rtk sh -lc 'curl -fsSL http://crl3.digicert.com/GandiCert.crl -o GandiCert.crl && openssl crl -inform DER -in GandiCert.crl -text -noout > crl.txt'
```

```bash
rtk rg -n "Version:|Serial Number:|Issuer:|Subject:|Public-Key:|X509v3 Key Usage:|X509v3 Extended Key Usage:|X509v3 CRL Distribution Points:|X509v3 Subject Alternative Name:|Not Before:|Not After:" cyber.gouv.fr.x509.txt
rtk rg -n "Last Update|Next Update|Revoked Certificates|Serial Number|Reason Code|X509v3 CRL Number|Authority Key Identifier" crl.txt
rtk rg -n "057E1FDDC48E7A0780643ABEEBCC52A5|05:7E:1F:DD:C4:8E:7A:07:80:64:3A:BE:EB:CC:52:A5" crl.txt
rtk rg -n "X509v3 CRL Reason Code:" crl.txt
rtk awk '/BEGIN CERTIFICATE/{c++} END{print c}' cyber.gouv.fr.chain.txt
```

## Erreurs rencontrees

- Premiere tentative de connexion TLS sans elevation:
  - `Temporary failure in name resolution`
  - `connect:errno=11`
