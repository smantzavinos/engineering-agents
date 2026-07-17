---
name: create-team-plan
description: Create a role-oriented team_plan.md directly from a reviewed approach for high-speed OpenCode team-mode execution. Use instead of create-plan when the user selects the team planning pipeline.
compatibility: opencode
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
and used to route the packet by lane tag. Members claim only within their lane, so the class
is the mechanism that keeps a cheap implementer from picking up work beyond its intended
scope.

| Class | Category route | Assign when the packet is... |
|---|---|---|
| mechanical | `unspecified-low` | simple, isolated, low-risk; localized/single-file; no design judgment (renames, config, string/constant edits, boilerplate, mechanical refactors) |
| bounded-cheap | `unspecified-low` | decision-complete: all design decisions frozen in the packet text, explicit write set, acceptance tests or precise evidence already exist, negative cases named; may span multiple tightly related files |
| standard | `unspecified-high` | normal backend/tooling/logic implementation with bounded ownership and local judgment |
| complex | `deep` | planned high-complexity: cross-module coordination, non-trivial design or algorithms, subtle correctness/state concerns, or security/authorization/migration judgment |

Rules:

- Classify by intrinsic packet difficulty, not by who happens to be idle.
- Classify by residual ambiguity, not file count. Multi-file work with a frozen design is
  bounded-cheap; single-file work with an open design decision is standard or complex.
- Bounded-cheap qualification test: could a competent implementer execute this packet from its
  text alone, without reading the approach and without making a single design decision? If
  not, it is not bounded-cheap. Never delegate security, migration, authorization, or
  distributed-state judgment to a cheap lane.
- Deferring a design decision into a mechanical or bounded-cheap packet is forbidden. Resolve
  it in the Frozen Decisions section or assign it to a named `complex` packet that must
  complete before the dependent cheap packets.
- UI/UX/a11y/visual packets route to the `visual-engineering` implementer regardless of class.
- `deep` (complex) is a distinct routable class, not the Strong rescue implementer; rescue
  (`hephaestus`) is reserved for failed retries and cross-cutting escalations.

### Frozen Decisions

The plan must contain a Frozen Decisions section. Every decision the approach deferred —
interface shapes, data-loading mechanisms, discriminators, file/module locations, naming —
is either resolved there or assigned to a `complex` decision packet scheduled before its
dependents. Verify that planned file locations respect framework import boundaries (for
example, client code must not import server-only modules).

### DAG task table

The plan must contain one table with a row per task: id, lane
(`[cheap]`/`[std]`/`[complex]`/`[visual]`/`[verify]`), write set, `blockedBy` dependencies,
acceptance contracts, and targeted check profile. This table is what the lead feeds directly
into `team_task_create`. Waves, where used, are commit checkpoints only — never hold a
dependency-satisfied packet behind a stage or wave boundary without a named dependency or
resource lock.

### Resource locks

Declare non-file resources that cannot safely overlap, and which tasks hold them: build
output directories, test harnesses/ports/preview servers, shared route files with serialized
ownership, and the git index (lead only).

### Verification profiles

Name each verification command set once (for example `backend-targeted`, `web-client`,
`e2e-local`, `broad-gate`) with exact commands copied from canonical repo docs. Packets and
gates reference profiles by name instead of restating commands.

### Throughput summary

The plan must state: the critical path, the maximum ready width per wave, declared role
multiplicity (simultaneous instances required per role), and the projected share of
implementation packets on cheap routes. If the cheap share is below 50%, justify each
non-cheap packet by naming its residual ambiguity or risk.

### Default team topology

- Up to three implementation slots routed by packet class lane: mechanical/bounded-cheap
  (`unspecified-low`), standard (`unspecified-high`), and complex (`deep`), active when file
  ownership allows. Prefer plans where two or more cheap-lane implementers stay busy through
  the main build frontier.
- Strong rescue implementer: direct `hephaestus`, created only when escalation fires or a
  planned high-risk packet becomes ready. Not a default dormant member.
- One or two contract/verifier lanes with disjoint test files: author contracts early, publish
  each contract family immediately when ready, later wake for targeted verification.
- One live reviewer: cost-controlled streaming review and remediation-task creation; an idle
  verifier may serve as a second reviewer within its own domain.
- Primary chat: lead, dispatcher of last resort under the Turn-Exit Contract, broad-gate
  runner, committer, and lifecycle owner.
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

Blocked members must not poll on a timer. An event-triggered board check — once, after
completing a task — is required, and members may claim ready, file-disjoint tasks within
their own lane. The plan names each packet's relay-dispatch successors (who is notified when
it completes) and the wake event for any role the lane-claim mechanism cannot reach. Idle
roles stop after reporting idle; the lead dispatches anything relay and lane claims miss.

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
- Do not hold a dependency-satisfied packet behind a stage/wave boundary without a named
  dependency or resource lock.
- Do not defer a design decision into a mechanical or bounded-cheap packet.
- Do not schedule more simultaneous instances of a role than the roster declares.
- Do not restate verification commands per packet instead of referencing named profiles.
- Do not make the live reviewer the final authoritative reviewer.
- Do not implement code, run tests, or modify source files.
