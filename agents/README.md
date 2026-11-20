# Agent & Preset Configuration

This directory contains the Pi agent definitions and presets. Pi runs the frontier pipeline (`docs/frontier-pipeline.md`, ADR 0007).

## Setup

### Presets (Pi preset extension)

Placed at `~/.pi/agent/preset.jsonc` (handled by Nix). A preset sets the session's model and tells it which skills to read first:
- **scope** — agree the scope with the human, get the plan and its model written and reviewed, record the approval
- **run-plan** — build one approved plan unattended
- **run-epic** — run an approved epic of several plans

### Agents (Pi subagents extension)

Sub-agents do the work the orchestrating session hands out. Placed at `~/.pi/agent/agents/` (handled by Nix).

## Agent Set

### Frontier pipeline

Used by the `scope`, `run-plan` and `run-epic` presets and skills.



| Agent | Model Tier | Role |
|-------|-----------|------|
| `plan-author` | Frontier | Write and revise one plan and its model; resumed across review rounds |
| `implementer` | Frontier | Build a whole plan, tag the code, keep the model in line, pass gates and model checks, fix findings; resumed across review rounds |
| `reviewer` | Frontier | Fresh-context review (epic, plan, code, epic-diff); new session every pass |
| `helper` | Fast | Errands for frontier agents: scout, run and digest, verify, sweep |
| `researcher` | Execution | Web/external documentation research |
| `oracle` | Frontier (highest) | Read-only second opinion |

### Older agents, still installed

From the sequential pipeline, which Pi no longer runs. No installed Pi skill starts `planner`, `plan-reviewer` or `code-reviewer`; they stay until consumers stop naming them in `agentOverrides` (ADR 0007, "Not done").

| Agent | Model Tier | Role |
|-------|-----------|------|
| `planner` | Frontier (reasoning) | Create detailed plans from brief + approach |
| `plan-reviewer` | Frontier (reasoning) | Review approaches, epic decompositions, and plans |
| `code-reviewer` | Frontier (code) | Review code diffs against plan requirements |
| `worker-high`, `worker-low`, `worker` | Execution | Task implementation, general fixes |
| `ui-worker` | Execution (UI) | Frontend/UI implementation |
| `vision` | Visual | Screenshot/mockup/visual analysis |

## Files

- `preset.jsonc` — the `scope`, `run-plan` and `run-epic` modes
- `<name>.md` — one file per agent above

## Usage

```
/preset scope
```
Then: "Scope the work in PROTOTYPE.md on branch prototype/my-feature." Ends with the plan approved and recorded.

```
/preset run-plan
```
Then: "Run the plan at plans/2026_05_01_my_feature/."

```
/preset run-epic
```
Then: "Run the epic at plans/2026_05_01_my_epic/."

## Per-Repo Model Overrides

Repos should override models or thinking levels in `.pi/settings.json` using `subagents.agentOverrides` rather than copying agent files into `.pi/agents/`. That keeps the canonical checked-in agent prompts centralized while still allowing repo-local tuning. See the orchestration doc's "Per-Repository Model Configuration" section for details.
