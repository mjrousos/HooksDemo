# Tests for plugins\guardrails\scripts\url-allowlist.ps1.
#
# Run directly:  pwsh plugins\guardrails\tests\url-allowlist.tests.ps1
# Or via:        pwsh plugins\guardrails\tests\run.ps1

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_helpers.ps1')
$Hook = Join-Path $here '..\scripts\url-allowlist.ps1'

Write-Host 'url-allowlist.ps1' -ForegroundColor White

# ---- pass-through paths ----

Invoke-TestCase 'empty input passes through' {
    Invoke-Hook -Hook $Hook -Payload ''
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'unknown tool passes through' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"view","toolArgs":"{\"path\":\"C:\\\\Windows\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'web_fetch with no url arg passes through' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_fetch","toolArgs":"{}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'bash with no web command passes through' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"echo https://evil.example.com\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

# ---- allow paths ----

Invoke-TestCase 'web_fetch with allowed host' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://github.com/octocat\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'web_fetch with allowed subdomain via dot rule' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://api.github.com/repos/x/y\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'web_fetch url with port' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://github.com:443/x\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'web_fetch url with userinfo' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://user:pw@github.com/x\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'web_search with allowed url in query' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_search","toolArgs":"{\"query\":\"see https://github.com/octocat\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'bash curl with allowed host' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"curl -sSL https://github.com/x\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'bash wget with allowed host' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"wget https://raw.githubusercontent.com/x/y/main/z\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'powershell Invoke-WebRequest with allowed host' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"powershell","toolArgs":"{\"command\":\"Invoke-WebRequest https://github.com/x\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

# ---- deny paths ----

Invoke-TestCase 'web_fetch with disallowed host denied' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://evil.example.com/x\"}"}'
    Assert-Eq        $script:HookEc 0 'exit code'
    Assert-Contains  $script:HookOut '"permissionDecision":"deny"' 'deny json'
    Assert-Contains  $script:HookOut 'evil.example.com'            'host in reason'
}

Invoke-TestCase 'web_fetch with confusable host denied' {
    # evilgithub.com must NOT match github.com (dot-boundary rule).
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://evilgithub.com/x\"}"}'
    Assert-Eq        $script:HookEc 0 'exit code'
    Assert-Contains  $script:HookOut '"permissionDecision":"deny"' 'deny json'
    Assert-Contains  $script:HookOut 'evilgithub.com'              'host in reason'
}

Invoke-TestCase 'web_search with disallowed url denied' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"web_search","toolArgs":"{\"query\":\"see https://evil.example.com/x\"}"}'
    Assert-Eq        $script:HookEc 0 'exit code'
    Assert-Contains  $script:HookOut '"permissionDecision":"deny"' 'deny json'
}

Invoke-TestCase 'bash curl with disallowed host denied' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"curl -sSL https://evil.example.com/x\"}"}'
    Assert-Eq        $script:HookEc 0 'exit code'
    Assert-Contains  $script:HookOut '"permissionDecision":"deny"' 'deny json'
}

Invoke-TestCase 'bash curl with multiple urls one disallowed denied' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"curl https://github.com/a && curl https://evil.example.com/b\"}"}'
    Assert-Eq        $script:HookEc 0 'exit code'
    Assert-Contains  $script:HookOut '"permissionDecision":"deny"' 'deny json'
    Assert-Contains  $script:HookOut 'evil.example.com'           'denied host in reason'
}

Complete-TestRun
