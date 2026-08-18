---
name: configure-pi
description: Configure Pi safely for the current repository through `.pi/settings.json` and the Pi-team profile, including project-specific models, resources, subagent role overrides, and Crew lane routing. Use when a user asks to change Pi behavior for one project or diagnose why a project Pi setting is not taking effect.
compatibility: pi
metadata:
  domain: pi
---

## What I do
- Create or update the committed, project-local Pi settings file: `.pi/settings.json`.
- Configure project-specific model defaults, model cycling, resource paths, `subagents.agentOverrides`, and Pi-team Crew lane routing without inventing model IDs or overwriting unrelated settings.
- Diagnose project trust, invalid JSON, precedence, and reload/restart requirements when a project setting appears ignored.
- Explain when a requested behavior belongs to a user-wide extension configuration rather than this project skill's scope.

## When to use me
Use this when a user asks to:
- Make this repository use a different Pi default provider, model, thinking level, UI behavior, resource path, or subagent role model.
- Configure Pi settings that should be committed with this repository.
- Diagnose why `.pi/settings.json` is not taking effect in this project.

Do not use this skill to configure every Pi project, edit `~/.pi/agent/`, author an extension, skill, theme, or prompt template. Use the specialized skill or Pi documentation for those surfaces.

## Scope and precedence

This skill changes **only**:

```text
.pi/settings.json
```

Pi loads `~/.pi/agent/settings.json` as the user-wide base and merges `.pi/settings.json` as the current project's override. Nested objects merge, so add only the keys that differ for this repository. Do not copy the user's entire global configuration into the project file.

Project-local settings and resources require Pi to trust the project. In non-interactive runs, use an existing trust decision or the appropriate explicit trust flag rather than assuming `.pi/` content was loaded.

## What I need before editing
- The project behavior that should differ from the user's normal Pi defaults.
- The current `.pi/settings.json`, if it exists.
- Available model IDs when changing model routing. Inspect the current Pi model list or existing valid configuration; never invent a provider/model ID.
- Any error message or evidence that the setting is being ignored.

Ask a clarifying question if the desired project behavior is not clear. Do not turn a project-local request into a global configuration change.

## Supported project settings

Use `.pi/settings.json` for settings such as:

- `defaultProvider`, `defaultModel`, `defaultThinkingLevel`, and `enabledModels`.
- `thinkingBudgets`, display settings, compaction, retry, and session settings when they must differ for this repository.
- Project-local `extensions`, `skills`, `prompts`, and `themes` paths.
- `subagents.agentOverrides` for repository-specific subagent model, thinking, tool, fallback-chain, or role behavior.
- `subagents.defaultModel` to give subagents without an explicit model their own default model (separate from the session model).

Example: keep the project's default model and route a reviewer to a verified stronger model:

```json
{
  "defaultProvider": "github-copilot",
  "defaultModel": "github-copilot/gpt-5.6-terra",
  "subagents": {
    "agentOverrides": {
      "code-reviewer": {
        "model": "github-copilot/gpt-5.6-sol",
        "thinking": "medium"
      }
    }
  }
}
```

Use only model IDs available in the current environment. Keep every project configuration secret-free.

### Subagent model fallback chains

`pi-subagents` supports an ordered fallback chain per agent. Set it in `subagents.agentOverrides.<agent>.fallbackModels` (array) or directly in an agent definition's frontmatter (`fallbackModels: provider/id, provider/id`).

```json
{
  "subagents": {
    "agentOverrides": {
      "worker": {
        "model": "zai-coding-plan/glm-5.2",
        "fallbackModels": [
          "fireworks/accounts/fireworks/models/deepseek-v4-flash",
          "fireworks/accounts/fireworks/models/qwen3p8-max"
        ]
      }
    }
  }
}
```

Fallback semantics (verified against the pinned pi-subagents source):

- The chain is tried **in order** after the primary model fails.
- Fallback triggers only on **provider/model failure classes**: rate limit (429), quota/billing, auth/API-key errors, timeouts, provider overloaded/unavailable, model not found/disabled, and network errors. **Ordinary task failures never trigger fallback** — a failing test or bad code output is retried by the same model, not routed to the next one.
- Model IDs resolve fuzzily (case/separator/date-stamp tolerant); a `provider/id` reference never silently switches providers.

Precedence rule — important: an override field is **skipped when the agent definition's frontmatter already declares that field**. An agent file with `model:` in frontmatter ignores `agentOverrides.<agent>.model` (same for `fallbackModels`/`thinking`). Settings-level overrides apply only to fields the agent file leaves undeclared. To re-point a frontmatter-declared model per environment, either edit the agent definition or, in engineering-agents-managed deployments, use the `agentOverrides` argument of `makePiConfig`/`engineering-agents.pi-for-user.args`, which patches the shipped agent frontmatter at build time.

