# Requires Pester 5. Run: Invoke-Pester ./tests
BeforeAll {
    . (Join-Path $PSScriptRoot "../modules/BootPartition.ps1")
    . (Join-Path $PSScriptRoot "../modules/RaspberryPiOS.ps1")
    . (Join-Path $PSScriptRoot "../modules/NixOS.ps1")
}

Describe "Raspberry Pi OS image selection" {
    It "chooses the latest Lite 64-bit release" {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                os_list = @(
                    [pscustomobject]@{
                        subitems = @(
                            [pscustomobject]@{ name = "Raspberry Pi OS Lite (64-bit)"; release_date = "2025-01-01"; url = "older" }
                            [pscustomobject]@{ name = "Another OS"; release_date = "2026-01-01"; url = "other" }
                            [pscustomobject]@{ name = "Raspberry Pi OS Lite (64-bit)"; release_date = "2026-01-01"; url = "newer" }
                        )
                    }
                )
            }
        }
        (Get-RaspberryPiOsImage).url | Should -Be "newer"
    }
}

Describe "Boot file text encoding" {
    It "writes without a UTF-8 BOM and normalizes CRLF to LF" {
        $path = Join-Path $TestDrive "user-data"
        $inputText = "line1" + [char]13 + [char]10 + "line2"
        Write-BootTextFile -Path $path -Content $inputText
        $bytes = [System.IO.File]::ReadAllBytes($path)
        [System.Text.Encoding]::UTF8.GetString($bytes) | Should -Be ("line1" + [char]10 + "line2")
        $bytes[0] | Should -Be 108
    }
}

Describe "NixOS support" {
    It "returns an explicit unsupported error" {
        { Assert-NixOsSupported } | Should -Throw "*NixOS is not supported yet*"
    }
}


Describe "Raspberry Pi Imager discovery" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../modules/Image.ps1")
    }

    It "uses an explicitly specified full path" {
        $explicitPath = Join-Path $TestDrive "imager-custom.exe"
        Set-Content -LiteralPath $explicitPath -Value "test"
        (Resolve-ImagerPath -ImagerPath $explicitPath) | Should -Be $explicitPath
    }

    It "rejects a relative explicit path instead of silently searching" {
        { Resolve-ImagerPath -ImagerPath "missing.exe" } | Should -Throw "*absolute path*"
    }

    It "fails for an absent explicit executable instead of falling back" {
        $missingPath = Join-Path $TestDrive "does-not-exist.exe"
        { Resolve-ImagerPath -ImagerPath $missingPath } | Should -Throw "*specified -ImagerPath*"
    }

    It "prefers an application discovered on PATH" {
        Mock Get-Command {
            [pscustomobject]@{ Source = "C:\tools\rpi-imager.exe" }
        } -ParameterFilter { $Name -eq "rpi-imager.exe" }
        (Resolve-ImagerPath) | Should -Be "C:\tools\rpi-imager.exe"
    }

    It "finds the current installer directory under Program Files" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "rpi-imager.exe" }
        $previous = $env:ProgramFiles
        try {
            $env:ProgramFiles = $TestDrive
            $directory = Join-Path $TestDrive "Raspberry Pi Ltd\Imager"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $exe = Join-Path $directory "rpi-imager.exe"
            Set-Content -LiteralPath $exe -Value "test"
            (Resolve-ImagerPath) | Should -Be $exe
        }
        finally {
            $env:ProgramFiles = $previous
        }
    }
}
