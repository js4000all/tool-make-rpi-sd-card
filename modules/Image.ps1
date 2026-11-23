function Resolve-ImagerPath {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [string[]]$SearchRoots
    )

    # A machine-local configuration file is optional. An explicit invalid path
    # must fail rather than silently selecting another executable.
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to read Imager configuration at '$ConfigPath': $($_.Exception.Message)"
        }

        if ($null -ne $config.imagerPath -and -not ($config.imagerPath -is [string])) {
            throw "imagerPath must be a string in '$ConfigPath'."
        }
        if (-not [string]::IsNullOrWhiteSpace($config.imagerPath)) {
            $configuredPath = $config.imagerPath
            if (-not [System.IO.Path]::IsPathRooted($configuredPath)) {
                throw "Configured imagerPath must be an absolute path: $configuredPath"
            }
            if (-not (Test-Path -LiteralPath $configuredPath -PathType Leaf)) {
                throw "Raspberry Pi Imager was not found at configured imagerPath: $configuredPath"
            }
            return (Resolve-Path -LiteralPath $configuredPath).ProviderPath
        }
    }

    # A portable/PATH installation takes precedence over installed directories.
    $command = Get-Command -Name "rpi-imager.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    if (-not $PSBoundParameters.ContainsKey("SearchRoots")) {
        $SearchRoots = @($env:ProgramFiles, [Environment]::GetEnvironmentVariable("ProgramFiles(x86)"), $env:LOCALAPPDATA)
    }

    foreach ($root in @($SearchRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        # Find folders whose names contain Raspberry or Imager, and then
        # locate rpi-imager.exe anywhere beneath each matching folder.
        $folders = @(Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Raspberry|Imager' } |
            Sort-Object FullName)
        foreach ($folder in $folders) {
            $executable = Get-ChildItem -LiteralPath $folder.FullName -File -Recurse -Filter "rpi-imager.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName |
                Select-Object -First 1
            if ($executable) {
                return $executable.FullName
            }
        }
    }

    throw "Raspberry Pi Imager was not found. Install it, add it to PATH, or set imagerPath in config.local.json."
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
