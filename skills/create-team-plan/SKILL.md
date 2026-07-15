---
name: create-team-plan
description: Create a role-oriented team_plan.md directly from a reviewed approach for high-speed OpenCode team-mode execution. Use instead of create-plan when the user selects the team planning pipeline.
harnesses: [opencode]
metadata:
  domain: opencode
---

# Create Team Plan

Create the canonical execution plan for team mode directly from the reviewed approach.

## Role

You are a team-execution planner. Optimize for parallel throughput, explicit ownership,
early acceptance contracts, inexpensive first-pass implementation, independent review,
and bounded escalation.

## Inputs

- Plan directory path
- `brief.md`, `approach.md`, `approach_review.md`, and relevant `findings/`
- Parent epic context when planning an epic child
- Repo verification, backlog, requirements, and directory-specific guidance

## Pipeline Boundary

The reviewed approach is the branch point:

- Sequential execution creates `plan.md` with `create-plan`.
- Team execution creates `team_plan.md` with this skill.

Do not create `plan.md` first. `team_plan.md` is not a derivative or optimization pass over
a sequential plan; it is the canonical plan for this execution mode.

## Process

1. Read the brief, findings, reviewed approach, and repo execution contracts.
2. Extract measurable acceptance contracts before decomposing implementation work.
3. Create Acceptance Contract Packets that can start before or alongside implementation.
4. Create file-owned implementation packets sized for fast, bounded workers.
5. Assign domain, risk tier, implementer class, minimal check, retry limit, and escalation
   target.
6. Define live-review readiness events, remediation routing, verification packets, and
   integration groups.
7. Confirm the active-slot schedule never exceeds four concurrent members.
8. Write `team_plan.md` using
   [references/team-plan-template.md](references/team-plan-template.md).
9. Update `state.json` to `{ "phase": "planned", "status": "active", "mode": "team" }`.

## Quality Rules

### Acceptance contracts come first

Every behavioral outcome must be stated independently of the implementation. Contract
packets name the test location, assertion, expected pre-implementation result, and exact
command. Prefer contract tests that can be authored immediately and prove red against the
current behavior.

### Packets optimize role separation

An implementation packet contains one coherent write-set and no broad verification duty.
Related same-file edits belong in one packet unless a real readiness boundary requires
separation. Do not reproduce sequential TDD tasks as team packets.

### Every packet declares

- readiness condition and dependencies
- role and domain
- risk tier: low, medium, high, or critical
- implementer class: mechanical, standard, or complex
- files owned
- deliverable and acceptance contracts satisfied
- minimal implementer check
- reviewer checklist
- retry limit and escalation target
- integration group

### Implementer classification

Every implementation packet is classified at plan time into exactly one implementer class.
The class is a plan-time decision, recorded on the packet, verified during team-plan review,
and used by the lead to route the packet. Workers never self-select, so the class is the
mechanism that keeps a mechanical implementer from picking up work beyond its intended scope.

| Class | Category route | Assign when the packet is... |
|---|---|---|
| mechanical | `quick` | simple, isolated, low-risk; localized/single-file; no design judgment (renames, config, string/constant edits, boilerplate, mechanical refactors) |
| standard | `unspecified-high` | normal backend/tooling/logic implementation with bounded ownership |
| complex | `deep` | planned high-complexity: cross-module coordination, non-trivial design or algorithms, or subtle correctness/state concerns |

Rules:

- Classify by intrinsic packet difficulty, not by who happens to be idle.
- A packet that owns multiple files, crosses modules, or carries design ambiguity must not be
  mechanical; classify it standard or complex.
- UI/UX/a11y/visual packets route to the `visual-engineering` implementer regardless of class.
- `deep` (complex) is a distinct routable class, not the Strong rescue implementer; rescue
  (`hephaestus`) is reserved for failed retries and cross-cutting escalations.

### Default team topology

- Up to three implementation slots routed by packet class: mechanical (`quick`),
  standard (`unspecified-high`), and complex (`deep`), active when file ownership allows.
- One Strong rescue implementer: direct `hephaestus`, idle until escalation or a planned
  high-risk packet.
- One contract/verifier: authors contracts early, later wakes for targeted verification.
- One live reviewer: cost-controlled streaming review and remediation-task creation.
- Primary chat: lead, sole scheduler, broad-gate runner, committer, and lifecycle owner.
- Final reviewer: fresh external `deep` review after the implementation team closes;
  escalate to `ultrabrain` only for unusually hard or unique review situations.

Declared membership may exceed four; the Active Slot Schedule must keep no more than four
members working concurrently.

### Reviewer-created remediation

The live reviewer may create scoped remediation packets. The original implementer receives
one retry when the defect is local and the contract is clear. Escalate immediately or after
that retry to the Strong rescue implementer for ambiguity, cross-cutting defects,
security/migration/compatibility risk, repeated defect classes, or unclear broad-gate
failures.

### Event-driven readiness

Blocked members must not poll. The plan names the readiness event and who wakes each role.
Idle roles stop after reporting idle; the lead uses team messages to wake them with an
actionable packet.

### Verification ownership

- Implementers run only the packet's minimal check.
- Contract/verifier runs acceptance and targeted integration evidence.
- Live reviewer may add risk-based verification packets.
- Lead runs package/repo gates once per integration group and at final completion.

## Output

Write `team_plan.md` in the plan directory. Do not create `plan.md`, `worklog.md`, or source
changes.

## What You MUST NOT Do

- Do not derive this artifact from a sequential `plan.md`.
- Do not require every implementer to own Red → Green → Break-it → Verify.
- Do not assign a member only blocked work with instructions to keep checking.
- Do not exceed four active members.
- Do not make the live reviewer the final authoritative reviewer.
- Do not implement code, run tests, or modify source files.
