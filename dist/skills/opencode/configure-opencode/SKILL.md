---
name: configure-opencode
description: Create or update repo-local OpenCode overrides — `.opencode/opencode.jsonc` plus canonical `.opencode/oh-my-openagent.jsonc` — to align a repo with the desired agent/category model routing, MCP/provider behavior, and existing custom-agent strategy without editing global config.
compatibility: opencode
metadata:
  domain: opencode
---

## What I do
- Create or edit two repo-local OpenCode config files inside `.opencode/`:
  - `.opencode/opencode.jsonc` — OpenCode-native overrides for default `model`, provider gating, plugin pins, MCP servers, and inline `agent` overrides.
  - `.opencode/oh-my-openagent.jsonc` — canonical oh-my-openagent plugin overrides for built-in agent routing, categories, disabled hooks/MCPs, and related plugin behavior.
- Align a repo with an existing OpenCode/oh-my-openagent setup when the user wants one repo to mirror another.
- Inspect existing repo-local custom agents before changing them, then preserve, migrate, disable, or remove them only according to explicit user intent.
- Keep config JSONC-valid, minimal, and secret-free.

## When to use me
Use this when:
- A repo should use different models than the user's global OpenCode defaults.
- The user wants a repo to match or resemble another working OpenCode config.
- The user wants repo-local routing for built-in oh-my-openagent agents or categories.
- The user wants repo-local MCP/provider/plugin overrides.
- The repo already has local custom agents and the user wants help deciding how they should coexist with updated config.

Do NOT use me to edit global config under `~/.config/opencode/` or Nix-managed config. This skill is for committed, repo-local overrides only.

## Canonical file names and precedence

### Canonical naming
- Canonical plugin config basename: `.opencode/oh-my-openagent.jsonc`
- Legacy-compatible basenames: `.opencode/oh-my-opencode.jsonc`, `.opencode/oh-my-openagent.json`, `.opencode/oh-my-opencode.json`

Prefer the canonical `oh-my-openagent` name for all new repo-local work.

### Important compatibility warning
During the rename transition, runtime still recognizes both `oh-my-openagent` and legacy `oh-my-opencode` basenames. If both exist in the same directory, the legacy file may win in some resolution paths. Do **not** create both names in the same repo unless the user explicitly needs that compatibility behavior.

### Resolution order
Three independent things determine which config wins. Do not collapse them into one priority list.

**1. Directory walk (project vs user).** Project configs are discovered by walking from the working directory upward to `$HOME`; the closest directory wins. User config (`~/.config/opencode/`) is the fallback when no project config is found.

**2. In-directory basename tiebreak (the gotcha).** Within a single directory, `.json` vs `.jsonc` and canonical vs legacy names are resolved by the runtime, not by "canonical is always first." For the oh-my-openagent plugin config specifically, detection currently checks the legacy `oh-my-opencode.*` basename **before** `oh-my-openagent.*`, so if both exist in the same directory the **legacy file wins**. This is why you must not create both names side by side. Prefer `.jsonc` over `.json` so comments survive.

**3. File-type chains.** OpenCode-native config and plugin config resolve on separate chains:

| Config type | Canonical repo-local | Legacy repo-local (compat) | User fallback |
| --- | --- | --- | --- |
| OpenCode-native | `.opencode/opencode.jsonc` (then `.json`) | — | `~/.config/opencode/opencode.json[c]` |
| oh-my-openagent plugin | `.opencode/oh-my-openagent.jsonc` (then `.json`) | `.opencode/oh-my-opencode.jsonc` (then `.json`) — currently wins in-directory | `~/.config/opencode/oh-my-openagent.json[c]` or `oh-my-opencode.json[c]` |

For all new work use the canonical `oh-my-openagent.jsonc` and do not also add a legacy basename in the same repo.

## What I need before editing
- The repo root where `.opencode/` lives.
- The target behavior: what should differ from the user's global config.
- The available model IDs from `opencode models`. Never invent model IDs.
- Whether the user wants exact mirroring of another config or just a similar pattern.
- Whether the repo already contains local custom agents, and if so what the user wants done with them.

If the user has not specified model strategy, agent/category routing, or custom-agent disposition, ask instead of guessing.

## If the user has an existing config to mirror
When the user says anything like:
- “make this repo similar to my other config”
- “mirror the config from repo X”
- “use the same models as my other workspace”
- “align this repo with my usual OpenCode setup”

you must inspect that reference config first.

