# Engineering Agents

A structured process for using AI coding agents to design and implement software features, bug fixes, and large initiatives with minimal human interaction. Includes everything you need: process documentation, skills, agent definitions, and a Nix Flake for installing [Pi](https://github.com/badlogic/pi-mono) and [OpenCode](https://github.com/sst/opencode).

## Philosophy

Three components work together to produce effective autonomous AI development:

1. **Repository setup** — The right information in the right places, discoverable at the right time
2. **Skills** — Reusable process definitions that tell agents what to do at each stage
3. **Agent modes** — Three distinct agents drive the process at different phases:
   - **Discovery** — Socratic dialogue to clarify intent and determine direction (high human interaction)
   - **Design** — Collaborative research and approach development with delegated sub-agents (medium interaction)
   - **Execution** — Autonomous implementation from approach to completion (minimal interaction)

The key insight: you don't need a complex extension or state machine to orchestrate multi-step development workflows. Capable LLMs in the right mode can drive each phase of the process.

## Quick Start

### 1. Add to your Nix Flake

```nix
# flake.nix
inputs = {
  engineering-agents.url = "github:<your-username>/engineering-agents";
};
```

### 2. Import the Home Manager modules

```nix
# In your home-manager config:
imports = [
  engineering-agents.homeManagerModules.default
];

engineering-agents.pi.enable = true;
engineering-agents.opencode.enable = true;
```

### 3. Apply

```bash
home-manager switch --flake .#<hostname>
```

### 4. Authenticate

```bash
# Pi: run /login inside pi once per machine
pi
/login

# OpenCode: run auth login once per machine
opencode auth login
```

### 5. Inspect managed package freshness

If Pi warns that managed packages/plugins need attention, run `check-updates --dry-run` to inspect what is stale, then apply your configuration with `home-manager switch --flake .#<hostname>`.

Direct cloned installs such as `agent-kit` and `visual-explainer` are outside this startup-warning scope.

## What's Included

### Process Documentation (`docs/`)

| Document | Purpose |
|----------|---------|
| [Process](docs/process.md) | Full lifecycle for each workflow type, stage-by-stage |
| [Plan Levels](docs/plan-levels.md) | When to use simple, standard, or epic |
| [Plan Directory Structure](docs/plan-directory-structure.md) | Artifacts, naming conventions, directory layout |
| [Repository Setup](docs/repo-setup.md) | What repos need to work with this process |
| [Agent Architecture](docs/agent_architecture_and_workflow.md) | Visual diagrams: agent modes, sub-agent calls |
| [Orchestration](docs/orchestration.md) | Detailed reference: three agent modes, prompt patterns |
| [Extension Spec](docs/extension-spec.md) | Minimal state validation and continuation enforcement |

### Repo Operational Contracts

This repository also documents its own operating contract so contributors can use the process here without guessing:
- [Root Agent Guide](AGENTS.md)
- [Repository Architecture](docs/architecture.md)
- [Coding Rules](docs/coding-rules.md)
- [Development Environment](docs/development-environment.md)
- [Testing Strategy](docs/testing-strategy.md)
- [Backlog](docs/backlog.md)
- [Requirements](docs/requirements.md)
- [Plans Directory Guide](plans/README.md)
- [Issues and Learnings Log](docs/issues_learnings.md)
- [ADR Index](docs/adr/README.md)

### Skills (`skills/`)

17 skills covering the full development lifecycle:

| Skill | Stage | Purpose |
|-------|-------|---------|
| `discovery` | Discovery | Socratic dialogue to clarify intent |
| `design` | Design | Collaborative research and approach development |
| `research` | Design | Investigate a specific topic in a codebase |
| `create-plan` | Planning | Create detailed implementation plans |
| `review-plan` | Planning | Review plans for completeness and consistency |
| `review-approach` | Planning | Review approaches for architectural soundness |
| `create-worklog` | Execution | Create execution log from approved plan |
| `create-team-worklog` | Execution | Create wave-oriented team worklog for team-mode execution (OpenCode-only) |
| `execute-task` | Execution | Execute one plan task using strict TDD |
| `execution-orchestrator` | Execution | Autonomous orchestrator driving plan to completion |
| `execution-orchestrator-team` | Execution | Fast-lane orchestrator running tasks in parallel via team mode (OpenCode-only) |
| `review-code` | Review | Post-implementation code review |
| `review-epic` | Review | Epic-level review across child plans |
| `assess-repo` | Setup | Assess and set up a repo for the workflow |
| `create-skills` | Utility | Create valid SKILL.md skills |
| `create-new-repo-docs` | Utility | Bootstrap repo documentation foundation |
| `configure-opencode` | Utility | Create/update repo-local OpenCode config overrides (OpenCode-only) |

### Agent Definitions (`agents/`)

8 specialized agents for different tasks and model tiers:

| Agent | Model Tier | Role |
|-------|-----------|------|
| `planner` | Frontier (reasoning) | Create detailed plans from brief + approach |
| `plan-reviewer` | Frontier (reasoning) | Review approaches and plans |
| `code-reviewer` | Frontier (code) | Review code diffs against plan requirements |
| `worker` | Execution | Backend/logic implementation |
| `ui-worker` | Execution (UI) | Frontend/UI implementation |
| `researcher` | Execution | Web/external documentation research |
| `vision` | Visual | Screenshot/mockup/visual analysis |
| `oracle` | Frontier (highest) | Read-only second opinion |

Plus `preset.jsonc` defining three workflow presets: **discovery**, **design**, and **execute**.

## Nix Configuration Options

### Pi Module (`engineering-agents.pi`)

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable Pi with all engineering-agents skills and agents |
| `defaultProvider` | `"zai-coding-plan"` | Default model provider |
| `defaultModel` | `"glm-5.2"` | Default model |
| `defaultThinkingLevel` | `"medium"` | Default thinking level |
| `theme` | `"catppuccin-mocha"` | Pi theme |
| `enabledModels` | *(see default)* | Models for Ctrl+P cycling |
| `enableGitNexus` | `false` | Enable the GitNexus CLI and `pi-gitnexus` managed package |
| `enableAgentKit` | `true` | Install agent-kit extensions (direnv, ast-grep) |
| `enableVisualExplainer` | `true` | Install visual-explainer skill (pinned via the `visualExplainer` flake input) |

### OpenCode Module (`engineering-agents.opencode`)

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable OpenCode with engineering-agents configuration |
| `model` | `openai/gpt-5.5` | Default model |
| `enableTmux` | `true` | Enable tmux integration |
| `enableVisualExplainer` | `true` | Install the visual-explainer skill (pinned via the `visualExplainer` flake input) |
| `enableServer` | `false` | Enable OpenCode server systemd service |
| `serverPort` | `3124` | Server port |

## Workflows

| Workflow | When to use | Process |
|----------|-------------|---------|
| Feature Development | New capabilities, enhancements | brief → research → approach → plan → review → execute → code review |
| Bug Fix | Defects, regressions | brief → debug/research → approach → plan → execute → code review |
| Epic | Large initiatives | brief → findings → approach → epic decomposition → child plans |
| Simple Change | Trivial fixes, config | brief → implement → verify |

## Usage with Pi

```bash
# Start a Discovery session
pi
/preset discovery

# Start a Design session
/preset design

# Start Execution
/preset execute
# Then: "Execute the plan at plans/my_feature/. Auto-continue."
```

## Usage without Nix

Canonical skills in `skills/` are harness-neutral templates. The final per-harness skill files are generated into `dist/skills/<harness>/` by the renderer (`node tools/render-skills.mjs --write`). See [Skill Rendering](docs/skill-rendering.md) for the pipeline. The `agents/` and `docs/` directories are plain Markdown/JSON.

You can copy the generated trees to any coding agent's configuration directory:

- **Pi**: Copy `dist/skills/pi/*` to `~/.pi/agent/skills/`, agents from `agents/` to `~/.pi/agent/agents/`
- **OpenCode**: Copy `dist/skills/opencode/*` to `~/.config/opencode/skills/`
- **Claude Code**: Reference rendered skill files from `.claude/` configuration

> In OpenCode, the review and read-only-escalation roles are delegated via task categories rather than dedicated subagents — see [Skill Rendering](docs/skill-rendering.md).

## Core Principles

- **Deliberate stages over speed** — Each stage exists because skipping it produces worse results
- **Skills define process, repos define specifics** — Skills know *what* to do; repos define *how*
- **Documentation drives discovery** — AGENTS.md files enable progressive information discovery
- **Everything in one directory** — One plan directory = one unit of work
- **Commits are process checkpoints** — Implementation committed after every completed task
- **TDD is non-negotiable** — Every change requires a failing test first

## License

MIT
