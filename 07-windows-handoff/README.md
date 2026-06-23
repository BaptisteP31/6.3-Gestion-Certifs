# Windows Handoff

Ce document décrit les étapes à prévoir pour la partie Windows du TP.

Il s’agit d’une procédure de préparation et d’exploitation, pas d’un compte rendu d’exécution.

Variables à adapter :

- `[TRI]` : trigramme du TP
- `HSM_Root_CA_[TRI]` : autorité racine signant la chaîne
- `HSM_Sub_CA_[TRI]` : autorité subordonnée Windows
- `TLS_[TRI]` : certificat TLS final

## À exécuter sur Windows Server

### 1. Importer la chaîne de certification pour qu’un certificat apparaisse valide

Importer la racine dans le magasin de confiance et la subordonnée dans le magasin des autorités intermédiaires.

#### Méthode MMC

1. Ouvrir `mmc.exe`.
2. Ajouter le composant logiciel enfichable `Certificats`.
3. Choisir `Compte d’ordinateur` puis `Ordinateur local`.
4. Importer le certificat racine dans `Autorités de certification racines de confiance`.
5. Importer le certificat subordonné dans `Autorités de certification intermédiaires`.
6. Vérifier ensuite la chaîne dans les détails du certificat.

#### Méthode PowerShell / certutil

```powershell
Import-Certificate -FilePath C:\PKI\HSM_Root_CA_[TRI].cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath C:\PKI\HSM_Sub_CA_[TRI].cer  -CertStoreLocation Cert:\LocalMachine\CA
```

Ou en ligne de commande :

```powershell
certutil -addstore Root C:\PKI\HSM_Root_CA_[TRI].cer
certutil -addstore CA   C:\PKI\HSM_Sub_CA_[TRI].cer
```

### 2. Installer ADCS en mode Standalone

Installer d’abord le rôle, puis lancer la configuration en mode `StandaloneSubordinateCA`.

```powershell
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
```

Procédure PowerShell indicative pour une AC subordonnée autonome :

```powershell
Install-AdcsCertificationAuthority `
  -CAType StandaloneSubordinateCA `
  -CACommonName "HSM_Sub_CA_[TRI]" `
  -KeyLength 4096 `
  -HashAlgorithmName SHA256 `
  -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
  -OutputCertRequestFile C:\PKI\HSM_Sub_CA_[TRI].req `
  -ValidityPeriod Years `
  -ValidityPeriodUnits 5
```

Cette configuration génère une requête de certificat pour l’AC subordonnée et laisse l’installation en attente jusqu’au retour du certificat signé.

### 3. Créer une autorité subordonnée ADCS avec clé RSA 4096 bits valable 5 ans

Les paramètres à retenir pour la subordonnée sont :

- type : `StandaloneSubordinateCA`
- algorithme : `RSA`
- taille de clé : `4096 bits`
- hachage : `SHA256`
- durée de validité : `5 ans`
- nom de CA : `HSM_Sub_CA_[TRI]`

Le point important est que la clé privée reste sur Windows Server, tandis que le certificat de l’AC subordonnée est obtenu après signature par `HSM_Root_CA_[TRI]`.

### 4. Générer la CSR PKCS#10 côté Windows

Pour une AC subordonnée ou pour un certificat TLS, la CSR peut être générée avec `certreq` à partir d’un fichier INF.

Exemple pour une demande TLS :

```ini
[Version]
Signature="$Windows NT$"

[NewRequest]
Subject = "CN=TLS_[TRI]"
KeySpec = 1
KeyLength = 4096
Exportable = FALSE
MachineKeySet = TRUE
SMIME = FALSE
PrivateKeyArchive = FALSE
UserProtected = FALSE
UseExistingKeySet = FALSE
RequestType = PKCS10
HashAlgorithm = SHA256
KeyAlgorithm = RSA
KeyUsage = 0xa0

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "dns=TLS_[TRI].local"
_continue_ = "&dns=TLS_[TRI]"

