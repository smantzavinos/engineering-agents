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
| **Worker** | fresh Crew worker per task (1–4 concurrent) | Execute one packet: implement, run its cheap check, hand off | Commit; run broad suites; claim outside its write set |
| **Reviewer** | fresh Crew reviewer per handoff | Verdict every handoff: SHIP / NEEDS_WORK (retry with feedback) / RETHINK (block, escalate to lead) | Fix code; approve its own findings |
| **Board** | pi-messenger crew (files, not an agent) | Hold the task DAG, statuses, file reservations. Wake agents on events. Give the human a live overlay. | — |

Escalation is a rule, not a role: **a worker gets one retry as a fresh worker carrying the
review findings; if that fails the task blocks and the lead rescues it with a strong
subagent.** Two failures → lead pauses
and asks you.

### Model tiers

Lanes multiply **models, not roles**. A worker is the same contract regardless of the model
running it; the plan's lane tag picks the tier.

| Lane | Team role | Tier | Qualifies when | Escalates to |
|---|---|---|---|---|
| `cheap` | `worker-cheap` | small/fast | **decision-complete**: executable from the packet row + referenced contracts/decisions with zero judgment calls | `complex` on failed retry |
| `std` | `worker-std` | mid | normal implementation | `complex` on failed retry |
| `complex` | `worker-complex` | strong + thinking | design-bearing, security, migration, concurrency; all risk-flagged tasks | human |
| `visual` | `worker-visual` | std/complex variant | UI/UX/a11y — a routing specialization, not a fourth tier | as base tier |

**A lane is a Team role, and that is the whole routing mechanism** — one `role` string on a
task sets its model, thinking level, and skills [SUB-2]. Lanes are declared once in the Team
profile:

```json
{ "roles": {
    "worker-cheap":   { "model": "<small>" },
    "worker-std":     { "model": "<mid>" },
    "worker-complex": { "model": "<strong>", "thinking": "high" },
    "worker-visual":  { "model": "<mid>" } } }
```

Two constraints this imposes. **Never name a lane with a bare packaged role** — the `worker-*`
prefix keeps lanes distinct and editing-capable [SUB-2a]. **And the Team profile must be
active**, or every task silently falls back to the default worker model with no error, so the
materializer asserts it before creating any task [SUB-2b].

Three tiers total across the whole process: small (cheap workers), standard (std workers,
handoff reviewer), strong (complex workers, lead-owned rescue, final reviewer). The lead runs
on your session model. Target ≥ 50% of tasks on `cheap` (measured: $0.60 vs $3.10 per task, no
quality loss); a plan that can't hit that hasn't settled enough decisions — that is a planning
signal, not a routing problem.

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
1. Lead materializes the plan's task table onto the board (`task.create` with deps, **role**
   — which carries the lane's model, thinking level, and skills — risk flags, and the packet
   body as task content).
2. Workers claim ready, file-disjoint tasks. Claim = reserve write set; handoff = release.
3. **On every handoff**, the reviewer runs. SHIP → done. NEEDS_WORK → task resets and retries
   as a *fresh worker carrying the review findings and its own progress log* (Crew workers run
   `--no-session`; there is no session resume). RETHINK, or a second failure, → blocked for the
   lead.
4. **Escalation is the lead's, not Crew's.** A task that exhausts `maxAttemptsPerTask` blocks.
   The lead — which, being the primary session, is the only participant holding the `subagent`
   tool — remediates it with a strong fresh subagent, then `task.done`s it. This is the one
   place `pi-subagents` is used, and it is exactly the place its resume, watchdog, and
   telemetry are worth paying for.
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
| NEEDS_WORK verdict | fresh worker, same task | fix, with findings + progress log injected |
| RETHINK / attempts exhausted | lead | remediate via strong subagent, or escalate to you |
| risk pause | lead → you | approve / reject |
| wave complete | lead | broad gate, commit |
| board empty | lead | close sequence |
| agent silent 2 turns | lead | nudge once, then restart that member |

Commits do **not** trigger review — review already happened at handoff, and the lead is the
only committer. Timed loops are banned; if an event isn't firing, fix the event.

## 5. Context rules

