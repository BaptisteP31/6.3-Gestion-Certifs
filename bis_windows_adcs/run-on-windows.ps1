#requires -RunAsAdministrator
param(
    [switch]$ResetADCS
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

<#
TP Cryptographie - Windows Server ADCS
But : creer une CA subordonnee autonome ADCS, generer sa CSR,
finaliser la CA apres signature Linux, puis emettre un certificat TLS de test.

Important :
- Script prevu pour Windows Server 2019/2022.
- Lancer dans PowerShell en administrateur.
- Ne pas exporter de cle privee.
- Les noms de CA ADCS utilisent des tirets, pas des underscores, pour eviter
  les erreurs d'encodage ASN.1 / Unicode d'ADCS.
#>

$WorkDir = "C:\TP-Crypto-ADCS"
$CACommonName = "Sub-ADCS-CA-APV"
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

$IssuedCertValidityYears = 1
$DatabaseDir = "$WorkDir\db"
$CertLogDir = "$WorkDir\certlog"
$LogRoot = "$WorkDir\logs"
$OutputRoot = "$WorkDir\output"
$InputRoot = "$WorkDir\input"
$ManualRoot = "$WorkDir\captures-a-faire"
$TranscriptPath = $null
$ExecutedCommands = New-Object System.Collections.Generic.List[string]
$CAReady = $false
$WebCertIssued = $false
$StopAfterReport = $false

function Write-StepLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO",
        [string]$LogPath = ""
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    if ($LogPath -ne "") {
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    }
}

function Add-ExecutedCommand {
    param([Parameter(Mandatory = $true)][string]$CommandText)
    [void]$ExecutedCommands.Add($CommandText)
}

