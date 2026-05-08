#!/usr/bin/env bash
# preToolUse hook: when a bash/shell/powershell tool call contains a deletion
# command (rm, rmdir, del, erase, ri, Remove-Item, Remove-ItemProperty), block
# on a TTY confirmation prompt and deny the call if the user does not
# explicitly approve. Fails closed (denies) when no TTY is available so the
# hook cannot be silently bypassed in non-interactive contexts.

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

# Need a real, writable terminal to ask the user.
if [ ! -e /dev/tty ] || ! { : >/dev/tty; } 2>/dev/null; then
  deny "rm-confirm hook requires interactive confirmation but no TTY is available; failing closed. **DO NOT** retry the same command without user approval."
fi

DISPLAY_CMD=$CMD
if [ "${#DISPLAY_CMD}" -gt 500 ]; then
  DISPLAY_CMD="${DISPLAY_CMD:0:500}..."
fi

exec 3<>/dev/tty
{
  printf '\n'
  printf '\033[1;33m⚠️  rm-confirm hook\033[0m\n'
  printf 'Copilot wants to run a %s command containing a deletion command:\n\n' "$TOOL_NAME"
  printf '  %s\n\n' "$DISPLAY_CMD"
  printf 'Allow this command? [y/N]: '
} >&3
IFS= read -r ANSWER <&3 || ANSWER=""
exec 3<&-

case "$ANSWER" in
  y|Y|yes|YES|Yes)
    exit 0
    ;;
  *)
    deny "User declined the deletion command at the rm-confirm hook prompt. **DO NOT** retry the same command without re-asking the user."
    ;;
esac
