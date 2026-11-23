function Write-SdImage {
    param(
        [Parameter(Mandatory = $true)][string]$ImagerPath,
        [Parameter(Mandatory = $true)][string]$ImageUrl,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][string]$Device
    )
    Write-Host ""
    Write-Host "Starting Raspberry Pi Imager..."
    $arguments = @("--cli", "--disable-eject", "--sha256", $Sha256, $ImageUrl, $Device)
    $process = Start-Process -FilePath $ImagerPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Raspberry Pi Imager failed with exit code $($process.ExitCode)."
    }
    Write-Host "Image write completed successfully."
}
