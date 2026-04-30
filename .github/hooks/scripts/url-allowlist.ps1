#!/usr/bin/env pwsh
# preToolUse hook: deny tool calls that try to access a URL whose host is
# not on the allowlist in ..\allowed-domains.txt. Allowed (or unrelated)
# calls produce no output and exit 0.

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$allowlistPath = Join-Path $scriptDir '..\allowed-domains.txt'

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$toolName = [string]$payload.toolName
$toolArgsRaw = [string]$payload.toolArgs
$toolArgs = $null
if ($toolArgsRaw) {
    try { $toolArgs = $toolArgsRaw | ConvertFrom-Json } catch { $toolArgs = $null }
}

$urls = New-Object System.Collections.Generic.List[string]

switch -Regex ($toolName) {
    '^(web_fetch|fetch|http_get|url_fetch)$' {
        if ($toolArgs -and $toolArgs.url) { $urls.Add([string]$toolArgs.url) }
        break
    }
    '^(bash|shell|powershell)$' {
        $cmd = $null
        if ($toolArgs -and $toolArgs.command) { $cmd = [string]$toolArgs.command }
        if ($cmd -and $cmd -match '(?i)curl|wget|Invoke-WebRequest|Invoke-RestMethod|\biwr\b|\birm\b') {
            foreach ($m in [regex]::Matches($cmd, 'https?://[^\s"''<>`]+')) {
                $urls.Add($m.Value)
            }
        }
        break
    }
    default { exit 0 }
}

if ($urls.Count -eq 0) { exit 0 }

$allowed = @()
if (Test-Path $allowlistPath) {
    foreach ($line in Get-Content -LiteralPath $allowlistPath) {
        $clean = ($line -split '#', 2)[0].Trim().ToLowerInvariant()
        if ($clean) { $allowed += $clean }
    }
}

function Get-UrlHost([string]$url) {
    try { return ([Uri]$url).Host.ToLowerInvariant() } catch { return '' }
}

function Test-HostAllowed([string]$h) {
    foreach ($entry in $allowed) {
        if ($h -eq $entry -or $h.EndsWith('.' + $entry)) { return $true }
    }
    return $false
}

foreach ($u in $urls) {
    $h = Get-UrlHost $u
    if (-not $h -or -not (Test-HostAllowed $h)) {
        $shown = if ($h) { $h } else { '<unparseable>' }
        $reason = "URL host '$shown' is not on the approved allowlist (.github/hooks/allowed-domains.txt)."
        $obj = [pscustomobject]@{
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
        $obj | ConvertTo-Json -Compress
        exit 0
    }
}

exit 0
