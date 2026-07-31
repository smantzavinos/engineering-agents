# Pi Team Execution

**Status:** proposal — fresh design, not canonical
**Scope:** Pi only. Team mode only. Replaces the Discovery/Design/Execute pipeline and
sequential mode if adopted.
**Visual companion:** `pi-team-execution-plan.html` (sequence diagrams + trigger taxonomy).

One sentence: **talk until the intent is clear, freeze it into one plan, put the tasks
on a board, let a small team execute with review-on-handoff, and read the summary at the
end.**

---

## 1. Principles

1. **Conversation is the front of the process.** Discovery and design happen in normal chat
   with the lead. No ceremony, no separate agents, no artifacts until intent is clear.
2. **One plan contract.** A single `plan.md` holds everything a worker needs. It lives in a
   plan directory that may hold reference and generated material beside it, but nothing else
   is load-bearing. No brief, findings, approach, approach-review, worklog chain.
3. **Feedback is immediate, not terminal.** Every handoff is reviewed on arrival. Defects
   found at the end of a plan are a process failure.
4. **Context is the scarce resource.** Workers get a packet, not a transcript. The lead
   never ingests full diffs. Remediation reuses the context that already exists.
5. **The human sets intent and reads outcomes.** Everything between is agent work unless the
   human opts in.
6. **Measure every run.** A run that leaves no telemetry can't improve the next one.

## 2. Roles

Five roles. Three are agents, one is a mechanism, one is you.

| Role | Who | Responsibility | Never does |
|---|---|---|---|
| **Human** | you | Set intent in conversation. Approve only when asked or on high-risk flags. Watch live if desired. Read the closing summary; iterate if needed. | Babysit execution |
| **Lead** | primary Pi session | Converse → write plan → create board → dispatch → run wave gates → commit → close and summarize | Implement tasks; read full diffs |
| **Worker** | fresh subagent per task (1–4 concurrent) | Execute one packet: implement, run its cheap check, hand off | Commit; run broad suites; claim outside its write set |
| **Reviewer** | fresh subagent per handoff + always-on watchdog | Verdict every handoff: SHIP / NEEDS_WORK (back to same worker, with feedback) / RETHINK (block, escalate to lead) | Fix code; approve its own findings |
| **Board** | pi-messenger crew (files, not an agent) | Hold the task DAG, statuses, file reservations. Wake agents on events. Give the human a live overlay. | — |

Escalation is a rule, not a role: **a worker gets one remediation retry with its own retained
context; a failed retry gets a fresh worker on a strong model.** Two failures → lead pauses
and asks you.

### Model tiers

Lanes multiply **models, not roles**. A worker is the same contract regardless of the model
running it; the plan's lane tag picks the tier.

| Lane | Tier | Qualifies when | Escalates to |
|---|---|---|---|
| `cheap` | small/fast | **decision-complete**: executable from the packet row + referenced contracts/decisions with zero judgment calls | `complex` on failed retry |
| `std` | mid | normal implementation | `complex` on failed retry |
| `complex` | strong + thinking | design-bearing, security, migration, concurrency; all risk-flagged tasks | human |
| `visual` | std/complex variant | UI/UX/a11y — a routing specialization, not a fourth tier | as base tier |