`subagents.defaultModel` applies only to agents **without** an explicit model (frontmatter `model:` and any per-agent override win).

### Pi-team Crew lane models

Pi-team model routing is separate from `subagents.agentOverrides`. Configure the five Crew lanes
in the repository's `config/pi-team/team-profile.json`; the installed `pi` wrapper automatically
sets `PI_MESSENGER_TEAM_PROFILE_DIR` to the current repository's `config/pi-team` when the
repository provides `config/pi-team/pi-team.json`. Keep that entry as a relative symlink to the
canonical profile so the profile remains one authored source.

Example profile roles:

```json
{
  "name": "pi-team",
  "roles": {
    "worker-cheap": {
      "model": "github-copilot/gpt-5.6-luna",
      "thinking": "high",
      "skills": ["pi-team-worker"]
    },
    "worker-std": {
      "model": "github-copilot/gpt-5.6-terra",
      "thinking": "medium",
      "skills": ["pi-team-worker"]
    },
    "worker-complex": {
      "model": "github-copilot/gpt-5.6-sol",
      "thinking": "medium",
      "skills": ["pi-team-worker"]
    },
    "worker-visual": {
      "model": "github-copilot/claude-sonnet-5",
      "thinking": "medium",
      "skills": ["pi-team-worker"]
    },
    "worker-visual-complex": {
      "model": "github-copilot/claude-opus-5",
      "thinking": "medium",
      "skills": ["pi-team-worker"]
    }
  }
}
```

The exact role choices are repository policy, not universal defaults. Verify model availability
with `pi --list-models` before committing a profile. Keep rescue and final-review policy in the
Pi-team lead contract; do not silently replace the configured lane model from a worker packet.

## Out-of-scope: subagent runtime limits

`pi-subagents` has extension runtime configuration that is separate from Pi's main settings. In particular, `maxSubagentSpawnsPerSession` does **not** belong in `.pi/settings.json`; putting it there has no effect.

The extension defaults to 40 child spawns per parent session. That count includes single launches, parallel children, chain steps, and bounded dynamic fanout, and it resets only in a new parent session.

Because changing that limit requires a user-wide extension configuration or process environment variable, do not edit it with this skill. Explain the boundary and direct the user to their Pi/global-configuration maintainer if they need a persistent different limit.

For a one-process override, tell the user to start Pi with a finite cap in the environment:

```bash
PI_SUBAGENT_MAX_SPAWNS_PER_SESSION=100 pi
```

This affects only that Pi process and does not modify project files or global configuration. `0` blocks new child launches. A new parent session has a fresh spawn budget.

## Process
1. Confirm that the request is for the current repository and identify the exact project behavior.
2. Inspect `.pi/settings.json`, any relevant project-local resources, and `config/pi-team/team-profile.json` when the repository uses Pi-team.
3. Verify project trust if local settings or resources are not loading.
4. Preserve unrelated configuration and make the smallest valid JSON change.
5. Validate the file with `jq -e . .pi/settings.json`.
6. Restart Pi after startup-loaded setting changes. `/reload` is appropriate for reloadable resources, but a restart is the reliable default for settings changes.
7. Validate the relevant JSON files with `jq -e .`, report the modified file and changed keys, and state any required Pi restart or Home Manager activation.

## Examples
- “Make this repo use a different default Pi model.” → inspect `.pi/settings.json` and available models, then add the minimal project override.
- “Use stronger reviewers but keep workers cheap in this repo.” → update only `subagents.agentOverrides` in `.pi/settings.json` with verified model IDs; if Pi-team is also enabled, update its five lane models in `config/pi-team/team-profile.json`.
- “Use Luna for cheap work, Terra for standard work, Sol for complex work, Sonnet 5 for visual work, and Opus 5 for complex visual work.” → update the repository's Pi-team profile with those verified IDs and thinking levels; do not change unrelated subagent overrides.
- “My project settings do nothing.” → verify project trust, configuration path, JSON validity, precedence, and whether a restart is required.
- “Raise the subagent cap above 40.” → explain that the cap is user-wide extension runtime configuration and is outside this project-scoped skill.

## Non-goals
- I will not edit `~/.pi/agent/settings.json`, `~/.pi/agent/extensions/`, or any other user-wide Pi configuration.
- I will not place extension runtime keys such as `maxSubagentSpawnsPerSession` in `.pi/settings.json`.
- I will not edit Nix/Home Manager-managed global configuration.
- I will not overwrite unrelated project settings, invent provider/model IDs, or commit credentials.
