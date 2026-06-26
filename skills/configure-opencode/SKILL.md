---
name: configure-opencode
description: Create per-repo OpenCode overrides — a project-local .opencode/opencode.jsonc (model, plugins, providers, MCP enable/disable) and .opencode/oh-my-opencode.jsonc (per-agent and per-category model/variant/temperature overrides, disabled hooks/MCPs) for oh-my-openagent / engineering-agents agents. Use when a repo needs different models or agent behavior than the global ~/.config/opencode config, without editing global state or Nix.
harnesses: [opencode]
metadata:
  domain: opencode
---

## What I do
- Create or edit two project-local OpenCode config files in a repo's `.opencode/` directory:
  - `.opencode/opencode.jsonc` — OpenCode-native overrides (default `model`, `plugin` list, `disabled_providers`, per-repo `mcp` enable/disable, `share`, `agent`).
  - `.opencode/oh-my-opencode.jsonc` — oh-my-openagent / engineering-agents overrides (per-agent `model`/`variant`/`prompt_append`, per-category `model`/`temperature`, `disabled_hooks`, `disabled_mcps`, `sisyphus_agent`).
- Override only what the repo needs and let the global `~/.config/opencode/` config supply everything else.
- Keep both files valid JSONC (comments allowed) and secret-free.

## When to use me
Use this when:
- A repo should use different models than your global default (e.g. Copilot models in one repo, Z.ai in another).
- You want specific oh-my-openagent agents (`oracle`, `plan`, `sisyphus`, `atlas`, …) or categories (`quick`, `ultrabrain`, …) to use particular models/variants in this repo only.
- You need to disable a global MCP, hook, or provider inside one repo.
- You want repo-pinned plugin versions independent of the global install.

Do NOT use me to edit global config (`~/.config/opencode/...`) or Nix-managed config — this skill is for committed, per-repo `.opencode/` overrides that work with any OpenCode install.

## What I need
- The repo root (where `.opencode/` should live).
- Which models are available: run `opencode models` to list valid IDs before writing any `model` value.
- What the repo actually needs to override (models, agents, categories, MCPs, plugins). Ask if unspecified rather than copying a full config.

## Precedence (how overrides resolve)
Project config wins over global. For each file type, the first existing wins:

| Priority | oh-my-opencode | opencode |
| --- | --- | --- |
| 1 (highest) | `.opencode/oh-my-opencode.jsonc` | `.opencode/opencode.jsonc` |
| 2 | `.opencode/oh-my-opencode.json` | `.opencode/opencode.json` |
| 3 | `~/.config/opencode/oh-my-opencode.json` | `~/.config/opencode/opencode.json` |

Prefer the `.jsonc` form for repo-local files so you can leave comments. Override the smallest set of keys required; everything you omit falls back to global.

## File 1 — `.opencode/opencode.jsonc` (OpenCode-native)
OpenCode's own config. Use it for the default model, plugin pins, provider gating, and per-repo MCP servers.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "share": "disabled",

  // Repo-pinned plugins (independent of global install)
  "plugin": [
    "oh-my-opencode@3.7.4",
    "opencode-ignore@1.1.0"
  ],

  // Force a single provider family in this repo by disabling the rest
  "disabled_providers": ["openai", "anthropic", "gemini", "zai-coding-plan", "google"],

  // Default model when an agent/category does not override it
  "model": "github-copilot/gpt-5.3-codex",

  // Turn global MCPs off here, add repo-specific ones
  "mcp": {
    "web-search-prime": { "type": "remote", "url": "https://api.z.ai/api/mcp/web_search_prime/mcp", "enabled": false },
    "context7": { "type": "local", "command": ["npx", "-y", "@upstash/context7-mcp"], "enabled": true }
  },

  "agent": {}
}
```

Key fields:
- `model` — default model ID for the session (must exist in `opencode models`).
- `plugin` — array of `name@version`; repo pin overrides the global plugin list.
- `disabled_providers` — provider IDs to disable in this repo.
- `mcp` — per-server config; set `"enabled": false` to silence a global MCP, or add a new local/remote server.
- `share` — `"disabled"` to prevent session sharing.

### Important: preserving the built-in `plan` agent
If you override `agent.plan` in `.opencode/opencode.jsonc`, include `"mode": "primary"` unless you intentionally want `plan` to become a subagent. In current oh-my-openagent runtime behavior, config-defined agents with no explicit `mode` can be defaulted to `subagent`, even when `sisyphus_agent.replace_plan` is `false`.

Safe pattern:

```jsonc
"agent": {
  "plan": {
    "model": "github-copilot/gpt-5.5",
    "mode": "primary"
  }
}
```

## File 2 — `.opencode/oh-my-opencode.jsonc` (agent + category model overrides)
oh-my-openagent / engineering-agents config. Use it to route specific agents and delegation categories to specific models.

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json",

  // Per-agent model overrides
  "agents": {
    "sisyphus": { "model": "github-copilot/claude-sonnet-4.6" },
    "sisyphus-junior": { "model": "github-copilot/claude-sonnet-4.6" },
    "build": { "model": "github-copilot/gpt-5.3-codex", "variant": "xhigh" },
    "plan": { "model": "github-copilot/gpt-5.5", "variant": "xhigh" },
    "oracle": { "model": "github-copilot/gpt-5.5", "variant": "xhigh" },
    "explore": { "model": "github-copilot/gpt-5.4-mini" }
  },

  // Per-category overrides (used by delegate_task(category="..."))
  "categories": {
    "quick": { "model": "github-copilot/gpt-5.4-mini", "temperature": 0.3 },
    "ultrabrain": { "model": "github-copilot/gpt-5.5", "temperature": 0.1 },
    "visual-engineering": { "model": "github-copilot/claude-sonnet-4.6", "temperature": 0.7 }
  },

  "disabled_hooks": ["keyword-detector"],
  "disabled_mcps": ["websearch"],

  "sisyphus_agent": {
    "default_builder_enabled": true,
    "disabled": false,
    "planner_enabled": true,
    "replace_plan": false
  }
}
```

