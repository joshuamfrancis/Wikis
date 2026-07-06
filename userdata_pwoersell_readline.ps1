<powershell>
# =====================================================================
# EC2 User Data - PSReadLine patch for Fleet Manager Remote Desktop
# ---------------------------------------------------------------------
# Fixes the Windows Server 2022 keyboard-input bug in the PowerShell
# console over SSM Fleet Manager RDP by ensuring PSReadLine >= 2.2.2.
#
# Runs ONCE at first boot as SYSTEM (elevated). Idempotent + logged.
# Log: C:\ProgramData\bootstrap\psreadline-patch.log
# =====================================================================

$ErrorActionPreference = 'Stop'
$MinVersion = [Version]'2.2.2'
$LogDir     = 'C:\ProgramData\bootstrap'
$LogFile    = Join-Path $LogDir 'psreadline-patch.log'

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path $LogFile -Append | Out-Null

function Log($m) { Write-Output ("[{0}] {1}" -f (Get-Date -Format 'u'), $m) }

try {
    Log "Starting PSReadLine patch. Minimum target version: $MinVersion"

    # 1. Force TLS 1.2 so PSGallery / NuGet endpoints are reachable on older images.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 2. Detect current version and short-circuit if already good enough.
    $current = Get-Module -ListAvailable -Name PSReadLine |
               Sort-Object Version -Descending | Select-Object -First 1
    $currentText = if ($current) { $current.Version } else { 'none' }
    Log "Currently installed PSReadLine: $currentText"

    if ($current -and $current.Version -ge $MinVersion) {
        Log "Already >= $MinVersion. No action needed."
    }
    else {
        # 3. Ensure NuGet provider + a trusted PSGallery for non-interactive install.
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        # 4. Unload the in-box module in case the launch session imported it.
        Remove-Module PSReadLine -Force -ErrorAction SilentlyContinue

        # 5. Install to AllUsers (Program Files), which overrides the in-box copy.
        #    -SkipPublisherCheck avoids the Microsoft-signed vs PSGallery publisher
        #    mismatch when replacing the in-box module.
        Install-Module -Name PSReadLine -MinimumVersion $MinVersion `
            -Scope AllUsers -Repository PSGallery `
            -Force -AllowClobber -SkipPublisherCheck

        # 6. Verify.
        $new = Get-Module -ListAvailable -Name PSReadLine |
               Sort-Object Version -Descending | Select-Object -First 1
        if ($new -and $new.Version -ge $MinVersion) {
            Log "SUCCESS: PSReadLine $($new.Version) installed."
        }
        else {
            throw "PSReadLine install did not reach $MinVersion (found: $($new.Version))."
        }
    }
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript | Out-Null
}
</powershell>