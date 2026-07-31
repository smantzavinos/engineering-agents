---
name: pi-team-lead
description: Lead the Pi-only Crew lifecycle from reviewed plan through isolated wave transactions, fresh reviews, integration evidence, final gate, and telemetry.
compatibility: pi
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
2. Re-run `pi-team check <plan> --json`; require a clean semantic review and any requested plan
   approval. Risk-labelled tasks are never auto-approved.
3. Refuse board initialization if runtime entries exist. Stable `config.json` and `agents/` are
   no-clobber inputs. For a partial pre-worker materialization, archive only runtime state; for
   started work, obtain human confirmation before recovery.
4. Run `pi-team init-board` once. Create every task through `pi_messenger` in stable topological order
   (numeric plan ID tie-breaker). Save each returned Crew ID in the
   **plan-ID→Crew-ID map**, and translate `Deps` only through that map.
5. Use the compiler's LF packet bytes, title `<ID> — <deliverable truncated to 80 Unicode code
   points>`, lane role, and risk labels for `task.create`. Risk-labelled tasks persist blocked
   until the human uses `task.approve` (**SUB-9**).
6. Run `crew.validate`. Only its expected missing-board-`plan.md` warning is acceptable; graph,
   count, or any other warning archives partial state and stops.

## Executable CLI commands

Set these values once before materialization. `BASE` is the clean transaction base and remains the
current `HEAD` until the single wave commit. Every `--output-dir` below is created as a fresh,
nonexistent path because `review-wave` refuses an existing output directory.

```bash
REPO="$(git rev-parse --show-toplevel)"
PLAN="$REPO/plans/YYYY_MM_DD_<slug>/plan.md"
CREW="$REPO/.pi/messenger/crew"
BASE="$(git -C "$REPO" rev-parse HEAD)"
WAVE_IDS="T1,T2"
RETRY_IDS="T1"
OUTPUT_PARENT="$REPO/.pi/messenger/reviews"
mkdir -p "$OUTPUT_PARENT"
fresh_output_dir() { local d; d="$(mktemp -d "$OUTPUT_PARENT/pi-team-review.XXXXXX")"; rmdir "$d"; printf '%s\n' "$d"; }

pi-team check "$PLAN" --json
pi-team init-board "$PLAN" --crew-dir "$CREW" --repo-root "$REPO"

WAVE_OUTPUT_DIR="$(fresh_output_dir)"
pi-team review-wave "$PLAN" --scope "$WAVE_IDS" --bundle "$WAVE_IDS" --repo-root "$REPO" --base "$BASE" --output-dir "$WAVE_OUTPUT_DIR"
```

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
   must be complete, untruncated, path-scoped, and include untracked changes. Send every changed
   bundle with its exact packet to a **fresh `pi-team-reviewer`** subagent. Accept only `SHIP`,
   `NEEDS_WORK`, or `MAJOR_RETHINK`; never reuse reviewer context or let it inspect peer write
   sets.
2. For `NEEDS_WORK`, record findings in task progress, reset the task, and retry in this dirty
   transaction. Regenerate the requested retry bundles before deciding what to re-review, compare
   the old and new manifest task `sha256` values, and re-review only changed bundles while
   retaining original-wave scope:

```bash
LAST_MANIFEST="$WAVE_OUTPUT_DIR/manifest.json"
RETRY_OUTPUT_DIR="$(fresh_output_dir)"
pi-team review-wave "$PLAN" --scope "$WAVE_IDS" --bundle "$RETRY_IDS" --repo-root "$REPO" --base "$BASE" --output-dir "$RETRY_OUTPUT_DIR"
CHANGED_RETRY_IDS="$(node - "$LAST_MANIFEST" "$RETRY_OUTPUT_DIR/manifest.json" <<'NODE'
const fs = require('fs');
const tasks = file => new Map(JSON.parse(fs.readFileSync(file, 'utf8')).tasks.map(({ id, sha256 }) => [id, sha256]));
const before = tasks(process.argv[2]);
const after = tasks(process.argv[3]);
console.log([...after].filter(([id, sha256]) => before.get(id) !== sha256).map(([id]) => id).join(','));
NODE
)"
test -n "$CHANGED_RETRY_IDS" # Send only these packet/bundle pairs to fresh reviewers.
```

   At two Crew attempts, stop ordinary retry.
3. For `MAJOR_RETHINK` or exhausted attempts, reset/block the task and use one fresh strong
   `github-copilot/gpt-5.6-sol` rescue. It receives progress/findings and bounded ownership.
   Re-review its changed bundle fresh. After `SHIP`, explicitly close the original Crew task in
   this order: `task.unblock` -> `task.start` -> `task.done`, with summary and review evidence
   attached to the progress/done record. A rescue failure remains blocked; do not mark it done or
   advance the dependency graph.

## Integration and commit

1. From each review manifest, retain the last green digest per integration group. Run every
   affected completed group once whenever its normalized write-set content digest differs; never
   rerun an unchanged digest.
2. On failure, create a fresh strong remediation pass owning only that group union. Scope review
   to original wave plus failed-group tasks; bundle only task IDs whose paths the remediation
   changed (the `--bundle` argument takes task IDs, never paths); re-review changed bundles.

```bash
REMEDIATION_SCOPE_IDS="$WAVE_IDS,T3" # Original wave plus complete failed-group task IDs.
REMEDIATION_IDS="T3"                 # Changed task IDs, never file paths.
REMEDIATION_OUTPUT_DIR="$(fresh_output_dir)"
pi-team review-wave "$PLAN" --scope "$REMEDIATION_SCOPE_IDS" --bundle "$REMEDIATION_IDS" --repo-root "$REPO" --base "$BASE" --output-dir "$REMEDIATION_OUTPUT_DIR"
```

   Allow at most two remediation revisions, and rerun the integration check only on a new digest.
3. Commit every reviewed wave locally before dispatching the next. Commit only when each affected
completed group has a green digest; a spanning group waits until complete.

## Final closure

After all findings are remediated on a clean `HEAD`, run the final repo gate and commit the fix.
Then commission a fresh full-diff review explicitly on that new HEAD with
`github-copilot/gpt-5.6-sol`; it must inspect the full diff from the run base, not a reused wave
review. For final-review findings, allow at most two fresh remediation passes. For each pass:
remediate on clean HEAD, run the final gate, commit the fix, then run another fresh full-diff
review on the same new HEAD commit. Green final gate and clean review must therefore describe the
same commit; cap exhaustion pauses for the human. Write `telemetry.md` from observable facts only:
timestamps, task/attempt/reset counts, scope findings, gate failures, classified human
interruptions, and `cost: unavailable`. Report shipped behavior, evidence, approved risks, and
backlog IDs. Do not push.
