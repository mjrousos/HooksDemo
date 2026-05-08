# Runs every *.tests.ps1 file in this directory and aggregates results.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$exe = (Get-Command pwsh -ErrorAction SilentlyContinue)
if (-not $exe) { $exe = Get-Command powershell -ErrorAction Stop }
$exePath = $exe.Source

$failed = 0
$total  = 0
Get-ChildItem -LiteralPath $here -Filter '*.tests.ps1' | Sort-Object Name | ForEach-Object {
    $total++
    & $exePath -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { $failed++ }
    Write-Host ''
}

if ($total -eq 0) {
    Write-Host "No *.tests.ps1 files found in $here." -ForegroundColor Red
    exit 1
}
if ($failed -eq 0) {
    Write-Host "All $total test file(s) passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$failed of $total test file(s) had failures." -ForegroundColor Red
    exit 1
}
