# Notes - Standalone Subordinate CA

Une **Standalone Subordinate CA** est une autorité de certification Windows ADCS autonome et subordonnée. Elle n'est pas intégrée à Active Directory comme une Enterprise CA. Elle génère sa propre clé privée localement, puis produit une CSR qui doit être signée par une autorité parente.

Dans ce TP, l'autorité parente est la racine Linux/OpenSSL/SoftHSM2. Windows ne peut donc pas finaliser la CA immédiatement : il génère d'abord `sub-adcs-ca.req`, puis attend que Linux signe cette requête.

## Fichiers à transférer

De Windows vers Linux :

- `C:\TP-Crypto-ADCS\output\sub-adcs-ca.req`

De Linux vers Windows :

- `sub-adcs-ca-signed.crt` vers `C:\TP-Crypto-ADCS\input\sub-adcs-ca-signed.crt`
- `root-ca.crt` vers `C:\TP-Crypto-ADCS\input\root-ca.crt`

## Captures à faire

- Premier lancement PowerShell administrateur.
- Génération de la CSR du sous-CA.
- Signature Linux de la CSR.
- Import du certificat racine dans Windows.
- Démarrage du service `CertSvc`.
- Génération de la CSR TLS `www.tp-crypto.local`.
- Émission du certificat TLS par ADCS.
- `certutil -dump` et `certutil -verify` sur le certificat TLS.
