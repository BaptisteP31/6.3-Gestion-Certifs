# Windows ADCS pour le TP Cryptographie

## Prerequis
- Windows Server 2019 ou 2022.
- Session administrateur locale.
- Rôle ADCS disponible sur la machine.
- Certificat racine Linux/OpenSSL disponible au format `.crt`.

## Installation du dossier sur la VM Windows
Copier tout le dossier `windows-adcs/` vers la VM, par exemple dans un partage ou via le presse-papiers, puis le placer sur le Bureau ou dans `C:\Temp`.

## Lancement
Ouvrir PowerShell **en administrateur**, puis autoriser temporairement l'execution si necessaire:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Lancer ensuite:
```powershell
.\run-on-windows.ps1
```

## Premier passage
Le premier lancement:
- cree `C:\TP-Crypto-ADCS`;
- installe ADCS si besoin;
- genere la CSR du sous-CA;
- laisse l'installation inachevee tant que le certificat signe Linux n'est pas present.

La CSR se trouve ici:
- `C:\TP-Crypto-ADCS\output\sub-adcs-ca.req`

## Signature cote Linux
Le script Linux se trouve dans:
- `windows-adcs/sign-subca-on-linux.sh`

Copier la CSR Windows dans:
- `windows-adcs/from-windows/sub-adcs-ca.req`

Puis executer le script Linux pour produire:
- `windows-adcs/to-windows/sub-adcs-ca-signed.crt`

## Retour cote Windows
Copier ensuite le certificat signe dans:
- `C:\TP-Crypto-ADCS\input\sub-adcs-ca-signed.crt`

Copier aussi le certificat racine Linux/OpenSSL dans:
- `C:\TP-Crypto-ADCS\input\root-ca.crt`

Relancer alors:
```powershell
.\run-on-windows.ps1
```

## Captures requises
- ouverture PowerShell en administrateur;
- generation de la CSR du sous-CA;
- import du certificat racine;
- finalisation du service `CertSvc`;
- generation de la CSR TLS;
- verification du certificat TLS;
- contenu du rapport Markdown final.

## Checklist finale
- [ ] ADCS installe en mode Standalone Subordinate CA.
- [ ] CSR du sous-CA generee.
- [ ] Certificat racine importe dans `Trusted Root Certification Authorities`.
- [ ] Certificat signe du sous-CA copie dans `C:\TP-Crypto-ADCS\input`.
- [ ] Sous-CA finalisee et service `CertSvc` actif.
- [ ] CSR TLS generee.
- [ ] Certificat TLS emis ou demande en attente traitee.
- [ ] Rapport `C:\TP-Crypto-ADCS\RAPPORT-WINDOWS-ADCS.md` produit.
