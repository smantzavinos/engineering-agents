# Engineering Agents

A structured process for using AI coding agents to design and implement software features, bug fixes, and large initiatives with minimal human interaction. Includes everything you need: process documentation, skills, agent definitions, and a Nix Flake for installing [Pi](https://github.com/badlogic/pi-mono) and [OpenCode](https://github.com/sst/opencode).

## Philosophy

Three components work together to produce effective autonomous AI development:

1. **Repository setup** — The right information in the right places, discoverable at the right time
2. **Skills** — Reusable process definitions that tell agents what to do at each stage
3. **Agent modes** — which process an agent runs depends on the harness ([ADR 0007](docs/adr/0007-frontier-pipeline-on-pi.md)):
   - **Pi** runs the [frontier pipeline](docs/frontier-pipeline.md): a throwaway prototype, a scope agreed with the human, one plan whose design is a model built from the project's pattern catalog, approval from a tour of that model, and an unattended build checked against it.
   - **OpenCode and Hermes** run the sequential pipeline: Discovery (clarify intent), Design (research and approach), Execution (plan, worklog, task-by-task build, review). [Process](docs/process.md) describes it.

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

### 6. Test Pi changes from this checkout

Use the repo-local development sandbox to test uncommitted Pi module, package, skill, and extension changes without pushing or switching your active Home Manager generation:

```bash
# Build/activate into .pi-dev/ and launch Pi.
./scripts/pi-dev.sh

# Copy existing Pi credentials into the sandbox, then launch.
./scripts/pi-dev.sh --copy-auth

# Activate the sandbox and run the live proof-set against it.
./scripts/pi-dev.sh --verify

# Delete the sandbox, including its copied credentials and sessions.
./scripts/pi-dev.sh --reset
```

The sandbox uses `.pi-dev/home` as `HOME` and never modifies `~/.pi`. `--copy-auth` copies `~/.pi/agent/auth.json`; it does not symlink or modify the source credential file. `.pi-dev/` is ignored by Git.

## What's Included

### Process Documentation (`docs/`)

| Document | Purpose |
|----------|---------|
| [Frontier Pipeline](docs/frontier-pipeline.md) | The process on Pi, run by `scope`, `run-plan` and `run-epic`, with an example execution diagram |
| [Process](docs/process.md) | The sequential pipeline (OpenCode and Hermes): full lifecycle for each workflow type, stage-by-stage |
| [Plan Levels](docs/plan-levels.md) | Sequential pipeline: when to use simple, standard, or epic |
| [Plan Directory Structure](docs/plan-directory-structure.md) | Artifacts, naming conventions, directory layout |
| [Repository Setup](docs/repo-setup.md) | What repos need to work with this process |
| [Agent Architecture](docs/agent_architecture_and_workflow.md) | Sequential pipeline: diagrams of agent modes and sub-agent calls |
| [Orchestration](docs/orchestration.md) | Sequential pipeline: three agent modes, prompt patterns |
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

Which skills a harness gets is set by each skill's `harnesses:` line ([skill rendering](docs/skill-rendering.md)).

**Pi: the frontier pipeline**

| Skill | Used by | Purpose |
|-------|---------|---------|
| `prototype` | The human starts it | Build a throwaway prototype that shows the behaviour wanted |
| `scope` | The human starts it | Agree the scope, get the plan and its model written and reviewed, approve from the tour |
| `run-plan` | The human starts it | Build one approved plan unattended; stop only for re-approval |
| `run-epic` | The human starts it | The rare multi-plan case: lanes, checkpoints, integration |
| `map-patterns` | The human starts it | Write the project's pattern catalog from the code that exists |
| `plan`, `implement`, `review` | plan-author, implementer, reviewer | Each role's job |
| `architecture-model` | Every role | Shared rules for the model, tags, checks, deviations and approvals; ships the check |
| `delegate`, `test-quality` | Every role | Offloading read-heavy work; which tests to write and keep |

**OpenCode and Hermes: the sequential pipeline**

| Skill | Stage | Purpose |
|-------|-------|---------|
| `discovery` | Discovery | Socratic dialogue to clarify intent |
| `design` | Design | Collaborative research and approach development |
| `research` | Design | Investigate a specific topic in a codebase |
| `create-plan` | Planning | Create sequential implementation plans with verification class + execution tier per task |
| `review-plan` | Planning | Review sequential plans for completeness and consistency |
| `review-approach` | Planning | Review approaches for architectural soundness |
| `create-worklog` | Execution | Create execution log from approved plan |
| `execute-task` | Execution | Execute one plan task per its verification class |
| `execution-orchestrator` | Execution | Autonomous orchestrator driving plan to completion |
| `review-code` | Review | Post-implementation code review |
| `review-epic` | Review | Epic-level review across child plans |
| `work-item` | Backlog | Run one backlog item to its gate, block or PR |
| `configure-opencode` | Utility | Create/update repo-local OpenCode config overrides (OpenCode-only) |

**Every harness**

| Skill | Purpose |
|-------|---------|
| `assess-repo` | Assess and set up a repo for the workflow |
| `pull-request` | Prepare or review a PR per the PR review process: body, evidence, rules, verdict |
| `backlog`, `triage-backlog` | Tracker operations; triaging Inbox items |
| `create-skills` | Create valid SKILL.md skills |

Retired skills (parallel execution, team mode) are archived under
`docs/investigations/2026-09-23-retired-parallel-execution/` — see ADR 0006.

### Agent Definitions (`agents/`)

Pi roles, shared by the terminal and T3 launchers. The frontier pipeline uses the first six; the rest are older and still installed (ADR 0007, "Not done").

| Agent | Model Tier | Role |
|-------|-----------|------|
| `plan-author` | Frontier | Write and revise one plan and its model |
| `implementer` | Frontier | Build a whole plan, tag the code, pass the gates and model checks |
| `reviewer` | Frontier | Fresh-context review of an epic, a plan or a diff |
| `helper` | Fast | Scouting, gate runs, digests, sweeps |
| `researcher` | Execution | Web/external documentation research |
| `oracle` | Frontier (highest) | Read-only second opinion |
| `planner`, `plan-reviewer`, `code-reviewer` | Frontier | Sequential-pipeline roles; no installed Pi skill starts them |
| `worker`, `worker-high`, `worker-low`, `ui-worker` | Execution | General implementation |
| `vision` | Visual | Screenshot/mockup/visual analysis |

Plus `preset.jsonc` defining three presets: **scope**, **run-plan** and **run-epic**.

## Nix Configuration Options

### Pi Module (`engineering-agents.pi`)

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable Pi with all engineering-agents skills and agents |
| `modelSet` | `"direct"` | `"direct"` uses OpenAI Codex and optional GLM; `"copilot"` uses GitHub Copilot only |
| `zai.enable` | `true` | Install z.ai model definitions and the MCP adapter/config; use Codex in GLM role slots when off |
| `defaultProvider` | Set-selected | OpenAI Codex in `direct`, GitHub Copilot in `copilot` |
| `defaultModel` | Set-selected | `gpt-5.6-sol` in `direct`, `claude-sonnet-5.5` in `copilot` |
| `defaultThinkingLevel` | `"medium"` | Default thinking level |
| `theme` | `"catppuccin-mocha"` | Pi theme |
| `footer` | `"powerline"` | Exclusive footer/editor profile: `"powerline"` or `"zentui"` |
| `powerline.config` | *(see module default)* | Declarative Powerline preset, editor, welcome, placement, and cost-display settings |
| `powerline.shortcuts` | `Ctrl+Alt+U` / `Ctrl+Alt+D` | Powerline fixed-editor chat scroll bindings |
| `powerline.nerdFonts` | `"force"` | Nerd Font detection: `"auto"`, `"force"`, or `"disable"` |
| `powerline.theme` | *(see module default)* | Declarative Powerline `theme.json` color and icon override |
| `enabledModels` | Set-selected | Models for cycling |
| `enableAgentKit` | `true` | Install the agent-kit direnv extension |
| `enableVisualExplainer` | `true` | Install the pinned, manual-only visual-explainer skill |

The NixOS service-user module exposes `modelSet` and `zai.enable` under
`engineering-agents.pi-for-user`. Explicit session defaults still win over
set defaults, and project role overrides still win at runtime. This
repository's own `.pi/settings.json` assumes the `copilot` set.

### OpenCode Module (`engineering-agents.opencode`)

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable OpenCode with engineering-agents configuration |
| `model` | `zai-coding-plan/glm-5.2` | Default model |
| `enableTmux` | `true` | Enable tmux integration |
| `enableVisualExplainer` | `true` | Install the visual-explainer skill (pinned via the `visualExplainer` flake input) |
| `enableServer` | `false` | Enable OpenCode server systemd service |
| `serverPort` | `3124` | Server port |

## Workflows (sequential pipeline: OpenCode and Hermes)

| Workflow | When to use | Process |
|----------|-------------|---------|
| Feature Development | New capabilities, maximum rigor | brief → research → approach → plan → review → execute → code review → PR review |
| Bug Fix | Defects, regressions | brief → debug/research → approach → planning → execute → review |
| Epic | Large initiatives | brief → findings → approach → epic decomposition → child plans |
| Simple Change | Trivial fixes, config | brief → implement → verify |

## Usage with Pi

The wrapper selects the T3 profile only for T3 RPC launches with an installed
`t3-profile.args`; other launches retain the terminal configuration. Both
profiles include guardrails, code intelligence, checkpointing, web tools and
task tracking. Only the terminal loads the footer, presets and Pi subagent
launcher. T3 uses its own delegation tools, with the same installed role
models and `.pi/settings.json` overrides. In T3, start the process with
`/skill:scope`, `/skill:run-plan` or `/skill:run-epic` instead of `/preset`.
See [ADR 0009](docs/adr/0009-delegation-through-t3.md).

```bash
pi
# Once per repository: write its pattern catalog and check the set-up.
#   "Use map-patterns to start a pattern catalog for this repo."
#   "Use assess-repo to check this repo."

# Agree the scope and approve the plan from its tour.
/preset scope
# Then: "Scope the work in PROTOTYPE.md on branch prototype/my-feature."

# Build the approved plan unattended.
/preset run-plan
# Then: "Run the plan at plans/2026_05_01_my_feature/."
```

See [Frontier Pipeline](docs/frontier-pipeline.md).

## Usage with Hermes

Hermes agents install the rendered Hermes tree into their own skill stores
and self-manage it: copy `dist/skills/hermes/*` into the agent's skill
directory (once, by hand — then the `skill-sync` skill keeps it aligned via
`tools/sync-skills.mjs`). Process entry for any fresh session: the
`software-development` skill (trigger: "follow the dev process"), which
routes into the pipeline stage skills. The docs reference map in
`docs/hermes/README.md` covers the full pipeline including PR babysitting
(`skills/babysit-pr/SKILL.md`).

## Usage without Nix

Canonical skills in `skills/` are harness-neutral templates. The final per-harness skill files are generated into `dist/skills/<harness>/` by the renderer (`node tools/render-skills.mjs --write`). See [Skill Rendering](docs/skill-rendering.md) for the pipeline. The `agents/` and `docs/` directories are plain Markdown/JSON.

You can copy the generated trees to any coding agent's configuration directory:

- **Pi**: Copy `dist/skills/pi/*` to `~/.pi/agent/skills/`, agents from `agents/` to `~/.pi/agent/agents/`
- **OpenCode**: Copy `dist/skills/opencode/*` to `~/.config/opencode/skills/`
- **Hermes**: Copy `dist/skills/hermes/*` into the agent's skill directory, then keep aligned with the `skill-sync` skill + `tools/sync-skills.mjs`
- **Claude Code**: Reference rendered skill files from `.claude/` configuration

> In OpenCode, the review and read-only-escalation roles are delegated via task categories rather than dedicated subagents — see [Skill Rendering](docs/skill-rendering.md).

## Core Principles

- **Deliberate stages over speed** — Each stage exists because skipping it produces worse results
- **Skills define process, repos define specifics** — Skills know *what* to do; repos define *how*
- **Documentation drives discovery** — AGENTS.md files enable progressive information discovery
- **Everything in one directory** — One plan directory = one unit of work
- **Commits are process checkpoints** — every task ends with exactly one atomic commit
  (`task(T<N>): <desc>`) including source, tests, and the worklog update
- **Tests define contracts early** — test-first discipline per the task's verification class;
  a failing test exists before implementation for `contract` tasks

## License

MIT
