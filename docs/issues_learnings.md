# Issues and Learnings Log

Use this file as lightweight operational memory for recurring execution issues and confirmed learnings that should stay visible but do not yet require a full ADR.

## How to Use This Log
- Add entries when a discovery is likely to matter again across future plans, reviews, or repo maintenance.
- Link each entry back to the plan, worklog, review, or verification artifact where it was discovered.
- Use `Requirement refs:` when a finding relates to a durable requirement such as `FR-002` or `OPR-001`.
- Promote accepted, long-lived directional decisions to `docs/adr/` instead of letting this log become a hidden policy store.
- Move resolved or superseded observations into the historical notes inside the same section instead of silently deleting them.

## Entry Template

```markdown
### <short title>
- Date: YYYY-MM-DD
- Type: issue | learning
- Source: <path or artifact reference>
- Requirement refs: optional, for example `FR-002`, `OPR-001`
- Summary: one or two sentences
- Follow-up: optional backlink to `TASK-XXXX`, ADR, or remediation artifact
```

## Open Issues

_No entries yet._

## Confirmed Learnings

### Parallel is one approach: DAG plus planned fences
- Date: 2026-08-19
- Type: learning
- Source: process clarification after the requirement-labels closeout DAG run
- Summary: Waves and “attended DAG” are not separate lanes. The scheduler is always a DAG.
  A fence is a planned verify+commit cut. Default is one fence at the end. Ready-set waves
  and “human is watching” are the wrong axes. Sequential is frozen; team is abandoned; Pi
  develops only Parallel. See `docs/approaches/parallel.md`.
- Follow-up: done in ADR 0005 — one executor, `fenceGroups` on `tasks.json`

### Provider quota exhaustion needs its own failure class
- Date: 2026-08-19
- Type: learning
- Source: labels DAG run — child died mid-verification on `429: usage limit reached for 5 hour`
- Summary: A provider 429 is neither a real failure nor a configuration error. Under the old
  table it classified as "real failure → retry once with the strong model" — but the strong
  model was the same capped provider, so the retry would have burned the one attempt and
  escalated. The correct move (made ad hoc in the run) was rerouting to a different provider.
  A 429 riding a sub-cap `Run fan-out: N/64` banner is also quota, not spawn-budget.
- Follow-up: done — `classifyFailure` returns `quota` (engine + spec checks); both failure
  tables instruct reroute-or-wait, never a same-provider retry, and quota does not consume
  the strong retry

