# ==============================================================
# Install-GiocastiHub.ps1
#
# Installer iniziale per GIOCASTI HUB:
#  - Verifica il certificato pubblico GIOCASTI_
#  - Installa il certificato in:
#       * Autorita' di certificazione radice attendibili
#       * Autori attendibili
#  - Legge l'ultima release da version.json su GitHub
#  - Scarica lo ZIP
#  - Verifica lo SHA-256 dello ZIP
#  - Usa C:\GIOCASTI HUB anche per i file temporanei dell'installazione
#  - Estrae GIOCASTI HUB.exe in C:\GIOCASTI HUB
#  - Verifica firma Authenticode + thumbprint del firmatario
#  - Crea un collegamento sul Desktop
#
# NOTA:
#  Il certificato pubblico GIOCASTI_ viene scaricato automaticamente
#  dal repository GitHub e verificato tramite thumbprint PRIMA
#  dell'installazione.
#
# Eseguire questo script come Amministratore
#
# ==============================================================

$ErrorActionPreference = "Stop"

# --------------------------------------------------------------
# CONFIGURAZIONE
# --------------------------------------------------------------
$installDir = "C:\GIOCASTI HUB"
$exeName = "GIOCASTI HUB.exe"

$versionUrl = "https://raw.githubusercontent.com/Giocasti/giocasti-hub-updates/main/version.json"
$certUrl    = "https://raw.githubusercontent.com/Giocasti/giocasti-hub-updates/main/GIOCASTI_-CodeSigning.cer"

$expectedCertThumbprint = "22CD8A193E351CA5BBFCC590DA524D18C6DCE1AA"
$certFileName = "GIOCASTI_-CodeSigning.cer"

$tempCert = Join-Path $installDir $certFileName
$tempZip = Join-Path $installDir "GiocastiHub_install.zip"
$tempExtract = Join-Path $installDir "GiocastiHub_install_extract"

# --------------------------------------------------------------
# FUNZIONI
# --------------------------------------------------------------
function Normalize-Thumbprint([string]$Thumbprint)
{
    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        return ""
    }

    return ($Thumbprint -replace '\s', '').ToUpperInvariant()
}

function Test-IsAdministrator
{
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )

    return $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Test-CertificateInstalled([string]$StorePath, [string]$Thumbprint)
{
    $normalized = Normalize-Thumbprint $Thumbprint

    $found = Get-ChildItem -Path $StorePath -ErrorAction SilentlyContinue |
        Where-Object {
            (Normalize-Thumbprint $_.Thumbprint) -eq $normalized
        } |
        Select-Object -First 1

    return ($null -ne $found)
}

# --------------------------------------------------------------
# VERIFICA AMMINISTRATORE
# --------------------------------------------------------------
if (-not (Test-IsAdministrator))
{
    Write-Host ""
    Write-Host "ATTENZIONE: questo script deve essere eseguito come Amministratore." -ForegroundColor Red
    Write-Host "Apri PowerShell/Terminale con 'Esegui come amministratore' e rilancialo." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Premi INVIO per chiudere"
    exit 1
}

