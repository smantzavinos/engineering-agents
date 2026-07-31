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

### Dogfood small plans before locking proportional packet gates
- Date: 2026-07-31
- Type: learning
- Source: Pi team rollout dogfood before T5
- Summary: Dogfooding exposed a small-plan ceremony trap: a strict 20% critical-path share forced
  artificial five-task chains even when three independent tasks were each 20 minutes or less.
  Use an absolute floor with proportional packet gates so small plans stay naturally parallel.

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