[RequestAttributes]
CertificateTemplate = WebServer
```

Génération :

```powershell
certreq -new C:\PKI\tls.inf C:\PKI\tls.req
```

Pour la CSR de l’AC subordonnée, l’installation ADCS peut déjà produire la requête via `-OutputCertRequestFile`. Si vous préférez une génération explicite, utiliser un fichier INF équivalent avec `RequestType = PKCS10`.

### 5. Transférer la CSR vers Linux

Transférer le fichier `.req` sans le modifier, par exemple :

- `scp`
- partage SMB
- WinSCP
- dossier de transfert monté temporairement

Exemple :

```powershell
scp C:\PKI\HSM_Sub_CA_[TRI].req user@linux:/tmp/
scp C:\PKI\tls.req user@linux:/tmp/
```

Si un contrôle d’intégrité est souhaité, conserver aussi un hachage du fichier avant transfert.

## À exécuter sur Linux

### 6. Signer la CSR par `HSM_Root_CA_[TRI]`

La CSR Windows est envoyée vers la machine Linux où réside la racine `HSM_Root_CA_[TRI]`.

Procédure attendue :

1. Ouvrir la CSR reçue.
2. Vérifier le sujet, les SAN et la durée demandée.
3. Signer avec la configuration de la racine `HSM_Root_CA_[TRI]`.
4. Produire un certificat `.cer` ou `.crt` correspondant.

Exemple conceptuel :

```bash
openssl ca \
  -config /chemin/vers/hsm_root_ca_[tri].cnf \
  -extensions v3_subca \
  -days 1825 \
  -in HSM_Sub_CA_[TRI].req \
  -out HSM_Sub_CA_[TRI].cer
```

Pour un HSM, la clé privée de la racine doit rester dans le module matériel et la commande doit utiliser la méthode d’accès prévue par la configuration du TP.

### 7. Retourner le certificat signé vers Windows

Après signature côté Linux, récupérer le fichier `.cer` vers Windows Server.

Exemple :

```powershell
scp user@linux:/tmp/HSM_Sub_CA_[TRI].cer C:\PKI\
scp user@linux:/tmp/TLS_[TRI].cer        C:\PKI\
```

Pour l’AC subordonnée, le certificat signé doit correspondre exactement à la clé privée déjà présente sur Windows.

### 8. Finaliser l’autorité subordonnée ADCS

Une fois le certificat de l’AC reçu, l’importer pour terminer l’installation.

```powershell
certreq -accept C:\PKI\HSM_Sub_CA_[TRI].cer
```

Selon le contexte, vérifier ensuite :

```powershell
Get-Service CertSvc
certutil -config "NomServeur\HSM_Sub_CA_[TRI]" -ping
```

L’AC doit alors apparaître comme configurée et opérationnelle dans la console `certsrv.msc`.

### 9. Créer une requête de certificat TLS avec certreq

Pour le certificat TLS final, préparer un fichier INF avec :

- le sujet `CN=...`
- les SAN `DNS=...`
- `RequestType = PKCS10`
- `KeyLength = 4096`
- `HashAlgorithm = SHA256`
- l’usage serveur TLS via le modèle ou les attributs appropriés

Exemple de génération :

```powershell
certreq -new C:\PKI\tls.inf C:\PKI\tls.req
```

### 10. Signer avec certutil

Dans un flux ADCS Windows, `certutil` peut servir à soumettre la requête à la CA puis à récupérer le certificat émis. La signature elle-même reste effectuée par la CA.

Workflow indicatif :

```powershell
certutil -config "NomServeur\HSM_Sub_CA_[TRI]" -submit C:\PKI\tls.req C:\PKI\tls.cer
```

Si la CA est configurée avec approbation manuelle, la demande peut rester en attente. Dans ce cas :

1. Issuer la demande depuis `certsrv.msc` ou l’outil d’administration de la CA.
2. Récupérer ensuite le certificat émis.

Le point à conserver dans le TP est que la signature doit être attribuée à l’AC subordonnée Windows, pas à la racine Linux.

## Captures d’écran nécessaires

- rôle ADCS installé
- autorité subordonnée configurée
- certificat racine installé
- certificat subordonné valide
- certificat TLS émis
- chaîne de certification visible dans Windows

## Contrôles utiles

Les contrôles suivants peuvent servir à valider la cohérence de la chaîne :

```powershell
certutil -store Root
certutil -store CA
certutil -store My
```

Dans la console graphique, vérifier :

- `certlm.msc` pour les magasins locaux
- `certsrv.msc` pour l’état de la CA
- l’onglet `Certification Path` d’un certificat pour la chaîne complète
