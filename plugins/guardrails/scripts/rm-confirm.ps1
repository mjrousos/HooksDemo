#!/usr/bin/env pwsh
# preToolUse hook: when a bash/shell/powershell tool call contains a deletion
# command (rm, rmdir, del, erase, ri, Remove-Item, Remove-ItemProperty), pop
# a Windows Forms MessageBox to ask the user before allowing the call. Fails
# closed (denies) when no interactive desktop is available so the hook
# cannot be silently bypassed in non-interactive contexts.

$ErrorActionPreference = 'Stop'

function Deny([string]$reason) {
    ([pscustomobject]@{
        permissionDecision       = 'deny'
        permissionDecisionReason = $reason
    }) | ConvertTo-Json -Compress
    exit 0
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$toolName = [string]$payload.toolName
if ($toolName -notin @('bash', 'shell', 'powershell')) { exit 0 }

$toolArgsRaw = [string]$payload.toolArgs
if (-not $toolArgsRaw) { exit 0 }

try { $toolArgs = $toolArgsRaw | ConvertFrom-Json } catch { exit 0 }

$cmd = [string]$toolArgs.command
if (-not $cmd) { exit 0 }

# Match common deletion commands as standalone tokens, case-insensitive.
# Word boundaries prevent matches like "warm" -> "rm" or "delete" -> "del".
$deletePattern = '(?i)\b(rm|rmdir|del|erase|ri|Remove-Item|Remove-ItemProperty)\b'
if ($cmd -notmatch $deletePattern) { exit 0 }

# Need an interactive desktop session to show the dialog.
$haveDesktop = $false
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $haveDesktop = [System.Environment]::UserInteractive
} catch {
    $haveDesktop = $false
}

if (-not $haveDesktop) {
    Deny "rm-confirm hook requires interactive confirmation but no interactive desktop is available; failing closed. **DO NOT** retry the same command without user approval."
}

$displayCmd = $cmd
if ($displayCmd.Length -gt 1000) {
    $displayCmd = $displayCmd.Substring(0, 1000) + '...'
}

$message = "Copilot wants to run a $toolName command containing a deletion command:`n`n$displayCmd`n`nAllow this command?"
$result = [System.Windows.Forms.MessageBox]::Show(
    $message,
    'rm-confirm: Confirm deletion command',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button2
)

if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
    Deny "User declined the deletion command at the rm-confirm hook prompt. **DO NOT** retry the same command without re-asking the user."
}

exit 0
