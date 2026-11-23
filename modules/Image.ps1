function Resolve-ImagerPath {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [string[]]$SearchRoots
    )

    # config.local.json serves both as a persistent override and a discovery cache.
    # Preserve unrelated configuration properties when refreshing an outdated path.
    $config = [pscustomobject]@{}
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $ConfigPath -Raw |
                ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to read Imager configuration at '$ConfigPath': $($_.Exception.Message)"
        }
        if ($null -eq $config -or $config -isnot [pscustomobject]) {
            throw "Imager configuration must be a JSON object: $ConfigPath"
        }
    }

    $configuredPath = $config.imagerPath
    if ($null -ne $configuredPath -and $configuredPath -isnot [string]) {
        throw "imagerPath must be a string in '$ConfigPath'."
    }
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        if (-not [System.IO.Path]::IsPathRooted($configuredPath)) {
            throw "Configured imagerPath must be an absolute path: $configuredPath"
        }
        if (Test-Path -LiteralPath $configuredPath -PathType Leaf) {
            return (Resolve-Path -LiteralPath $configuredPath).ProviderPath
        }
        Write-Warning "Cached Imager path no longer exists: $configuredPath. Searching again."
    }

    if (-not $PSBoundParameters.ContainsKey("SearchRoots")) {
        $SearchRoots = @(
            $env:ProgramFiles,
            [Environment]::GetEnvironmentVariable("ProgramFiles(x86)"),
            $env:LOCALAPPDATA
        )
    }

    Write-Host "Searching for Raspberry Pi Imager in program directories..."
    $foundPaths = @{} # PowerShell hashtable keys are case-insensitive by default.
    foreach ($root in @($SearchRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        # Match folder names, then search below them for rpi-imager.exe.
        # Deduplicate nested-folder matches (e.g. Raspberry Pi Ltd\Imager).
        $folders = @(Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Raspberry|Imager' } |
            Sort-Object FullName)
        foreach ($folder in $folders) {
            $executables = @(Get-ChildItem -LiteralPath $folder.FullName -File -Recurse -Filter "rpi-imager.exe" -ErrorAction SilentlyContinue)
            foreach ($exe in $executables) {
                $foundPaths[$exe.FullName] = $true
            }
        }
    }

    if ($foundPaths.Count -eq 0) {
        throw "Raspberry Pi Imager was not found. Install it or set imagerPath in config.local.json."
    }
    if ($foundPaths.Count -gt 1) {
        $choices = (@($foundPaths.Keys) | Sort-Object) -join [Environment]::NewLine
        throw "Multiple Raspberry Pi Imager executables were found. Set imagerPath in config.local.json to choose one:$([Environment]::NewLine)$choices"
    }

    $resolved = @($foundPaths.Keys)[0]
    # Write the cache only after a unique executable has been found.
    # Ensure the parent directory exists, and preserve other config keys.
    $config | Add-Member -NotePropertyName imagerPath -NotePropertyValue $resolved -Force
    $parent = Split-Path -Parent $ConfigPath
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
    $json = $config | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, $utf8NoBom)
    Write-Host "Cached Raspberry Pi Imager path: $ConfigPath"
    return $resolved
}

function Write-SdImage {
    param(
        [Parameter(Mandatory = $true)][string]$ImagerPath,
        [Parameter(Mandatory = $true)][string]$ImageUrl,
        [string]$Sha256,
        [Parameter(Mandatory = $true)][string]$Device
    )
    Write-Host ""
    Write-Host "Starting Raspberry Pi Imager..."
    $arguments = @("--cli", "--disable-eject")
    if (-not [string]::IsNullOrWhiteSpace($Sha256)) {
        $arguments += @("--sha256", $Sha256)
    }
    $arguments += @($ImageUrl, $Device)
    $process = Start-Process -FilePath $ImagerPath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Raspberry Pi Imager failed with exit code $($process.ExitCode)."
    }
    Write-Host "Image write completed successfully."
}