Process for alignment requests:
1. Read the reference config files directly.
2. Determine whether the user wants exact mirroring or only pattern-level similarity.
3. Copy only the repo-local overrides that matter for this repo.
4. Do **not** blindly duplicate unrelated global/user-specific behavior.
5. Tell the user which parts were mirrored exactly and which parts were intentionally omitted.

## Handling existing custom agents
Before changing repo-local custom agents, inspect what already exists.

Check for at least these cases:
1. Inline custom agents in `opencode.jsonc` under the `agent` key.
2. Custom agent files loaded from `.opencode/agents/`.
3. Stale or legacy agent content elsewhere that may not actually be active.

Do **not** assume every `.opencode/agent` or similar directory is active runtime configuration. Verify current discovery behavior first.

Default behavior:
- Inspect existing custom-agent definitions.
- Determine which ones are actually active.
- Ask the user what should happen if intent is not explicit.

Ask a question equivalent to:
> “I found existing repo-local custom agents. Do you want me to preserve them, migrate them to the new config pattern, disable them, or remove them?”

Do **not** disable or remove custom agents by default.

If the user explicitly wants them disabled, use the mechanism appropriate to the active form:
- inline `opencode.jsonc` `agent` definitions → remove or rewrite those definitions as requested
- `.opencode/agents/` custom agents → disable via config or remove/migrate as requested
- plugin-level disablement → use `disabled_agents` only when the user explicitly wants disablement rather than preservation/migration

## Which file routes which agent
The two files hold different agent sets, and some overlap is normal.

- **`opencode.jsonc` `agent`** — OpenCode-native agents: `build`, `plan`, `planner`, `plan-reviewer`, `code-reviewer`, `worker`, `ui-worker`, and any repo-defined custom agents.
- **`.opencode/oh-my-openagent.jsonc` `agents`** — oh-my-openagent built-ins: `sisyphus`, `sisyphus-junior`, `oracle`, `explore`, `librarian`, `atlas`, `prometheus`, `metis`, `momus`, `multimodal-looker`, `deep`, `hephaestus`, plus `OpenCode-Builder`. `hephaestus` is the direct-subagent Strong rescue implementer used by team-mode escalations — see [Team-Mode Execution](../../docs/team-mode-execution.md).

Overlap (e.g. `plan`, `build`, `worker` appearing in both) is intentional and sometimes required: the OpenCode-native side controls the agent as OpenCode sees it, and the plugin side controls oh-my-openagent routing/behavior. When an agent exists in both, keep the model choices consistent unless you have a specific reason to diverge. If you only need to change plugin-driven behavior, edit only `oh-my-openagent.jsonc`.

## File 1 — `.opencode/opencode.jsonc`
Use OpenCode-native config for:
- default session `model`
- provider gating via `disabled_providers`
- repo-pinned plugins
- repo-local MCP server enable/disable
- inline `agent` overrides for OpenCode-visible agents

### Standard baseline example
Use this as the default example for repos that want the user's established default model-routing pattern unless the user requests something else.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",

  // Repo-local override: use the established default model-routing pattern in this workspace.
  "model": "github-copilot/gpt-5.4",

  "agent": {
    "build": { "model": "github-copilot/gpt-5.3-codex" },
    "plan": { "model": "github-copilot/claude-opus-4.8", "mode": "primary" },
    "planner": { "model": "github-copilot/claude-opus-4.8" },
    "plan-reviewer": { "model": "github-copilot/claude-opus-4.8" },
    "code-reviewer": { "model": "github-copilot/claude-opus-4.8" },
    "worker": { "model": "github-copilot/gpt-5.3-codex" },
    "ui-worker": { "model": "github-copilot/gemini-3.5-flash" }
  }
}
```

`planner`/`plan-reviewer`/`code-reviewer` are low-volume, high-stakes reasoning roles (they map to
the `deep` category in team-mode routing), so a Powerful-tier model is worth the cost here even
though the repo defaults to `gpt-5.4` elsewhere. `ui-worker` must use a `github-copilot/` model in a
Copilot-only repo — bare `google/gemini-3.5-flash` would fail once `gemini` is in `disabled_providers`.

### Important: preserving the built-in `plan` agent
If you override `agent.plan` in `.opencode/opencode.jsonc`, include `"mode": "primary"` unless you intentionally want `plan` to become a subagent. In current runtime behavior, config-defined agents with no explicit `mode` can be treated as `subagent`, even when `replace_plan`-style plugin settings suggest otherwise.

### Common additional fields
```jsonc
{
  "$schema": "https://opencode.ai/config.json",

  // Disable session sharing for this repo.
  "share": "disabled",

  // Turn off providers this repo should not use.
  "disabled_providers": ["openai", "anthropic", "gemini"],

  // Pin the plugin version used in this repo.
  "plugin": ["oh-my-opencode@3.7.4"],

  // Override or add repo-local MCP servers.
  "mcp": {
    "context7": { "type": "local", "command": ["npx", "-y", "@upstash/context7-mcp"], "enabled": true }
  }
}
```

- `share` — use `"disabled"` when the repo should not publish/share sessions by default.
- `disabled_providers` — use this only when the repo should forbid specific provider families; omit it if normal global provider access should continue.
- `plugin` — pin repo-local plugin versions when the repo must be stable or intentionally differ from the global install. The package name remains `oh-my-opencode` during the rename transition even though the canonical config basename is `oh-my-openagent`.
- `mcp` — add repo-specific MCP servers here or disable inherited/global ones for this repo only.

### Copilot-only provider lock-down example
Use a block like this when the repo should allow GitHub Copilot models only and explicitly disable other provider families.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "github-copilot/gpt-5.4",

  // Leave github-copilot enabled by omitting it here.
  "disabled_providers": [
    "openai",
    "anthropic",
    "gemini",
    "openrouter",
    "bedrock",
    "azure",
    "deepseek",
    "xai",
    "mistral",
    "groq",
    "fireworks",
    "together",
    "cerebras",
    "perplexity",
    "cohere",
    "opencode"
  ]
}
```

