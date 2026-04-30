# HooksDemo

A collection of [GitHub Copilot CLI plugins](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating)
that demonstrate how to use [hooks](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-hooks)
to extend and constrain Copilot agent behavior.

Each subdirectory under [`plugins/`](./plugins) is a self-contained,
installable plugin packaging one or more hook scripts together with a
`plugin.json` manifest.

## Plugins

| Plugin | Description |
| --- | --- |
| [`plugins/url-filter`](./plugins/url-filter) | Adds a `preToolUse` hook that denies any tool call attempting to fetch a URL whose host is not on an editable allowlist. |

More plugins demonstrating other hook triggers (e.g. `sessionStart`,
`userPromptSubmitted`, `postToolUse`, `errorOccurred`) may be added over
time.

## Installing a plugin locally

From the repository root:

```sh
copilot plugin install ./plugins/url-filter
copilot plugin list
```

Re-run `copilot plugin install ./plugins/<name>` whenever you change a
plugin's files — the CLI caches plugin contents and only refreshes on
install.

To uninstall, use the `name` from the plugin's `plugin.json`:

```sh
copilot plugin uninstall url-filter
```

## Repository layout

```
.
├── .github/hooks/        # Repository-scoped hooks (auto-loaded by Copilot in this repo)
├── plugins/              # Installable plugins (one subdirectory per plugin)
│   └── url-filter/
└── README.md
```

## Further reading

- [About hooks](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-hooks)
- [Hooks configuration reference](https://docs.github.com/en/copilot/reference/hooks-configuration)
- [CLI plugin reference](https://docs.github.com/en/copilot/reference/cli-plugin-reference)
