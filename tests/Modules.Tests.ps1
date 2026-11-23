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


Describe "Raspberry Pi Imager discovery and caching" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../modules/Image.ps1")
    }

    BeforeEach {
        $configPath = Join-Path $TestDrive "config.local.json"
        Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
        $root = Join-Path $TestDrive "ImagerTestRoot"
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }

    It "reuses an existing cached path without searching" {
        $exe = Join-Path $TestDrive "custom-imager.exe"
        Set-Content -LiteralPath $exe -Value "test"
        @{ imagerPath = $exe } | ConvertTo-Json | Set-Content -LiteralPath $configPath
        (Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @()) | Should -Be $exe
    }

    It "rejects a relative configured path" {
        '{"imagerPath":"relative.exe"}' | Set-Content -LiteralPath $configPath
        { Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @() } | Should -Throw "*absolute path*"
    }

    It "rejects malformed JSON config" {
        '{"imagerPath":' | Set-Content -LiteralPath $configPath
        { Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @() } | Should -Throw "*Unable to read Imager configuration*"
    }

    It "announces directory search when no cached path is available" {
        $directory = Join-Path $root "Raspberry Pi Ltd\Imager"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $directory "rpi-imager.exe") -Value "test"
        Mock Write-Host {}
        Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root) | Out-Null
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -eq "Searching for Raspberry Pi Imager in program directories..."
        }
    }

    It "skips search message when cached path is valid" {
        $exe = Join-Path $TestDrive "cached-imager.exe"
        Set-Content -LiteralPath $exe -Value "test"
        @{ imagerPath = $exe } | ConvertTo-Json | Set-Content -LiteralPath $configPath
        Mock Write-Host {}
        Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @() | Out-Null
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter {
            $Object -eq "Searching for Raspberry Pi Imager in program directories..."
        }
    }

    It "discovers an executable and saves its path on first use" {
        $directory = Join-Path $root "Raspberry Pi Ltd\Imager"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $exe = Join-Path $directory "rpi-imager.exe"
        Set-Content -LiteralPath $exe -Value "test"

        (Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root)) | Should -Be $exe
        (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).imagerPath | Should -Be $exe
        # Cache should work even when the search roots are empty on a later run.
        (Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @()) | Should -Be $exe
    }

    It "refreshes an invalid cache and preserves other keys" {
        @{ imagerPath = (Join-Path $TestDrive "missing.exe"); marker = "keep" } |
            ConvertTo-Json | Set-Content -LiteralPath $configPath
        $directory = Join-Path $root "Portable Imager\bin"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $exe = Join-Path $directory "rpi-imager.exe"
        Set-Content -LiteralPath $exe -Value "test"

        (Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root)) | Should -Be $exe
        $saved = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $saved.imagerPath | Should -Be $exe
        $saved.marker | Should -Be "keep"
    }

    It "rejects multiple distinct executables without overwriting the config" {
        foreach ($folder in @("Raspberry One", "Imager Two")) {
            $directory = Join-Path $root $folder
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory "rpi-imager.exe") -Value "test"
        }
        { Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root) } | Should -Throw "*Multiple Raspberry Pi Imager executables*"
        Test-Path -LiteralPath $configPath | Should -BeFalse
    }

    It "ignores an executable outside folders matching Raspberry or Imager" {
        $directory = Join-Path $root "OtherApps"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $directory "rpi-imager.exe") -Value "test"
        { Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root) } | Should -Throw "*not found*"
    }

    It "does not overwrite a stale cache when rediscovery fails" {
        $oldPath = Join-Path $TestDrive "missing.exe"
        @{ imagerPath = $oldPath } | ConvertTo-Json | Set-Content -LiteralPath $configPath
        { Resolve-ImagerPath -ConfigPath $configPath -SearchRoots @($root) } | Should -Throw "*not found*"
        (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).imagerPath | Should -Be $oldPath
    }
}