function New-StepLogPath {
    param([Parameter(Mandatory = $true)][string]$StepName)
    if (-not (Test-Path $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }
    $safe = $StepName -replace "[^a-zA-Z0-9_-]", "_"
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return Join-Path $LogRoot "$safe-$stamp.txt"
}

function Invoke-LoggedExe {
    param(
        [Parameter(Mandatory = $true)][string]$StepName,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $logPath = New-StepLogPath -StepName $StepName
    $cmdText = "$FilePath " + ($Arguments -join " ")
    Add-ExecutedCommand -CommandText $cmdText
    Write-StepLog -Message "Commande: $cmdText" -LogPath $logPath

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $textOutput = $output | Out-String
    Add-Content -Path $logPath -Value $textOutput -Encoding UTF8
    Write-StepLog -Message "Code de sortie: $exitCode" -LogPath $logPath

    if ((-not $AllowFailure) -and ($exitCode -ne 0)) {
        throw "Echec de la commande: $cmdText. Voir: $logPath"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $textOutput
        LogPath = $logPath
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "Le script doit etre lance dans PowerShell en administrateur."
    }
    Write-StepLog -Message "Verification administrateur OK."
}

function Initialize-Workspace {
    Write-StepLog -Message "Initialisation de l'espace de travail: $WorkDir"
    foreach ($dir in @($WorkDir, $InputRoot, $OutputRoot, $LogRoot, $ManualRoot, $DatabaseDir, $CertLogDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-StepLog -Message "Dossier cree: $dir"
        }
        else {
            Write-StepLog -Message "Dossier deja present: $dir"
        }
    }

    $readmePath = Join-Path $WorkDir "README-ACTIONS-MANUELLES.txt"
    $manualText = @"
TP Cryptographie - Actions manuelles ADCS

Fichiers attendus:
- CSR Windows a signer sur Linux:
  $SubCARequestPath
- Certificat signe a remettre cote Windows:
  $SubCACertSignedPath
- Certificat racine Linux/OpenSSL a remettre cote Windows:
  $RootCACertPath

Deroulement normal:
1. Premier lancement du script Windows: installation ADCS et generation de la CSR.
2. Copier la CSR vers Linux.
3. Signer la CSR avec la racine OpenSSL / SoftHSM2.
4. Copier root-ca.crt et sub-adcs-ca-signed.crt dans C:\TP-Crypto-ADCS\input.
5. Relancer le script Windows pour finaliser la CA subordonnee.
6. Generer puis emettre le certificat TLS de test.

Captures utiles:
- PowerShell admin avec lancement du script.
- Presence de C:\TP-Crypto-ADCS\output\sub-adcs-ca.req.
- Import du certificat racine dans le magasin Root.
- Service CertSvc en Running.
- certutil -dump du certificat TLS.
- certutil -verify du certificat TLS.
"@
    Set-Content -Path $readmePath -Value $manualText -Encoding UTF8

    if ($null -eq $TranscriptPath) {
        $script:TranscriptPath = Join-Path $LogRoot ("transcript-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
        Start-Transcript -Path $TranscriptPath -Force | Out-Null
    }
}

function Get-CAConfigRoot {
    return "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration"
}

function Get-CARegistryPath {
    return (Join-Path (Get-CAConfigRoot) $CACommonName)
}

function Get-ExistingCAConfigNames {
    $root = Get-CAConfigRoot
    if (-not (Test-Path $root)) {
        return @()
    }
    $items = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
    if ($null -eq $items) {
        return @()
    }
    return @($items | Select-Object -ExpandProperty PSChildName)
}

function Get-CAConfigString {
    return "$env:COMPUTERNAME\$CACommonName"
}

function Reset-ADCSStateForTP {
    Write-StepLog -Message "Nettoyage ADCS demande par -ResetADCS." -Level "WARN"

    Stop-Service -Name CertSvc -Force -ErrorAction SilentlyContinue

    try {
        Import-Module ADCSDeployment -ErrorAction Stop
        Add-ExecutedCommand -CommandText "Uninstall-AdcsCertificationAuthority -Force"
        Uninstall-AdcsCertificationAuthority -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-StepLog -Message "Uninstall-AdcsCertificationAuthority ignore: $($_.Exception.Message)" -Level "WARN"
    }

    try {
        Import-Module ServerManager -ErrorAction Stop
        $feature = Get-WindowsFeature -Name ADCS-Cert-Authority
        if ($feature.Installed) {
            Add-ExecutedCommand -CommandText "Remove-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools"
            $removeResult = Remove-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
            $logPath = New-StepLogPath -StepName "remove-adcs-role"
            $removeResult | Format-List * | Out-String | Set-Content -Path $logPath -Encoding UTF8
            Write-StepLog -Message "Role ADCS retire. Details: $logPath" -Level "SUCCESS"
        }
    }
    catch {
        Write-StepLog -Message "Remove-WindowsFeature ignore: $($_.Exception.Message)" -Level "WARN"
    }

    foreach ($path in @(
        $WorkDir,
        "C:\Windows\System32\CertLog",
        "C:\Windows\System32\CertSrv\CertEnroll",
        (Get-CAConfigRoot)
    )) {
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-StepLog -Message "Suppression ignoree pour $path : $($_.Exception.Message)" -Level "WARN"
        }
    }

    Write-StepLog -Message "Nettoyage termine. Le script va recreer le dossier de travail et reinstaller le role si possible." -Level "SUCCESS"
}

function Install-ADCSRole {
    Import-Module ServerManager -ErrorAction Stop
    $feature = Get-WindowsFeature -Name ADCS-Cert-Authority

    if ($feature.Installed) {
        Write-StepLog -Message "Role ADCS-Cert-Authority deja installe." -Level "SUCCESS"
        Add-ExecutedCommand -CommandText "Get-WindowsFeature ADCS-Cert-Authority"
        return
    }

    Add-ExecutedCommand -CommandText "Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools"
    $result = Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools
    $logPath = New-StepLogPath -StepName "install-adcs-role"
    $result | Format-List * | Out-String | Set-Content -Path $logPath -Encoding UTF8
    Write-StepLog -Message "Role ADCS installe. Details: $logPath" -Level "SUCCESS"

    if ($result.RestartNeeded -ne "No") {
        Write-StepLog -Message "Un redemarrage est conseille par Windows. Si une erreur apparait ensuite, redemarrez puis relancez." -Level "WARN"
    }
}

function Create-SubCARequest {
    Write-StepLog -Message "Creation ou verification de la CSR du sous-CA."

    $existing = Get-ExistingCAConfigNames
    if (($existing.Count -gt 0) -and (-not (Test-Path (Get-CARegistryPath)))) {
        Write-StepLog -Message "Une autre configuration ADCS existe deja: $($existing -join ', ')." -Level "WARN"
        Write-StepLog -Message "Pour une VM de TP, relancez: .\run-on-windows.ps1 -ResetADCS" -Level "WARN"
        $script:StopAfterReport = $true
        return
    }

    if (Test-Path $SubCARequestPath) {
        Write-StepLog -Message "CSR deja presente: $SubCARequestPath" -Level "SUCCESS"
        return
    }

    if (Test-Path (Get-CARegistryPath)) {
        Write-StepLog -Message "ADCS semble deja initialise mais la CSR attendue est absente." -Level "WARN"
        Write-StepLog -Message "Relancez avec -ResetADCS sur une VM de TP, ou restaurez la CSR manquante." -Level "WARN"
        $script:StopAfterReport = $true
        return
    }

    Import-Module ADCSDeployment -ErrorAction Stop

    $params = @{
        CAType                = "StandaloneSubordinateCA"
        CACommonName          = $CACommonName
        CADistinguishedNameSuffix = "O=TP Crypto, C=FR"
        CryptoProviderName    = "RSA#Microsoft Software Key Storage Provider"
        KeyLength             = $KeyLength
        HashAlgorithmName     = $HashAlgorithm
        OutputCertRequestFile = $SubCARequestPath
        DatabaseDirectory     = $DatabaseDir
        LogDirectory          = $CertLogDir
        Force                 = $true
        IgnoreUnicode         = $true
    }

    Add-ExecutedCommand -CommandText "Install-AdcsCertificationAuthority -CAType StandaloneSubordinateCA -CACommonName $CACommonName -KeyLength $KeyLength -HashAlgorithmName $HashAlgorithm -OutputCertRequestFile $SubCARequestPath -IgnoreUnicode -Force"

    try {
        Install-AdcsCertificationAuthority @params | Out-Null
    }
    catch {
        $msg = $_.Exception.Message
        Write-StepLog -Message "Echec de creation de la CSR ADCS: $msg" -Level "ERROR"
        Write-StepLog -Message "Cause frequente: ancienne configuration ADCS partielle. Sur VM de TP, lancez: .\run-on-windows.ps1 -ResetADCS" -Level "WARN"
        throw
    }

    if (-not (Test-Path $SubCARequestPath)) {
        throw "La CSR attendue n'a pas ete generee: $SubCARequestPath"
    }

    Write-StepLog -Message "CSR du sous-CA creee: $SubCARequestPath" -Level "SUCCESS"
    Write-StepLog -Message "Etape suivante: signer cette CSR cote Linux/OpenSSL/SoftHSM2." -Level "WARN"
}

function Get-CertificateThumbprintFromFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $cert.Import($Path)
    return (($cert.Thumbprint -replace "\s", "").ToUpperInvariant())
}

function Test-CertificateInStore {
    param(
        [Parameter(Mandatory = $true)][string]$StorePath,
        [Parameter(Mandatory = $true)][string]$Thumbprint
    )

    $found = Get-ChildItem -Path $StorePath -ErrorAction SilentlyContinue | Where-Object {
        (($_.Thumbprint -replace "\s", "").ToUpperInvariant()) -eq $Thumbprint
    }
    return [bool]$found
}

function Import-RootCACertificate {
    if (-not (Test-Path $RootCACertPath)) {
        Write-StepLog -Message "Certificat racine absent. A placer ici: $RootCACertPath" -Level "WARN"
        return $false
    }

    $thumb = Get-CertificateThumbprintFromFile -Path $RootCACertPath
    if (Test-CertificateInStore -StorePath "Cert:\LocalMachine\Root" -Thumbprint $thumb) {
        Write-StepLog -Message "Certificat racine deja present dans LocalMachine Root." -Level "SUCCESS"
    }
    else {
        Invoke-LoggedExe -StepName "import-root-ca" -FilePath "certutil.exe" -Arguments @("-addstore", "Root", $RootCACertPath) | Out-Null
        Write-StepLog -Message "Certificat racine importe dans LocalMachine Root." -Level "SUCCESS"
    }

    $dump = Invoke-LoggedExe -StepName "root-store-dump" -FilePath "certutil.exe" -Arguments @("-store", "Root") -AllowFailure
    Set-Content -Path (Join-Path $LogRoot "root-store.txt") -Value $dump.Output -Encoding UTF8
    return $true
}

function Complete-SubCAInstallation {
    if (-not (Test-Path $SubCACertSignedPath)) {
        Write-StepLog -Message "Certificat signe du sous-CA absent: $SubCACertSignedPath" -Level "WARN"
        Write-StepLog -Message "C'est normal au premier lancement. Signez la CSR sur Linux puis relancez." -Level "WARN"
        return $false
    }

    if (-not (Test-Path $RootCACertPath)) {
        Write-StepLog -Message "Certificat racine absent: $RootCACertPath" -Level "WARN"
        Write-StepLog -Message "Copiez aussi le certificat racine Linux avant de finaliser ADCS." -Level "WARN"
        return $false
    }

    [void](Import-RootCACertificate)

    Stop-Service -Name CertSvc -Force -ErrorAction SilentlyContinue

    Invoke-LoggedExe -StepName "install-subca-cert" -FilePath "certutil.exe" -Arguments @("-installCert", $SubCACertSignedPath) | Out-Null

    Start-Service -Name CertSvc -ErrorAction Stop
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name CertSvc
    $svc | Format-List * | Out-String | Set-Content -Path (Join-Path $LogRoot "certsvc-status.txt") -Encoding UTF8

    if ($svc.Status -ne "Running") {
        throw "Le service CertSvc n'est pas en cours d'execution apres installation du certificat signe."
    }

    Write-StepLog -Message "Sous-CA finalise et service CertSvc en cours d'execution." -Level "SUCCESS"
    return $true
}

function Configure-CAValidity {
    if (-not $CAReady) {
        Write-StepLog -Message "CA non prete. Configuration de validite sautee." -Level "WARN"
        return
    }

    Invoke-LoggedExe -StepName "set-validity-period" -FilePath "certutil.exe" -Arguments @("-setreg", "CA\ValidityPeriod", "Years") | Out-Null
    Invoke-LoggedExe -StepName "set-validity-units" -FilePath "certutil.exe" -Arguments @("-setreg", "CA\ValidityPeriodUnits", "$IssuedCertValidityYears") | Out-Null
    Invoke-LoggedExe -StepName "set-crl-period" -FilePath "certutil.exe" -Arguments @("-setreg", "CA\CRLPeriod", "Months") | Out-Null
    Invoke-LoggedExe -StepName "set-crl-units" -FilePath "certutil.exe" -Arguments @("-setreg", "CA\CRLPeriodUnits", "1") | Out-Null

    Restart-Service -Name CertSvc -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    Invoke-LoggedExe -StepName "publish-crl" -FilePath "certutil.exe" -Arguments @("-crl") -AllowFailure | Out-Null
    Write-StepLog -Message "Validite des certificats emis configuree a $IssuedCertValidityYears an et CRL a 1 mois." -Level "SUCCESS"
}

function Create-WebTLSRequest {
    $infPath = Join-Path $OutputRoot "web-tls.inf"
    $infContent = @"
[Version]
Signature="`$Windows NT`$"

[NewRequest]
Subject = "$WebCertSubject"
KeyAlgorithm = RSA
KeyLength = 3072
KeySpec = AT_KEYEXCHANGE
KeyUsage = 0xa0
MachineKeySet = TRUE
Exportable = FALSE
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
RequestType = PKCS10
HashAlgorithm = SHA256

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "dns=$WebCertDnsName"

[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.1
"@

    Set-Content -Path $infPath -Value $infContent -Encoding ASCII

    if (Test-Path $WebCertRequestPath) {
        Write-StepLog -Message "CSR TLS deja presente: $WebCertRequestPath" -Level "SUCCESS"
        return
    }

    Invoke-LoggedExe -StepName "create-web-tls-csr" -FilePath "certreq.exe" -Arguments @("-new", $infPath, $WebCertRequestPath) | Out-Null

    if (-not (Test-Path $WebCertRequestPath)) {
        throw "La CSR TLS n'a pas ete generee: $WebCertRequestPath"
    }

    Write-StepLog -Message "CSR TLS creee: $WebCertRequestPath" -Level "SUCCESS"
}

function Get-RequestIdFromText {
    param([string]$Text)

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match "(?i)(RequestId|Request ID|ID de la demande|Id de la demande|ID demande|Demande).*?([0-9]+)") {
            return $Matches[2]
        }
    }

    return $null
}

