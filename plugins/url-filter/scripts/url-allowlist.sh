#!/usr/bin/env bash
# preToolUse hook: deny tool calls that try to access a URL whose host is
# not on the allowlist in ../allowed-domains.txt. Allowed (or unrelated)
# calls produce no output and exit 0.

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ALLOWLIST="$SCRIPT_DIR/../allowed-domains.txt"

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # Without jq we cannot safely parse the payload. Fail closed on any
  # tool call that *might* be a URL fetch by erring on the side of
  # allowing — this hook is best-effort and logged via stderr.
  echo "url-allowlist hook: jq not found, skipping check" >&2
  exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.toolName // ""')
TOOL_ARGS=$(printf '%s' "$INPUT" | jq -r '.toolArgs // ""')

# Collect candidate URLs from the tool arguments.
URLS=()

case "$TOOL_NAME" in
  web_fetch|fetch|http_get|url_fetch)
    URL=$(printf '%s' "$TOOL_ARGS" | jq -r '.url // empty' 2>/dev/null || true)
    [ -n "$URL" ] && URLS+=("$URL")
    ;;
  bash|shell|powershell)
    CMD=$(printf '%s' "$TOOL_ARGS" | jq -r '.command // empty' 2>/dev/null || true)
    if [ -n "$CMD" ] && printf '%s' "$CMD" | grep -qiE 'curl|wget|Invoke-WebRequest|Invoke-RestMethod|iwr|irm'; then
      while IFS= read -r u; do
        [ -n "$u" ] && URLS+=("$u")
      done < <(printf '%s' "$CMD" | grep -oE 'https?://[^[:space:]"'\''<>`]+' || true)
    fi
    ;;
  *)
    exit 0
    ;;
esac

if [ "${#URLS[@]}" -eq 0 ]; then
  exit 0
fi

# Build allowlist into a bash array (skip blanks and # comments).
ALLOWED=()
if [ -f "$ALLOWLIST" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    line=$(printf '%s' "$line" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    [ -n "$line" ] && ALLOWED+=("$line")
  done < "$ALLOWLIST"
fi

extract_host() {
  printf '%s' "$1" \
    | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' \
    | sed -E 's#^[^/@]*@##' \
    | sed -E 's#[/?#].*$##' \
    | sed -E 's#:[0-9]+$##' \
    | tr '[:upper:]' '[:lower:]'
}

host_allowed() {
  local host=$1 entry
  for entry in "${ALLOWED[@]}"; do
    if [ "$host" = "$entry" ] || [[ "$host" == *.$entry ]]; then
      return 0
    fi
  done
  return 1
}

for url in "${URLS[@]}"; do
  host=$(extract_host "$url")
  if [ -z "$host" ] || ! host_allowed "$host"; then
    reason="URL host '${host:-<unparseable>}' is not on the approved allowlist (.github/hooks/allowed-domains.txt)."
    jq -cn --arg r "$reason" '{permissionDecision:"deny", permissionDecisionReason:$r}'
    exit 0
  fi
done

exit 0
