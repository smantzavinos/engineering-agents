# Agent Roles

The harness-neutral inventory of agent roles in this repo's development
process: who does what across planning, implementation, and review, which
execution tier each defaults to, and the independence rules between them.
Orchestration docs map these roles to specific runtimes (Pi subagents,
OpenCode categories); per-repo model assignments are a repo hook (see
"Per-repo model assignment" below).

## The roles

| # | Role | Stage(s) | Responsibility | Default tier |
|---|------|----------|----------------|--------------|
| 1 | Orchestrator | all | Owns the loop: advances stages, dispatches roles, runs verification on the host, commits checkpoints. Never implements. | high |
| 2 | Brief author | brief | Clarifies intent with the human; produces `brief.md`. | high |
| 3 | Researcher | research | Investigates the codebase; produces findings files with verified anchors. | low |
| 4 | Approach author | approach | Defines the conceptual model and structural decisions; produces `approach.md`. | high |
| 5 | Approach reviewer | approach review | Reviews the approach to zero significant issues. ≠ approach author. | high |
| 6 | Planner / contract author | plan | Decomposes into tasks; assigns verification class + execution tier; authors failing contract tests (observes red, never implements). | high |
| 7 | Plan reviewer | plan review | Reviews the plan to zero Blocker/Critical/Major. ≠ planner. | high |
| 8 | Implementer (standard) | execute | Executes one task per its verification class; atomic task commit. | task's tier (high or low) |
| 9 | Visual implementer | execute | UI-specific tasks. | high |
| 10 | Code reviewer | code review | Post-implementation review to zero Blocker/Critical/Major. ≠ implementer(s). | high |
| 11 | PR reviewer | PR review | Executes the PR review process; posts verdict + stamp. ≠ author. | high |
| 12 | Fresh final reviewer | after code review | Full-diff review with no prior context. Read-only. | high |

## Independence rules

- A reviewer must not share an agent session (or subagent lineage) with the
  author of what it reviews: approach ≠ approach reviewer, planner ≠ plan
  reviewer, implementer(s) ≠ code reviewer, PR author ≠ PR reviewer.
- The fresh final reviewer has no prior context on the work at all.
- Contract tests are authored by someone other than the implementer
  (role 6 vs role 8).
- Verification runs on the host (orchestrator), never in the context that
  did the work.

## Execution tiers

Plans assign each task a tier (`high` / `low`); role 8 executes at the
task's tier. All reviewer roles default to `high` — review quality is not
where cost is saved. Tier → model mapping is repo configuration, not canon.

## Per-repo model assignment (required hook)

Every repo consuming this process **must document which model fills each
role**, because the right assignment is stack- and budget-specific. The
repo records this in its agent-configuration surface (e.g.
`.pi/settings.json` → `subagents.agentOverrides`, the OpenCode equivalent,
or the Hermes equivalent), and `skills/assess-repo` checks for it during
assessment:

- every role above has a named model (or an explicit "default" record);
- role 8's tier mapping is stated (which model is `high`, which is `low`);
- critical roles (implementer, code reviewer, plan reviewer) have fallback
  models configured where any provider has quota/reliability limits;
- the assignment is auditable — a reviewer can tell from repo config alone
  which model reviewed the code.

A repo that cannot state its role→model mapping fails assessment. The
mapping lives in the repo, not here: this document defines the roles; the
repo defines who plays them.
