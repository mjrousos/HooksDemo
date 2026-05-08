# Test helpers for the guardrails hook script tests (PowerShell side).
# Dot-sourced by *.tests.ps1 files.

$script:Pass = 0
$script:Fail = 0
$script:HookOut = ''
$script:HookErr = ''
$script:HookEc  = 0

function script:Get-PowerShellExe {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command powershell -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'Neither pwsh nor powershell.exe found on PATH.'
}

function Invoke-Hook {
    param(
        [Parameter(Mandatory)][string]$Hook,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Payload
    )
    $stdinFile  = [System.IO.Path]::GetTempFileName()
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        # Write the payload as raw UTF-8 (no BOM, no trailing newline) so the
        # hook sees exactly what Copilot would feed it.
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($stdinFile, $Payload, $utf8)

        $exe = Get-PowerShellExe
        $proc = Start-Process -FilePath $exe `
            -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', $Hook) `
            -RedirectStandardInput  $stdinFile `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError  $stderrFile `
            -PassThru -Wait -NoNewWindow

        $script:HookEc = $proc.ExitCode
        $out = Get-Content -LiteralPath $stdoutFile -Raw
        $err = Get-Content -LiteralPath $stderrFile -Raw
        if ($null -eq $out) { $out = '' }
        if ($null -eq $err) { $err = '' }
        $script:HookOut = $out.TrimEnd("`r","`n")
        $script:HookErr = $err.TrimEnd("`r","`n")
    } finally {
        Remove-Item -LiteralPath $stdinFile,$stdoutFile,$stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Assert-Eq {
    param($Actual, $Expected, [string]$Label = 'value')
    if ($Actual -ne $Expected) {
        throw "$Label mismatch:`n  expected: [$Expected]`n  actual:   [$Actual]"
    }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Label = 'output')
    if ($Haystack -notlike "*$Needle*") {
        throw "$Label missing '$Needle':`n  actual: [$Haystack]"
    }
}

function Assert-NotContains {
    param([string]$Haystack, [string]$Needle, [string]$Label = 'output')
    if ($Haystack -like "*$Needle*") {
        throw "$Label unexpectedly contains '$Needle':`n  actual: [$Haystack]"
    }
}

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Pass++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } catch {
        $script:Fail++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        $msg = if ($_.Exception.Message) { $_.Exception.Message } else { "$_" }
        foreach ($line in ($msg -split "`n")) {
            Write-Host "         $line" -ForegroundColor Red
        }
    }
}

function Complete-TestRun {
    $total = $script:Pass + $script:Fail
    Write-Host ''
    if ($script:Fail -eq 0) {
        Write-Host "$($script:Pass)/$total passed" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "$($script:Fail)/$total failed ($($script:Pass) passed)" -ForegroundColor Red
        exit 1
    }
}