### Frozen contract tests need a parent-side repair path
- Date: 2026-08-19
- Type: learning
- Source: labels DAG run — frozen specs shipped author-side defects: mock typing that broke
  the repo typecheck (a gate not in the plan's final matrix), and an option-locator collision
  visible only in full-suite runs
- Summary: "Frozen means immutable" binds implementers, not the oracle itself. Contract
  tests are authored ahead of implementation, so they can contain author bugs; without a
  sanctioned repair path an agent either stalls on a broken oracle or edits it in a way that
  is indistinguishable from cheating in the diff. The run improvised the path (parent-applied,
  assertion-neutral, disclosed diff, worklog-recorded, escalate-on-meaning-change) and it
  held up under review.
- Follow-up: done — "Repairing a broken oracle" in `dynamic-execute-plan`; review-code
  recognizes a recorded parent repair; `docs/approaches/parallel.md` carries the one-liner

### Resume from the tree, not the checkpoint
- Date: 2026-08-19
- Type: learning
- Source: labels DAG run — provider 429 killed a task mid-verification; 11 tasks of intact
  work sat in the tree; the then-current doc said "reset to the last checkpoint"
- Summary: A crashed group leaves partially verified work that is not waste. Task write-sets
  + verify commands + frozen-test diffs re-derive done-ness from the tree directly; relaunch
  only the incomplete subgraph. Resetting to the checkpoint for a one-group plan would have
  destroyed all of it — and a hard reset is destructive in target repos that forbid it.
- Follow-up: done — "Resume" in `docs/execution-patterns.md` and the execute skill now
  prescribe resume-from-tree, with reset as an irreconcilable-tree last resort gated on
  human approval

### Scoped verifies passing do not make a full suite green
- Date: 2026-08-19
- Type: learning
- Source: labels DAG run — a locator collision (`getByRole('option', { name: 'Blocked' })`
  substring-matching a seeded label "Blocked Compose" while two pickers were open) passed
  every per-task grep scope and failed 2 of 3 full-suite runs
- Summary: Per-task scoped verifies systematically miss cross-test interference. A failure
  that reproduces in full-suite runs but not scoped runs is a locator or resource collision
  until proven otherwise — not flake. First instinct (twice) was "flake"; the evidence was
  in the strict-mode violation message all along.
- Follow-up: done — "Scoped green is not full green" in `docs/execution-patterns.md`;
  final gate must cover the repo's complete CI surface

### Inline workflowScript is not a reviewable record
- Date: 2026-08-19
- Type: learning
- Source: plan closeout DAG run; human asked where the script was stored
- Summary: An attended `dynamic-execute-dag-plan` run inlined the DAG `workflowScript` only
  on the `subagent` tool call. After the run, the script existed only inside the session
  JSONL, so it could not be reviewed before launch or kept with the plan. Persist the exact
  body as `<plan-dir>/dataflow.js` (or `waves/wave-NN.js`) and launch that file.
- Follow-up: `docs/plan-directory-structure.md`, `docs/execution-patterns.md`,
  `skills/dynamic-execute-dag-plan/SKILL.md`, `skills/dynamic-execute-plan/SKILL.md`

### Dogfood small plans before locking proportional packet gates
- Date: 2026-07-31
- Type: learning
- Source: Pi team rollout dogfood before T5
- Summary: Dogfooding exposed a small-plan ceremony trap: a strict 20% critical-path share forced
  artificial five-task chains even when three independent tasks were each 20 minutes or less.
  Use an absolute floor with proportional packet gates so small plans stay naturally parallel.

### Crew worker tool allowlists can hide Messenger itself
- Date: 2026-08-01
- Type: learning
- Source: `docs/investigations/2026-07-31-plan-execution-efficiency/calibration/bootstrap/review.md`; `notes/README.md` (SUB-12)
- Summary: `pi-messenger` loads its extension for Crew workers but filters agent-frontmatter
  `tools` to built-ins before applying Pi's `--tools` allowlist. Listing `pi_messenger` in that
  frontmatter therefore drops the custom extension tool and prevents the worker protocol from
  completing. The project Crew worker override must omit `tools` frontmatter so Pi defaults and
  the explicitly loaded Messenger extension remain available.
- Follow-up: Preserve the no-`tools` assertion in the Pi-team configuration and readiness specs.

### Team contracts must start before implementation completion
- Date: 2026-07-15
- Type: learning
- Source: UI work team-mode trial
- Requirement refs: FR-007, FR-008, OPR-003
- Summary: Blocking the verifier until implementation completed delayed the acceptance
  contract and caused repeated task-board polling. Contract packets should start immediately,
  blocked members should stop until messaged, and final review should use fresh strong context.
- Follow-up: ADR 0002 and `docs/team-mode-execution.md`

### Ephemeral agent run state is not covered by the `.pi` gitignore rule
- Date: 2026-07-31
- Type: issue
- Source: `docs/investigations/2026-07-31-plan-execution-efficiency/` (commit `cad5f8d`)
- Summary: `.gitignore` contained `.pi`, which matches only that exact name — not sibling
  directories like `.pi-subagents/`. Four research subagent runs left full transcripts,
  inputs, and metadata in `.pi-subagents/artifacts/` and these were staged by a routine
  `git add -A`. Subagent transcripts embed raw task text, which carries file paths and
  feature names, so this is a disclosure risk in any public repo, not just noise.
- Follow-up: `.pi-subagents/` added to `.gitignore`. When adopting any agent extension that
  writes run state, confirm its directory is ignored before the first delegated run.

### Prefer source inspection over runtime spikes for "does the tool do X" questions
- Date: 2026-07-31
- Type: learning
- Source: `docs/investigations/2026-07-31-plan-execution-efficiency/notes/`
- Summary: Five planned half-day integration spikes were replaced by four parallel read-only
  source inspections of the candidate dependency. All five questions were resolved, one was
  revealed to be moot (the mechanism did not exist), and two incorrect assumptions in the
  design were caught before any code was written. Reading cannot establish integration
  reality, race behavior, or version skew — those still need one cheap smoke test.
- Follow-up: The same principle the investigation applied to verification gates — do not run
  expensive verification where cheap verification suffices.
