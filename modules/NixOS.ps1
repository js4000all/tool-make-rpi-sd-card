# Fixed initial target: NixOS 26.05 stable, generic AArch64 SD image for Raspberry Pi 4.
# This points to Hydra's latest successful build *within* the 26.05 release.
# Pin a specific build artifact once the first working image is validated.
function Get-NixOsImage {
    param(
        [string]$ImageUrl = "https://hydra.nixos.org/job/nixos/release-26.05/nixos.sd_image.aarch64-linux/latest/download/1"
    )

    Write-Host "Selected NixOS image: 26.05 stable / aarch64 / generic SD image (Raspberry Pi 4)"
    return [pscustomobject]@{
        name = "NixOS 26.05 AArch64 SD image"
        release_date = "26.05"
        init_format = "NixOS"
        url = $ImageUrl
        extract_sha256 = $null
    }
}

function Save-NixOsImage {
    param(
        [Parameter(Mandatory = $true)][string]$ImageUrl,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    # Hydra's download endpoint has no .zst suffix. Give the locally saved
    # image the correct extension so Raspberry Pi Imager can detect compression.
    Write-Host "Downloading NixOS SD image..."
    try {
        Invoke-WebRequest -Uri $ImageUrl -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        $item = Get-Item -LiteralPath $Destination -ErrorAction Stop
        if ($item.Length -le 0) { throw "Downloaded NixOS image is empty." }
        return $item.FullName
    }
    catch {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw "Failed to download NixOS SD image: $($_.Exception.Message)"
    }
}