Treat this as an example pattern, not a mandatory full list. Keep only the provider IDs that actually exist in the current environment and repo policy.

Keep overrides minimal. Omit anything that should continue to inherit from global config.

## File 2 — `.opencode/oh-my-openagent.jsonc`
Use plugin config for:
- built-in oh-my-openagent agent model routing
- category routing used by delegated task categories
- `disabled_hooks`, `disabled_mcps`, `disabled_agents`, and related plugin knobs
- other oh-my-openagent behavior that belongs in plugin config rather than OpenCode core config

### Standard baseline example
```jsonc
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json",

  // Repo-local override: use the established default model-routing pattern in this workspace.
  "agents": {
    "sisyphus": { "model": "github-copilot/claude-opus-4.8" },
    "sisyphus-junior": { "model": "github-copilot/claude-opus-4.8" },
    "atlas": { "model": "github-copilot/claude-opus-4.8" },
    "hephaestus": { "model": "github-copilot/claude-opus-4.8" },

    "build": { "model": "github-copilot/gpt-5.3-codex" },
    "plan": { "model": "github-copilot/claude-opus-4.8" },
    "OpenCode-Builder": { "model": "github-copilot/gpt-5.3-codex" },

    "oracle": { "model": "github-copilot/claude-opus-4.8" },
    "prometheus": { "model": "github-copilot/claude-opus-4.8" },
    "metis": { "model": "github-copilot/claude-opus-4.8" },
    "momus": { "model": "github-copilot/claude-opus-4.8" },
    "planner": { "model": "github-copilot/claude-opus-4.8" },
    "plan-reviewer": { "model": "github-copilot/claude-opus-4.8" },
    "code-reviewer": { "model": "github-copilot/claude-opus-4.8" },
    "worker": { "model": "github-copilot/gpt-5.3-codex" },
    "ui-worker": { "model": "github-copilot/gemini-3.5-flash" },

    "librarian": { "model": "github-copilot/gpt-5.6-terra" },
    "explore": { "model": "github-copilot/gpt-5.4-mini" }
  },

  "categories": {
    "visual-engineering": { "model": "github-copilot/gemini-3.5-flash", "temperature": 0.7 },
    "ultrabrain": { "model": "github-copilot/claude-opus-4.8", "temperature": 0.1 },
    "deep": { "model": "github-copilot/claude-opus-4.8", "temperature": 0.2 },
    "artistry": { "model": "github-copilot/gpt-5.6-terra", "temperature": 0.9 },
    "quick": { "model": "github-copilot/gpt-5.4-mini", "temperature": 0.3 },
    "writing": { "model": "github-copilot/gpt-5.6-terra", "temperature": 0.5 },
    "unspecified-low": { "model": "github-copilot/kimi-k2.7-code", "temperature": 0.3 },
    "unspecified-high": { "model": "github-copilot/claude-sonnet-5", "temperature": 0.3 }
  }
}
```