Three tiers total across the whole process: small (cheap workers), standard (std workers,
handoff reviewer), strong (complex workers, rescue, watchdog — on a *complementary* strong
model to the lead's — and final reviewer). The lead runs on your session model. Target ≥ 50%
of tasks on `cheap` (measured: $0.60 vs $3.10 per task, no quality loss); a plan that can't
hit that hasn't settled enough decisions — that is a planning signal, not a routing problem.

## 3. Lifecycle

```
CONVERSE ──► PLAN ──► EXECUTE ──► CLOSE
 (chat)     (1 file)  (board+team)  (summary)
```

### Converse
Normal chat with the lead. Talk through the problem, options, constraints. The lead may spawn
throwaway scouts/researchers to inform the conversation; their output lands in chat, not in
artifacts. Two optional, **human-only** skills exist for when plain conversation isn't enough:
`/discovery` (Socratic pushback for fuzzy problems) and `/design` (structured option
comparison with scout fanout). Both carry `disable-model-invocation: true` — Pi cannot
discover or auto-load them, so they cost zero context until you type the slash command.
The stage ends when you trigger **`/pi-team-plan`**.

### Plan
The lead creates `plans/<date>-<slug>/` and writes `plan.md` (template in §6) directly from
the conversation. Then:

1. A **fresh reviewer** checks it against four mechanical gates (no judgment calls):
   - critical path ≤ 60% of the serial estimate
   - no task > 20% of the critical path
   - no two same-wave tasks with overlapping write sets
   - every task executable from its packet alone (no "see conversation")
2. Gate failures → lead splits/decouples tasks and re-checks. No human involvement.
3. **Human approval only if:** you asked for it up front, or any task carries a risk flag
   (`migration`, `destructive`, `auth`, `api-contract`). Otherwise execution starts
   immediately and you're notified it started.

### Execute
1. Lead materializes the plan's task table onto the board (`task.create` with deps, model
   lane, risk flags; packet body as task content).
2. Workers claim ready, file-disjoint tasks. Claim = reserve write set; handoff = release.
3. **On every handoff**, the reviewer runs. SHIP → done. NEEDS_WORK → task resets to the
   *same worker, resumed with its context* plus the findings (max 1 retry, then fresh strong
   worker). RETHINK → blocked, lead decides.
4. Underneath, the **watchdog** reviews any writer's actual repo diff at turn end (edit-gated,
   includes LSP diagnostics) — a free adversarial net that costs nothing when nothing changed.
5. When a wave completes: lead runs the broad gate profile **once**, commits
   (`team(W<n>): <summary>`). Lead is the only committer. Expensive checks (full suites,
   lint-the-world, E2E) exist only here — never inside a worker's loop.
6. Risk-flagged tasks pause for your approval **only if planning couldn't resolve them**;
   otherwise they run and the outcome notes what to verify after the fact.
7. Blockers, ambiguity, or product decisions reach you via intercom immediately. Nothing
   else does.

**Watching:** `/messenger` overlay shows every agent, its status, current task, and the
activity feed, live. You can DM any agent from there. Watching is optional; the run doesn't
need you.

### Close
1. Lead runs the final gate, then commissions a **fresh strong reviewer** on the full diff
   vs `plan.md`. Findings → one remediation pass → re-review.
2. Lead harvests telemetry (wall-clock, cost, per-task time, defects-by-origin, rework share)
   from run artifacts into the plan directory.
3. Lead posts the closing summary: what shipped, evidence, deferred items (→ backlog),
   risk-flag outcomes to verify, telemetry vs estimate.
4. You read it. Iterate in conversation if needed — a follow-up is just a new small plan.

## 4. Event model — nothing polls

| Event | Wakes | Action |
|---|---|---|
| task becomes ready (dep met) | idle worker | claim, reserve, execute |
| worker handoff | reviewer | review, verdict |
| NEEDS_WORK verdict | same worker (resumed) | fix with feedback |
| RETHINK / 2nd failure / risk pause | lead → you if needed | decide |
| wave complete | lead | broad gate, commit |
| board empty | lead | close sequence |
| agent silent 2 turns | lead | nudge once, then restart that member |

Commits do **not** trigger review — review already happened at handoff, and the lead is the
only committer. Timed loops are banned; if an event isn't firing, fix the event.

## 5. Context rules

| Situation | Context | Why |
|---|---|---|
| Worker, first attempt | **fresh + packet** | packet is cheaper and more reliable than a transcript |
| Worker, remediation retry | **resume** (`subagent resume`) | keeps the mental model; re-discovery was ~27% of measured runtime |
| Worker, after failed retry | **fresh, strong model** | the old context holds the wrong model — that's why it failed |
| Any reviewer | **fresh, always** | independence |
| Lead helper (replanning) | fork | genuinely needs the conversation |

Anti-bloat rules: handoffs are ≤ ~15 lines (files changed, check output, assumptions, risks);
full diffs go worker→reviewer directly, never through the lead; the plan template has no
prose sections a worker doesn't consume; skills state rules once and link, never restate.

## 6. The plan directory

