# Pi Team Execution

**Status:** reviewed proposal — additive rollout; not canonical until calibration passes
**Scope:** Pi only. Team mode only. OpenCode and the current canonical process remain unchanged
until a separately approved migration.
**Visual companion:** `pi-team-execution-plan.html`.

One sentence: **talk until intent is clear, freeze it into one self-contained plan, compile the
plan into a reviewed task board, let a small team execute one dependency wave at a time, and
close with objective evidence.**

---

## 1. Principles

1. **Conversation is the front of the process.** No required discovery/design artifact chain.
   Optional lead-invoked scouts inform chat; they do not create load-bearing artifacts.
2. **One plan contract.** `plan.md` is the only authored execution contract. Generated board,
   review, and telemetry files may sit beside it but do not become new sources of truth.
3. **Mechanical checks prove structure; fresh review proves meaning.** Never claim semantic
   packet sufficiency from a parser.
4. **Review follows each completed wave.** The lead generates task-scoped working-tree review
   bundles after the worker batch returns and sends them to fresh read-only reviewers—not at
   commit time or on a timer.
5. **Context is scarce.** Workers receive one packet. The lead does not ingest full worker
   transcripts or diffs.
6. **The human sets intent and controls risk.** All risk-labelled tasks require approval.
7. **Measure only observable facts.** Missing cost or attempt data stays unavailable, never
   inferred.

## 2. Roles and routing

| Role | Responsibility | Never does |
|---|---|---|
| Human | Set intent; approve risk-labelled work; read outcome | Babysit normal execution |
| Lead | Write/review plan; create board; dispatch waves; run broad gates; commit; close | Implement planned task packets |
| Worker | Implement one packet; run its minimal check; publish concise handoff | Commit; run broad suites; write outside its set |
| Task reviewer | Fresh `pi-team-reviewer` subagent; review one path-scoped bundle after the wave; emit exact verdict | Fix code; inspect peer write sets; approve truncated evidence |
| Board | Hold DAG, state, progress, and live activity | Make design decisions |
| Fresh final reviewer | Review full diff after the execution team closes | Reuse the live reviewer context |

A lane is a Team role; its `role` string carries model, thinking, and skills [SUB-2]. Never use
a bare packaged role name [SUB-2a]. The profile must be active before materialization [SUB-2b].

| Lane | Team role | Model | Thinking | Use |
|---|---|---|---|---|
| `cheap` | `worker-cheap` | `github-copilot/gpt-5.6-terra` | low | Decision-complete, isolated work |
| `std` | `worker-std` | `github-copilot/gpt-5.6-terra` | medium | Normal implementation |
| `complex` | `worker-complex` | `github-copilot/gpt-5.6-sol` | high | Security, migration, concurrency, cross-cutting work |
| `visual` | `worker-visual` | `github-copilot/gpt-5.6-terra` | high | Normal UI/UX/a11y work |
| `visual-complex` | `worker-visual-complex` | `github-copilot/gpt-5.6-sol` | high | Risk-bearing or cross-cutting visual work |

Cheap-lane share is telemetry, not a gate. Calibration may establish a useful target later.

## 3. Lifecycle

```text
CONVERSE → PLAN + REVIEW → MATERIALIZE → EXECUTE WAVES → FINAL REVIEW → CLOSE
```

### Converse

Normal chat is sufficient. `/discovery` and `/design` remain optional human-invoked helpers;
there is no mandatory pre-plan stage or durable artifact. `/pi-team-plan` begins planning.

### Plan and review

The lead creates `plans/YYYY_MM_DD_<slug>/plan.md` using §6, then runs two gates:

1. **Mechanical gate:** schema and reference integrity; acyclic dependencies; deterministic
   wave derivation; critical path ≤ 60% of serial estimate; no task > 20% of the critical path;
   no same-wave write-set overlap.
2. **Fresh semantic review:** verifies intent coverage, packet sufficiency, check adequacy,
   risk/approval classification, and that no implementer decision remains.

The lead fixes findings and repeats until both pass. Execution starts automatically unless the
human requested plan approval. Risk-labelled tasks remain blocked at the board until the human
approves them.

### Materialize

`pi_messenger` is a Pi tool rather than a CLI [SUB-7], so the lead performs task creation in
its Pi session. Before materialization, the lead-session preflight registers with
`pi_messenger({ action: "join" })`; registration is ephemeral and every other Crew action requires
that registered state [SUB-10]:

