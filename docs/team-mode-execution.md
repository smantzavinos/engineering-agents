# Team-Mode Execution

Team mode is a separate planning and execution pipeline optimized for wall-clock speed,
role separation, and cost-aware escalation.

## Pipeline Split

Discovery, research, approach, and approach review are shared. Planning branches only after
the approach is reviewed:

```text
brief → findings → approach → approach review
                              ├─ sequential: plan.md → plan_review.md → worklog.md
                              └─ team: team_plan.md → team_plan_review.md → team-worklog.md
```

`team_plan.md` is created directly from the reviewed approach. It is not derived from
`plan.md`.

## Roles

| Role | Default routing | Responsibility |
|---|---|---|
| Lead | primary chat | dispatcher of last resort, gates, commits, lifecycle |
| Implementation slots (up to 3) | `unspecified-low` (mechanical/bounded-cheap), `unspecified-high` (standard), or `deep` (complex) by packet class | speed-run file-owned packets; minimal checks; lane-scoped claims |
| Visual implementer (optional) | `visual-engineering` | replaces one implementation slot when UI/UX/a11y/visual packets exist |
| Strong rescue implementer | direct `hephaestus` | created only when escalation fires or a planned high-risk packet is ready |
| Contract/verifier (1–2 lanes) | `unspecified-high` or domain category | write contracts early on disjoint test files; publish each family immediately; run targeted evidence |
| Live reviewer | `unspecified-high` | review handoffs immediately in arrival order; create remediation tasks |
| Final reviewer | fresh external `deep` (escalate to `ultrabrain`) | authoritative full-diff review after team closure |

Category-backed members use the Sisyphus-Junior runtime but retain the category's model,
variant, temperature, and fallbacks. Direct team subagent types may be `sisyphus`, `atlas`,
`sisyphus-junior`, or `hephaestus`. Oracle and Prometheus remain external consultations.

The lead creates the full task DAG on the team board at creation time (`team_task_create`
with `blockedBy`) with a lane tag in each subject: `[cheap]`, `[std]`, `[complex]`,
`[visual]`, `[verify]`. Routing follows lanes: mechanical/bounded-cheap packets to
`unspecified-low`, standard to `unspecified-high`, complex to `deep`. Members claim only
ready, file-disjoint tasks within their own lane; they never claim outside it. Use one
`visual-engineering` slot whenever any packet owns frontend components, styling,
interaction, accessibility, responsive behavior, or visual verification.

## Active Slots

Teams may declare more members than they run concurrently. No more than four members work
at once.

Typical allocation:

1. Contract/verifier lanes plus up to three ready implementers.
2. Verifiers sleep after publishing contracts; live reviewer wakes as implementation handoffs
   arrive; an idle verifier may serve as a second reviewer within its own domain.
3. Strong rescue is created on escalation and replaces an active fast slot.
4. Targeted verification wakes only the verifier and roles needed to repair failures.

## Team Plan Structure

The team plan schedules role packets and readiness events, not sequential TDD chunks.

Every implementation packet declares:

- acceptance contracts
- readiness and dependencies
- exclusive files owned
- role/domain, risk tier, and implementer class (mechanical → `unspecified-low`, standard →
  `unspecified-high`, complex → `deep`)
- minimal implementer check
- reviewer checklist and handoff format
- retry limit and escalation target
- integration group

Acceptance contract packets are independently schedulable and start before or alongside
implementation whenever possible.

## Execution Protocol

### Contract stage

The verifier reads the brief, reviewed approach, team plan acceptance contracts, existing
tests, and repo test guidance before implementation. It owns test files declared by contract
packets, authors executable behavioral tests immediately, records current baseline/red
evidence where appropriate, and tells the lead when implementation packets have a stable
contract. It does not write production code or run broad suites.

### Implementation stage

Fast implementers make narrowly scoped changes. They do not commit or run broad suites.
Their handoff lists changed files, assumptions, minimal-check output, and known risks.

### Live review and remediation

The live reviewer reviews each handoff and creates remediation tasks directly. A local defect
gets one retry by its original implementer. A failed retry, ambiguous contract, repeated
defect class, cross-cutting issue, or security/migration/compatibility risk routes to the
Strong rescue implementer.

### Verification and integration

When the lead wakes it after reviewed implementation, the verifier runs contract and targeted
integration commands, records exact evidence, distinguishes implementation failures from
environment/baseline failures, and reports remediation needs to the lead and live reviewer.
It does not repair production code. The lead runs broad gates once per integration group,
updates the worklog, and commits.

### Final review

The lead closes the implementation team, then starts a fresh external `deep` review
against the complete diff and `team_plan.md`. Escalate to `ultrabrain` only for unusually
hard or unique final reviews. Final findings route to the Strong rescue
implementer or a fresh remediation team. The live reviewer is not the final reviewer.

## Event-Driven Coordination

Do not poll on a timer. An event-triggered board check — once, immediately after completing a
task — is required and is not polling.

- The lead pre-creates the full task DAG with `blockedBy` and lane tags.
- After a completion, the member checks the board once and claims the oldest ready,
  file-disjoint task in its own lane; relay-dispatch successors named in each packet are
  messaged directly by the completing member.
- A member with no ready lane work reports idle once and stops.
- Turn-Exit Contract: the lead never ends a turn while a ready task is undispatched, nudges a
  member silent across two turns, and restarts (not the team — the member) after a third.
- Members never use `todowrite`; the team board is the sole task system.
- Prefer per-member restart over team recreation; recreate teams only at wave-commit
  boundaries when a fresh context or changed role mix is cheaper than keeping long-running
  sessions.

There is no documented manual early-compaction control for team members. Short packets,
durable handoffs, idle sessions, and member restarts are the supported context controls.

## Model Escalation

| Condition | Route |
|---|---|
| mechanical isolated work | `unspecified-low` |
| bounded-cheap decision-complete work (frozen design, explicit write set, existing tests) | `unspecified-low` |
| normal implementation or live review | `unspecified-high` |
| UI work | `visual-engineering` |
| planned complex implementation | `deep` |
| failed retry or critical implementation | direct `hephaestus` |
| final independent review | external `deep` |
| unusually hard or unique final review or difficult debugging | external `ultrabrain` |

The original implementer gets one local retry. Strong rescue receives at most two attempts
before the lead pauses for a human decision.

## Ownership

- Lead alone writes git history, `team-worklog.md`, `state.json`, backlog, and requirements.
- Members write only assigned source/test files.
- Reviewer writes task state and findings through team coordination, not durable repo policy.
- Final completion requires clean fresh review and the repo's documented final gate.
