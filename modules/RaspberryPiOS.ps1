function Get-RaspberryPiOsImage {
    param([string]$OsListUrl = "https://downloads.raspberrypi.com/os_list_imagingutility_v4.json")
    $targetImageName = "Raspberry Pi OS Lite (64-bit)"
    Write-Host "Fetching Raspberry Pi OS image information..."
    $osList = Invoke-RestMethod -Uri $OsListUrl
    $image = $osList.os_list |
        ForEach-Object { $_.subitems } |
        Where-Object { $_.name -eq $targetImageName } |
        Sort-Object { [datetime]$_.release_date } -Descending |
        Select-Object -First 1
    if (-not $image) { throw "$targetImageName image was not found." }
    return $image
}

function Set-RaspberryPiOsBootFiles {
    param(
        [Parameter(Mandatory = $true)][string]$BootDrive,
        [Parameter(Mandatory = $true)][string]$Hostname,
        [Parameter(Mandatory = $true)][string]$ConfigDirectory
    )
    $userData = (Get-Content (Join-Path $ConfigDirectory "user-data.template") -Raw).Replace("__HOSTNAME__", $Hostname)
    Write-BootTextFile -Path (Join-Path $BootDrive "user-data") -Content $userData
    $networkConfig = Get-Content (Join-Path $ConfigDirectory "network-config") -Raw
    Write-BootTextFile -Path (Join-Path $BootDrive "network-config") -Content $networkConfig
    New-Item -Path (Join-Path $BootDrive "ssh") -ItemType File -Force | Out-Null
    Write-Host ""
    Write-Host "Verifying provisioning files..."
    foreach ($file in @("user-data", "network-config", "ssh")) {
        $filePath = Join-Path $BootDrive $file
        if (-not (Test-Path $filePath)) { throw "Required provisioning file is missing: $filePath" }
        Write-Host "OK: $filePath exists."
        Write-Host ""
        Write-Host "===== $file ====="
        Get-Content $filePath
    }
    $sshFile = Get-Item (Join-Path $BootDrive "ssh")
    if ($sshFile.Length -eq 0) {
        Write-Host "OK: ssh file exists and is empty."
    } else {
        Write-Warning "ssh file exists but is not empty. Size: $($sshFile.Length) bytes"
    }
    Write-Host ""
    Write-Host "Provisioning verification completed."
    Write-Host "Hostname: $Hostname"
    Write-Host "Boot drive: $BootDrive"
}
