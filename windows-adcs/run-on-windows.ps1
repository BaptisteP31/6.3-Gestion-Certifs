#requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<##
  TP Cryptographie - Automatisation Windows ADCS
  Cible : Windows Server 2019 / 2022
  Notes : le script automatise au maximum, mais certaines etapes restent manuelles
  car elles dependennt d'une signature externe cote Linux/OpenSSL/SoftHSM2.
##>

$WorkDir = "C:\TP-Crypto-ADCS"
$CACommonName = "Sub_ADCS_CA_APV"
$CAValidityYears = 5
$KeyLength = 4096
$HashAlgorithm = "SHA256"
$RootCACertPath = "$WorkDir\input\root-ca.crt"
$SubCACertSignedPath = "$WorkDir\input\sub-adcs-ca-signed.crt"
$SubCARequestPath = "$WorkDir\output\sub-adcs-ca.req"
$WebCertSubject = "CN=www.tp-crypto.local"
$WebCertDnsName = "www.tp-crypto.local"
$WebCertRequestPath = "$WorkDir\output\web-tls.req"
$WebCertPath = "$WorkDir\output\web-tls.cer"

$script:LogRoot = Join-Path $WorkDir 'logs'
$script:OutputRoot = Join-Path $WorkDir 'output'
$script:InputRoot = Join-Path $WorkDir 'input'
$script:ManualRoot = Join-Path $WorkDir 'captures-a-faire'
$script:ExecutedCommands = New-Object System.Collections.Generic.List[string]
$script:CAConfig = $null
$script:CAReady = $false
$script:WebCertIssued = $false
$script:TranscriptPath = $null

function Write-StepLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$LogPath = $null,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($LogPath) {
        Add-Content -Path $LogPath -Value $line
    }
}

function Add-ExecutedCommand {
    param([Parameter(Mandatory)][string]$CommandText)
    [void]$script:ExecutedCommands.Add($CommandText)
}

function New-StepLogPath {
    param([Parameter(Mandatory)][string]$StepName)
    $safe = ($StepName -replace '[^a-zA-Z0-9_-]', '_')
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path $script:LogRoot "$safe-$stamp.txt"
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)][string]$StepName,
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $logPath = New-StepLogPath -StepName $StepName
    $cmdText = "$FilePath " + ($Arguments -join ' ')
    Add-ExecutedCommand -CommandText $cmdText
    Write-StepLog -Message "Commande: $cmdText" -LogPath $logPath

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Add-Content -Path $logPath -Value ($line | Out-String).TrimEnd() }
    Write-StepLog -Message "Code de sortie: $exitCode" -LogPath $logPath
    if (-not $AllowFailure -and $exitCode -ne 0) { throw "Echec de la commande: $cmdText (code $exitCode)" }

    [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String); LogPath = $logPath }
}

function Get-CertificateThumbprintFromFile {
    param([Parameter(Mandatory)][string]$Path)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $cert.Import($Path)
    return ($cert.Thumbprint -replace '\s','').ToUpperInvariant()
}

function Test-CertificateInStore {
    param([Parameter(Mandatory)][string]$StorePath,[Parameter(Mandatory)][string]$Thumbprint)
    $found = Get-ChildItem -Path $StorePath -ErrorAction SilentlyContinue | Where-Object { ($_.Thumbprint -replace '\s','').ToUpperInvariant() -eq $Thumbprint }
    return [bool]$found
}

function Get-CARegistryPath { "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CACommonName" }

function Get-CAConfigString {
    if ($script:CAConfig) { return $script:CAConfig }
    $script:CAConfig = "$env:COMPUTERNAME\$CACommonName"
    return $script:CAConfig
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Le script doit etre execute en tant qu''administrateur.' }
    Write-StepLog -Message 'Verification administrateur OK.'
}

