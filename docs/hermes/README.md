# Hermes Agent Operations

Operating manuals for Hermes agents (and similar coding agents) that run this
repo's process against the repos they own. This section explains **mechanics
and setup** — cron jobs, labels, triggers, notification routing. The
**process policy** — what a review must check, what a PR body must contain,
what escalates to a human, how plans and tasks are structured — lives in the
canonical docs and is never restated here:

- [Development Process](../process.md) — the software development pipeline.
- [PR review process](../references/pr-review.md) — review contract, common
  rules, reviewer loop, Required Repo Hooks.

If this section and a canonical doc disagree, the canonical doc wins.

## Documents

| Document | Read when |
|----------|-----------|
| [Software development process](dev-process.md) | Setting up an agent to run the development pipeline on owned repos (skill sync, stop boundaries) |
| [Execution modes](execution-modes.md) | Deciding HOW Hermes drives the pipeline: Pi subprocesses vs Hermes subagents vs single session |
| [PR automation](pr-automation.md) | Setting up an agent to detect and review PRs automatically (no-agent cron sweep, labels, triggers, detached review sessions) |
| [Delivery pipeline](../references/delivery-pipeline.md) | Wiring triage, work dispatch and gate replies around the PR sweep (item state machine, WIP limit, human gates) |
| [Comment style](../references/comment-style.md) | Writing or checking any comment a bot posts (first line, sections, budgets, reply menus, board names) |

## How Hermes consumes this repo

Hermes agents install the **rendered Hermes tree** (`dist/skills/hermes/`)
into their own skill stores and self-manage it thereafter: the one-time
bootstrap is a manual copy (see [Usage with Hermes](../../README.md#usage-with-hermes)),
and every later alignment runs through the `skill-sync` skill +
`tools/sync-skills.mjs` — upstream `dist/skills/hermes/` is the source of
truth, local deltas are dispositions (`take-upstream` / `keep-local`
recorded / `propose-upstream` PR), never silent drift. The entry point for
any fresh session is the `software-development` skill (trigger: "follow
the dev process"), which routes into the pipeline stage skills below.

1. Read this README.
2. Run the `skill-sync` procedure (bootstrap if never synced).
3. Load `software-development` and locate your stage via its gate table.
4. For any job, read the canonical path from the map — never hunt.

## Skill reference map

Installed copies come from `dist/skills/hermes/` (kept aligned via
skill-sync); the canonical sources (`skills/<name>/SKILL.md`) are linked
here for direct reading.

| Job | Canonical path |
|-----|----------------|
| Onboard / audit a repo | `skills/assess-repo/SKILL.md` |
| Clarify intent → brief | `skills/discovery/SKILL.md` |
| Build-to-learn entry (human-paired prototype → brief) | `skills/prototype-first/SKILL.md` |
| Research → approach | `skills/design/SKILL.md`, `skills/research/SKILL.md` |
| Plan creation | `skills/create-plan/SKILL.md` |
| Plan review | `skills/review-plan/SKILL.md` |
| Execution log | `skills/create-worklog/SKILL.md` |
| Task execution | `skills/execute-task/SKILL.md` |
| Full autonomous execution | `skills/execution-orchestrator/SKILL.md` + [Execution modes](execution-modes.md) |
| Code review | `skills/review-code/SKILL.md` |
| Epic decomposition review | `skills/review-epic/SKILL.md` |
| PR body + one verdict | `skills/pull-request/SKILL.md` |
| Live-PR review cycling (session-scoped) | `skills/babysit-pr/SKILL.md` |
| PR monitoring infrastructure | [PR automation](pr-automation.md) |
| Backlog operations (capture, move, gates, claims) | `skills/backlog/SKILL.md` |
| Inbox triage (dispatched) | `skills/triage-backlog/SKILL.md` |
| Item work from pickup to PR (dispatched) | `skills/work-item/SKILL.md` |
| Item pipeline infrastructure | [Delivery pipeline](../references/delivery-pipeline.md) |

## Agent self-setup checklist

An agent being handed ownership of one or more repos runs this once:

1. **Verify each repo is onboarded.** Check for `pr-review-hooks.md` at the
   repo root (see the Required Repo Hooks table in the PR review process) and
   that `AGENTS.md` routes the process docs. Missing pieces: report to the
   human and offer an assess-repo setup run. Do not start automated review
   for a repo without a manifest.
2. **Sync your skills** against the checklist in
   [Software development process](dev-process.md), then create the sweep cron
   from the template in [PR automation](pr-automation.md) — one job covering
   all owned repos. If the repo runs the
   [Delivery pipeline](../references/delivery-pipeline.md), also:
   - install `scripts/*.py` with the prompt directories into
     `$HERMES_HOME/scripts/`;
   - set up the board once: `python3 scripts/gh-project.py fields` (Status,
     Waiting for and the other fields, with their board names) and
     `python3 scripts/gh-project.py labels`; on a board that used the older
     columns, run `python3 scripts/gh-project.py migrate-your-turn --dry`, then
     without `--dry`;
   - create the triage (every 15m), work (every 3m) and hygiene (every 7d) jobs
     from `scripts/pipeline-dispatch.py`, with
     `PIPELINE_LIST_CMD="python3 <scripts>/gh-project.py list"` and
     `PIPELINE_MOVE_CMD="python3 <scripts>/gh-project.py move {number} {status}"`
     (install notes in its header; run each once with `PIPELINE_DRY=1` first);
   - create the board-sync job (every 5m) from `scripts/board-sync.py` (run
     once with `--dry` first);
   - confirm the repo documents the pipeline hooks in its task-tracking doc.
3. **Register the trigger surface**: confirm the command handle
   (`PR_AGENT_HANDLE`, default `/devbot`; first line `<handle> <command>`)
   and the owner logins (`PIPELINE_OWNERS`), and check the repo's
   `pr-tracking` manifest row documents them.
4. **Agree the execution mode** (Pi subprocesses / Hermes subagents / single
   session) with the human when a plan is approved for execution — see
   [Execution modes](execution-modes.md).
5. **Confirm the never-merge boundary** with the human once: the agent
   detects, reviews, labels, and notifies. Only the human merges.
6. **Report the completed setup** to the human with the repo list and cron
   schedule so it is auditable.
