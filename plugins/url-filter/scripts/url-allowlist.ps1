#!/usr/bin/env pwsh
# preToolUse hook: Deny tool calls that try to access a URL whose host is
# not on the allowlist in ..\allowed-domains.txt. Allowed (or unrelated)
# calls produce no output and exit 0.

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$allowlistPath = Join-Path $scriptDir '..\allowed-domains.txt'

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

# The input to the hook is expected to be a JSON object
# as described at https://docs.github.com/en/copilot/reference/hooks-configuration
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

# Pre-tool use hooks receive a payload with at least "toolName" and "toolArgs" properties
$toolName = [string]$payload.toolName
$toolArgsRaw = [string]$payload.toolArgs
$toolArgs = $null
if ($toolArgsRaw) {
    try { $toolArgs = $toolArgsRaw | ConvertFrom-Json } catch { $toolArgs = $null }
}

$urls = New-Object System.Collections.Generic.List[string]

switch -Regex ($toolName) {
    # Web fetching tools have a url paramter that we can check directly
    '^(web_fetch|fetch|http_get|url_fetch)$' {
        if ($toolArgs -and $toolArgs.url) { $urls.Add([string]$toolArgs.url) }
        break
    }

    # web_search queries may contain URLs. Scan the raw args string for any
    # http(s) URLs and check each one against the allowlist.
    '^web_search$' {
        foreach ($m in [regex]::Matches($toolArgsRaw, 'https?://[^\s"''<>`]+')) {
            $urls.Add($m.Value)
        }
        break
    }
    # Shell tools could indirectly make web requests, so we look for common
    # command line tools like curl or wget and try to extract URLs via regex.
    # A more conservative script could instead choose to deny all shell calls that
    # include unallowed URLs.
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

# Exiting with 0 without any other output allows the tool call.
if ($urls.Count -eq 0) { exit 0 }

# Parse the allowed list
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

# Gets the host of each URL and checks if it's on the allowlist. 
# If any URL is not allowed, we output a JSON object with permissionDecision 'deny' 
# and a reason, then exit 0 to block the tool call. 
# If all URLs are allowed, we exit 0 with no output to allow the tool call.
foreach ($u in $urls) {
    $h = Get-UrlHost $u
    if (-not $h -or -not (Test-HostAllowed $h)) {
        $shown = if ($h) { $h } else { '<unparseable>' }
        $reason = "URL host '$shown' is not on the approved allowlist (.github/hooks/allowed-domains.txt). **DO NOT** attempt to access this URL or data through other means."
        $obj = [pscustomobject]@{
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }

        # The objection is output to stdout as JSON.
        # The hook handler will parse this output and enforce the permission decision.
        $obj | ConvertTo-Json -Compress
        exit 0
    }
}

exit 0
