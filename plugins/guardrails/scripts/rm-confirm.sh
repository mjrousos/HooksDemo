#!/usr/bin/env bash
# preToolUse hook: when a bash/shell/powershell tool call contains a deletion
# command (rm, rmdir, del, erase, ri, Remove-Item, Remove-ItemProperty), pop
# an out-of-band confirmation dialog and deny the call if the user does not
# explicitly approve. Fails closed (denies) when no dialog tool is available
# so the hook cannot be silently bypassed in non-interactive contexts.
#
# We deliberately do NOT prompt on /dev/tty: Copilot's TUI puts the terminal
# in raw / alt-screen mode and reads stdin itself, so an in-terminal prompt
# from a child process is invisible and unresponsive (the keystrokes go to
# the TUI). Instead we pop a separate window via, in priority order:
#   1. zenity            (GTK; works on most Linux desktops and WSLg)
#   2. kdialog           (KDE)
#   3. powershell.exe    (under WSL, shows a Windows Forms MessageBox)

set -u

INPUT=$(cat)

deny() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$1" '{permissionDecision:"deny", permissionDecisionReason:$r}'
  else
    esc=${1//\\/\\\\}
    esc=${esc//\"/\\\"}
    printf '{"permissionDecision":"deny","permissionDecisionReason":"%s"}\n' "$esc"
  fi
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  echo "rm-confirm hook: jq not found; failing closed" >&2
  deny "rm-confirm hook could not parse the tool payload because jq is not installed. Install jq or remove this hook. **DO NOT** retry the same command without user approval."
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.toolName // ""')
case "$TOOL_NAME" in
  bash|shell|powershell) ;;
  *) exit 0 ;;
esac

TOOL_ARGS=$(printf '%s' "$INPUT" | jq -r '.toolArgs // ""')
CMD=$(printf '%s' "$TOOL_ARGS" | jq -r '.command // empty' 2>/dev/null || true)

if [ -z "$CMD" ]; then
  exit 0
fi

# Match common deletion commands as standalone tokens, case-insensitive.
# Word boundaries prevent matches like "warm" -> "rm" or "delete" -> "del".
DELETE_PATTERN='\b(rm|rmdir|del|erase|ri|Remove-Item|Remove-ItemProperty)\b'
if ! printf '%s' "$CMD" | grep -qiE "$DELETE_PATTERN"; then
  exit 0
fi

DISPLAY_CMD=$CMD
if [ "${#DISPLAY_CMD}" -gt 500 ]; then
  DISPLAY_CMD="${DISPLAY_CMD:0:500}..."
fi

TITLE='rm-confirm: Confirm deletion command'
MESSAGE="Copilot wants to run a $TOOL_NAME command containing a deletion command:

$DISPLAY_CMD

Allow this command?"

# Each prompt_* function returns:
#   0  -> user said yes
#   1  -> user said no
#   2+ -> tool unavailable or dialog could not be shown; try the next strategy

prompt_zenity() {
  command -v zenity >/dev/null 2>&1 || return 2
  [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || return 2
  zenity --question \
    --title="$TITLE" \
    --text="$MESSAGE" \
    --default-cancel \
    --width=600 \
    >/dev/null 2>&1
  local rc=$?
  case $rc in
    0) return 0 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

prompt_kdialog() {
  command -v kdialog >/dev/null 2>&1 || return 2
  [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || return 2
  kdialog --title "$TITLE" --warningyesno "$MESSAGE" >/dev/null 2>&1
  local rc=$?
  case $rc in
    0) return 0 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

prompt_powershell_wsl() {
  command -v powershell.exe >/dev/null 2>&1 || return 2
  command -v base64         >/dev/null 2>&1 || return 2

  # base64-encode the title/message so the payload (which contains the literal
  # shell command and may include any combination of quotes, backticks, $,
  # newlines, etc.) can be safely embedded in the PowerShell script as a
  # plain ASCII string literal.
  local title_b64 msg_b64
  title_b64=$(printf '%s' "$TITLE"   | base64 | tr -d '\n')
  msg_b64=$(  printf '%s' "$MESSAGE" | base64 | tr -d '\n')

  local ps_script
  ps_script="\$ErrorActionPreference='Stop';
Add-Type -AssemblyName System.Windows.Forms | Out-Null;
\$t=[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$title_b64'));
\$m=[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$msg_b64'));
\$r=[System.Windows.Forms.MessageBox]::Show(\$m,\$t,
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button2);
if (\$r -eq [System.Windows.Forms.DialogResult]::Yes) { 'YES' } else { 'NO' }"

  local out
  out=$(powershell.exe -NoProfile -NonInteractive -Command "$ps_script" 2>/dev/null \
          | tr -d '\r' | tail -n 1 | tr -d '[:space:]')
  case "$out" in
    YES) return 0 ;;
    NO)  return 1 ;;
    *)   return 2 ;;
  esac
}

answer=
for prompt in prompt_zenity prompt_kdialog prompt_powershell_wsl; do
  $prompt
  rc=$?
  case $rc in
    0) answer=yes; break ;;
    1) answer=no;  break ;;
    *) ;;  # tool not available; try the next one
  esac
done

is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
  if [ -r /proc/sys/kernel/osrelease ]; then
    grep -qi 'microsoft\|wsl' /proc/sys/kernel/osrelease 2>/dev/null && return 0
  fi
  return 1
}

if [ -z "$answer" ]; then
  if is_wsl; then
    deny "rm-confirm hook could not find a usable confirmation dialog under WSL (tried zenity, kdialog, and the powershell.exe MessageBox fallback). Install zenity in your WSL distro: \`sudo apt install zenity\`. **DO NOT** retry the same command without user approval."
  else
    deny "rm-confirm hook could not find a usable confirmation dialog. Install zenity: \`sudo apt install zenity\` (kdialog is also supported on KDE). **DO NOT** retry the same command without user approval."
  fi
fi

if [ "$answer" = yes ]; then
  exit 0
fi

deny "User declined the deletion command at the rm-confirm hook prompt. **DO NOT** retry the same command without re-asking the user."
