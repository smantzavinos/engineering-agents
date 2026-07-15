---
name: review-team-plan
description: Review team_plan.md for contract completeness, role separation, concurrency safety, cost-aware routing, event-driven readiness, and escalation readiness before OpenCode team-mode execution.
compatibility: opencode
metadata:
  domain: opencode
---

# Review Team Plan

Review a team-mode plan before a team worklog or implementation team is created.

## Inputs

- Plan directory containing `team_plan.md`
- `brief.md`, `approach.md`, `approach_review.md`, and relevant findings
- Existing `team_plan_review.md`, if present
- Repo verification, backlog, requirements, and directory guidance

## Process

1. Read the reviewed approach and team plan.
2. Review solution coverage and team-execution readiness.
3. Apply obvious low-risk corrections directly to `team_plan.md`.
4. Record findings in `team_plan_review.md` using
   [references/review-template.md](references/review-template.md).
5. Repeat until a pass finds zero Blocker/Critical/Major issues.
6. Update `state.json` to `{ "phase": "reviewed", "status": "active", "mode": "team" }`
   only after a clean pass.

## Quality Criteria

### Contract-first readiness

- Every goal maps to an acceptance contract.
- Contract packets can begin before or alongside implementation where technically possible.
- Tests are not authored only after observing the finished implementation.
- Assertions validate observable behavior rather than source text or mocks alone.

### Packet quality

- Implementation packets own coherent, non-overlapping write-sets within active batches.
- Same-file edits are combined unless a real readiness boundary requires separation.
- Every packet has readiness, deliverable, minimal check, handoff, reviewer checklist,
  retry limit, escalation target, and integration group.
- Every packet declares a valid implementer class (mechanical, standard, or complex) that
  matches its intrinsic difficulty and risk. A mechanical packet must be simple, isolated,
  low-risk, and localized; cross-file, cross-module, or design-ambiguous work is standard or
  complex. Mis-classification is a finding because the lead routes strictly by class.

### Role and cost discipline

- Up to three fast implementers have useful independent work.
- A Strong rescue implementer is declared and initially idle unless risk requires it.
- Contract/verifier and live-review responsibilities are distinct.
- The live reviewer is cost-controlled; the fresh final reviewer defaults to `deep`, with
  `ultrabrain` reserved for unusually hard or unique final reviews.
- Category/direct-agent routing matches packet risk, domain, and implementer class
  (mechanical→`quick`, standard→`unspecified-high`, complex→`deep`).

### Event-driven coordination

- No member starts with only blocked work and instructions to keep checking.
- Every blocked role has a wake event and sender.
- Do not poll instructions are explicit.
- Active Slot Schedule never exceeds four concurrent members.

### Remediation and escalation

- Live reviewer may create remediation packets.
- Original implementer gets at most one local retry.
- Failed retry and high-risk/cross-cutting findings route to Strong rescue implementer.
- Contract ambiguity routes to lead clarification, not speculative implementation.

### Verification ownership

- Implementers run minimal checks only.
- Contract/verifier owns targeted acceptance evidence.
- Lead owns broad integration/final gates.
- Fresh final review (default `deep`) runs after the implementation team closes.

### Logic bug hunt

Flag contradictions such as dependent packets scheduled concurrently, overlapping files,
contracts that cannot be written until after implementation, rescue capacity counted as an
active fifth slot, reviewer bottlenecks, verification without an owner, integration groups
that can commit before their evidence exists, or a mechanical class assigned to a packet with
cross-file ownership, cross-module scope, or design ambiguity.

## Severity

- **Blocker:** unsafe or impossible execution graph
- **Critical:** missing acceptance contract, rescue/escalation path, or final review
- **Major:** polling worker, >4 active slots, ambiguous ownership, late-only tests, missing
  minimal check, implementer-class mismatch or missing class, or live reviewer serving as
  sole final reviewer
- **Minor/Nit:** clarity or formatting improvements

## Completion Criteria

The review is complete only after a clean pass with zero Blocker/Critical/Major findings.

## Output

Write or append `team_plan_review.md`. Do not create a sequential `plan.md` or implement code.