function Initialize-Workspace {
    Write-StepLog -Message "Initialisation de l'espace de travail: $WorkDir"
    foreach ($dir in @($WorkDir, $InputRoot, $OutputRoot, $LogRoot, $ManualRoot)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
            Write-StepLog -Message "Dossier cree: $dir"
        } else {
            Write-StepLog -Message "Dossier deja present: $dir"
        }
    }

    $manualPath = Join-Path $WorkDir 'README-ACTIONS-MANUELLES.txt'
    $manualText = @"
TP Cryptographie - Actions manuelles Windows ADCS

Etat attendu:
- Le sous-CA Windows est une CA subordonnee autonome (Standalone Subordinate CA).
- La CSR du sous-CA est generee dans:
  $SubCARequestPath
- Le certificat signe cote Linux doit etre place dans:
  $SubCACertSignedPath
- Le certificat racine Linux/OpenSSL doit etre place dans:
  $RootCACertPath

Actions manuelles possibles:
1. Copier la CSR Windows vers Linux.
2. Signer la CSR avec l'autorite racine OpenSSL/SoftHSM2.
3. Copier le certificat signe vers le dossier input Windows.
4. Relancer le script pour finaliser l'installation du sous-CA.
5. Approuver/emettre la demande TLS si la CA la laisse en attente.

Preuves a capturer:
- Affichage de la CSR subordonne.
- Import du certificat racine dans Root.
- Etat du service CertSvc.
- Dump et verification du certificat TLS.
"@
    Set-Content -Path $manualPath -Value $manualText -Encoding UTF8

    if (-not $script:TranscriptPath) {
        $script:TranscriptPath = Join-Path $LogRoot ("transcript-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
    }
}

function Install-ADCSRole {
    Import-Module ServerManager -ErrorAction Stop
    $feature = Get-WindowsFeature -Name ADCS-Cert-Authority
    if ($feature.Installed) {
        Write-StepLog -Message 'Role ADCS-Cert-Authority deja installe.' -Level 'SUCCESS'
        Add-ExecutedCommand -CommandText 'Get-WindowsFeature ADCS-Cert-Authority'
        return
    }

    Add-ExecutedCommand -CommandText 'Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools'
    $result = Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools -ErrorAction Stop
    $logPath = New-StepLogPath -StepName 'install-adcs-role'
    $result | Format-List * | Out-String | Set-Content -Path $logPath -Encoding UTF8
    Write-StepLog -Message "Role ADCS installe. Details: $logPath" -Level 'SUCCESS' -LogPath $logPath
}

