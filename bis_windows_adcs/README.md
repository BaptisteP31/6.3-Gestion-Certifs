# TP Cryptographie - Partie Windows / ADCS

Ce dossier contient les fichiers nécessaires pour automatiser la partie Windows Server ADCS du TP.

Objectif côté Windows : créer une **autorité de certification subordonnée autonome** avec ADCS, générer sa CSR, la faire signer côté Linux/OpenSSL/SoftHSM2, puis finaliser la CA et émettre un certificat TLS pour `www.tp-crypto.local`.

## Arborescence

```text
windows-adcs/
├── README.md
├── run-on-windows.ps1
├── sign-subca-on-linux.sh
├── templates/
│   ├── web-tls.inf
│   └── subordinate-ca-notes.md
└── output/
    └── .gitkeep
```

## Prérequis Windows Server

- Windows Server 2019 ou 2022.
- PowerShell lancé en administrateur.
- VM dédiée au TP recommandée.
- Pas besoin d'Active Directory Domain Services : le TP demande une CA **Standalone Subordinate CA**.

## Copier le dossier sur la VM Windows

Copie le dossier `windows-adcs` sur le Bureau de l'administrateur, par exemple :

```text
C:\Users\Administrateur\Desktop\6.3-Gestion-Certifs\windows-adcs
```

## Premier lancement Windows

Ouvre PowerShell en administrateur :

```powershell
cd C:\Users\Administrateur\Desktop\6.3-Gestion-Certifs\windows-adcs
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\run-on-windows.ps1
```

Si ta VM contient déjà des restes ADCS d'un essai précédent, lance plutôt :

```powershell
.\run-on-windows.ps1 -ResetADCS
```

Le premier passage doit générer :

```text
C:\TP-Crypto-ADCS\output\sub-adcs-ca.req
```

C'est normal que le script s'arrête ensuite : la CSR doit être signée par la racine Linux/OpenSSL/SoftHSM2.

## Transfert Windows vers Linux

Copie :

```text
C:\TP-Crypto-ADCS\output\sub-adcs-ca.req
```

vers :

```text
windows-adcs/from-windows/sub-adcs-ca.req
```

## Signature côté Linux

Avant de lancer le script Linux, adapte si besoin ces variables dans `sign-subca-on-linux.sh` :

```bash
ROOT_CA_CERT="../06-softhsm/certs/root-ca.crt"
ROOT_CA_CONFIG="../06-softhsm/openssl-root-ca.cnf"
ROOT_CA_NAME="HSM_Root_CA_BPA"
```

Puis lance :

```bash
chmod +x windows-adcs/sign-subca-on-linux.sh
./windows-adcs/sign-subca-on-linux.sh
```

Le certificat signé sera produit ici :

```text
windows-adcs/to-windows/sub-adcs-ca-signed.crt
```

## Retour Linux vers Windows

Copie côté Windows :

```text
windows-adcs/to-windows/sub-adcs-ca-signed.crt
```

vers :

```text
C:\TP-Crypto-ADCS\input\sub-adcs-ca-signed.crt
```

Copie aussi le certificat racine Linux :

```text
root-ca.crt
```

vers :

```text
C:\TP-Crypto-ADCS\input\root-ca.crt
```

## Deuxième lancement Windows

Relance :

```powershell
cd C:\Users\Administrateur\Desktop\6.3-Gestion-Certifs\windows-adcs
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\run-on-windows.ps1
```

Le script doit alors :

- importer le certificat racine ;
- finaliser la CA subordonnée ADCS ;
- démarrer `CertSvc` ;
- générer une CSR TLS pour `www.tp-crypto.local` ;
- soumettre/émettre le certificat TLS via ADCS si possible ;
- produire des logs et un rapport Markdown.

## Rapport et logs

Rapport :

```text
C:\TP-Crypto-ADCS\RAPPORT-WINDOWS-ADCS.md
```

Logs :

```text
C:\TP-Crypto-ADCS\logs
```

## Captures nécessaires pour le compte rendu

- Lancement du script dans PowerShell administrateur.
- CSR créée dans `C:\TP-Crypto-ADCS\output\sub-adcs-ca.req`.
- Signature côté Linux avec OpenSSL/SoftHSM2.
- Import de `root-ca.crt` dans le magasin `LocalMachine\Root`.
- Service `CertSvc` en état `Running`.
- Certificat TLS généré dans `C:\TP-Crypto-ADCS\output\web-tls.cer`.
- Résultats `certutil -dump` et `certutil -verify`.

## Checklist finale

- [ ] VM Windows Server 2019/2022 prête.
- [ ] PowerShell lancé en administrateur.
- [ ] Premier lancement Windows effectué.
- [ ] `sub-adcs-ca.req` transféré vers Linux.
- [ ] CSR signée par la racine Linux/OpenSSL/SoftHSM2.
- [ ] `root-ca.crt` et `sub-adcs-ca-signed.crt` replacés dans `C:\TP-Crypto-ADCS\input`.
- [ ] Deuxième lancement Windows effectué.
- [ ] Certificat TLS émis et vérifié.
- [ ] Rapport Markdown récupéré.
