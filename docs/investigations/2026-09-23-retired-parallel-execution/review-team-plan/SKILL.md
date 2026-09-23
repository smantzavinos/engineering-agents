---
name: review-team-plan
description: Review team_plan.md for contract completeness, role separation, concurrency safety, cost-aware routing, event-driven readiness, and escalation readiness before OpenCode team-mode execution.
harnesses: [opencode]
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
- Every packet declares a valid implementer class (mechanical, bounded-cheap, standard, or
  complex) that matches its residual ambiguity and risk, not its file count. A mechanical
  packet must be simple, isolated, low-risk, and localized. A bounded-cheap packet must be
  decision-complete: frozen design in the packet text, explicit write set, existing acceptance
  tests or precise evidence, named negative cases, and no security/migration/authorization/
  distributed-state judgment. Any cheap-lane packet containing an unresolved design decision
  is a Blocker. Mis-classification is a finding because routing follows class lanes.

### Throughput and scheduling

- Recompute ready width from the DAG task table; a roster count is not evidence of useful
  concurrency. Fewer than two runnable implementation lanes during the main build frontier is
  a Major finding unless the DAG genuinely forbids more.
- Scheduled simultaneous assignments must not exceed the declared instances of any role
  (Blocker: one member scheduled to run two packets concurrently).
- Any packet whose `blockedBy` is satisfiable earlier than its scheduled stage/wave is a
  missed pull-forward finding unless a named dependency or resource lock justifies the hold.
- Verify the Frozen Decisions section resolves or assigns every decision the approach
  deferred, and that planned file locations respect framework import boundaries (client code
  must not import server-only modules).
- Verify the projected cheap-lane share meets the plan's stated target or each exception is
  justified by named ambiguity/risk.
- Commands sharing generated build output, ports, or a local test harness must not be
  scheduled concurrently without a declared resource lock.
- Broad gates duplicated across baseline, integration groups, and final completion without a
  risk justification are a finding; profiles should be referenced, not restated.
- A single verifier owning unrelated contract lanes when test files could be split into
  disjoint lanes is a finding when it serializes the first implementation frontier.
- Review queue width exceeding review capacity (more than two concurrent handoffs feeding one
  reviewer with no overflow rule) is a finding.
- A worklog design that duplicates the plan rather than serving as a wave ledger is a finding.

### Role and cost discipline

- Up to three fast implementers have useful independent work, with two or more cheap-lane
  implementers busy through the main build frontier when the DAG permits.
- The Strong rescue implementer is created on escalation, not declared as a dormant default
  member.
- Contract/verifier and live-review responsibilities are distinct.
- The live reviewer is cost-controlled; the fresh final reviewer defaults to `deep`, with
  `ultrabrain` reserved for unusually hard or unique final reviews.
- Category/direct-agent routing matches packet risk, domain, and implementer class
  (mechanical/bounded-cheap→`unspecified-low`, standard→`unspecified-high`, complex→`deep`).

### Event-driven coordination

- No member starts with only blocked work and instructions to keep checking.
- Timer-based polling is prohibited; event-triggered post-completion board checks and
  lane-scoped claims are required and must be described.
- Every packet names its relay-dispatch successors; every blocked role the claim mechanism
  cannot reach has a wake event and sender.
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
that can commit before their evidence exists, a mechanical class assigned to a packet with
design ambiguity, a bounded-cheap class assigned to a packet with an unfrozen decision, one
role scheduled in two places at once, or a client-side contract file planned under a
server-only module path.

## Severity

- **Blocker:** unsafe or impossible execution graph; role scheduled beyond its declared
  multiplicity; cheap-lane packet with an unresolved design decision; invalid client/server
  import boundary
- **Critical:** missing acceptance contract, rescue/escalation path, Frozen Decisions
  coverage, or final review
- **Major:** timer-polling worker, >4 active slots, ambiguous ownership, late-only tests,
  missing minimal check, implementer-class mismatch or missing class, fewer than two runnable
  implementation lanes without DAG justification, missed pull-forward, unlocked shared
  resource, duplicated broad gates, or live reviewer serving as sole final reviewer
- **Minor/Nit:** clarity or formatting improvements

## Completion Criteria

The review is complete only after a clean pass with zero Blocker/Critical/Major findings.

## Output

Write or append `team_plan_review.md`. Do not create a sequential `plan.md` or implement code.