1. Activate and confirm the active profile is exactly `pi-team` and contains all five roles
   [SUB-2b].
2. Treat `config.json` and `agents/` as stable inputs. Board runtime entries are `plan.json`,
   `plan.md`, `tasks/`, `blocks/`, `artifacts/`, `planning-progress.md`, and
   `planning-outline.md`. Refuse initialization when any runtime entry exists.
3. Recovery moves only those runtime entries to
   `.pi/messenger/crew-runs/<UTC-basic-timestamp>/`; it never moves stable inputs. An incomplete
   run requires human confirmation before recovery. A partial materialization failure may be
   archived automatically because no worker has started.
4. Atomically initialize `plan.json` with `prd` equal to the repo-relative authored plan path,
   UTC ISO-8601 `created_at`/`updated_at`, and zero counters [SUB-3] [SUB-8].
5. Create tasks in stable topological order (numeric task ID as tie-breaker).
6. Capture each returned Crew ID and translate later `Deps` through the plan-ID→Crew-ID map.
7. Use title `<ID> — <Deliverable truncated to 80 Unicode code points>`. Serialize content in
   this fixed order: plan ID, lane, estimate, integration group, deliverable, write set,
   expanded Contracts, expanded Decisions, minimal Check, and worker rules.
8. Pass role and risk labels to `task.create`; matching labels persist pending approval and make
   the task unstartable until `task.approve` [SUB-9].
9. Run `crew.validate`. The single missing-`plan.md` warning is expected because the authored
   plan stays at `prd`; any graph/count error or any other warning stops execution. Partial state
   is archived and recreated, never resumed heuristically.

The authored `plan.md` remains canonical. Board files are generated runtime state.

### Execute waves

1. Open one **wave transaction**: require a clean index/worktree, record `BASE = HEAD`, then
   invoke one `work` wave; autonomous continuation stays off. Cleanliness is required only when
   opening the transaction. All retries, rescue, and integration remediation remain dirty inside
   the same transaction with `HEAD == BASE` until its single lead commit.
2. Up to four ready, file-disjoint workers run. Reservations are drift detection only; plan-time
   disjoint write sets are the actual collision control [SUB-4].
3. Crew auto-review is disabled. Its reviewer only sees `base_commit..HEAD`, which is empty
   before the lead commit; worker commits are forbidden because concurrent shared-index commits
   can capture peer changes. The lead records the wave base commit before dispatch.
4. After the batch returns, require `HEAD == BASE` (mechanically rejecting worker commits), then
   run `pi-team review-wave` with the original wave as both allowed scope and bundle set. It
   rejects changed paths outside the scope union and emits one complete bundle per requested
   task, including untracked files. Oversized or incomplete evidence blocks review.
5. A fresh read-only `pi-team-reviewer` subagent reviews each bundle against the expanded packet
   and emits exact verdict `SHIP`, `NEEDS_WORK`, or `MAJOR_RETHINK`.
6. `NEEDS_WORK`: lead writes each finding to task progress, resets the task, and retries inside
   the same dirty transaction. Regenerate evidence with allowed scope = original wave and bundle
   set = retried task; re-review only bundles whose SHA changed. The retry is fresh and receives
   recent progress [SUB-6]. Two Crew attempts are the limit.
7. `MAJOR_RETHINK` or exhausted attempts: lead resets/blocks the task and gets one strong rescue
   using a fresh `github-copilot/gpt-5.6-sol` subagent. Regenerate the bundle; a fresh task review
   must return `SHIP` before completion. Rescue failure pauses for the human.
8. `review-wave` hashes the current contents of every integration group's normalized write-set
   union. The lead stores the last green digest. After task review, run each completed group whose
   digest differs from its last green digest—even if a later wave changed an already-green group.
9. On integration failure, a fresh strong remediation pass owns only that group's union and stays
   inside the wave transaction. Regenerate evidence with allowed scope = original wave plus the
   failed group's tasks, bundle only tasks whose paths changed, and re-review changed bundles.
   Rerun the check only when its digest changed. Allow two remediation revisions; record every
   attempt and never rerun an unchanged digest.
10. Commit every reviewed wave before dispatching the next, even when an integration group spans
    waves. A spanning group runs only when complete; earlier wave commits keep review isolation.
    Commit only when every affected completed group has a green digest.