function Create-SubCARequest {
    Write-StepLog -Message 'Creation / verification de la requete CSR du sous-CA.'
    $caReg = Get-CARegistryPath
    if ((Test-Path $caReg) -and (Test-Path $SubCARequestPath)) {
        Write-StepLog -Message "Le sous-CA semble deja initialise et la requete existe: $SubCARequestPath" -Level 'SUCCESS'
        return
    }
    if (Test-Path $SubCARequestPath) {
        Write-StepLog -Message "La CSR existe deja: $SubCARequestPath" -Level 'SUCCESS'
        return
    }

    $params = @{
        CAType               = 'StandaloneSubordinateCA'
        CACommonName         = $CACommonName
        CryptoProviderName   = 'RSA#Microsoft Software Key Storage Provider'
        KeyLength            = $KeyLength
        HashAlgorithmName    = $HashAlgorithm
        ValidityPeriod       = 'Years'
        ValidityPeriodUnits  = $CAValidityYears
        OutputCertRequestFile = $SubCARequestPath
        Force                = $true
    }
    Add-ExecutedCommand -CommandText ("Install-AdcsCertificationAuthority " + (($params.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' '))
    Import-Module ADCSDeployment -ErrorAction Stop
    Install-AdcsCertificationAuthority @params | Out-Null

    if (-not (Test-Path $SubCARequestPath)) { throw "La requete CSR attendue n'a pas ete generee: $SubCARequestPath" }
    Write-StepLog -Message "CSR du sous-CA creee: $SubCARequestPath" -Level 'SUCCESS'
    Write-StepLog -Message 'Etape manuelle: transferer cette CSR vers Linux pour signature par la racine OpenSSL/SoftHSM2.'
}

function Import-RootCACertificate {
    if (-not (Test-Path $RootCACertPath)) {
        Write-StepLog -Message "Certificat racine absent. Placez-le ici puis relancez: $RootCACertPath" -Level 'WARN'
        return
    }

    $thumb = Get-CertificateThumbprintFromFile -Path $RootCACertPath
    if (Test-CertificateInStore -StorePath 'Cert:\LocalMachine\Root' -Thumbprint $thumb) {
        Write-StepLog -Message 'Le certificat racine est deja present dans Root.' -Level 'SUCCESS'
    } else {
        Invoke-LoggedCommand -StepName 'import-root-cert' -FilePath 'certutil.exe' -Arguments @('-addstore','Root',$RootCACertPath) | Out-Null
    }

    $storeDump = Invoke-LoggedCommand -StepName 'root-store-dump' -FilePath 'certutil.exe' -Arguments @('-store','Root') -AllowFailure
    Set-Content -Path (Join-Path $LogRoot 'root-store.txt') -Value $storeDump.Output -Encoding UTF8
}

function Complete-SubCAInstallation {
    if (-not (Test-Path $SubCACertSignedPath)) {
        Write-Host "A faire : signer la CSR sur Linux, puis placer le certificat signe ici : $SubCACertSignedPath"
        Write-StepLog -Message "Certificat signe absent. Finalisation de l'AC subordonnee repoussee." -Level 'WARN'
        return $false
    }

    $caReg = Get-CARegistryPath
    if (-not (Test-Path $caReg)) {
        Write-StepLog -Message "La configuration ADCS n'existe pas encore. Generer la CSR avant cette etape." -Level 'WARN'
        return $false
    }

    if (-not (Test-CertificateInStore -StorePath 'Cert:\LocalMachine\CA' -Thumbprint (Get-CertificateThumbprintFromFile -Path $SubCACertSignedPath))) {
        $svc = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { Stop-Service -Name CertSvc -Force -ErrorAction SilentlyContinue }
        Invoke-LoggedCommand -StepName 'install-subca-cert' -FilePath 'certutil.exe' -Arguments @('-installCert',$SubCACertSignedPath) | Out-Null
        Invoke-LoggedCommand -StepName 'add-subca-store' -FilePath 'certutil.exe' -Arguments @('-addstore','CA',$SubCACertSignedPath) | Out-Null
    }

    Start-Service -Name CertSvc -ErrorAction Stop
    Start-Sleep -Seconds 3
    $svcState = Get-Service -Name CertSvc
    $svcLog = Join-Path $LogRoot 'certsvc-status.txt'
    @(
        "Nom: $($svcState.Name)"
        "Etat: $($svcState.Status)"
        "Affichage: $($svcState.DisplayName)"
        "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content -Path $svcLog -Encoding UTF8

    $script:CAReady = $true
    $script:CAConfig = Get-CAConfigString
    Write-StepLog -Message "Sous-CA finalise. Configuration courante: $script:CAConfig" -Level 'SUCCESS'
    return $true
}

function Configure-CAValidity {
    $caReg = Get-CARegistryPath
    if (-not (Test-Path $caReg)) {
        Write-StepLog -Message "Impossible de configurer la validite: la CA n'est pas encore initialisee." -Level 'WARN'
        return
    }

    $desired = @{ ValidityPeriod = 'Years'; ValidityPeriodUnits = $CAValidityYears; CRLPeriod = 'Weeks'; CRLPeriodUnits = 1 }
    foreach ($k in $desired.Keys) {
        $cmd = "certutil -setreg ca\$k $($desired[$k])"
        Add-ExecutedCommand -CommandText $cmd
        Invoke-LoggedCommand -StepName "setreg-$k" -FilePath 'certutil.exe' -Arguments @('-setreg',"ca\$k","$($desired[$k])") | Out-Null
    }

    Restart-Service -Name CertSvc -Force -ErrorAction Stop
    Write-StepLog -Message 'Service CertSvc redemarre apres configuration.' -Level 'SUCCESS'
}

function Create-WebTLSRequest {
    $infPath = Join-Path $OutputRoot 'web-tls.inf'
    $infContent = @"
[Version]
Signature=`"`$Windows NT`$`"

[NewRequest]
Subject = $WebCertSubject
KeyLength = 3072
KeySpec = 1
KeyUsage = 0xa0
MachineKeySet = TRUE
Exportable = FALSE
ProviderName = Microsoft RSA SChannel Cryptographic Provider
ProviderType = 12
RequestType = PKCS10
HashAlgorithm = SHA256

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "DNS=$WebCertDnsName"
"@
    Set-Content -Path $infPath -Value $infContent -Encoding ASCII

    if (-not (Test-Path $WebCertRequestPath)) {
        Invoke-LoggedCommand -StepName 'create-web-csr' -FilePath 'certreq.exe' -Arguments @('-new',$infPath,$WebCertRequestPath) | Out-Null
    }
}

function Submit-And-Issue-WebTLSCertificate {
    if (-not $script:CAReady) {
        Write-StepLog -Message "Le sous-CA n'est pas encore operationnel. La demande web sera conservee pour plus tard." -Level 'WARN'
        return $false
    }
    if (-not (Test-Path $WebCertRequestPath)) {
        Write-StepLog -Message "CSR web absente: $WebCertRequestPath" -Level 'WARN'
        return $false
    }
    if (Test-Path $WebCertPath) {
        Write-StepLog -Message "Certificat web deja present: $WebCertPath" -Level 'SUCCESS'
        $script:WebCertIssued = $true
        return $true
    }

    $caConfig = Get-CAConfigString
    $submitRes = Invoke-LoggedCommand -StepName 'submit-web-csr' -FilePath 'certreq.exe' -Arguments @('-submit','-config',$caConfig,$WebCertRequestPath,$WebCertPath) -AllowFailure
    if (Test-Path $WebCertPath) {
        Invoke-LoggedCommand -StepName 'accept-web-cert' -FilePath 'certreq.exe' -Arguments @('-accept',$WebCertPath) -AllowFailure | Out-Null
        $script:WebCertIssued = $true
        return $true
    }

    Write-StepLog -Message "La demande web n'a pas ete emise automatiquement. Voir le journal: $($submitRes.LogPath)" -Level 'WARN'
    return $false
}

function Verify-WebCertificate {
    if (-not (Test-Path $WebCertPath)) {
        Write-StepLog -Message "Certificat web absent, verification sautee: $WebCertPath" -Level 'WARN'
        return
    }

    $dumpRes = Invoke-LoggedCommand -StepName 'web-cert-dump' -FilePath 'certutil.exe' -Arguments @('-dump',$WebCertPath) -AllowFailure
    Set-Content -Path (Join-Path $LogRoot 'web-cert-dump.txt') -Value $dumpRes.Output -Encoding UTF8

    $verifyRes = Invoke-LoggedCommand -StepName 'web-cert-verify' -FilePath 'certutil.exe' -Arguments @('-verify',$WebCertPath) -AllowFailure
    Set-Content -Path (Join-Path $LogRoot 'web-cert-verify.txt') -Value $verifyRes.Output -Encoding UTF8
}

function Export-Evidence {
    $reportPath = Join-Path $WorkDir 'RAPPORT-WINDOWS-ADCS.md'
    $files = @($RootCACertPath,$SubCACertSignedPath,$SubCARequestPath,$WebCertRequestPath,$WebCertPath,(Join-Path $WorkDir 'README-ACTIONS-MANUELLES.txt'),(Join-Path $LogRoot 'root-store.txt'),(Join-Path $LogRoot 'certsvc-status.txt'),(Join-Path $LogRoot 'web-cert-dump.txt'),(Join-Path $LogRoot 'web-cert-verify.txt'),$script:TranscriptPath) | Where-Object { $_ -and (Test-Path $_) }
    $statusLines = @(
        '# Rapport Windows ADCS','', '## Etat d''avancement',
        "- Sous-CA prepare: $(if (Test-Path $SubCARequestPath) { 'oui' } else { 'non' })",
        "- Certificat racine importe: $(if (Test-Path $RootCACertPath) { 'fichier present' } else { 'a importer' })",
        "- Sous-CA finalisee: $(if ($script:CAReady) { 'oui' } else { 'non' })",
        "- Certificat web emis: $(if ($script:WebCertIssued) { 'oui' } else { 'non' })",
        '', '## Commandes executees'
    )
    foreach ($cmd in $script:ExecutedCommands) { $statusLines += "- `$cmd`" }
    $statusLines += ''; $statusLines += '## Fichiers produits'
    foreach ($f in $files) { $statusLines += "- [$([IO.Path]::GetFileName($f))]($f)" }
    $statusLines += ''; $statusLines += '## Captures d''ecran a faire'; $statusLines += '- Lancement du script en administrateur.'; $statusLines += '- Presence de la CSR du sous-CA.'; $statusLines += '- Import du certificat racine dans Root.'; $statusLines += '- Etat du service CertSvc.'; $statusLines += '- Dump et verification du certificat TLS.'
    $statusLines += ''; $statusLines += '## Points a completer cote Linux'; $statusLines += '- Signer la CSR du sous-CA Windows avec l''AC racine OpenSSL/SoftHSM2.'; $statusLines += "- Copier le certificat signe dans: $SubCACertSignedPath"; $statusLines += "- Copier le certificat racine dans: $RootCACertPath"
    $statusLines += ''; $statusLines += '## Preuves certutil importantes'; $statusLines += "- `certutil -store Root`"; $statusLines += "- `certutil -dump $WebCertPath`"; $statusLines += "- `certutil -verify $WebCertPath`"
    Set-Content -Path $reportPath -Value ($statusLines -join [Environment]::NewLine) -Encoding UTF8
}

function Print-NextSteps {
    Write-Host ''
    Write-Host 'Prochaines actions:'
    Write-Host "1. Recuperer la CSR du sous-CA ici : $SubCARequestPath"
    Write-Host '2. La signer cote Linux/OpenSSL/SoftHSM2.'
    Write-Host "3. Placer le certificat signe ici : $SubCACertSignedPath"
    Write-Host '4. Relancer ce script pour finaliser le sous-CA.'
    Write-Host "5. Faire les captures demandees dans : $ManualRoot"
    Write-Host "6. Revoir le rapport final ici : $(Join-Path $WorkDir 'RAPPORT-WINDOWS-ADCS.md')"
}

function Main {
    try {
        Assert-Administrator
        Initialize-Workspace
        Install-ADCSRole
        Create-SubCARequest
        Import-RootCACertificate
        $script:CAReady = Complete-SubCAInstallation
        if ($script:CAReady) {
            Configure-CAValidity
            Create-WebTLSRequest
            [void](Submit-And-Issue-WebTLSCertificate)
            Verify-WebCertificate
        }
        else {
            Write-StepLog -Message "Le sous-CA n'est pas complet. Les etapes web seront traitees au prochain passage." -Level 'WARN'
        }
        Export-Evidence
        Print-NextSteps
    }
    catch {
        Write-StepLog -Message "Arret propre du script: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
    finally {
        if ($script:TranscriptPath) {
            try { Stop-Transcript | Out-Null } catch { }
        }
    }
}

Main