function Submit-And-Issue-WebTLSCertificate {
    if (-not $CAReady) {
        Write-StepLog -Message "CA non prete. Emission du certificat TLS sautee." -Level "WARN"
        return $false
    }

    if (-not (Test-Path $WebCertRequestPath)) {
        Write-StepLog -Message "CSR TLS absente: $WebCertRequestPath" -Level "WARN"
        return $false
    }

    if (Test-Path $WebCertPath) {
        Write-StepLog -Message "Certificat TLS deja present: $WebCertPath" -Level "SUCCESS"
        return $true
    }

    $caConfig = Get-CAConfigString
    $submit = Invoke-LoggedExe -StepName "submit-web-tls-csr" -FilePath "certreq.exe" -Arguments @("-submit", "-config", $caConfig, $WebCertRequestPath, $WebCertPath) -AllowFailure

    if (Test-Path $WebCertPath) {
        Invoke-LoggedExe -StepName "accept-web-tls-cert" -FilePath "certreq.exe" -Arguments @("-accept", $WebCertPath) -AllowFailure | Out-Null
        Write-StepLog -Message "Certificat TLS emis: $WebCertPath" -Level "SUCCESS"
        return $true
    }

    $requestId = Get-RequestIdFromText -Text $submit.Output
    if ($null -ne $requestId) {
        Write-StepLog -Message "Demande TLS en attente detectee. RequestId=$requestId. Tentative d'emission admin." -Level "WARN"
        Invoke-LoggedExe -StepName "issue-web-tls-request" -FilePath "certutil.exe" -Arguments @("-resubmit", $requestId) -AllowFailure | Out-Null
        Invoke-LoggedExe -StepName "retrieve-web-tls-cert" -FilePath "certreq.exe" -Arguments @("-retrieve", "-config", $caConfig, $requestId, $WebCertPath) -AllowFailure | Out-Null
    }

    if (Test-Path $WebCertPath) {
        Invoke-LoggedExe -StepName "accept-web-tls-cert-after-retrieve" -FilePath "certreq.exe" -Arguments @("-accept", $WebCertPath) -AllowFailure | Out-Null
        Write-StepLog -Message "Certificat TLS emis apres validation de la demande: $WebCertPath" -Level "SUCCESS"
        return $true
    }

    Write-StepLog -Message "Certificat TLS non emis automatiquement. Voir logs: $($submit.LogPath)" -Level "WARN"
    Write-StepLog -Message "Utilisez la console Certification Authority ou certutil -resubmit puis certreq -retrieve." -Level "WARN"
    return $false
}