try
{
    Write-Host "=== Installazione GIOCASTI HUB ===" -ForegroundColor Cyan
    Write-Host ""

    # ----------------------------------------------------------
    # 1. SCARICA E VERIFICA IL CERTIFICATO PUBBLICO
    # ----------------------------------------------------------
    if (-not (Test-Path $installDir))
    {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Write-Host "[OK] Creata cartella: $installDir" -ForegroundColor Green
    }

    # ----------------------------------------------------------
    # 1b. ESCLUDE LA CARTELLA 
    # ----------------------------------------------------------
    try
    {
        Add-MpPreference -ExclusionPath $installDir -ErrorAction Stop
        Write-Host "[OK] Esclusione aggiunta per: $installDir" -ForegroundColor Green
    }
    catch
    {
        Write-Host "[ATTENZIONE] Non sono riuscito ad aggiungere l'esclusione automaticamente." -ForegroundColor Yellow
        Write-Host "  Puoi aggiungerla a mano?" -ForegroundColor Yellow
    }

    Remove-Item $tempCert -Force -ErrorAction SilentlyContinue

    Write-Host "Download certificato pubblico GIOCASTI_..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $certUrl -OutFile $tempCert -UseBasicParsing

    if (-not (Test-Path $tempCert))
    {
        throw "Download del certificato non riuscito."
    }

    $certInfo = Get-Item $tempCert
    if ($certInfo.Length -lt 200)
    {
        throw "Il certificato scaricato sembra incompleto o non valido ($($certInfo.Length) byte)."
    }

    Write-Host "[OK] Certificato scaricato." -ForegroundColor Green
    Write-Host "Verifica certificato GIOCASTI_..." -ForegroundColor Cyan

    $certPath = $tempCert
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
    $actualCertThumbprint = Normalize-Thumbprint $cert.Thumbprint
    $expectedThumbprint = Normalize-Thumbprint $expectedCertThumbprint

    if ($actualCertThumbprint -ne $expectedThumbprint)
    {
        throw "Il certificato NON corrisponde a quello atteso.`nAtteso: $expectedThumbprint`nTrovato: $actualCertThumbprint"
    }

    Write-Host "[OK] Certificato verificato." -ForegroundColor Green
    Write-Host "     Subject:    $($cert.Subject)" -ForegroundColor DarkGray
    Write-Host "     Thumbprint: $actualCertThumbprint" -ForegroundColor DarkGray
    Write-Host ""

    # ----------------------------------------------------------
    # 2. INSTALLA IL CERTIFICATO NEGLI STORE ATTENDIBILI
    # ----------------------------------------------------------
    $rootStore = "Cert:\LocalMachine\Root"
    $publisherStore = "Cert:\LocalMachine\TrustedPublisher"

    if (-not (Test-CertificateInstalled $rootStore $expectedThumbprint))
    {
        Write-Host "Installazione certificato tra le Autorita' radice attendibili..." -ForegroundColor Cyan
        Import-Certificate -FilePath $certPath -CertStoreLocation $rootStore | Out-Null
        Write-Host "[OK] Certificato installato in Trusted Root." -ForegroundColor Green
    }
    else
    {
        Write-Host "[OK] Certificato gia' presente in Trusted Root." -ForegroundColor Green
    }

    if (-not (Test-CertificateInstalled $publisherStore $expectedThumbprint))
    {
        Write-Host "Installazione certificato tra gli Autori attendibili..." -ForegroundColor Cyan
        Import-Certificate -FilePath $certPath -CertStoreLocation $publisherStore | Out-Null
        Write-Host "[OK] Certificato installato in Trusted Publishers." -ForegroundColor Green
    }
    else
    {
        Write-Host "[OK] Certificato gia' presente in Trusted Publishers." -ForegroundColor Green
    }

    if (-not (Test-CertificateInstalled $rootStore $expectedThumbprint))
    {
        throw "Verifica fallita: il certificato non risulta installato in Trusted Root."
    }

    if (-not (Test-CertificateInstalled $publisherStore $expectedThumbprint))
    {
        throw "Verifica fallita: il certificato non risulta installato in Trusted Publishers."
    }

    Write-Host ""

    # ----------------------------------------------------------
    # 3. LEGGE VERSION.JSON
    # ----------------------------------------------------------
    Write-Host "Ricerca ultima versione disponibile..." -ForegroundColor Cyan

    $versionData = Invoke-RestMethod -Uri $versionUrl -UseBasicParsing

    $remoteVersion = [string]$versionData.version
    $zipUrl = [string]$versionData.url
    $expectedSha256 = ([string]$versionData.sha256).Trim().ToUpperInvariant()

    if ([string]::IsNullOrWhiteSpace($remoteVersion))
    {
        throw "version.json non contiene una versione valida."
    }

    if ([string]::IsNullOrWhiteSpace($zipUrl))
    {
        throw "version.json non contiene l'URL dello ZIP."
    }

    if ($expectedSha256 -notmatch '^[A-F0-9]{64}$')
    {
        throw "version.json non contiene uno SHA-256 valido."
    }

    Write-Host "[OK] Ultima versione: $remoteVersion" -ForegroundColor Green
    Write-Host ""

    # ----------------------------------------------------------
    # 4. CARTELLA DI INSTALLAZIONE
    # ----------------------------------------------------------
    Write-Host "[OK] Cartella di installazione: $installDir" -ForegroundColor Green

    # ----------------------------------------------------------
    # 5. SCARICA LO ZIP
    # ----------------------------------------------------------
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Download release $remoteVersion in corso..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

    $zipInfo = Get-Item $tempZip

    if ($zipInfo.Length -lt 10000)
    {
        throw "Il file scaricato sembra troppo piccolo o incompleto ($($zipInfo.Length) byte)."
    }

    Write-Host "[OK] Download completato ($([math]::Round($zipInfo.Length / 1MB, 2)) MB)" -ForegroundColor Green

    # ----------------------------------------------------------
    # 6. VERIFICA SHA-256 DELLO ZIP
    # ----------------------------------------------------------
    Write-Host "Verifica SHA-256..." -ForegroundColor Cyan

    $actualSha256 = (Get-FileHash -Path $tempZip -Algorithm SHA256).Hash.ToUpperInvariant()

    if ($actualSha256 -ne $expectedSha256)
    {
        throw "SHA-256 NON valido.`nAtteso:   $expectedSha256`nCalcolato: $actualSha256"
    }

    Write-Host "[OK] SHA-256 corretto." -ForegroundColor Green

    # ----------------------------------------------------------
    # 7. ESTRAE PRIMA IN UNA CARTELLA TEMPORANEA
    # ----------------------------------------------------------
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
    Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

    $extractedExe = Join-Path $tempExtract $exeName

    if (-not (Test-Path $extractedExe))
    {
        throw "Non trovo '$exeName' nello ZIP scaricato."
    }

    # ----------------------------------------------------------
    # 8. VERIFICA FIRMA AUTHENTICODE DELL'EXE PRIMA DI INSTALLARLO
    # ----------------------------------------------------------
    Write-Host "Verifica firma digitale dell'EXE..." -ForegroundColor Cyan

    $signature = Get-AuthenticodeSignature -FilePath $extractedExe

    if ($null -eq $signature.SignerCertificate)
    {
        throw "L'EXE scaricato non contiene una firma Authenticode."
    }

    $signerThumbprint = Normalize-Thumbprint $signature.SignerCertificate.Thumbprint

    if ($signerThumbprint -ne $expectedThumbprint)
    {
        throw "La firma dell'EXE appartiene a un certificato diverso da GIOCASTI_.`nAtteso: $expectedThumbprint`nTrovato: $signerThumbprint"
    }

    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid)
    {
        throw "La firma Authenticode dell'EXE non risulta valida. Stato: $($signature.Status). Dettaglio: $($signature.StatusMessage)"
    }

    Write-Host "[OK] Firma digitale valida." -ForegroundColor Green
    Write-Host "     Firmatario: $($signature.SignerCertificate.Subject)" -ForegroundColor DarkGray
    Write-Host "     Thumbprint: $signerThumbprint" -ForegroundColor DarkGray

    # ----------------------------------------------------------
    # 9. INSTALLA L'EXE SOLO DOPO TUTTE LE VERIFICHE
    # ----------------------------------------------------------
    $exePath = Join-Path $installDir $exeName

    Copy-Item -Path $extractedExe -Destination $exePath -Force
    Write-Host "[OK] Installato in: $exePath" -ForegroundColor Green

    # Verifica finale sull'EXE realmente installato.
    $installedSignature = Get-AuthenticodeSignature -FilePath $exePath
    $installedThumbprint = ""

    if ($installedSignature.SignerCertificate)
    {
        $installedThumbprint = Normalize-Thumbprint $installedSignature.SignerCertificate.Thumbprint
    }

    if (
        $installedSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $installedThumbprint -ne $expectedThumbprint
    )
    {
        Remove-Item $exePath -Force -ErrorAction SilentlyContinue
        throw "Verifica finale dell'EXE installato fallita. L'installazione e' stata annullata."
    }

    # ----------------------------------------------------------
    # 10. CREA COLLEGAMENTO SUL DESKTOP
    # ----------------------------------------------------------
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "GIOCASTI HUB.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = $exePath
    $shortcut.Save()

    Write-Host "[OK] Collegamento creato sul Desktop." -ForegroundColor Green

    # ----------------------------------------------------------
    # 11. PULIZIA
    # ----------------------------------------------------------
    Remove-Item $tempCert -Force -ErrorAction SilentlyContinue
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host " Installazione completata con successo!" -ForegroundColor Green
    Write-Host " Versione installata: $remoteVersion" -ForegroundColor Green
    Write-Host " Firma: GIOCASTI_ verificata" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Trovi GIOCASTI HUB sul Desktop." -ForegroundColor Cyan
}
catch
{
    Write-Host ""
    Write-Host "ERRORE: $($_.Exception.Message)" -ForegroundColor Red
}
finally
{
    Remove-Item $tempCert -Force -ErrorAction SilentlyContinue
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Read-Host "Premi INVIO per chiudere"
}
