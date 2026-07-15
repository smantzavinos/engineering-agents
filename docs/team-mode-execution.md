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
| Lead | primary chat | schedule, wake members, gates, commits, lifecycle |
| Implementation slots (up to 3) | `quick` (mechanical), `unspecified-high` (standard), or `deep` (complex) by packet class | speed-run file-owned packets; minimal checks |
| Visual implementer (optional) | `visual-engineering` | replaces one implementation slot when UI/UX/a11y/visual packets exist |
| Strong rescue implementer | direct `hephaestus` | high-risk packets and escalations; starts idle |
| Contract/verifier | `unspecified-high` or domain category | write contracts early; run targeted evidence |
| Live reviewer | `unspecified-high` | review handoffs; create remediation tasks |
| Final reviewer | fresh external `deep` (escalate to `ultrabrain`) | authoritative full-diff review after team closure |

Category-backed members use the Sisyphus-Junior runtime but retain the category's model,
variant, temperature, and fallbacks. Direct team subagent types may be `sisyphus`, `atlas`,
`sisyphus-junior`, or `hephaestus`. Oracle and Prometheus remain external consultations.

The lead selects the three implementation slots from the team plan and routes each packet
strictly by its declared implementer class: mechanical packets to `quick`, standard packets
to `unspecified-high`, and complex packets to `deep`. Members never self-select; a
mechanically-routed member receives only mechanically-classified packets. Use one
`visual-engineering` slot whenever any packet owns frontend components, styling,
interaction, accessibility, responsive behavior, or visual verification.

## Active Slots

Teams may declare more members than they run concurrently. No more than four members work
at once.

Typical allocation:

1. Contract/verifier plus up to three ready implementers.
2. Verifier sleeps after contract handoff; live reviewer wakes as implementation handoffs arrive.
3. Strong rescue stays idle until escalation and replaces an active fast slot.
4. Targeted verification wakes only the verifier and roles needed to repair failures.

## Team Plan Structure

The team plan schedules role packets and readiness events, not sequential TDD chunks.

Every implementation packet declares:

- acceptance contracts
- readiness and dependencies
- exclusive files owned
- role/domain, risk tier, and implementer class (mechanical → `quick`, standard →
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

Do not poll.

- The lead pre-assigns ready work.
- A member without an actionable assignment reports idle once and stops.
- The lead wakes members through `team_send_message` with a task ID, readiness evidence,
  write-set, and handoff expectation.
- The lead tracks blocked queues and readiness transitions.
- Recreate teams between major stages when a fresh context or changed role mix is cheaper
  than keeping long-running sessions.

There is no documented manual early-compaction control for team members. Short packets,
durable handoffs, idle sessions, and team recreation are the supported context controls.

## Model Escalation

| Condition | Route |
|---|---|
| mechanical isolated work | `quick` |
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