function Verify-WebCertificate {
    if (-not (Test-Path $WebCertPath)) {
        Write-StepLog -Message "Certificat TLS absent. Verification sautee." -Level "WARN"
        return
    }

    $dump = Invoke-LoggedExe -StepName "web-cert-dump" -FilePath "certutil.exe" -Arguments @("-dump", $WebCertPath) -AllowFailure
    Set-Content -Path (Join-Path $LogRoot "web-cert-dump.txt") -Value $dump.Output -Encoding UTF8

    $verify = Invoke-LoggedExe -StepName "web-cert-verify" -FilePath "certutil.exe" -Arguments @("-verify", $WebCertPath) -AllowFailure
    Set-Content -Path (Join-Path $LogRoot "web-cert-verify.txt") -Value $verify.Output -Encoding UTF8

    Write-StepLog -Message "Verification certutil terminee. Voir logs dans $LogRoot." -Level "SUCCESS"
}

function Export-Evidence {
    $reportPath = Join-Path $WorkDir "RAPPORT-WINDOWS-ADCS.md"
    $caNames = Get-ExistingCAConfigNames
    $files = @(
        $RootCACertPath,
        $SubCACertSignedPath,
        $SubCARequestPath,
        $WebCertRequestPath,
        $WebCertPath,
        (Join-Path $WorkDir "README-ACTIONS-MANUELLES.txt"),
        (Join-Path $LogRoot "root-store.txt"),
        (Join-Path $LogRoot "certsvc-status.txt"),
        (Join-Path $LogRoot "web-cert-dump.txt"),
        (Join-Path $LogRoot "web-cert-verify.txt"),
        $TranscriptPath
    ) | Where-Object { ($null -ne $_) -and (Test-Path $_) }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# Rapport Windows ADCS")
    [void]$lines.Add("")
    [void]$lines.Add("## Parametres")
    [void]$lines.Add("- WorkDir: $WorkDir")
    [void]$lines.Add("- CA ADCS: $CACommonName")
    [void]$lines.Add("- Type: Standalone Subordinate CA")
    [void]$lines.Add("- Cle CA subordonnee: RSA $KeyLength bits")
    [void]$lines.Add("- Hash: $HashAlgorithm")
    [void]$lines.Add("- Validite souhaitee du certificat de CA: $CAValidityYears ans, definie par la racine Linux lors de la signature")
    [void]$lines.Add("- Validite des certificats emis par ADCS: $IssuedCertValidityYears an")
    [void]$lines.Add("")
    [void]$lines.Add("## Etat")
    [void]$lines.Add("- CSR sous-CA presente: $(if (Test-Path $SubCARequestPath) { 'oui' } else { 'non' })")
    [void]$lines.Add("- Certificat racine present: $(if (Test-Path $RootCACertPath) { 'oui' } else { 'non' })")
    [void]$lines.Add("- Certificat sous-CA signe present: $(if (Test-Path $SubCACertSignedPath) { 'oui' } else { 'non' })")
    [void]$lines.Add("- Sous-CA finalisee: $(if ($CAReady) { 'oui' } else { 'non' })")
    [void]$lines.Add("- Certificat TLS emis: $(if ($WebCertIssued) { 'oui' } else { 'non' })")
    [void]$lines.Add("- Configurations ADCS detectees: $(if ($caNames.Count -gt 0) { $caNames -join ', ' } else { 'aucune' })")
    [void]$lines.Add("")
    [void]$lines.Add("## Commandes executees")
    foreach ($cmd in $ExecutedCommands) {
        [void]$lines.Add("- $cmd")
    }
    [void]$lines.Add("")
    [void]$lines.Add("## Fichiers produits")
    foreach ($f in $files) {
        [void]$lines.Add("- $f")
    }
    [void]$lines.Add("")
    [void]$lines.Add("## Captures conseillees")
    [void]$lines.Add("- Lancement du script dans PowerShell administrateur.")
    [void]$lines.Add("- Presence de la CSR du sous-CA dans C:\TP-Crypto-ADCS\output.")
    [void]$lines.Add("- Import du certificat racine dans le magasin Root.")
    [void]$lines.Add("- Etat du service CertSvc.")
    [void]$lines.Add("- Dump du certificat TLS avec certutil -dump.")
    [void]$lines.Add("- Verification du certificat TLS avec certutil -verify.")

    Set-Content -Path $reportPath -Value $lines -Encoding UTF8
    Write-StepLog -Message "Rapport ecrit: $reportPath" -Level "SUCCESS"
}

