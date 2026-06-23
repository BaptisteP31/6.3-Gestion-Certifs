# Notes sur la Standalone Subordinate CA

Une Standalone Subordinate CA est une autorite de certification subordonnee qui n'utilise pas les mecanismes Enterprise AD CS. Elle produit d'abord une requete CSR, puis attend qu'une autorite superieure signe ce certificat d'AC.

Dans ce TP, la CSR Windows doit etre signee cote Linux par l'autorite racine OpenSSL/SoftHSM2. C'est normal : Windows genere la cle privee et la CSR, mais la racine Linux emet le certificat d'AC subordonnee.

Fichiers a transferer entre Windows et Linux:
- `C:\TP-Crypto-ADCS\output\sub-adcs-ca.req` vers Linux.
- `sub-adcs-ca-signed.crt` depuis Linux vers `C:\TP-Crypto-ADCS\input\sub-adcs-ca-signed.crt`.
- `root-ca.crt` depuis Linux vers `C:\TP-Crypto-ADCS\input\root-ca.crt`.

Captures a faire pour le compte rendu:
- generation de la CSR du sous-CA;
- import du certificat racine dans le magasin Windows;
- finalisation du service CertSvc;
- generation de la CSR TLS;
- verification du certificat TLS;
- preuves `certutil -store Root`, `certutil -dump` et `certutil -verify`.
