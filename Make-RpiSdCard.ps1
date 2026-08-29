param (
    [Parameter(Mandatory = $true)]
    [string]$Hostname,

    [switch]$SkipImager
)

$targetImageName = "Raspberry Pi OS Lite (64-bit)"
$minSizeGB = 8
$maxSizeGB = 64
$imager = "C:\Program Files\Raspberry Pi Imager\rpi-imager.exe"
$osListUrl = "https://downloads.raspberrypi.com/os_list_imagingutility_v4.json"
$userDataTemplatePath = ".\cloud-init\user-data.template"
$networkConfigPath = ".\cloud-init\network-config"

Write-Host "Fetching Raspberry Pi OS image information..."
$osList = Invoke-RestMethod -Uri $osListUrl

$image = $osList.os_list |
    ForEach-Object { $_.subitems } |
    Where-Object {
        $_.name -eq $targetImageName
    } |
    Sort-Object { [datetime]$_.release_date } -Descending |
    Select-Object -First 1

if (-not $image) {
    throw "$targetImageName image was not found."
}

$imageUrl = $image.url
$sha256   = $image.extract_sha256

Write-Host "Selected image:"
Write-Host "  Name        : $($image.name)"
Write-Host "  Release date: $($image.release_date)"
Write-Host "  Init format : $($image.init_format)"
Write-Host "  URL         : $imageUrl"
Write-Host "  SHA256      : $sha256"


$disk = Get-Disk |
    Where-Object {
        $_.Number -ne 0 -and
        $_.IsBoot   -eq $false -and
        $_.IsSystem -eq $false -and
        ($_.Size / 1GB) -ge $minSizeGB -and
        ($_.Size / 1GB) -le $maxSizeGB
    }

if (@($disk).Count -ne 1) {
    throw "SD card detection failed. Expected exactly one candidate, but found $(@($disk).Count)."
}

Write-Host ""
Write-Host "Target disk:"
$disk | Format-Table `
    Number,
    FriendlyName,
    BusType,
    IsBoot,
    IsSystem,
    @{Name="SizeGB"; Expression={[math]::Round($_.Size / 1GB, 2)}},
    PartitionStyle

$diskNumber = $disk.Number
$device = "\\.\PhysicalDrive$diskNumber"

if($SkipImager){
    Write-Host "Skipping Raspberry Pi Imager."    
}
else {
    Write-Host ""
    Write-Host "WARNING: All data on this disk will be erased."

    $confirmation = "ERASE-$diskNumber"
    $answer = Read-Host "Type $confirmation to confirm"

    if ($answer -ne $confirmation) {
        Write-Host "Operation cancelled."
        exit 1
    }

    Write-Host ""
    Write-Host "Starting Raspberry Pi Imager..."

    $imager_args = @("--cli", "--disable-eject", "--sha256", $sha256, $imageUrl, $device)
    $process = Start-Process -FilePath $imager -ArgumentList $imager_args -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Raspberry Pi Imager failed with exit code $($process.ExitCode)."
    }

    Write-Host "Image write completed successfully."
}

Update-HostStorageCache
Start-Sleep -Seconds 2

$bootVolume = Get-Partition -DiskNumber $diskNumber |
    Where-Object { $_.DriveLetter } |
    ForEach-Object { Get-Volume -DriveLetter $_.DriveLetter } |
    Where-Object {
        $_.FileSystem -eq "FAT32"
    } |
    Select-Object -First 1

if (-not $bootVolume) {
    throw "Boot partition was not found."
}

$bootDrive = "$($bootVolume.DriveLetter):"

Write-Host "Detected boot partition: $bootDrive"

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$userData = Get-Content $userDataTemplatePath -Raw
$userData = $userData.Replace("__HOSTNAME__", $Hostname)
$userData = $userData -replace "`r`n", "`n"
[System.IO.File]::WriteAllText(
    "$bootDrive\user-data",
    $userData,
    $utf8NoBom
)

$networkConfig = Get-Content $networkConfigPath -Raw
$networkConfig = $networkConfig -replace "`r`n", "`n"
[System.IO.File]::WriteAllText(
    "$bootDrive\network-config",
    $networkConfig,
    $utf8NoBom
)

New-Item `
    -Path "$bootDrive\ssh" `
    -ItemType File `
    -Force | Out-Null

Write-Host ""
Write-Host "Verifying provisioning files..."

$filesToCheck = @(
    "user-data",
    "network-config",
    "ssh"
)

foreach ($file in $filesToCheck) {
    $filePath = Join-Path $bootDrive $file
    if (-not (Test-Path $filePath)) {
        throw "Required provisioning file is missing: $filePath"
    }

    Write-Host "OK: $filePath exists."
    Write-Host ""
    Write-Host "===== $file ====="
    Get-Content $filePath

}

$sshFile = Get-Item "$bootDrive\ssh"

if ($sshFile.Length -eq 0) {
    Write-Host "OK: ssh file exists and is empty."
}
else {
    Write-Warning "ssh file exists but is not empty. Size: $($sshFile.Length) bytes"
}

Write-Host ""
Write-Host "Provisioning verification completed."
Write-Host "Hostname: $Hostname"
Write-Host "Boot drive: $bootDrive"