function Print-NextSteps {
    Write-Host ""
    Write-Host "===== PROCHAINES ETAPES ====="

    if ($StopAfterReport) {
        Write-Host "Une configuration ADCS existante bloque la generation propre."
        Write-Host "Sur une VM de TP, lancez:"
        Write-Host "  .\run-on-windows.ps1 -ResetADCS"
        return
    }

    if (-not (Test-Path $SubCARequestPath)) {
        Write-Host "La CSR du sous-CA n'existe pas encore. Verifiez les logs dans $LogRoot."
        return
    }

    if (-not (Test-Path $SubCACertSignedPath)) {
        Write-Host "1. Copier la CSR vers Linux:"
        Write-Host "   $SubCARequestPath"
        Write-Host "2. La signer avec l'AC racine Linux/OpenSSL/SoftHSM2."
        Write-Host "3. Copier les fichiers suivants cote Windows:"
        Write-Host "   $RootCACertPath"
        Write-Host "   $SubCACertSignedPath"
        Write-Host "4. Relancer ce script:"
        Write-Host "   .\run-on-windows.ps1"
        return
    }

    if ($CAReady -and $WebCertIssued) {
        Write-Host "Tout est termine cote Windows ADCS."
        Write-Host "Rapport: $WorkDir\RAPPORT-WINDOWS-ADCS.md"
        Write-Host "Logs: $LogRoot"
        return
    }

    Write-Host "Consultez le rapport et les logs:"
    Write-Host "  $WorkDir\RAPPORT-WINDOWS-ADCS.md"
    Write-Host "  $LogRoot"
}

function Main {
    try {
        Assert-Administrator

        if ($ResetADCS) {
            Reset-ADCSStateForTP
        }

        Initialize-Workspace
        Install-ADCSRole
        Create-SubCARequest

        if ($StopAfterReport) {
            Export-Evidence
            Print-NextSteps
            return
        }

        [void](Import-RootCACertificate)
        $script:CAReady = Complete-SubCAInstallation

        if ($CAReady) {
            Configure-CAValidity
            Create-WebTLSRequest
            $script:WebCertIssued = Submit-And-Issue-WebTLSCertificate
            Verify-WebCertificate
        }
        else {
            Write-StepLog -Message "Sous-CA non finalisee. Fin normale du premier passage." -Level "WARN"
        }

        Export-Evidence
        Print-NextSteps
    }
    catch {
        Write-StepLog -Message "Arret du script: $($_.Exception.Message)" -Level "ERROR"
        Export-Evidence
        Print-NextSteps
        exit 1
    }
    finally {
        if ($null -ne $TranscriptPath) {
            try { Stop-Transcript | Out-Null } catch { }
        }
    }
}

Main