```
plans/<date>-<slug>/
  plan.md        ← the contract. The only file agents read by default.
  notes/         ← optional. Reference material, research, diagrams, superseded drafts.
  review.md      ← generated at close: final review findings.
  telemetry.md   ← generated at close: measured vs planned.
```

**Loading rule.** Only `plan.md` is injected into task packets. Anything else in the
directory is human/reference material and never enters an agent's context unless a task row
explicitly cites it. If a worker needs a note to do its job, the plan didn't freeze enough —
fix the plan, don't add a reference.

`plan.md` has five sections and nothing else:

```markdown
# <title>
Intent: <2–4 lines: what changes, why, what stays the same>
Risk flags: <none | migration, destructive, auth, api-contract>
Approval: <auto | human>

## Contracts
| ID | Behavior | Evidence (test/command) |

## Decisions
| ID | Decision | Resolution |          ← everything the conversation settled; workers never guess

## Checks
| Profile | Command | Cost | Inner-loop safe? |   ← measured; expensive ⇒ wave-gate only

## Tasks
| ID | Deps | Lane | Deliverable | Write set | Contracts | Check |
```

Lanes route models per the tier table in §2. A task row plus its referenced contracts and
decisions must be sufficient to execute it — that self-sufficiency is also what qualifies a
task for the `cheap` lane.

## 7. Repo hooks

The process touches durable repo state at exactly three points, all lead-owned:

| Hook | When | Contract |
|---|---|---|
| **Requirements** | plan cites IDs; approved edits are a plan task; final review checks alignment | `docs/requirements.md` |
| **Testing levels** | check profiles come from repo test docs; broad = wave gate, targeted = worker loop | `docs/testing-strategy.md` |
| **Backlog** | deferred/discovered non-critical work → `TASK-XXXX` at close; critical discoveries stop the line instead | `docs/backlog.md` |

Nothing else in the repo docs is process-load-bearing.

## 8. Deployment

| Piece | Provides | Status |
|---|---|---|
| `pi-subagents` | spawn / resume / steer / budgets / telemetry artifacts / intercom / watchdog | installed |
| `pi-messenger` | board + deps + waves, file reservations, review-on-handoff loop, live overlay, messaging | `pi install npm:pi-messenger` |
| `pi-hooks` (lsp, checkpoint) | free diagnostics; per-turn rollback refs | installed, enable |
| `pi-team` (ours, small) | plan table → board materializer; the four plan gates; telemetry harvest | build (~3 small scripts) |
| Skills | `/discovery`, `/design`, `/pi-team-plan` (human-only, `disable-model-invocation`) + `pi-team-lead`, `pi-team-worker` (model-facing) | write (5, replacing ~19) |

Config in one place (`.pi/settings.json` + messenger config): concurrency ≤ 4, reviewer
iterations ≤ 3, attempts-per-task ≤ 2, per-run cost/turn budgets, lane→model map, watchdog on
with a strong complementary model.

## 9. What this deletes

Discovery and Design as agent modes and artifacts (conversation covers them). Sequential mode
and per-task Red-Green-Break-Verify (contracts + handoff review + watchdog + wave gates are
the quality controls; break-it surfaced zero defects in the measured baseline). The
brief/findings/approach/approach-review/worklog chain (one plan contract; the board is the
live worklog; telemetry is the record). Dual-harness rendering (Pi only). Mandatory human
plan approval (opt-in or risk-triggered).

## 10. Known risks

- **Conversational planning can skip rigor for big work.** Mitigation: the four plan gates
  are mechanical and always run; you can always say "review this plan with me first."
- **Two schedulers** (board autonomy vs lead waves) can fight. Mitigation: run the board
  wave-by-wave under lead control until proven; autonomy is an optimization.
- **Reviewer-on-every-handoff costs money.** It buys the removal of late rework (21% of
  measured time) and per-task break-it. Telemetry per run proves or refutes it; budgets cap it.
- **Reservations are advisory.** The write-set gate at plan time is the real control;
  reservations catch drift.

---
*Evidence base: `README.md` in this directory — measured baseline (5.3 h / $47.61 / 1.61x
ceiling; all defects found by review+E2E, none by per-task break-it) and extension evaluation.*
