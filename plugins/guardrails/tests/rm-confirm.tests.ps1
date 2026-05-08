# Tests for plugins\guardrails\scripts\rm-confirm.ps1.
#
# NOTE: rm-confirm.ps1 prompts via [System.Windows.Forms.MessageBox]::Show,
# which cannot be mocked from outside the script without invasive refactoring
# or fragile UI automation. These tests therefore cover only the
# non-interactive paths (early exits and false-positive guards). The
# MessageBox prompt itself is verified manually.
#
# Run directly:  pwsh plugins\guardrails\tests\rm-confirm.tests.ps1
# Or via:        pwsh plugins\guardrails\tests\run.ps1

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_helpers.ps1')
$Hook = Join-Path $here '..\scripts\rm-confirm.ps1'

Write-Host 'rm-confirm.ps1 (non-interactive paths only)' -ForegroundColor White

Invoke-TestCase 'empty input passes through' {
    Invoke-Hook -Hook $Hook -Payload ''
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'unknown tool passes through' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"view","toolArgs":"{\"path\":\"C:\\\\x\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'shell with no deletion passes through' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"ls -la /tmp\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'powershell with no deletion passes through' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"powershell","toolArgs":"{\"command\":\"Get-ChildItem C:\\\\\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'word boundary: warm is not rm' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"echo warm\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'word boundary: deleted is not del' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"echo deleted\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Invoke-TestCase 'empty command passes through' {
    Invoke-Hook -Hook $Hook -Payload '{"toolName":"bash","toolArgs":"{\"command\":\"\"}"}'
    Assert-Eq $script:HookEc  0  'exit code'
    Assert-Eq $script:HookOut '' 'stdout'
}

Complete-TestRun
