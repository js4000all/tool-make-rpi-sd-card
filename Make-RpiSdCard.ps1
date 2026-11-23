param (
    [Parameter(Mandatory = $true)]
    [string]$Hostname,

    [ValidateSet("RaspberryPiOS", "NixOS")]
    [string]$OS = "RaspberryPiOS",

    [switch]$SkipImager
)

$ErrorActionPreference = "Stop"
$moduleDirectory = Join-Path $PSScriptRoot "modules"
. (Join-Path $moduleDirectory "Disk.ps1")
. (Join-Path $moduleDirectory "Image.ps1")
. (Join-Path $moduleDirectory "BootPartition.ps1")
. (Join-Path $moduleDirectory "RaspberryPiOS.ps1")
. (Join-Path $moduleDirectory "NixOS.ps1")

# Fix Imager before querying image metadata or probing a target disk.
if ($SkipImager) {
    Write-Host "Skipping Raspberry Pi Imager."
} else {
    $resolvedImagerPath = Resolve-ImagerPath -ConfigPath (Join-Path $PSScriptRoot "config.local.json")
    Write-Host "Raspberry Pi Imager: $resolvedImagerPath"
}

# Stage 1: Fix the target OS image.
switch ($OS) {
    "RaspberryPiOS" { $image = Get-RaspberryPiOsImage }
    "NixOS"         { $image = Get-NixOsImage }
}
$imageUrl = $image.url
$sha256 = $image.extract_sha256

Write-Host "Selected image:"
Write-Host "  Name        : $($image.name)"
Write-Host "  Release date: $($image.release_date)"
Write-Host "  Init format : $($image.init_format)"
Write-Host "  URL         : $imageUrl"
Write-Host "  SHA256      : $sha256"

$disk = Get-TargetDisk
$diskNumber = $disk.Number
$device = "\\.\PhysicalDrive$diskNumber"

# Stage 2: Write the image (unless explicitly skipped).
if (-not $SkipImager) {
    Confirm-DiskErase -Disk $disk
    if ($OS -eq "NixOS") {
        $downloadPath = Join-Path ([System.IO.Path]::GetTempPath()) ("nixos-pi4-" + [guid]::NewGuid().ToString("N") + ".img.zst")
        try {
            $localImage = Save-NixOsImage -ImageUrl $imageUrl -Destination $downloadPath
            Write-SdImage -ImagerPath $resolvedImagerPath -ImageUrl $localImage -Device $device
        }
        finally {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-SdImage -ImagerPath $resolvedImagerPath -ImageUrl $imageUrl -Sha256 $sha256 -Device $device
    }
}

# Stage 3: OS-specific post-write work.
switch ($OS) {
    "RaspberryPiOS" {
        $bootDrive = Get-BootDrive -DiskNumber $diskNumber
        Write-Host "Detected boot partition: $bootDrive"
        $configDirectory = Join-Path $PSScriptRoot "cloud-init"
        Set-RaspberryPiOsBootFiles -BootDrive $bootDrive -Hostname $Hostname -ConfigDirectory $configDirectory
    }
    "NixOS" {
        Write-Host "NixOS post-write provisioning is deferred to the next phase."
    }
}
