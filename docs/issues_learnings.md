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

### Check strength must match risk label, not task size
- Date: 2026-08-06
- Type: learning
- Source: `docs/investigations/2026-08-06-team-mode-throughput-regression/README.md` §3
- Requirement refs: `NFR-003`
- Summary: The two `destructive`/`migration` tasks in the Hermes run were authored with `bash -n`
  as their minimal check. Workers truthfully reported the check passing while the real contract
  suite had failing assertions, so verification silently moved to the lead and those two tasks
  absorbed 46% of all attempts. Risk-labelled tasks require an executable check that runs their
  own fixtures and reports assertion totals.
- Follow-up: `docs/adr/0004-continuous-crew-execution-and-per-task-review.md`

### Unbounded fresh review ratchets instead of converging
- Date: 2026-08-06
- Type: learning
- Source: `docs/investigations/2026-08-06-team-mode-throughput-regression/README.md` §4
- Summary: Fourteen review rounds using one model, one prompt shape, and no stopping rule kept
  producing new high-severity findings on already-reviewed code, including demands outside the
  write set and evidence the bundle format cannot carry. Bound review to two rounds, give the
  reviewer an explicit negative scope, require in-scope/out-of-scope tagging, and rotate reviewer
  identity between rounds.
- Follow-up: `docs/adr/0004-continuous-crew-execution-and-per-task-review.md`

### Crew barriers serve review and Git, not scheduling
- Date: 2026-08-06
- Type: learning
- Source: `docs/investigations/2026-08-06-team-mode-throughput-regression/README.md` §5–§6
- Summary: `crew/handlers/work.ts` awaits the whole dispatched batch, so there is no slot refill,
  but the decisive serialization was the lead protocol: per-wave diff review plus per-wave commit
  requires a frozen HEAD. Because write sets are disjoint, `git diff -- <write set>` supports
  per-task review with no frozen HEAD, which removes the barrier without weakening review.
- Follow-up: `docs/adr/0004-continuous-crew-execution-and-per-task-review.md`; `TASK-0005`

### Lobby-worker crashes consume the Crew attempt budget
- Date: 2026-08-06
- Type: issue
- Source: `docs/investigations/2026-08-06-team-mode-throughput-regression/README.md` §5
- Summary: Five `Lobby worker <name> exited (code 1)` events counted as genuine attempts and
  auto-blocked three tasks under `maxAttemptsPerTask: 2`, forcing 15 live mutations of
  `config/pi-team/crew-config.json` mid-run. Keep the package default of 5 attempts and treat
  lobby crashes as retryable infrastructure events rather than task failures.
- Follow-up: `TASK-0006`

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
- Source: Atlas layout dropdown team-mode trial
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
