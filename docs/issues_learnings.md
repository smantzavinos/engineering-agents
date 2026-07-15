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

### Team contracts must start before implementation completion
- Date: 2026-07-15
- Type: learning
- Source: Atlas layout dropdown team-mode trial
- Requirement refs: FR-007, FR-008, OPR-003
- Summary: Blocking the verifier until implementation completed delayed the acceptance
  contract and caused repeated task-board polling. Contract packets should start immediately,
  blocked members should stop until messaged, and final review should use fresh strong context.
- Follow-up: ADR 0002 and `docs/team-mode-execution.md`