Only events wake work. No polling, commit-triggered review, or timer-triggered review.

### Final review and close

1. Run the repo final gate.
2. Close Crew execution and commission a fresh `github-copilot/gpt-5.6-sol` full-diff review.
3. If findings require changes, allow at most two fresh strong remediation passes. After each
   pass, rerun the final gate on the changed tree and commission a fresh re-review. Completion
   requires both a green final gate and a clean review on the same commit. Cap exhaustion pauses.
4. Write `telemetry.md` from observable data only: start/end timestamps, task count, Crew
   attempts/review resets when present, out-of-write-set findings, integration/final gate
   failures, and human interruptions by enumerated category. Cost is `unavailable` [SUB-5].
5. Summarize shipped behavior, exact evidence, approved risk outcomes, backlog IDs, and measured
   calibration results.

## 4. The plan contract

```text
plans/YYYY_MM_DD_<slug>/
  plan.md       # authored source of truth
  review.md     # generated semantic/final review record
  telemetry.md  # generated objective run record
  notes/        # optional human reference; never injected by default
```

`plan.md` has exactly these sections and declares its input contract version:

```markdown
# <title>
Plan schema: 1
Intent: <what changes, why, and what stays unchanged>
Approval: <auto | requested>

## Contracts
| ID | Behavior | Evidence |

## Decisions
| ID | Decision | Resolution |

## Checks
| ID | Scope | Command | Cost | Worker-safe |

## Tasks
| ID | Deps | Lane | Estimate min | Risk labels | Integration | Deliverable | Write set | Contracts | Decisions | Check |
```

Rules:

- Task IDs match `T[1-9][0-9]*`; contract IDs `C[1-9][0-9]*`; decision IDs
  `D[1-9][0-9]*`; check IDs `K[1-9][0-9]*`; integration groups `G[1-9][0-9]*`.
  IDs are unique, references resolve, and dependencies form a DAG.
- `Deps`, `Risk labels`, `Contracts`, and `Decisions` use comma-separated values or `—`.
- `Write set` uses comma-separated POSIX repo-relative paths. Absolute paths, `.`/`..`, empty
  segments, backslashes, symlinks, and globs are rejected. A trailing `/` means directory;
  otherwise the path is an exact file. Same-wave sets must be disjoint by normalized prefix.
- Wave = dependency depth; numeric task ID breaks ties. More than four tasks at one depth are
  chunked in groups of four in that order.
- Every task has a positive integer estimate, one worker-safe `Check`, and one integration group.
  Each referenced integration group has exactly one `Checks` row with scope `integration:G<n>`.
  Exactly one Checks row has scope `final`. A check row used by a task has scope `worker` and
  `Worker-safe` = `yes`.
- Allowed lanes are the five roles above.
- Allowed risk labels are `migration`, `destructive`, `auth`, and `api-contract`; every such task
  requires human approval through the active profile [SUB-9]. No per-task waiver exists.
- Mechanical self-sufficiency means required fields are non-empty and references resolve.
  Semantic sufficiency is the fresh reviewer's responsibility.

The task `content` passed to `task.create` is exactly this LF-terminated template. Referenced rows
are sorted by numeric ID; `—` fields expand to `- none`. The worker-rules block is invariant.

```markdown
# Plan task <TASK_ID>

Lane: <LANE>
Estimate min: <N>
Integration: <GROUP_ID>

## Deliverable
<DELIVERABLE>

## Write set
- <PATH>

## Contracts
- <ID>: <BEHAVIOR> | Evidence: <EVIDENCE>

## Decisions
- <ID>: <DECISION> | Resolution: <RESOLUTION>

## Minimal check
<CHECK_ID>: <COMMAND>

## Worker rules
- Modify only the declared write set.
- Use structured edit/write tools; do not mutate files through bash.
- Run only the minimal check above.
- Do not commit or run broad gates.
- Record concise progress and complete the Crew task with evidence.
```

## 5. Configuration and deployment boundary

Stable configuration is reproducible; runtime state is not:

| State | Durable source | Runtime location |
|---|---|---|
| `pi-messenger@0.15.0` | `nix/modules/pi/default.nix` | managed Pi package |
| Crew defaults | `config/pi-team/crew-config.json` | tracked relative symlink at `.pi/messenger/crew/config.json` |
| Task reviewer | `agents/pi-team-reviewer.md` via Nix `home.file` | `~/.pi/agent/agents/pi-team-reviewer.md` |
| `pi-team` profile | `config/pi-team/team-profile.json` via Nix `home.file` | `~/.pi/agent/messenger/team-profiles/pi-team.json` |
| Active Team and board | generated | `.pi/messenger/team/`, `.pi/messenger/crew/` |
| Pi-only skills | canonical `skills/*`, `harnesses: [pi]`, rendered `dist/skills/pi/*` | `~/.pi/agent/skills/*` |

`.gitignore` narrowly admits the stable project config symlink and ignores all other `.pi/`
runtime state. `config/pi-team/` is the single source for Crew/profile configuration; the task
reviewer is a normal repo-owned Pi agent. Each repository adopting this experimental flow copies
that config scaffold and commits the same narrow symlink/ignore rules. Each lead session first
joins Messenger, then activates `pi-team` via `team.profile.use` [SUB-10]; activation is
idempotent and is a lead preflight, not durable project state.

Exact Crew config:

```json
{"concurrency":{"workers":4},"artifacts":{"enabled":true},"review":{"enabled":false,"maxIterations":2},"work":{"maxAttemptsPerTask":2,"maxWaves":1,"stopOnBlock":true},"dependencies":"strict","coordination":"minimal"}
```

Exact Nix-managed `pi-team` profile:

```json
{"name":"pi-team","roles":{"worker-cheap":{"model":"github-copilot/gpt-5.6-terra","thinking":"low","skills":["pi-team-worker"]},"worker-std":{"model":"github-copilot/gpt-5.6-terra","thinking":"medium","skills":["pi-team-worker"]},"worker-complex":{"model":"github-copilot/gpt-5.6-sol","thinking":"high","skills":["pi-team-worker"]},"worker-visual":{"model":"github-copilot/gpt-5.6-terra","thinking":"high","skills":["pi-team-worker"]},"worker-visual-complex":{"model":"github-copilot/gpt-5.6-sol","thinking":"high","skills":["pi-team-worker"]}},"approval":{"mode":"risk-labels","labels":["migration","destructive","auth","api-contract"]},"memory":{"inject":["decision","interface","risk"],"maxCharsPerType":4000}}
```

The additive rollout does not alter OpenCode outputs, existing shared skills, current canonical
requirements, or current process docs. New skills use unique names and `harnesses: [pi]`.

## 6. Verification and calibration

Implementation uses the repo's canonical gates:

- targeted specs during each task;
- `./tests/run-tests.sh fast` at task/integration completion;
- `./scripts/pi-dev.sh --verify` for current-checkout Pi package/skill/module wiring;
- `home-manager switch --flake .#<hostname>` before active-install proof;
- `./tests/run-tests.sh all` before rollout completion.

Baseline failures are recorded before the touched gate and compared after it; only new failures
block completion.

Bootstrap calibration lives under this investigation's `calibration/` directory, not canonical
`plans/`, because current accepted requirements still prescribe `team_plan.md` and a team
worklog. This is an isolated experiment, not a silent process exception.

Each run freezes its serial comparator before execution and records only objective measures:
wall-clock start/end; review resets; out-of-write-set findings; integration/final gate failures;
and human interruptions classified as `intent`, `risk-approval`, `blocked-correctness`, or
`environment`. A run passes correctness only with no out-of-write-set change, no significant
defect surviving final review, all required gates green relative to baseline, and no unclassified
interruption. The documentation bootstrap does not count toward efficiency promotion. Promotion additionally
requires three representative code-change runs whose median wall-clock is ≤ 60% of their frozen
serial estimates. Cheap-lane share is diagnostic only.

Only after those calibration criteria pass may a separate, explicitly approved migration update
canonical requirements/process docs or retire existing Pi/OpenCode paths.

## 7. Known constraints

- Crew workers, not `pi-subagents`, execute tasks [SUB-1]. `pi-subagents` is lead-side for
  path-scoped task review, rescue, and final review.
- The retry is fresh but carries findings and progress [SUB-6].
- Direct `plan.json` initialization is the only internal-store coupling [SUB-3] [SUB-8]. Re-check
  it on every version bump.
- Reservations do not protect bash writes [SUB-4].
- Crew stores no task cost [SUB-5].

---

*Evidence base: this directory's `README.md`; substrate mechanism and citations live only in
`notes/README.md` under `SUB-n` IDs.*
