function Resolve-ImagerPath {
    param([string]$ImagerPath)

    if (-not [string]::IsNullOrWhiteSpace($ImagerPath)) {
        if (-not [System.IO.Path]::IsPathRooted($ImagerPath)) {
            throw "-ImagerPath must be an absolute path: $ImagerPath"
        }
        if (-not (Test-Path -LiteralPath $ImagerPath -PathType Leaf)) {
            throw "Raspberry Pi Imager was not found at the specified -ImagerPath: $ImagerPath"
        }
        return (Resolve-Path -LiteralPath $ImagerPath).ProviderPath
    }

    # Check PATH first, including user-managed and portable installations.
    $command = Get-Command -Name "rpi-imager.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    # Support both current and legacy installer locations, including per-user installs.
    $roots = @($env:ProgramFiles, $env:LOCALAPPDATA) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86 -and $programFilesX86 -notin $roots) {
        $roots = @($roots) + $programFilesX86
    }

    $relativePaths = @(
        "Raspberry Pi Ltd\Imager\rpi-imager.exe",
        "Raspberry Pi Imager\rpi-imager.exe",
        "Programs\Raspberry Pi Ltd\Imager\rpi-imager.exe",
        "Programs\Raspberry Pi Imager\rpi-imager.exe"
    )

    foreach ($root in $roots) {
        foreach ($relativePath in $relativePaths) {
            $candidate = Join-Path $root $relativePath
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).ProviderPath
            }
        }
    }

    throw "Raspberry Pi Imager was not found. Install it or specify its executable using -ImagerPath 'C:\path\to\rpi-imager.exe'."
}

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
