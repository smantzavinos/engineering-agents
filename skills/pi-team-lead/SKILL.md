---
name: pi-team-lead
description: Lead the Pi-only Crew lifecycle from reviewed plan through isolated wave transactions, fresh reviews, integration evidence, final gate, and telemetry.
harnesses: [pi]
metadata:
  domain: pi-team
---

# Pi Team Lead

## Role

Own lifecycle, board state, Git, broad gates, commits, and durable records. Do not implement a
planned packet. `plan.md` is the only authored execution contract; board/review/telemetry files
are generated evidence.

## Preflight and materialization

1. Confirm the active profile is exactly `pi-team`: invoke `team.profile.use` idempotently, then
   verify all five lane roles, their models/thinking/`pi-team-worker` skill, and risk-label
   approval policy. Never use a bare packaged role.
2. Re-run `pi-team check <plan> --json`; require a clean semantic review and any
   requested plan approval. Risk-labelled tasks are never auto-approved.
3. Refuse board initialization if runtime entries exist. Stable `config.json` and `agents/` are
   no-clobber inputs. For a partial pre-worker materialization, archive only runtime state; for
   started work, obtain human confirmation before recovery.
4. Run `pi-team init-board` once. Create every task through `pi_messenger` in exact
   stable topological order (numeric plan ID tie-breaker). Save each returned Crew ID in the
   **plan-ID→Crew-ID map**, and translate `Deps` only through that map.
5. Use the compiler's LF packet bytes, title `<ID> — <deliverable truncated to 80 Unicode code
   points>`, lane role, and risk labels for `task.create`. Risk-labelled tasks persist blocked
   until the human uses `task.approve` (**SUB-9**).
6. Run `crew.validate`. Only its expected missing-board-`plan.md` warning is acceptable; graph,
   count, or any other warning archives partial state and stops.

## Wave transaction and dispatch

1. Open one wave transaction only on a clean index/worktree. Record `BASE = HEAD`; autonomous
   continuation is off. All retry, rescue, and integration remediation stays dirty with
   `HEAD == BASE` until the lead's single wave commit.
2. Dispatch one computed wave, up to four ready file-disjoint workers, with one complete packet
   each. Workers may run only their minimal checks; no worker commits or broad gates.
3. When workers return, require `HEAD == BASE`. A mismatch rejects worker commits. Do not open
   the next wave or commit before review and integration closure.

## Review, retries, and rescue

1. Run `pi-team review-wave` with the original wave as both allowed scope and bundle. Evidence
   must be complete, untruncated, path-scoped, and include untracked changes.
2. Send every changed bundle with its exact packet to a **fresh `pi-team-reviewer`** subagent.
   Accept only `SHIP`, `NEEDS_WORK`, or `MAJOR_RETHINK`; never reuse reviewer context or let it
   inspect peer write sets.
3. For `NEEDS_WORK`, record findings in task progress, reset the task, and retry in this dirty
   transaction. Re-bundle only retried tasks whose SHA changed, retaining original-wave scope.
   At two Crew attempts, stop ordinary retry.
4. For `MAJOR_RETHINK` or exhausted attempts, reset/block the task and use one fresh strong
   `github-copilot/gpt-5.6-sol` rescue. It receives progress/findings and bounded ownership.
   Re-review its changed bundle fresh; rescue failure pauses for the human.

## Integration and commit

1. From each review manifest, retain the last green digest per integration group. Run every
   affected completed group once whenever its normalized write-set content digest differs; never
   rerun an unchanged digest.
2. On failure, create a fresh strong remediation pass owning only that group union. Scope review
   to original wave plus failed-group tasks; bundle only changed paths; re-review changed bundles.
   Allow at most **two remediation revisions**, and rerun the integration check only on a new digest.
3. Commit every reviewed wave locally before dispatching the next. Commit only when each affected
   completed group has a green digest; a spanning group waits until complete.

## Final closure

Run the final repo gate, close Crew execution, and commission a fresh full-diff strong review.
For findings, allow at most two fresh remediation passes; each needs final gate and fresh re-review
on the same commit. Cap exhaustion pauses for the human. Write `telemetry.md` from observable
facts only: timestamps, task/attempt/reset counts, scope findings, gate failures, classified human
interruptions, and `cost: unavailable`. Report shipped behavior, evidence, approved risks, and
backlog IDs. Do not push.
