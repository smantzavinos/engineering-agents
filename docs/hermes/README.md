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
| [PR automation](pr-automation.md) | Setting up an agent to detect and review PRs automatically (cron sweep, labels, triggers, monitor script) |

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
   all owned repos.
3. **Register the trigger surface**: confirm which GitHub handle mentions
   should trigger this agent, and check the repo's `pr-tracking` manifest
   row documents it.
4. **Agree the execution mode** (Pi subprocesses / Hermes subagents / single
   session) with the human when a plan is approved for execution — see
   [Execution modes](execution-modes.md).
5. **Confirm the never-merge boundary** with the human once: the agent
   detects, reviews, labels, and notifies. Only the human merges.
6. **Report the completed setup** to the human with the repo list and cron
   schedule so it is auditable.
