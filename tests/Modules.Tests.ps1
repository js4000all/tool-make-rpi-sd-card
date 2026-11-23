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

    BeforeEach {
        $configPath = Join-Path $TestDrive "config.local.json"
    }

    It "uses an executable specified in the machine config" {
        $exe = Join-Path $TestDrive "custom-imager.exe"
        Set-Content -LiteralPath $exe -Value "test"
        @{ imagerPath = $exe } | ConvertTo-Json | Set-Content -LiteralPath $configPath
        (Resolve-ImagerPath -ConfigPath $configPath) | Should -Be $exe
    }

    It "rejects a relative configured path" {
        '{"imagerPath":"relative.exe"}' | Set-Content -LiteralPath $configPath
        { Resolve-ImagerPath -ConfigPath $configPath } | Should -Throw "*absolute path*"
    }

    It "fails on a nonexistent configured path without fallback" {
        $exe = Join-Path $TestDrive "missing.exe"
        @{ imagerPath = $exe } | ConvertTo-Json | Set-Content -LiteralPath $configPath
        { Resolve-ImagerPath -ConfigPath $configPath } | Should -Throw "*configured imagerPath*"
    }

    It "rejects malformed JSON config" {
        '{"imagerPath":' | Set-Content -LiteralPath $configPath
        { Resolve-ImagerPath -ConfigPath $configPath } | Should -Throw "*Unable to read Imager configuration*"
    }

    It "prefers an application from PATH when config is absent" {
        Mock Get-Command {
            [pscustomobject]@{ Source = "C:\tools\rpi-imager.exe" }
        } -ParameterFilter { $Name -eq "rpi-imager.exe" }
        (Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @()) | Should -Be "C:\tools\rpi-imager.exe"
    }

    It "finds an Imager directory nested below a Raspberry-named folder" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "rpi-imager.exe" }
        $root = Join-Path $TestDrive "ProgramFiles"
        $directory = Join-Path $root "Raspberry Pi Ltd\Imager"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $exe = Join-Path $directory "rpi-imager.exe"
        Set-Content -LiteralPath $exe -Value "test"
        (Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root)) | Should -Be $exe
    }

    It "finds a custom nested installation with Imager in its folder name" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "rpi-imager.exe" }
        $root = Join-Path $TestDrive "LocalAppData"
        $directory = Join-Path $root "Programs\Vendor\Portable Imager\bin"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $exe = Join-Path $directory "rpi-imager.exe"
        Set-Content -LiteralPath $exe -Value "test"
        (Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root)) | Should -Be $exe
    }

    It "does not select an executable outside matching folders" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "rpi-imager.exe" }
        $root = Join-Path $TestDrive "OtherApps"
        New-Item -ItemType Directory -Path (Join-Path $root "Unrelated") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root "Unrelated\rpi-imager.exe") -Value "test"
        { Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root) } | Should -Throw "*not found*"
    }
}
