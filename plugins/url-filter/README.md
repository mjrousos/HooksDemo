# URL allowlist hook for GitHub Copilot CLI

This directory contains a demo [`preToolUse`][hooks-docs] hook that blocks
GitHub Copilot CLI from fetching any URL whose host is not on an approved
allowlist.

[hooks-docs]: https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks

## Layout

```
.github/hooks/
├── hooks.json              # registers the preToolUse hook
├── allowed-domains.txt     # one domain per line (# comments allowed)
└── scripts/
    ├── url-allowlist.sh    # Bash implementation (needs jq)
    └── url-allowlist.ps1   # PowerShell implementation
```

## How it works

For every tool invocation, Copilot CLI runs the hook with a JSON payload
on stdin like:

```json
{
  "timestamp": 1704614600000,
  "cwd": "/path/to/project",
  "toolName": "web_fetch",
  "toolArgs": "{\"url\":\"https://example.com/foo\"}"
}
```

The script:

1. Returns immediately (exit 0, no output) for tool calls that have nothing
   to do with URLs.
2. For URL-fetching tools (`web_fetch`, `fetch`, `http_get`, `url_fetch`)
   it pulls the `url` argument directly.
3. For shell tools (`bash`, `shell`, `powershell`) it scans the command
   for `curl` / `wget` / `Invoke-WebRequest` / `Invoke-RestMethod` /
   `iwr` / `irm` and extracts every `http(s)://…` URL.
4. Each URL's host is compared to `allowed-domains.txt`. A host matches
   an entry if it is exactly equal **or** ends with `.<entry>` — so
   `github.com` allows `api.github.com` but not `evilgithub.com`.
5. The first non-matching URL produces a single-line deny response:

   ```json
   {"permissionDecision":"deny","permissionDecisionReason":"URL host 'example.com' is not on the approved allowlist (.github/hooks/allowed-domains.txt)."}
   ```

   Per the [hooks reference][ref], only `deny` is currently honored, so
   allowed calls simply exit 0 with no output.

[ref]: https://docs.github.com/en/copilot/reference/hooks-configuration

## Editing the allowlist

Edit `allowed-domains.txt`. One domain per line, blank lines and `#`
comments are ignored. Changes take effect on the next tool call — no
restart required.

## Testing locally

Pipe sample payloads into the script and check the exit code / output.

Bash:

```bash
# allowed
echo '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://docs.github.com/en\"}"}' \
  | .github/hooks/scripts/url-allowlist.sh
echo "exit=$?"

# blocked
echo '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://example.com/\"}"}' \
  | .github/hooks/scripts/url-allowlist.sh

# unrelated tool — no output, exit 0
echo '{"toolName":"edit","toolArgs":"{\"path\":\"src/app.ts\"}"}' \
  | .github/hooks/scripts/url-allowlist.sh
```

PowerShell:

```powershell
'{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://docs.github.com/en\"}"}' `
  | pwsh -File .github/hooks/scripts/url-allowlist.ps1

'{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://example.com/\"}"}' `
  | pwsh -File .github/hooks/scripts/url-allowlist.ps1

'{"toolName":"bash","toolArgs":"{\"command\":\"curl https://evil.test/x\"}"}' `
  | pwsh -File .github/hooks/scripts/url-allowlist.ps1
```

## Extending

- **Logging.** Append the decision to a log file inside the script, e.g.
  `Add-Content .github/hooks/logs/audit.jsonl …`. Add
  `.github/hooks/logs/` to `.gitignore`.
- **Per-tool rules.** Extend the `switch`/`case` block to recognize
  additional tool names your environment exposes.
- **Stricter parsing.** Replace the regex URL extraction in the shell
  branch with a dedicated parser if you need to handle exotic command
  lines.
