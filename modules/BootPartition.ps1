function Get-BootDrive {
    param([Parameter(Mandatory = $true)][int]$DiskNumber)
    Update-HostStorageCache
    Start-Sleep -Seconds 2
    $bootVolume = Get-Partition -DiskNumber $DiskNumber |
        Where-Object { $_.DriveLetter } |
        ForEach-Object { Get-Volume -DriveLetter $_.DriveLetter } |
        Where-Object { $_.FileSystem -eq "FAT32" } |
        Select-Object -First 1
    if (-not $bootVolume) { throw "Boot partition was not found." }
    return "$($bootVolume.DriveLetter):"
}

function Write-BootTextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $normalized = $Content.Replace([string][char]13 + [char]10, [string][char]10)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}