`oracle`/`prometheus`/`metis`/`momus`/`planner`/`plan-reviewer`/`code-reviewer`/`sisyphus`/`atlas`/
`hephaestus` are the low-volume reasoning/lead/rescue roles — team-mode's `deep`/`ultrabrain`/primary-lead
tiers all suggest a Powerful-class model (`claude-opus-4.8`) for these. `unspecified-low` (team-mode's
mechanical-implementer category, formerly routed through `quick`) uses `kimi-k2.7-code` as a
low-cost coding-specialized alternative to a generic lightweight model. `quick` itself remains a
separate, general-purpose trivial-task category outside team-mode packet routing and keeps the
cheaper `gpt-5.4-mini`. `unspecified-high` uses `claude-sonnet-5` — newer and cheaper than the
Claude Sonnet 4.6 generation it replaces. `visual-engineering` (and `ui-worker`) uses
`gemini-3.5-flash` instead — Gemini's strong multimodal/visual grounding is a better fit for
UI work than a general reasoning model, at a lower price than `claude-sonnet-5`. `ultrabrain` and
`hephaestus` are
escalation-only/low-volume by construction, so `github-copilot/claude-fable-5` (priciest, smartest)
is a reasonable swap-in for either when a repo values maximum reasoning quality over cost.

### Valid agent keys
Common built-in keys include:
`sisyphus`, `sisyphus-junior`, `prometheus`, `metis`, `momus`, `atlas`, `hephaestus`, `OpenCode-Builder`, `build`, `plan`, `oracle`, `librarian`, `explore`, `multimodal-looker`, `deep`.

Per-agent fields commonly include:
- `model`
- `variant`
- `prompt_append`
- `temperature`
- `disable`

### Valid category keys
Common category keys include:
`quick`, `ultrabrain`, `writing`, `visual-engineering`, `artistry`, `unspecified-low`, `unspecified-high`, `deep`.

`unspecified-low` is also the team-mode mechanical-implementer category (see
[Team-Mode Execution](../../docs/team-mode-execution.md)); `quick` remains a distinct
general-purpose category and is not used by team-mode packet routing.

Per-category fields commonly include:
- `model`
- `temperature`
- `variant`
- `prompt_append`

## Process
1. Confirm the repo root.
2. Check whether `.opencode/oh-my-openagent.jsonc` or any legacy plugin config basename already exists.
3. Run `opencode models` and use only model IDs that actually exist in the current environment.
4. If the user wants similarity to another config, inspect that reference config first.
5. Inspect existing repo-local custom agents before changing them.
6. Decide which file(s) are actually needed:
   - default model / plugin / provider / MCP / inline agent overrides → `opencode.jsonc`
   - built-in agent routing / category routing / plugin disablement knobs → `.opencode/oh-my-openagent.jsonc`
7. Write the minimal override set.
8. Avoid creating both canonical and legacy plugin-config basenames in the same repo.
9. Keep every file secret-free.
10. Validate that each file actually parses as JSONC before finishing (comments and trailing commas allowed). A silently broken config is a common failure.
11. Tell the user to restart OpenCode after config changes.

## Non-goals
- I will not edit global config under `~/.config/opencode/`.
- I will not edit Nix-managed config when the request is for repo-local overrides.
- I will not invent model IDs.
- I will not disable or remove custom agents by default.
- I will not duplicate an entire global config into a repo when only a few overrides are needed.

## Examples
- “Make this repo use the same default model routing as my other workspace.” → inspect the reference config first, then create `.opencode/oh-my-openagent.jsonc` and/or `.opencode/opencode.jsonc` with only the needed overrides.
- “Route `explore` to a cheap model and keep `oracle` on a stronger one in this repo only.” → update `.opencode/oh-my-openagent.jsonc` `agents`.
- “Disable a global MCP in this repo.” → update `.opencode/opencode.jsonc` `mcp`.
- “This repo already has custom agents; help me modernize config without breaking them.” → inspect inline `agent` config and `.opencode/agents/` first, then ask whether to preserve, migrate, disable, or remove them.
- “Disable these old custom agents in this repo.” → confirm which ones are active, then use the appropriate mechanism such as deleting/removing active definitions or adding `disabled_agents` if that matches the user's intent.

## Troubleshooting
- **Configured model not found** — run `opencode models` and use a valid model ID.
- **`plan` disappeared from the picker** — if `agent.plan` is overridden in `.opencode/opencode.jsonc`, add `"mode": "primary"`.
- **Override not applied** — confirm the file is at `.opencode/oh-my-openagent.jsonc` or `.opencode/opencode.jsonc`, is valid JSONC, and OpenCode was restarted.
- **Unexpected config wins** — check for both canonical and legacy plugin basenames in the same directory; legacy may win during rename compatibility.
- **Custom agents still appear unexpectedly** — verify whether they come from inline `opencode.jsonc` `agent` definitions, `.opencode/agents/`, or another higher-priority config layer before changing anything.
