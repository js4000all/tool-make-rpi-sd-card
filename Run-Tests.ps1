# Run the project's Pester 5 tests from any working directory.
# Usage: .\Run-Tests.ps1
$ErrorActionPreference = "Stop"

$pester5 = Get-Module -Name Pester -ListAvailable |
    Where-Object { $_.Version -ge [version]"5.0.0" } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester5) {
    throw "Pester 5 or later is required. Install it with: Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck"
}

$loadedPester = @(Get-Module -Name Pester)
if ($loadedPester.Count -gt 0) {
    $loadedPester | Remove-Module -Force -ErrorAction Stop
}

Import-Module -Name $pester5.Path -Force -ErrorAction Stop

$testsDirectory = Join-Path $PSScriptRoot "tests"
$result = Invoke-Pester -Path $testsDirectory -PassThru

if ($result.FailedCount -gt 0 -or $result.PassedCount -eq 0 -or $result.NotRunCount -gt 0) {
    throw "Pester tests did not pass: $($result.PassedCount) passed, $($result.FailedCount) failed, $($result.NotRunCount) not run."
}
