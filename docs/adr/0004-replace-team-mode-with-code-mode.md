# ADR 0004: Replace team mode with a code-mode dynamic workflow

Status: Accepted

Date: 2026-08-18

Requirement refs: FR-008, NFR-003

Supersedes: ADR 0002 (the pipeline split), ADR 0003 (team throughput scheduling)

## Context

ADR 0002 branched the process after approach review into a sequential pipeline and a
role-based team pipeline coordinated through `pi-messenger` Crew. ADR 0003 kept that model and
tried to fix its throughput by moving scheduling onto a task board with lanes, claims, and a
Turn-Exit Contract.

Both encoded coordination as **prose instructions an agent was asked to obey**: check the
board once after finishing, never end a turn with a ready task undispatched, nudge a silent
member across two turns, restart on the third. Every one of those rules is a control-flow
statement written in English and executed by a language model on a best-effort basis. When it
was not followed, nothing detected it — the failure mode was silent latency and a worklog that
drifted from reality, with the human acting as the scheduling watchdog.

The `pi-subagents` extension since gained **code mode**: a `workflowScript` that runs real
JavaScript to fan out children, inspect their results, and decide what happens next. Readiness,
retry, and escalation become code that either runs or throws, rather than instructions that are
followed or quietly are not.

Before adopting it, the runtime was exercised directly rather than trusted
(`docs/investigations/2026-08-18-code-mode-process/spike.md`). That produced several findings
that changed the design, most importantly that a child `gate:` cannot carry verification: the
acceptance-evidence check short-circuits before the gate command's result is consulted, and
`gate: "true"` and `gate: "false"` were indistinguishable.

## Decision

Retire team mode entirely and replace it with a **dynamic workflow** on Pi.

1. **Orchestration is code.** One wave engine (`workflows/wave.mjs`), configured rather than
   reimplemented per pattern: a pipeline is `maxWidth: 1`, a solo change is a one-task graph.
2. **The loop lives in the parent.** The parent computes the ready set, invokes one
   `workflowScript` per wave, runs verification itself on the host, reviews, and commits a
   checkpoint. Verification is never delegated to a child, both because `gate:` cannot carry it
   and because there is no `worktree.apply` to reintegrate isolated work.
3. **The plan is machine-readable.** `plan.md` is the human narrative; `tasks.json` is the
   executable graph. `tools/check-plan.mjs` gates them, sharing its graph validation with the
   engine so a plan cannot pass review and fail at execution.
4. **Write-set collisions are a plan-time error.** Two tasks that can run concurrently and
   write the same path are rejected before execution rather than racing in the shared tree.
5. **Verification is per-task, not one ritual.** Each task declares `contract`,
   `characterization`, `check`, or `none`. Contract tests are authored by an agent other than
   the implementer, observed red once, and frozen at a commit; verification asserts they did
   not change.
6. **The mandatory break-it step is removed.** It was self-administered by the same context
   that wrote the test. It survives only as a reviewer-initiated demand on a specific test that
   looks like it cannot fail.
7. **OpenCode is unchanged.** It has no code-mode equivalent, so it keeps the sequential
   pipeline. The two pipelines share no files: Pi uses `dynamic-*` skills, OpenCode keeps
   `create-plan`, `review-plan`, `review-code`, `execution-orchestrator`, `execute-task`, and
   `create-worklog` byte-for-byte.

## Consequences

- `pi-messenger` and its team profile, board, compiler, agents, skills, and specs are removed.
  The Pi extension set drops from 20 to 16 packages and the Pi skill surface from 20 to 13,
  with 4 discoverable.
- The human approval gate between plan and execution is retained unchanged.
- Resume is a git checkpoint per wave rather than a worklog ledger. Mission `state` is a
  secondary cross-check. A crashed wave requires a `git status` check before relaunch, since
  aborted children leave partial edits that can produce a false pass.
- Capacity is bounded by the runtime: 64 spawns per run, never refunded, and a 30-minute
  default per child. At roughly four spawns per task this caps a single run near 16 tasks.
- The engine depends on an unreleased `pi-subagents` commit
  (`3847deeaa6e814c328ff4964fc28d7c2e6f9fc9b`), because the v0.50.0 tag requires
  `node:v8 promiseHooks`, which the Bun-built Pi does not implement. Revisit at 0.51.0.
- Sequential-mode prose and artifacts remain valid for OpenCode; `docs/process.md` and
  `docs/orchestration.md` now document both pipelines side by side.

## Alternatives considered

- **Keep team mode and fix the scheduling again.** Rejected: ADR 0003 was already the second
  attempt, and the defect is the medium, not the tuning.
- **Run waves in isolated worktrees.** Rejected for now: there is no `worktree.apply`, and the
  script sandbox has no filesystem or shell access, so the parent would have to apply patches
  between waves. That is a different architecture and must be costed separately.
- **Parameterize the existing shared skills per harness.** Attempted, then reverted. It
  required two new renderer mechanisms, broke the OpenCode byte constraint once, and produced
  files whose behaviour could not be read off the source.
