# Agent Roles

The harness-neutral inventory of agent roles in this repo's development
process: who does what across planning, implementation, and review, which
execution tier each defaults to, and the independence rules between them.
Orchestration docs map these roles to specific runtimes (Pi subagents,
OpenCode categories); per-repo model assignments are a repo hook (see
"Per-repo model assignment" below).

## The roles

| # | Role | Stage(s) | Responsibility | Tier |
|---|------|----------|----------------|------|
| 1 | Orchestrator | all | Owns the loop: advances stages, dispatches roles, runs verification on the host, commits checkpoints. Never implements. | high |
| 2 | Author | brief, approach | Clarifies intent with the human, defines the conceptual model and structural decisions; produces `brief.md` and `approach.md`. | high |
| 3 | Researcher | research | Investigates the codebase; produces findings files with verified anchors. | low |
| 4 | Planner / contract author | plan | Decomposes into tasks; assigns verification class + execution tier; authors failing contract tests (observes red, never implements). | high |
| 5 | Reviewer | approach, plan, code, PR review | Runs the review procedure for the stage — the stage skill defines the checklist; the role is the identity. Never reviews artifacts it authored. | high |
| 6 | Fresh reviewer | final review; second reviewer in two-reviewer loops | Full-diff review with **no prior context** on the work. Read-only. | high (strongest available) |
| 7 | Implementer, high tier | execute | Executes high-tier tasks per their verification class; atomic task commit. | high |
| 8 | Implementer, low tier | execute | Executes low-tier tasks (mechanical, bounded, well-specified work). | low |
| 9 | Visual implementer *(optional)* | execute (UI) | UI-specific tasks needing a UI-specialized model. Assign only if the repo wants a distinct UI model; otherwise implementer-high covers it. | high |

Review stages share one Reviewer role because the thing that varies per
stage is the **procedure** (a skill: review-plan, review-code, the PR
review process), not the identity — and every review stage defaults to the
same tier, so per-stage roles would all resolve to the same model slot.
The one exception is the Fresh reviewer: freshness is a context property,
not a procedure, and it cannot be produced by a role that has been in the
loop.

## Independence rules

- A reviewer must not review artifacts it authored: the Reviewer role never
  covers a stage whose artifact came from the same agent session or lineage.
- The Fresh reviewer has no prior context on the work at all — clean
  session, read-only.
- Two-reviewer review loops use two distinct reviewer instances (Reviewer +
  Fresh reviewer, or two Reviewer instances with different sessions/models).
- Contract tests are authored by the Planner, never by an implementer.
- Verification runs on the host (Orchestrator), never in the context that
  did the work.

## Execution tiers

Plans assign each task a tier (`high` / `low`); the Orchestrator dispatches
the matching implementer role. All reviewer and authoring roles default to
`high` — review quality is not where cost is saved. Tier → model mapping is
repo configuration, not canon.

## Per-repo model assignment (required hook)

Every repo consuming this process **must document which model fills each
role**, because the right assignment is stack- and budget-specific. The
repo records this in its agent-configuration surface (e.g.
`.pi/settings.json` → `subagents.agentOverrides`, the OpenCode equivalent,
or the Hermes equivalent), and `skills/assess-repo` checks for it during
assessment:

- every role above has a named model (or an explicit "default" record);
- the Implementer tier mapping is stated (which model is `high`, which is
  `low`);
- critical roles (implementers, Planner, Reviewer) have fallback models
  configured where any provider has quota/reliability limits;
- the assignment is auditable — a reviewer can tell from repo config alone
  which model reviewed the code.

A repo that cannot state its role→model mapping fails assessment. The
mapping lives in the repo, not here: this document defines the roles; the
repo defines who plays them.
