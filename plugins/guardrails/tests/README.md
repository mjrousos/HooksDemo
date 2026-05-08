# guardrails plugin tests

Regression tests for the hook scripts in [`../scripts/`](../scripts). Each
hook script has both a `bash` and a `pwsh` variant, so the test suite is
also split between the two.

## Running

```sh
# bash side (Linux, macOS, WSL)
bash plugins/guardrails/tests/run.sh

# PowerShell side (Windows or pwsh on any platform)
pwsh plugins/guardrails/tests/run.ps1
```

Individual test files are also runnable on their own:

```sh
bash plugins/guardrails/tests/url-allowlist.tests.sh
pwsh plugins/guardrails/tests/rm-confirm.tests.ps1
```

Each runner exits `0` when every assertion passes and `1` otherwise, so the
suites are CI-friendly.

## What is covered

- **`url-allowlist.{sh,ps1}`** — the full pass-through / allow / deny matrix
  for `web_fetch`, `web_search`, and `bash`/`shell`/`powershell` invocations
  containing `curl` / `wget` / `Invoke-WebRequest`. Includes the
  dot-boundary rule (`api.github.com` allowed via `github.com`,
  `evilgithub.com` denied), URLs with port numbers and userinfo, and the
  multi-URL "one disallowed denies the call" case.
- **`rm-confirm.sh`** — every non-interactive path (early exits, the
  word-boundary guards that stop `warm`/`deleted` from triggering on
  `rm`/`del`), the "no GUI tools available → fail closed" deny path, and —
  via a mocked `zenity` injected into `PATH` — the user-says-yes and
  user-says-no paths. Each deletion token (`rm`, `rmdir`, `Remove-Item`,
  `Remove-ItemProperty`) is verified to actually trigger the prompt.
- **`rm-confirm.ps1`** — only the non-interactive paths. The
  `MessageBox` prompt cannot be mocked from outside the script without
  invasive refactoring or fragile UI automation, so it is verified
  manually.

## Requirements

- bash side: `bash`, `jq`, plus the standard coreutils used by the hook
  itself (`grep`, `sed`, `tr`, `tail`, `cat`, `base64`, `mktemp`, `chmod`).
- PowerShell side: `pwsh` (PowerShell 7+) or Windows PowerShell 5.1.

## Layout

```
tests/
├── _helpers.sh             # bash assertions + Invoke-Hook helper
├── _helpers.ps1            # pwsh assertions + Invoke-Hook helper
├── rm-confirm.tests.ps1
├── rm-confirm.tests.sh
├── run.ps1                 # invokes every *.tests.ps1
├── run.sh                  # invokes every *.tests.sh
├── url-allowlist.tests.ps1
└── url-allowlist.tests.sh
```
