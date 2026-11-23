function Get-TargetDisk {
    $disks = @(Get-Disk | Where-Object {
        $_.Number -ne 0 -and $_.IsBoot -eq $false -and $_.IsSystem -eq $false -and
        ($_.Size / 1GB) -ge 8 -and ($_.Size / 1GB) -le 64
    })
    if ($disks.Count -ne 1) {
        throw "SD card detection failed. Expected exactly one candidate, but found $($disks.Count)."
    }
    return $disks[0]
}

function Confirm-DiskErase {
    param([Parameter(Mandatory = $true)]$Disk)
    Write-Host ""
    Write-Host "Target disk:"
    $Disk | Format-Table Number, FriendlyName, BusType, IsBoot, IsSystem, @{
        Name = "SizeGB"; Expression = { [math]::Round($_.Size / 1GB, 2) }
    }, PartitionStyle
    Write-Host ""
    Write-Host "WARNING: All data on this disk will be erased."
    $confirmation = "ERASE-$($Disk.Number)"
    $answer = Read-Host "Type $confirmation to confirm"
    if ($answer -ne $confirmation) { throw "Operation cancelled." }
}