### Valid agent keys
Lowercase except `OpenCode-Builder`. Verify against the schema for the plugin version pinned in `opencode.jsonc`.

`sisyphus`, `sisyphus-junior`, `prometheus`, `metis`, `momus`, `atlas`, `OpenCode-Builder`, `build`, `plan`, `oracle`, `librarian`, `explore`, `multimodal-looker`, `deep`.

Per-agent fields: `model` (required to override), `variant` (e.g. `xhigh` for reasoning models), `prompt_append` (extra system text for that agent).

`agents.plan` in `.opencode/oh-my-opencode.jsonc` only tunes the oh-my-openagent-side planner settings. It does **not** replace the need to keep OpenCode's native `agent.plan` primary when you override it in `.opencode/opencode.jsonc`.

### Valid category keys
`quick`, `ultrabrain`, `writing`, `visual-engineering`, `artistry`, `unspecified-low`, `unspecified-high`, `deep`.

Per-category fields: `model`, `temperature`.

## Process
1. Confirm the repo root and create `.opencode/` if missing.
2. Run `opencode models` and pick only IDs that exist in the user's environment.
3. Decide which file(s) you need:
   - Default model / plugins / providers / MCP → `opencode.jsonc`.
   - Agent or category model routing / disabled hooks / sisyphus knobs → `oh-my-opencode.jsonc`.
4. Write the minimal override. Start from the smallest set of keys; do not paste a full config.
5. Match the agent/category key names exactly (lowercase, except `OpenCode-Builder`) — unknown keys are silently ignored.
6. Keep both files JSONC and secret-free (no API keys; rely on `opencode auth login` or `{env:VAR}` references).
7. Tell the user to restart OpenCode to pick up the new config, and to verify with `opencode models` if a model "not found" warning appears.

## Non-goals
- I will not edit global config under `~/.config/opencode/` or any Nix-managed config — only committed per-repo `.opencode/` files.
- I will not invent model IDs; every `model` value must be confirmed via `opencode models`.
- I will not add secrets to config files.
- I will not duplicate a full global config into a repo; repo files override only what differs.

## Examples
- "Make this repo use Copilot GPT-5.3-codex by default and route `oracle`/`plan` to gpt-5.5 xhigh." → create both `.opencode/opencode.jsonc` (`model`) and `.opencode/oh-my-opencode.jsonc` (`agents`).
- "Disable the Z.ai web-search MCP and the keyword-detector hook just in this repo." → `opencode.jsonc` `mcp.*.enabled=false` + `oh-my-opencode.jsonc` `disabled_hooks`/`disabled_mcps`.
- "Use the cheap mini model for the `quick` category here." → `.opencode/oh-my-opencode.jsonc` `categories.quick`.
- "Pin oh-my-opencode 3.7.4 for this repo only." → `.opencode/opencode.jsonc` `plugin`.

## Troubleshooting
- **Keys ignored silently** — agent/category key does not match the schema. Use lowercase keys (except `OpenCode-Builder`) and check the schema for your pinned plugin version.
- **`plan` disappeared from the agent picker** — if `.opencode/opencode.jsonc` overrides `agent.plan`, add `"mode": "primary"`. `sisyphus_agent.replace_plan = false` alone may not preserve visibility when the OpenCode-native `plan` override omits `mode`.
- **"Configured model not found" / fallback** — the model ID is unavailable. Run `opencode models` and pick a valid ID, or authenticate the provider via `opencode auth login`.
- **Override not applied** — confirm the file is at `.opencode/<name>.jsonc` in the repo OpenCode is running from, valid JSONC, and that OpenCode was restarted.