| Situation | Context | Why |
|---|---|---|
| Worker, first attempt | **fresh + packet** | packet is cheaper and more reliable than a transcript |
| Worker, remediation retry | **fresh + findings + progress log** | not a choice: Crew workers run `--no-session`. Crew re-injects the task spec, `last_review` feedback, and ~30 progress lines, which recovers part of the re-discovery cost |
| Worker, attempts exhausted | **lead-owned strong subagent** | the old context holds the wrong model — that's why it failed. Only the lead can spawn, so escalation necessarily leaves Crew |
| Any reviewer | **fresh, always** | independence |
| Lead helper (replanning) | fork | genuinely needs the conversation |

> Earlier drafts specified `subagent resume` for retry #1. That mechanism does not exist here
> [SUB-1]; the retry is fresh but carries findings and progress [SUB-6].

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
| `pi-messenger` | board + deps + waves, **worker/reviewer execution**, file reservations, review-on-handoff loop, live overlay, messaging | `pi install npm:pi-messenger` |
| `pi-subagents` | lead-side only: rescue of blocked tasks, final reviewer, budgets, telemetry, intercom | installed |
| `pi-hooks` (lsp, checkpoint) | free diagnostics; per-turn rollback refs. Lead session by default; reaching Crew workers requires adding the extension path to `crew-worker.md` frontmatter | installed, enable |
| `pi-team` (ours, small) | plan table → board materializer; the four plan gates; telemetry harvest | build (~3 small scripts) |
| Skills | `/discovery`, `/design`, `/pi-team-plan` (human-only, `disable-model-invocation`) + `pi-team-lead`, `pi-team-worker` (model-facing) | write (5, replacing ~19) |

**Crew executes; `pi-subagents` does not** [SUB-1]. The consequences are load-bearing and are
reflected above: no worker session resume, no edit-gated watchdog over workers, and no stored
cost/tool telemetry. What we trade that for — review on every handoff — is the control the
evidence says actually catches defects.

Config in one place (messenger config + Team profile): concurrency ≤ 4, reviewer iterations
≤ 3, attempts-per-task ≤ 2, `dependencies: strict`, lane roles with their models, per-run
budgets.

## 9. What this deletes

Discovery and Design as agent modes and artifacts (conversation covers them). Sequential mode
and per-task Red-Green-Break-Verify (contracts + handoff review + wave gates are the quality
controls; break-it surfaced zero defects in the measured baseline). The
brief/findings/approach/approach-review/worklog chain (one plan contract; the board is the
live worklog; telemetry is the record). Dual-harness rendering (Pi only). Mandatory human
plan approval (opt-in or risk-triggered).

## 10. Known risks

- **Conversational planning can skip rigor for big work.** Mitigation: the four plan gates
  are mechanical and always run; you can always say "review this plan with me first."
- **Two schedulers** (board autonomy vs lead waves) can fight. Mitigation: `work` runs exactly
  one wave by default; `autonomous: true` is opt-in. Run lead-driven until proven.
- **Reviewer-on-every-handoff costs money.** It buys the removal of late rework (21% of
  measured time) and per-task break-it. Telemetry per run proves or refutes it; budgets cap it.
- **Reservations only block structured `edit`/`write` — bash writes bypass them entirely**
  [SUB-4]. The plan-time disjoint-write-set gate is therefore the real control; reservations
  only catch drift, and only for well-behaved edits. Do not let this design lean on them.
- **We depend on `plan.json`'s on-disk shape** [SUB-3]. It is the only place we touch Crew's
  internals — pin the `pi-messenger` version and re-check on upgrade.
- **A missing Team profile degrades silently** [SUB-2b]. The materializer must assert it
  before creating tasks.
- **Cost telemetry is weaker than the baseline's** [SUB-5]. The calibration run cannot be
  compared to the baseline on cost. Wall-clock and task counts remain comparable.

---
*Evidence base: `README.md` in this directory — measured baseline (5.3 h / $47.61 / 1.61x
ceiling; all defects found by review+E2E, none by per-task break-it) and extension evaluation.*

*`SUB-n` references point to the substrate constraints table in `notes/README.md`, which is the
single source for how the substrate behaves. State consequences here; never restate mechanism
or `file:line` citations — change them in one place.*
