## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | Location | Decision required | Status |
|---|---|---|---|---|---|
| RN-01 | Blocker | The purported quiescent boundary is neither an observable zero-lobby precondition nor a process/write barrier; a refusal has no event-driven recovery path | approach.md D-I; execution-model.md §3/§5; plan.md Boundary Quiescence/T6; `crew/handlers/work.ts`, `crew/registry.ts`, `index.ts` | Yes | not resolved |
| RN-02 | Major | Lead rerun removes forged worker attestation but does not make every minimal check non-mutating, bounded, failure-handled, or affordable at each boundary | approach.md D-D; plan.md State Ownership/T6; `config/pi-team/crew-worker.md` | Yes | partially resolved |
| RN-03 | Major | A static `scopeIsValid` chunk is not necessarily the actual completed/retry dirty cohort; reset/blocked work and a one-task retry from a multi-task chunk cannot use the claimed completed-wave scope | approach.md D-H; plan.md T3/T6; `tools/pi-team.mjs:reviewWave` | Yes | not resolved |
| RN-04 | Critical | The `--evidence` schema/failure ordering is much stronger but remains ambiguous about raw duplicate keys, exact object/byte/path rules, `pathStatus` placement, and ordering within evidence failures | plan.md CLI Contract Mini-Spec/T3; `tools/pi-team.mjs` | Yes | partially resolved |
| RN-05 | Major | ADR 0004 `review-wave` evidence consequence lacked an owner | plan.md T1/T4 | No | resolved |
| RN-06 | Major | Template lint now names positionals/duplicates but cannot parse its own valueless `--require-quiescent` flag or fully validate option arity | plan.md T6; `tests/specs/skill-content-spec.sh` | No | not resolved |
| RN-07 | Major | Dogfood metrics were not reproducible and misrepresented the schema-1 gate boundary | plan.md Task Graph metrics | No | resolved |
| RN-08 | Minor | Task graph falsely claimed disjoint write sets | plan.md Task Graph | No | resolved |
| RN-09 | Minor | Materially changed specs lacked mapped requirement citations | plan.md T2/T3/T4 | No | resolved |
| RN-10 | Critical | `task.progress` author is neither role-authenticated nor authoritatively classifiable as worker versus lead | prior progress-record design | Yes | resolved |
| RN-11 | Blocker | `pi-team` cannot map plan IDs to Crew task files from `--crew-dir`, so it cannot read status/progress evidence | prior `review-task` design | Yes | resolved |
| RN-12 | Blocker | Gate-only commits can change the global bundle base while unrelated work remains in progress, invalidating a task-record base match | prior per-task-record design | Yes | resolved |
| RN-13 | Major | A 4 KiB tail becomes a 5.5 KiB progress line injected into retry prompts, with no aggregate budget | prior progress-record design | No | resolved |
| RN-14 | Major | T8 still lacks a required Break-it check and executable closure assertion | plan.md T8 | No | not resolved |
| RN-15 | Critical | `review-wave` promises optional/valueless flags, but its only current option parser requires every declared option to take a value; the parser migration and invalid-combination contract are absent | plan.md CLI Contract Mini-Spec/T3; `tools/pi-team.mjs:parseOptions` | Yes | not resolved |
| RN-16 | Major | ADR 0004 and brief still promise *worker* check evidence while the design supplies lead-rerun evidence; T1 wrongly says the former is literally satisfied | brief.md; plan.md T1/D-D; ADR 0004 Consequences | Yes | not resolved |

## Open Decisions (roll-up — update each pass)

| ID | Decision | Options | Recommendation | Status |
|---|---|---|---|---|
| RN-01 | Can this workflow establish and recover an all-worker terminal boundary without polling? | upstream event-driven all-assignment barrier/interlock; an observable enforced no-lobby mode; manual controlled run | Stop claiming local quiescence. The registry is not exposed to the lead and board status is not process liveness. Require an upstream observable cohort barrier/wake, or descope runtime continuous execution to a human-controlled protocol that does not claim NFR-003 compliance. | Open |
| RN-02 | How are lead reruns restricted, isolated, and handled when they fail or cost too much? | explicit read-only bounded check class with pre/post verification; isolated snapshot/worktree reruns; no rerun/evidence absent | Do not infer safety from `Worker-safe: yes`. Define a lead-safe contract, timeout/budget, failure transition, and snapshot order; otherwise omit the feature. | Open |
| RN-03 | What is the valid allowed dirty cohort after retry/reset/block and across integration groups? | clean/reset old paths before a boundary; immutable cohort manifest; adapt `scopeIsValid` to an exact dispatch record | Define the recovery invariant and make the tool validate it. A retry must either retain its original full compiler chunk as scope or use a new validated cohort; a singleton retry is not generally a valid current scope. | Open |
| RN-04 | What is the complete evidence JSON grammar and deterministic rejection order? | streaming duplicate-detecting parser plus closed schema; constrain/reject duplicate keys before ordinary JSON parse | Specify JSON object types, UTF-8 byte measurement, evidence pathname/root policy, duplicate-key rejection, `pathStatus` location, and a total ordered list within evidence validation as well as across Git checks. | Open |
| RN-06 | What command grammar must the template lint validate? | per-option arity table including boolean flags; shell-aware parser restricted to canonical commands | Define valueless `--require-quiescent`, value-taking flags, rejection of flag-as-value, `${VAR}` normalization, and canonical logical-line tokenization; add mutations for each. | Open |
| RN-10 | What authenticated Crew-owned fact distinguishes the producing worker from the lead? | upstream task-evidence/progress authorization; durable authenticated actor binding; label all records untrusted | Superseded for this plan: no worker-role evidence is used; bundle verification is only `lead-verified` or `absent`. | Resolved |
| RN-11 | How can `pi-team` resolve plan task `Tn` to `tasks/task-N.{json,progress.md}` without a second state store? | formal title encoding; a Crew task field/upstream extension; immutable map passed to tool | Superseded for bundle evidence: `review-wave` no longer reads Crew task files. Materialization still needs its in-session map to translate plan dependencies. | Resolved |
| RN-12 | How are task-local check bases reconciled with a global `HEAD == BASE` after an integration commit? | prohibit commits while any task is active; two base identities/snapshot binding; rerun in isolation | Superseded with no per-task evidence record; retain `HEAD == BASE` only for the actual boundary snapshot. | Resolved |
| RN-15 | How does `review-wave` parse optional/value/boolean flags while preserving existing calls? | structured option declaration with arity/requiredness; a command-specific parser | T3 must explicitly replace the all-required `parseOptions` use, define legal partial pairs and argument-error precedence, and test legacy plus every invalid optional form. | Open |
| RN-16 | Does ADR 0005 amend ADR 0004's worker-evidence consequence, and what does the brief promise? | amend it to lead-verified boundary evidence; restore a genuine authenticated worker producer (upstream) | Amend ADR 0004 explicitly. Do not call lead-generated command/exit/output the worker's evidence. Align brief, T1, approach, plan, and ADR consequences. | Open |

---

## Review 2026-08-06 (Review 1)

**Plan:** `plans/2026_08_06_continuous_crew_execution/plan.md`
**Scope:** full
**Handoff readiness:** No

### Source-citation verification

- **Confirmed:** D-A's substrate citation is real. `crew/handlers/work.ts` awaits one
  `spawnAgents(...)` batch and returns; `index.ts`'s `agent_end` handler sends the
  `crew_continue` message with `triggerTurn: true` and `deliverAs: "steer"`. It is therefore
  valid to say the lead gets a turn at an autonomous *wave boundary*, rather than that Crew has
  internal continuous slot refill. The plan correctly preserves `TASK-0005` as upstream work.
- **Confirmed:** D-B's citation is real. `crew/handlers/review.ts` builds the implementation
  review from `git diff ${baseCommit}..HEAD` and `git log ${baseCommit}..HEAD`, and truncates a
  diff over 50,000 characters. With lead-only gate commits, it will see no committed delta while
  `HEAD == BASE`. Keeping native `review.enabled: false` is justified.
- The citations do **not** establish that the proposed external-review protocol preserves
  dependency correctness or has the worker evidence it claims; those are the blockers below.

### ADR 0004 Consequence Coverage

| ADR 0004 consequence | Owning plan task | Review result |
|---|---|---|
| Config values; native review disabled | T2 | Covered. |
| Lead continuous dispatch, per-task review, gate barriers | T6 | Nominally covered, but blocked by RN-01/RN-02/RN-03. |
| Plan decomposition, operator-task exclusion, strong risk checks | T5/T3 | Covered, but CLI contract is unresolved (RN-04). |
| Reviewer negative scope/classification/two-round limit | T4 | Covered. |
| `pi-team.mjs` reporting and worker evidence in **`review-wave`** bundles | No task owns this as written | **Not covered** (RN-05). T3 instead freezes `review-wave` and adds `review-task`. |
| Setup and team-execution docs | T7 | Covered, but docs lack contract-specific Red coverage (RN-06). |
| Upstream slot refill / infra attempt accounting | Non-goals, TASK-0005/TASK-0006 | Safely deferred; the plan has a local attempt-budget mitigation. |
| Calibration before promotion | T8 backlog item | Covered, subject to the metric correction in RN-07. |
| Render/redeploy installed skills | T7 | Covered. |

### Implementer Decisions Remaining

The following decisions change a tooling/CLI or execution contract and therefore cannot be left
for implementation:

- The dependency-release point relative to an asynchronous review verdict (RN-01).
- The persistent source and representation of worker check command, exit code, tail, and status
  (RN-02).
- The allowed dirty scope for `review-task` (RN-03).
- JSON/human warning taxonomy, exit behavior, deterministic field shape, and command grammar for
  `GATE_RISK_CHECK` and `review-task` (RN-04).
- Whether ADR 0005 replaces, or T3 extends, the accepted `review-wave` evidence contract (RN-05).

### Test Adequacy Assessment

- Coverage matrix complete: **No.** It has no row/test for preventing dependent dispatch before
  effective `SHIP`, collecting durable worker-check evidence, allowing siblings in the declared
  dirty run scope, staged/index status, or the finding-filter/rescue transition.
- Negative/edge cases identified for each row: **No.** In particular, T3 omits staged status,
  missing/invalid check-output source, sibling changes, unsupported shell syntax, and downstream
  dispatch after `NEEDS_WORK`.
- Bad-test avoidance addressed in approach.md: **Partly.** T3's fixture tests can be behavioral,
  but the new lead protocol is protected chiefly by text anchors; this can go green while the
  stated protocol is impossible.
- E2E seed/fixture data confirmed to support scenarios: **No.** The existing tool fixture supports
  `review-wave`, but the plan does not specify a fixture that has one reviewed task, a dirty
  sibling, a dependent, durable worker evidence, and a later `NEEDS_WORK`.
- TDD checklists include break-it step for all tasks: **No.** T1's human-decision exception is
  legitimate. T7's generator regeneration exception is legitimate only for generated `dist/`,
  not for its two semantic documentation changes. T4's target spec is already known rather than
  a Red-step discovery.

### Issues

#### Blocker

##### RN-01: Logic bug: asynchronous review permits execution of unreviewed-task dependents
- **Severity:** Blocker
- **Location:** `plan.md:130`, `152`, `362-374`; approach D-A/D-D.
- **Problem:** T6 launches reviewers asynchronously and immediately calls autonomous `work`; it
  only collects verdicts at the next boundary. Crew makes dependencies ready from worker
  `task.done`, not from this external effective verdict. Thus, if T1 completes, its reviewer is
  still pending, and T2 depends on T1, the immediate next `work` can start T2. A later
  `NEEDS_WORK` resets/retries T1 after T2 has already consumed T1's unreviewed implementation.
  The proposed filter cannot undo T2's work or restore a valid dependency graph.
- **Why it matters:** This breaks the core "per reviewed task" safety contract, invalidates the
  retry/rescue path, and can produce a gate-green merged state whose dependency execution order
  was unsound. Disjoint file ownership does not solve semantic dependencies.
- **Fix:** Specify a state machine and executable mechanism that holds a task's dependents until
  the effective verdict is `SHIP`. It may overlap a pending review only with tasks independent of
  that reviewed task. Add a fixture/integration-style protocol test covering T1 -> T2, a delayed
  `NEEDS_WORK`, and the fact that T2 is not dispatched; add the corresponding SHIP release case.
- **Decision required:** Yes.
- **Status:** open.

##### RN-02: Logic bug: the plan cannot produce the bundle evidence it calls authoritative
- **Severity:** Blocker
- **Location:** `plan.md:45-47`, `253-259`, `287-294`, `362-366`; ADR 0004 Consequences.
- **Problem:** `review-task` accepts externally supplied `--check-cmd`, `--check-exit`, and
  optionally `--check-output FILE`, but no task creates a durable authoritative value for them.
  The current local worker only sends `evidence.tests: ["<minimal-check-command>"]` in
  `config/pi-team/crew-worker.md`; it records neither exit code nor output. Current Crew task
  evidence has no output field. Direct-worker artifacts are not a safe substitute because they
  are not task-keyed and lobby-assigned workers (`crew/lobby.ts`) write no standard artifacts.
  The plan also changes ADR 0004's requested **staged-path status** into merely
  `tracked/untracked`, which cannot answer staged-file evidence requests.
- **Why it matters:** The reviewer is instructed to treat fields as authoritative that the lead
  must invent, infer, or omit. This repeats exactly the structurally impossible-evidence failure
  from the investigation and makes the principal D-D mitigation non-implementable.
- **Fix:** Before T3/T6, choose and task a durable local evidence protocol. It must define who
  writes command, exit status, bounded output, and per-path index/worktree/untracked status; how
  the lead binds it to the plan task and snapshot; and failure behavior when it is absent or
  malformed. Add any necessary worker/config/test ownership. Alternatively declare that the lead
  reruns the named check, label it lead evidence, and update the policy accordingly. Test direct
  and lobby-compatible paths plus staged, unstaged, and untracked files.
- **Decision required:** Yes.
- **Status:** open.

##### RN-03: Logic bug: `review-task --task` cannot review a member of a dirty concurrent wave
- **Severity:** Blocker
- **Location:** `plan.md:45-47`, `253-259`, `362-366`; current `tools/pi-team.mjs:reviewWave`.
- **Problem:** T3 says a single-task invocation uses that task's write set under the same
  out-of-scope invariant as `review-wave`. Current `review-wave` rejects *any* changed path not
  in its supplied scope. In a legitimate wave where T1 and T2 have disjoint write sets, invoking
  `review-task --task T1` after both workers complete sees T2 as out of scope and must reject.
  Its proposed signature supplies no allowed-wave/run scope from which it could distinguish T2
  from a genuinely undeclared dirty path.
- **Why it matters:** The command fails exactly when parallel work exists, so T6 cannot generate
  per-task snapshots at a wave boundary. Relaxing the check without another scope would instead
  conceal unauthorized edits.
- **Fix:** Define an explicit allowed dirty scope (for example `--allowed-scope T1,T2`) separate
  from the one bundled task, or use immutable per-task worktree snapshots. Preserve HEAD==BASE
  and reject a path outside the allowed scope. Add T3 cases for accepted dirty sibling changes,
  rejected undeclared changes, and no leakage of sibling diff bytes into `T1.diff`.
- **Decision required:** Yes.
- **Status:** open.

#### Critical

##### RN-04: The new CLI contract is materially underspecified
- **Severity:** Critical
- **Location:** `plan.md:95-97`, `120-122`, `243-259`, `263-275`, `504-508`.
- **Problem:** This is a versioned CLI/JSON surface, but the plan leaves central contract choices
  to the implementer: advisory output is "a new non-fatal diagnostic class **or** warning lines";
  it never states the JSON warning field/schema, human rendering, ordering, or compatibility
  behavior. The `GATE_RISK_CHECK` parser is likewise undefined for command forms, quoting,
  environment prefixes, pipelines, `bash script`, `bash -n script`, `sh -c`, wrappers, and more
  than one possible file argument; "under the write root" is not defined in the existing compiler.
  Optional `--check-output` has no missing-file/empty-file semantics. Exit codes for the new
  command's argument, policy, and I/O failures are also not stated.
- **Why it matters:** Two reasonable implementations will admit/reject different risk checks and
  serialize different output while both satisfy the prose. This is a tooling contract boundary,
  not an implementation detail; string-based tests would false-green it.
- **Fix:** Put a concrete mini-spec in T1/T3: versioned JSON fields (including a deterministic
  warnings collection distinct from fatal diagnostics), human format, stable diagnostic/warning
  codes, sorting, and 0/1/2 exit policy. Define a deliberately limited check-command grammar and
  reject unsupported shell constructs rather than pretending to parse shell; state exactly how a
  script path is resolved and what assertion-total regex is accepted. The idiom does exist:
  numerous `tests/specs/*.sh` initialize `PASS=0 FAIL=0` and print
  `Results: %d passed, %d failed`, including `pi-team-config-spec.sh` and
  `skill-content-spec.sh`; use that verified static pattern. Add fixture tests for every listed
  accepted/rejected grammar branch and JSON determinism.
- **Decision required:** Yes.
- **Status:** open.

#### Major

##### RN-05: ADR 0004 coverage is silently narrowed beyond the commit-granularity amendment
- **Severity:** Major
- **Location:** ADR 0004 Consequences; `plan.md:64`, `154`, `158`, `253-259`, `379`, `463-464`.
- **Problem:** ADR 0004 specifically says that `tools/pi-team.mjs` should embed command, exit,
  and staged-path status in **`review-wave` bundles**. T3 instead adds `review-task`, retains
  `review-wave` unchanged, and its matrix asserts that it remains unchanged. The plan only says
  that ADR 0005 narrows "per reviewed task or per gate" commits; it does not explicitly amend
  this separate `review-wave` consequence. Further, `tracked/untracked` is not the ADR's staged
  status.
- **Why it matters:** An accepted ADR consequence has no owning task, and gate-scope audits still
  use the old bundle that lacks the evidence the ADR requires. The implementation could be
  accepted while materially failing the declared decision.
- **Fix:** The gate-only D-C narrowing itself is sound: per-task commits conflict with frozen
  `HEAD == BASE`, and gate commits preserve the existing integration-digest model. In ADR 0005,
  explicitly state whether `review-task` supersedes `review-wave` evidence for all task review
  and why gate audits need not carry it, *or* extend `review-wave` too. Then align T3, the
  compatibility statement, matrix, and tests, including real staged/index status. Do not start
  the dependent work until the human accepts that explicit amendment.
- **Decision required:** Yes.
- **Status:** open.

##### RN-06: Verification/TDD only checks prose where the runtime protocol needs behavioral proof
- **Severity:** Major
- **Location:** `plan.md:168`, `297-310`, `383-426`, `456-467`.
- **Problem:** T6's `skill-content-spec.sh` assertions prove literals such as `review-task` and
  `autonomous: true`, not that the sequence safely records evidence, filters a verdict, holds
  dependents, retries once, routes a backlog finding, and invokes a valid bundle command. The
  proposed scratch-fixture execution is neither an exact command nor a maintained test. T4's
  choice is not unresolved: `skill-content-spec.sh:298-306` already specifically covers
  `agents/pi-team-reviewer.md`; `repo-structure-spec.sh` only checks agent presence/frontmatter.
  T7 has no failing assertion for the two semantic documentation edits; render staleness is a
  legitimate exception for generated `dist/`, not for those docs.
- **Why it matters:** The plan can satisfy all stated break-it checks while shipping an impossible
  or contradictory lead protocol. It also violates the strict Red → Green → Break-it contract for
  documentation semantics.
- **Fix:** Make T4 explicitly own `tests/specs/skill-content-spec.sh`. Add deterministic protocol
  fixtures/lints that validate the lead command template against the actual T3 CLI contract and
  cover RN-01--RN-03 scenarios; do not call text-anchor tests full behavioral coverage. Add
  failing readiness/skill-content assertions for the required new Pi setup/team-mode statements
  before editing them, with a narrow mutation break-it check. Keep the render exception limited to
  `dist/` regeneration.
- **Decision required:** No.
- **Status:** open.

##### RN-07: Dogfood arithmetic is partially correct but not auditable, and the gate claim is misleading
- **Severity:** Major
- **Location:** `plan.md:176-183`.
- **Problem:** The wave arithmetic is correct: `(4 + 1 + 1 + 1 + 1) / 5 = 1.6`, maximum is 4,
  and `4 / 5 = 80%`. The displayed ratio is also arithmetically consistent if the unsupported
  estimates are assumed: `120 / 175 = 0.6857…`, approximately 0.69. But no per-task estimates
  or estimate table appear anywhere in this sequential plan, so neither 175 nor 120 nor the
  critical path can be recomputed. Moreover the existing `pi-team check` accepts only schema-1
  Crew plans, whereas this is a standard sequential plan; it is not actually a board plan being
  exempted from the 0.6 gate.
- **Why it matters:** Calling the result "honest" and saying it "would trip" an uninvoked,
  inapplicable compiler gate obscures the important distinction between advisory dogfood math and
  an enforced board gate.
- **Fix:** Either remove the unsupported serial/critical-path claim, or add a small explicit
  estimate ledger for T1–T8 plus calculation. State plainly that the sequential plan is outside
  the schema-1 `pi-team check` contract; the T3 fixture, not this plan, exercises the board hard
  gate. This is an acceptable rationale for sequential execution only after that boundary is
  explicit.
- **Decision required:** No.
- **Status:** open.

#### Minor

##### RN-08: Declared task ownership is internally inconsistent
- **Severity:** Minor
- **Location:** `plan.md:168-174`, `286`, `329-344`, `354-355`.
- **Problem:** The Task Graph says all write sets are disjoint, but T4, T5, and T6 all modify
  `tests/specs/skill-content-spec.sh`; T4's graph row does not list it, despite its checklist
  requiring assertions there. T5's statement that the file "belongs to no other task" directly
  contradicts its later note.
- **Why it matters:** Sequential execution makes the overlap safe, but inaccurate ownership
  undermines the plan's own decomposition example and makes a future conversion to team mode
  hazardous.
- **Fix:** List the spec in T4/T5/T6 touched files, remove the false disjointness claim, and say
  that sequential task order serializes this intentional shared-test edit. Keep assertions scoped
  by subject as proposed.
- **Decision required:** No.
- **Status:** open.

##### RN-09: Test requirement-citation work is omitted
- **Severity:** Minor
- **Location:** `plan.md:225-280`; `tests/AGENTS.md`; `docs/requirements.md`.
- **Problem:** T2 and especially T3 materially extend requirement-backed readiness/tool specs,
  but the plan does not assign updates to their `Requirement:` citations. The affected behavior
  is described as FR-008/NFR-003, while current `pi-team-tool-spec.sh` and
  `pi-team-config-spec.sh` only cite FR-002/OPR-001.
- **Why it matters:** This misses the repo's required traceability format and leaves the durable
  Team-execution requirements without a test backlink.
- **Fix:** In T2/T3 Red steps, add the relevant `Requirement: FR-008` and/or
  `Requirement: NFR-003` citations next to the new assertions (retaining FR-002/OPR-001 where
  they remain true), and state the expected citation checks.
- **Decision required:** No.
- **Status:** open.

### Summary

| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-01 | Blocker | T6 review pipeline | Yes | open |
| RN-02 | Blocker | T3/T6 evidence pipeline | Yes | open |
| RN-03 | Blocker | T3 `review-task` scope | Yes | open |
| RN-04 | Critical | T3 CLI contract | Yes | open |
| RN-05 | Major | ADR coverage / T1/T3 | Yes | open |
| RN-06 | Major | T4/T6/T7 verification | No | open |
| RN-07 | Major | Dogfood metrics | No | open |
| RN-08 | Minor | Task graph ownership | No | open |
| RN-09 | Minor | T2/T3 spec citations | No | open |

### Changes Applied to Plan

- None. The user restricted changes to `plan_review.md`; the significant issues require design
  decisions and are not safe review-only edits.

### Review Status

- Significant issues found: 7 (3 Blocker, 1 Critical, 3 Major)
- **Readiness verdict:** **Must be revised first; not ready for sequential execution.**
- Status: **NEEDS_ANOTHER_PASS**

---

## Review 2026-08-06 (Review 2)

**Plan:** `plans/2026_08_06_continuous_crew_execution/plan.md`
**Scope:** delta — revised response to RN-01..RN-09, plus source re-verification
**Handoff readiness:** No

### Source re-verification

- `crew/store.ts:getReadyTasks` still releases a task solely when all Crew dependency IDs are
  `status === "done"`; it has no external-review state. `getTransitiveDependents` exists and
  makes the proposed graph calculation mechanically possible only after the plan-ID→Crew-ID
  mapping is applied.
- `crew/handlers/work.ts` assigns available lobby workers, marks them `in_progress`, and does
  **not** await those assignments. Its `succeeded` list contains only `spawnAgents` results.
  A lobby completion can therefore be invisible to the proposed “newly-done task” review loop;
  if all work is lobby-assigned, the handler can see no ready task and stop autonomous mode while
  lobby work remains in progress. If another spawned task causes a later boundary, a completed
  lobby predecessor can make its dependent ready without ever entering `pendingReviewSet`.
- `crew/types.ts` limits `TaskEvidence` to `commits`, `tests`, and `prs`. `completeTask` persists
  that shape, while `appendTaskProgress` persists only an unstructured timestamped string. Thus
  the current substrate offers no structured command/exit/output evidence field. A worker could
  encode a record into `task.progress`, but the revision does not define that encoding, attempt
  binding, or reader/validator.
- `tools/pi-team.mjs` confirms the referenced implementation constraints: `reviewWave` currently
  has no check/provenance options, `changedPaths()` returns only paths plus an untracked set (and
  special-cases R/C records), `validateWritePath()` is its symlink check, and `parseOptions()`
  cannot express optional paired evidence arguments. These source facts expose gaps in the new
  mini-spec rather than being implementation details.
- ADR 0004 Consequences now all have an owner: T2 config; T7 lead loop; T6 planning contract;
  T5 reviewer; T4 tools including `review-wave` evidence; T8 docs/render; and T9 calibration
  follow-up. Its upstream work remains explicitly deferred as TASK-0005/TASK-0006.

### Resolution checklist

| Prior ID | Result | Review 2 assessment |
|---|---|---|
| RN-01 | **PARTIALLY RESOLVED** | D-A/T7 correctly identifies that plain `done` is insufficient and the transitive-dependent test is the right normal-batch predicate. It is not yet safe: it has no persisted review state, lobby completions need not become pending reviews, and it specifies neither how blocking async reviews are collected before the lead turn ends nor how autonomous mode is stopped/resumed without the three-repeat guard. |
| RN-02 | **PARTIALLY RESOLVED** | T3 acknowledges a producer and labels a lead fallback, which is material progress. But “task progress/evidence” is not a durable protocol: only unstructured progress is available and TaskEvidence cannot carry the promised fields. No schema, delimiter, maximum, task/Crew/attempt/base binding, malformed-record behavior, or lead reader is specified. A rerun is also not guarded against a check that mutates the dirty tree. |
| RN-03 | **PARTIALLY RESOLVED** | Separating bundle task from allowed dirty scope correctly allows a sibling without leaking sibling diff bytes. However, the caller may name any known IDs; nothing constrains the set to the dispatched/current run. That lets an accidental or malicious lead authorize a future task’s write set and defeats the prior `review-wave` scope protection. |
| RN-04 | **PARTIALLY RESOLVED** | The versioned warnings, basic exits, and deny/allow intent are much stronger. The grammar still lacks deterministic tokenization and args-after-path rules, option-pair/provenance consistency, complete absent/unreadable-output semantics, and rename/copy `pathStatus` behavior. It also does not say whether `warnings: []` is present on validation/I-O JSON outputs or how provenance reaches either command. |
| RN-05 | **RESOLVED** | T1 explicitly says ADR 0005 satisfies rather than amends this consequence; T4 owns a shared builder for both commands and tests `review-wave` evidence fields. “Scope semantics unchanged” now means the existing scope rule, not evidence content, and is not contradictory. |
| RN-06 | **PARTIALLY RESOLVED** | T4 now has genuine behavioral fixture cases and T5/T8 have concrete Red and break-it steps. T7’s “every invocation parses” lint is still an aspiration, not a buildable contract: it gives no extraction boundary, accepted literal/variable command forms, invocation inventory, or expected assertions. The admitted runtime limit is honest but leaves the safety-critical hold protocol unproven before the production run. |
| RN-07 | **RESOLVED** | Recomputed graph: depth 0 `{T1,T2,T3,T5,T6}` chunks to widths 4 and 1; T4, T7, T8, T9 add four width-1 waves. Widths are `4,1,1,1,1,1`; mean `9/6=1.5`; max 4; width-1 `5/6=83%`; serial 200; longest path `T1→T4→T7→T8→T9 = 135`; ratio `135/200=0.675`, correctly rounded 0.68. The schema-1 boundary statement is now accurate. |
| RN-08 | **RESOLVED** | The shared config/skill spec files are named, their writers are enumerated, and sequential ordering is correctly used as the serialization mechanism. |
| RN-09 | **RESOLVED** | T2 assigns NFR-003, and T4 assigns FR-008/NFR-003 while retaining the old citations. This meets the stated traceability correction; the tests should use separate `Requirement:` lines if the shell-spec style requires it. |

### Issues

#### Blocker

##### RN-01: Logic bug: dependency hold is better, but not safe against source behavior
- **Status:** PARTIALLY RESOLVED
- **Location:** approach D-A; plan T7; upstream `crew/handlers/work.ts`, `crew/store.ts`, and
  `index.ts`.
- **Problem:** The proposed disjointness check protects only a task already present in
  `pendingReviewSet`. Crew itself will release a dependency at `task.done`. Lobby tasks are not
  included in `work.ts`’s `succeeded` array, despite being placed `in_progress` and later able to
  call `task.done`; the lead therefore has no specified reliable way to launch/bind their review
  before a later boundary sees their dependent as ready. Conversely, a no-spawn lobby wave can
  reach the handler’s `nextReady.length === 0` branch and stop autonomous mode before it has
  completed. For ordinary spawned tasks, the plan does not define whether the lead awaits the
  blocking reviewers in the same turn, stops autonomous work and registers a completion wake-up,
  or reuses the `crew_continue` steer. The latter repeats the same ready signature and hits
  `AUTONOMOUS_CONTINUE_REPEAT_LIMIT` after three turns.
- **Correction:** T7 must define a persisted per-plan-task review state keyed to Crew ID and
  attempt (`done-unbundled`, `review-pending`, `effective-SHIP`, retry/block) and derive
  “newly done” by diffing the store against that state, not only `succeeded`. At every possible
  continuation, cover direct and lobby assignments. Specify exactly how a hold waits/resumes
  (including an explicit `work.stop`/later resume or same-turn await) so the repeat guard cannot
  silently stop the run. Add a source-compatible protocol fixture/lint for direct and lobby
  completion plus T1→T2 delayed `NEEDS_WORK` and `SHIP` release. The rule is **BETTER, not SAFE**
  until then.
- **Decision required:** Yes.

##### RN-02: Durable worker evidence still has no executable data contract
- **Status:** PARTIALLY RESOLVED
- **Location:** plan T3/T4/T7; approach D-D; `config/pi-team/crew-worker.md`; upstream
  `crew/types.ts`, `crew/store.ts`, `crew/handlers/task.ts`.
- **Problem:** The planned producer is described as “task progress/evidence,” but those are not
  interchangeable. Current `task.done` accepts only `tests`/`commits`/`prs`; it cannot persist an
  exit code or tail. `task.progress` can persist arbitrary text but has no structure, attempt
  identity, atomic record, byte bound, or query API beyond reading a text log. The plan does not
  choose a record syntax or say how a lead rejects stale/malformed/duplicate records. It also
  never makes the lobby case executable beyond asserting prompt text: a lobby worker has the same
  tool surface, but its completion is not represented in `work.ts`’s results. Finally, “rerun the
  named check” is unsafe while a dirty concurrent wave exists unless the plan requires a
  read-only check or snapshots/verifies the worktree/index before and after it.
- **Correction:** Choose one source (for example one versioned JSON line written through
  `task.progress`) and specify exact fields: schema version, plan ID, Crew ID, attempt, base,
  command, integer exit, UTF-8 lossy bounded tail, producer timestamp, and explicit failure
  record. T7 must read and validate the newest matching record before the bundle snapshot, for
  both direct and lobby tasks. Either make lead reruns run in an isolated copy or require and
  verify no index/worktree delta outside the already-allowed scope; a mutating rerun is a policy
  refusal. Add an integration-style fixture for direct/lobby/progress record selection and stale,
  malformed, absent, and mutation outcomes.
- **Decision required:** Yes.

##### RN-03: `--allowed-scope` does not preserve authorization detection as written
- **Status:** PARTIALLY RESOLVED
- **Location:** approach D-H; CLI mini-spec `review-task`; plan T4/T7.
- **Problem:** `review-wave` validates `--scope` through `scopeIsValid()` against a computed
  chunk plus complete integration groups. The new mini-spec merely checks that a unique ID set
  contains `--task`. A caller can include any future task with a convenient write set, causing an
  undeclared dirty path to be accepted as “allowed.” The plan’s phrase “in-flight/completed run
  task IDs” is not an input invariant or a tool-checkable source of truth.
- **Correction:** Carry a lead-created immutable dispatch/run manifest (with plan/base/task IDs)
  and have `review-task` validate `--allowed-scope` against it, or retain a precisely adapted
  `scopeIsValid` rule. Define retry/remediation additions separately. Test rejection of a path
  owned by a valid-but-not-dispatched future task, not merely a wholly unknown path.
- **Decision required:** Yes.

#### Critical

##### RN-04: Mini-spec remains insufficiently deterministic at the CLI boundary
- **Status:** PARTIALLY RESOLVED
- **Location:** plan CLI Contract Mini-Spec; T4.
- **Problem:** A reasonable implementer must still decide: how the admissible command is tokenized
  (spaces, quotes, escaped spaces, and arguments after the path); whether options such as
  `--check-cmd`, `--check-exit`, and `--check-output` are all-or-none and their valid ranges;
  whether absent means an omitted option or a non-existent supplied filename; and whether every
  error JSON emits `warnings: []`. “Same resolution and symlink rules as `validateWritePath`”
  does not identify the invocation root or define realpath handling of an existing final symlink.
  `changedPaths()` currently expands porcelain R/C entries into two paths but discards their
  XY code, so literal `pathStatus` for renamed/copied source/destination paths and deterministic
  ordering are not specified. The byte-tail rule says lossy UTF-8 but does not establish whether
  truncation happens before decoding or the expected replacement behavior; its relation to
  `MAX_EVIDENCE_BYTES`/failure ordering is also open.
- **Correction:** Add a token grammar (not shell parsing) with a quoted-token policy and exact
  allowed trailing argv; specify required option combinations, integer range, omitted vs missing
  pathname semantics, output shape for all exits, root/realpath/symlink policy, R/C entries and
  ordering, and byte-slice-then-decode behavior. Specify a deterministic order when output read,
  evidence-size, scope, and HEAD failures coexist. Add a fixture for every choice.
- **Decision required:** Yes.

##### RN-10: New logic bug: specified commands cannot carry evidence provenance
- **Status:** OPEN (new)
- **Location:** plan shared manifest mini-spec; T4/T7.
- **Problem:** The manifest promises `checkAttestation: "worker" | "lead" | "absent"`, while
  `review-task` exposes only command/exit/output options and `review-wave` has no new option
  signature at all. T7 says to “pass `checkAttestation: "lead"` inputs,” but no such input exists.
  The tool cannot distinguish a worker-sourced command from an identical lead-supplied command,
  so any implementation must invent provenance. This contradicts the plan’s central claim that
  the reviewer sees authoritative rather than invented evidence.
- **Correction:** Define a validated evidence-source interface for **both** commands: e.g. a
  `--worker-evidence FILE` / `--lead-evidence FILE` record with the T3 schema, or an explicit
  `--check-attestation` constrained to a matching validated record. State what `absent` permits
  and add fixture cases proving all three values and invalid combinations. Update the exact T7
  command block and template lint accordingly.
- **Decision required:** Yes.

#### Major

##### RN-06: The new command-template lint and runtime acceptance remain non-executable
- **Status:** PARTIALLY RESOLVED
- **Location:** plan T7 and coverage matrix.
- **Problem:** T7 asks a Bash spec to ensure every `pi-team` invocation “parses against the CLI
  mini-spec,” but it does not delimit executable blocks, list expected invocations, define how
  shell variables/placeholders are normalized, or supply a parser/helper. A grep can prove a
  flag appears but cannot prove command shape; a shell parser would make policy decisions the
  mini-spec leaves open. The plan then explicitly excludes the most safety-critical behavior
  (holding T1→T2 through a delayed review) from pre-execution evidence and accepts a production
  run as its first proof.
- **Correction:** Make the lint concrete: mark command blocks, provide a fixture file or a
  small deterministic validator with exact accepted canonical templates, and mutation-test each
  required flag. Add a non-production simulated-store protocol test if the skill cannot be made
  executable; otherwise treat the first live run as a controlled calibration/promotion barrier,
  not as proof that this plan is safe to execute normally.
- **Decision required:** No.

### Resolved findings and new-defect sweep

- **RN-05:** Resolved as stated above. The revised change summary, compatibility section, T1,
  T4, and matrix agree that `review-wave` remains with unchanged command/scope semantics but
  gains additive evidence fields.
- **RN-07:** Resolved; all requested arithmetic is reproducible from the new ledger, with no
  task-graph cycle or stale T1–T9 dependency reference found.
- **RN-08/RN-09:** Resolved. Ownership and requirement-citation statements are now honest and
  assigned.
- **New revision defects:** RN-10 is new. RN-01 through RN-04 also retain material execution
  holes despite stronger prose; no stale old task IDs were found in the revised task graph,
  dependency list, or ADR-consequence ownership mapping.

### Implementer decisions remaining

The following decisions still change a CLI or production execution contract and therefore cannot
be delegated to an implementer:

1. The persisted review-state/continuation protocol, especially for lobby completions and the
   autonomous repeat guard (RN-01).
2. The exact task-keyed evidence record, validation, and safe lead-rerun policy (RN-02).
3. The authoritative source used to constrain `--allowed-scope` (RN-03).
4. The remaining command grammar, option/output, root/symlink, and porcelain status semantics
   (RN-04).
5. The provenance channel that makes `checkAttestation` truthful (RN-10).

### Review status

- Issues found this pass: **3 Blocker, 2 Critical, 1 Major** (plus the previously resolved minor/
  major findings recorded above).
- Issues fixed this pass: **0** (review-only assignment; the needed changes are contract/design
  decisions, not safe editorial corrections).
- Remaining significant issues: **6**.
- **Readiness verdict:** **Not ready for sequential execution.** The revision is materially
  better, but the central dependent-release and evidence-authority mechanisms are not executable
  against the actual Crew substrate. Resolve RN-01 through RN-04 and RN-10, then obtain another
  review pass.
- **Status: NEEDS_ANOTHER_PASS**

---

## Review 2026-08-06 (Review 3)

**Plan:** `plans/2026_08_06_continuous_crew_execution/plan.md`
**Scope:** delta — Revision 3 Durable State Policy, CLI contract, T3/T4/T7, and prior RN-01/02/03/04/06/10
**Handoff readiness:** No

### Source re-verification

- **Progress transport itself works.** `task.progress` exposes `message: Type.String()` with no
  length limit, sanitization, or newline conversion in the handler. It calls
  `appendTaskProgress(cwd, id, state.agentName || "unknown", message)`, which appends exactly
  `[ISO] (agent) ${message}\n`. A single-line base64 JSON record therefore survives that write
  format and can be parsed by taking the text after the `) ` prefix. The proposed 4,096-byte tail
  expands to 5,464 base64 characters (plus JSON/prefix); it is not truncated by this path.
- **The claimed author classification does not work.** Direct spawned workers get a randomly
  generated `PI_AGENT_NAME`; lobby workers get another randomly generated memorable name. Neither
  is literally `crew-worker`. `completeTask()` clears `assigned_to`, while `task.progress` checks
  neither task assignment nor task status, so any registered agent can append a record to any
  task. `pi-team` receives only `--crew-dir`; it has neither the live lead name nor a durable
  worker-role/assignment binding with which to classify the prefix author.
- **Progress persists across retries, but the stated selector is not sufficient.**
  `resetTask()` retains the `.progress.md` file and `attempt_count`, clears `base_commit`, and a
  subsequent `startTask()` sets `base_commit` to the then-current HEAD. This handles a retry only
  if the tool can first identify the Crew task and the global bundle base has not moved. It also
  leaves old high-attempt/malformed records unbounded; the plan does not define full field/base64
  validation or whether selection is highest attempt then newest versus newest then attempt.
- **The tool cannot find the record it names.** Crew task JSON has `task-N` IDs and no plan ID.
  `handlers/plan.ts` creates task IDs sequentially and stores only title/description/dependencies.
  The asserted plan-ID→Crew-ID map exists only in lead instructions; the Durable State Policy
  gives it no durable location, and neither bundle command accepts it. Thus T4 cannot turn
  `review-task ... --task T3 --crew-dir ...` into `tasks/task-N.progress.md`, nor derive the
  status-authorized plan IDs from `tasks/*.json`, including the absent-record case.
- **Lobby recovery remains without a wake source.** `work.ts` places lobby assignments outside
  `remainingTasks`, awaits no lobby completion, and stops autonomous mode when `nextReady` is
  empty. A lobby worker's `task.done` does not cause the lead-side `agent_end` continuation
  (`index.ts` returns early for `PI_LOBBY_ID`). T7 says to “wait” for terminal state but supplies
  no event/wake mechanism; timer polling is prohibited by NFR-003. Independently, `index.ts`
  computes continuation readiness only from Crew `done` state, not `PI-TEAM-REVIEW/1`, and its
  three-repeat guard still runs whenever a lead turn ends with the same ready signature.
- **Board scope is not closed under Crew's real state transitions.** `task.reset()` changes a
  done task to `todo` without cleaning its changes; cascade reset does the same to dependents.
  `blockTask()` also leaves dirty files. `in_progress|done` admits active/completed siblings, but
  rejects these genuinely dispatched reset/blocked paths and therefore makes subsequent bundles
  reject the whole dirty tree. The plan tests only a never-dispatched future task, not these
  source-supported transitions.
- **The CLI contract contains executable contradictions.** The mini-spec says the risk path uses
  the same `validateWritePath` walk, which rejects a `./` segment, while T4 requires `./<spec>`
  to be accepted. It says both bundle commands take `--crew-dir` but also promises unchanged
  `review-wave` command surface; a newly required option is a breaking surface change. The
  current tool confirms that this work is additive implementation, not an existing compatibility
  behavior.
- **The command-template lint is not yet a valid parser contract.** Its required-flag table says
  `check` has no flags and unknown flags fail, but its required canonical invocation is
  `pi-team check "$PLAN" --json`. Set comparison also cannot catch a missing option value or a
  value accidentally consumed as another option. It needs allowed flags, option arity, positional
  grammar, and logical-line/continuation handling.

### Resolution checklist

| Prior ID | Result | Review 3 assessment |
|---|---|---|
| RN-01 | **PARTIALLY RESOLVED** | Board scanning sees lobby completions and in-turn collection is the right direction. It is still **better, not safe**: neither a lobby completion wake nor an interlock in `index.ts` prevents Crew-ready dependents/repeat-guard behavior while a verdict is pending. |
| RN-02 | **PARTIALLY RESOLVED** | A single-line record is genuinely writable, durable through reset, and base64-safe. It is not yet an authoritative evidence contract because task mapping, producer authorization, complete validation/selection, safe lead reruns, and base reconciliation are unspecified. |
| RN-03 | **PARTIALLY RESOLVED** | Replacing caller-provided scope closes the future-task authorization hole for current active/completed tasks. It creates holes for reset/cascade-reset/blocked dirty work, all of which the source preserves. |
| RN-04 | **PARTIALLY RESOLVED** | Tokenization, ordering, status intent, and warning shape are materially more deterministic. `./path` versus `validateWritePath` and required `--crew-dir` versus unchanged `review-wave` compatibility still require decisions. |
| RN-06 | **PARTIALLY RESOLVED** | The extraction boundary and variable normalization make the lint buildable in principle, but the stated table rejects `check --json` and flag-set checking cannot establish real CLI parsing. Runtime dependency-hold safety remains production-only evidence. |
| RN-10 | **NOT RESOLVED** | Removing caller evidence flags prevents one forgery route, but the only remaining author prefix is neither access-controlled nor role-classifiable. It cannot truthfully produce `worker` versus `lead`. |

### Implementer Decisions Remaining

The following remain contract-changing decisions and cannot be delegated to an implementer:

1. A source-compatible wait/wake and dispatch interlock for pending review, including lobby-only
   completion and the autonomous repeat guard (RN-01).
2. An authenticated plan-ID→Crew-ID/producer binding and safe isolated rerun protocol for check
   evidence (RN-02, RN-10, and new RN-11).
3. The authorized-scope semantics for dispatched work after reset, cascade reset, and block
   (RN-03).
4. The final `./path` grammar and whether `review-wave --crew-dir` is optional/additive or a
   breaking versioned interface (RN-04).
5. Whether an integration commit may occur while unrelated tasks remain active; if yes, the
   record must distinguish task-start base from global bundle base (new RN-12).

### Test Adequacy Assessment

- Coverage matrix complete: **No.** It lacks a plan-ID→Crew-file mapping case, unauthorized
  `task.progress` writer case, direct/lobby author-name fixtures, reset/cascade/blocked-scope
  cases, an active-unrelated-task followed by gate commit/base-change case, and retry-prompt
  budget coverage.
- Negative/edge cases identified for each row: **No.** The current selection test does not cover
  an invalid base64/value schema, same-attempt duplicate ordering, or a base reset after a
  concurrent gate commit.
- Bad-test avoidance addressed in approach.md: **Partly.** T4 fixtures can prove tool behavior,
  but T3/T7 text checks cannot prove the Messenger's absent authorization/wake capabilities.
- E2E seed/fixture data confirmed to support scenarios: **No.** The proposed tool fixtures do not
  materialize real `tasks/task-N.json` and `.progress.md` state with the plan-to-Crew mapping,
  lifecycle transitions, and gate/base movement required by the contract.
- TDD checklists include break-it step for all tasks: **Yes, but insufficient.** The listed
  mutations do not falsify the new source-backed lifecycle/mapping/base cases.

### Issues

#### Blocker

##### RN-01: Logic bug: review hold still has no source-compatible wake or scheduler interlock
- **Severity:** Blocker
- **Location:** `approach.md` D-A; `plan.md` T7; `crew/handlers/work.ts`; `index.ts`.
- **Problem:** The T7 procedure observes board state, but neither `work.ts` nor `index.ts` reads
  `PI-TEAM-REVIEW/1`. Lobby completion has no lead wake; a “stopped-but-incomplete” lead cannot
  event-wait for it. For direct completion, `index.ts` may send another `crew_continue` whenever
  Crew sees a dependent ready, even while external review is pending. Awaiting a reviewer in a
  lead turn does not disable that handler or the repeated-signature counter.
- **Why it matters:** A dependent can still be offered for dispatch before effective `SHIP`, or a
  held/lobby-only run can silently stop. The proposed same-turn assertion is not a guarantee
  supplied by the substrate.
- **Correction:** Specify a real completion wake and a stop/resume/interlock that is valid against
  the installed source (or change the upstream non-goal). Demonstrate direct and lobby `T1 → T2`
  delayed `NEEDS_WORK` and `SHIP` cases without timer polling or a repeat-guard stop.
- **Decision required:** Yes.
- **Status:** PARTIALLY RESOLVED.

##### RN-11: Logic bug: bundle commands have no durable plan-ID-to-Crew-file binding
- **Severity:** Blocker
- **Location:** `plan.md` Durable State Policy, CLI mini-spec, T4/T7; `crew/handlers/plan.ts`.
- **Problem:** `--task T3` is a compiler plan ID, while `--crew-dir` exposes only `task-N` files.
  The plan calls the mapping “already exists today” but supplies no persisted/readable mapping and
  no tool argument. A title convention is not stated or validated; a missing record cannot be
  used to discover the association. Consequently the status union and evidence reader have no
  input mapping from a Crew file to a plan write set.
- **Why it matters:** `review-task` and evidence-enriched `review-wave` cannot be implemented from
  their specified inputs, including the required `absent` evidence outcome.
- **Correction:** Define one durable, tool-readable and validated binding (or an upstream task
  field) and fixtures for reordered materialization, missing/mismatched binding, and absent
  evidence. If it is a map, state its lifecycle, source of truth, and recovery behavior rather
  than calling it an unchanged ephemeral lead fact.
- **Decision required:** Yes.
- **Status:** OPEN (new).

##### RN-12: Logic bug: per-record base matching conflicts with gate-only commits during continuous work
- **Severity:** Blocker
- **Location:** `approach.md` D-C/D-D; `plan.md` Durable State Policy, Decisions, T7.
- **Problem:** `startTask()` captures a task-local `base_commit`; reset/retry can capture another
  one. T7 permits a gate commit at group completion while unrelated tasks continue. That advances
  global HEAD, so `review-task` must use the new global `--base` to satisfy `HEAD == BASE`, but
  the still-running worker's record carries its older task-start base and is discarded by the
  stated match rule.
- **Why it matters:** Normal continuous execution loses worker evidence precisely at gate overlap,
  falls into the unsafe rerun path, and cannot meet the claimed selection contract.
- **Correction:** Either prohibit a gate commit while any task is active, or define distinct
  task-start and bundle-base identities with an immutable snapshot/diff binding. Add a fixture
  with an unrelated in-progress task, a completed integration group/commit, and subsequent
  evidence selection.
- **Decision required:** Yes.
- **Status:** OPEN (new).

#### Critical

##### RN-10: Logic bug: author-derived attestation is not truthful or non-forgeable
- **Severity:** Critical
- **Location:** `plan.md` Durable State Policy and shared manifest fields; `crew/handlers/task.ts`,
  `crew/store.ts`, `crew/agents.ts`, `crew/lobby.ts`.
- **Problem:** The plan classifies author `crew-worker`/lobby as `worker`, but direct/lobby agents
  write random names. More importantly, `task.progress` merely verifies task existence and uses
  the caller's registered `state.agentName`; it does not require the author to equal
  `assigned_to`, to be a worker role, or to be the lead. `assigned_to` is cleared on done. Thus a
  different registered agent can append a syntactically valid record, and the external tool
  cannot derive role from the stored prefix.
- **Why it matters:** `checkAttestation` would advertise authority that the source does not supply,
  recreating RN-10 under a different transport rather than resolving it.
- **Correction:** Add a durable authenticated role/assignment binding readable by the tool (or
  label all progress evidence untrusted/unknown until upstream support exists). Do not use a
  self-reported JSON field or an unauthenticated author-name convention.
- **Decision required:** Yes.
- **Status:** NOT RESOLVED.

##### RN-04: CLI contract still has compatibility and path-grammar contradictions
- **Severity:** Critical
- **Location:** `plan.md` CLI Contract Mini-Spec and T4/T7.
- **Problem:** T4 requires `./<spec>` be accepted, while the referenced `validateWritePath` rejects
  any `.` path segment. Both bundle commands are said to take `--crew-dir`, yet Change Summary,
  Non-goals, and Compatibility say the `review-wave` command surface is unchanged. The command
  lint also treats all non-table flags as unknown while its own canonical `check` invocation has
  `--json`.
- **Why it matters:** Implementers cannot make both sides true. A required `--crew-dir` breaks
  existing callers; accepting `./` only in one code path creates a security/grammar divergence.
- **Correction:** Choose and state one normalized path grammar, then align the fixture list and
  `validateWritePath` use. Declare `--crew-dir` optional with defined absent-evidence behavior,
  or version/break `review-wave` explicitly. Give the lint an allowed-flag plus arity/positional
  table, including `check --json`.
- **Decision required:** Yes.
- **Status:** PARTIALLY RESOLVED.

#### Major

##### RN-02: Evidence record protocol works at the byte transport layer but not as an authoritative lifecycle contract
- **Severity:** Major
- **Location:** `plan.md` Durable State Policy, T3/T4/T7; `crew/store.ts`; `crew/prompt.ts`.
- **Problem:** The 4 KiB base64 line is writable and reset retains it, but the record validity
  rules are incomplete (field types, canonical base64, decoded bound, duplicate tie-break). The
  selector cannot be applied without RN-11 and fails across RN-12. “Rerun must be read-only; if
  it would mutate, refuse” is not operational: mutation is only knowable after executing the
  check against the shared dirty tree. The plan neither isolates the rerun nor specifies a
  pre/post state protocol that can safely recover a mutation.
- **Why it matters:** The worker record can be stale, malformed, misbound, or replaced by an
  unsafe lead rerun, while the bundle still presents it as authoritative.
- **Correction:** Fully validate/decode records; specify attempt ordering and task/base/snapshot
  binding; run fallback checks in an isolated copy/snapshot (or declare no fallback). Add direct,
  lobby, stale retry, malformed-value, duplicate, and mutating-check fixtures.
- **Decision required:** Yes.
- **Status:** PARTIALLY RESOLVED.

##### RN-03: Board-derived scope excludes legitimate dirty reset and blocked work
- **Severity:** Major
- **Location:** `approach.md` D-H; `plan.md` `review-task` mini-spec/T4/T7; `crew/store.ts`.
- **Problem:** `in_progress|done` is not the set of dispatched work. `resetTask()` preserves its
  dirty files while changing status to `todo`; cascade reset does likewise for dependents; and
  `blockTask()` leaves worktree changes under `blocked`. Any one of those paths causes all later
  `review-task` calls to reject `REVIEW_OUT_OF_SCOPE`, including a retry/rescue flow the plan
  explicitly retains.
- **Why it matters:** This is both a false refusal of authorized work and a recovery dead end.
  The current future-task test misses every real transition that creates it.
- **Correction:** Define authorized transitions using Crew-verifiable prior dispatch identity (for
  example explicitly include `blocked` and retryable `todo` only when `attempt_count > 0`), or
  require cleanup before narrowing the authorized union. Cover reset, cascade reset, block, and
  never-dispatched future paths.
- **Decision required:** Yes.
- **Status:** PARTIALLY RESOLVED.

##### RN-06: Template lint still cannot accept and validate the specified CLI forms
- **Severity:** Major
- **Location:** `plan.md` T7; `tests/specs/skill-content-spec.sh`.
- **Problem:** The concrete extraction rule is a valuable improvement, but a “required-flag” set
  cannot establish the parser contract. As written, `check: none` plus “unknown flags fail”
  rejects the plan's mandatory `check --json`. It also accepts `--crew-dir --repo-root ROOT` as a
  complete flag set even though the first option has no value, and does not state treatment of
  multi-line shell continuations or `${VAR}`.
- **Why it matters:** The lint either false-fails the canonical skill or false-greens malformed
  commands. It cannot be the claimed guard against lead/tool drift.
- **Correction:** Define a small tokenizer for complete logical command lines, normalize all
  documented variable forms, and compare subcommand positional count plus each allowed flag's
  required value and cardinality. Include `--json` in `check`'s allowed optional flags and
  mutation cases for a missing value, unknown flag, and continuation.
- **Decision required:** No.
- **Status:** PARTIALLY RESOLVED.

##### RN-13: Logic bug: durable 4 KiB evidence tails crowd retry prompts without a budget
- **Severity:** Major
- **Location:** `plan.md` Durable State Policy; `crew/prompt.ts`; T3/T4 coverage matrix.
- **Problem:** `prompt.ts` blindly injects the last 30 progress *lines*. A max 4,096-byte tail
  becomes at least 5,464 base64 characters in one line. Five retry attempts can contribute about
  27 KiB of opaque base64 (roughly 7k tokens) before normal progress, review, task, and plan
  context; lead reruns are not bounded to one per attempt. There is no character/byte cap in the
  prompt reinjection path.
- **Why it matters:** A retry prompt can spend material context on evidence that the worker cannot
  use, degrading the remediation context the protocol depends on.
- **Correction:** Reduce the stored/reinjected tail to a justified bound, or update the protocol
  so retry prompt construction omits/abbreviates versioned evidence records while the bundle tool
  still reads them. Add a deterministic prompt-size/record-count fixture.
- **Decision required:** No.
- **Status:** OPEN (new).

### New-defect sweep

- No active occurrence of removed `--allowed-scope`, `--check-cmd`, `--check-exit`, or
  `--check-output` remains outside the historical Review 1/2 and Progress Log narrative. The
  ledger references are historical decision/progress context, not an implementation instruction.
- The task graph still has valid IDs and ordering; T4 remains correctly dependent on T1/T3, T7 on
  T1/T4/T5, T8 on T6/T7, and T9 on T2/T8. The new defects are contract/source gaps, not graph
  cycles.
- ADR 0004 consequences remain nominally owned by T2–T9, including shared `review-wave` evidence
  in T4. RN-04 means that ownership does not yet satisfy a stable backwards-compatible command
  contract; no ADR consequence was silently dropped.

### Summary

| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-01 | Blocker | D-A/T7 autonomous and lobby hold | Yes | PARTIALLY RESOLVED |
| RN-02 | Major | Durable check evidence lifecycle | Yes | PARTIALLY RESOLVED |
| RN-03 | Major | D-H/T4 board scope transitions | Yes | PARTIALLY RESOLVED |
| RN-04 | Critical | CLI mini-spec/T4/T7 | Yes | PARTIALLY RESOLVED |
| RN-06 | Major | T7 template lint | No | PARTIALLY RESOLVED |
| RN-10 | Critical | progress-author attestation | Yes | NOT RESOLVED |
| RN-11 | Blocker | plan-ID↔Crew-file mapping | Yes | OPEN (new) |
| RN-12 | Blocker | task/base versus gate/base | Yes | OPEN (new) |
| RN-13 | Major | retry prompt evidence budget | No | OPEN (new) |

### Changes Applied to Plan

- None. The assignment permits editing only `plan_review.md`; all significant findings require
  contract decisions or a source-compatible design revision.

### Review Status

- Issues found this pass: **3 Blocker, 2 Critical, 4 Major**.
- Issues fixed this pass: **0** (review-only assignment).
- Remaining significant issues: **9**.
- **Readiness verdict:** **Not ready for sequential execution.** Revision 3 successfully removes
  the duplicated-ledger direction and proves that a compact record can travel through
  `task.progress`, but it does not make the record authenticated or addressable, does not make
  pending review control the actual scheduler, and conflicts with gate commits and retry-context
  limits. Resolve RN-01, RN-02, RN-03, RN-04, RN-06, RN-10, RN-11, RN-12, and RN-13 before
  execution; then obtain another review pass.
- **Status: NEEDS_ANOTHER_PASS**


---

## Review 2026-08-06 (Review 4)

**Plan:** `plans/2026_08_06_continuous_crew_execution/plan.md`
**Scope:** delta — Revision 4 removal of `review-task`, progress records, and ledger; new
boundary snapshot/evidence loop and `execution-model.md`
**Handoff readiness:** No

### Source re-verification

- **The tree is not quiet at the proposed boundary.** `work.ts` marks each available lobby
  assignment `in_progress`, sends it through `assignTaskToLobbyWorker()`, excludes it from
  `remainingTasks`, and then awaits only `spawnAgents(workerTasks)`. Thus an all-lobby call
  returns immediately with workers actively editing; a mixed call returns when direct workers
  finish while lobby workers may still edit. It then computes `nextReady` from the board. With
  only lobby work it is empty (the assignments are `in_progress`), so `work.ts` stops autonomous
  mode as `blocked` even though those workers run. This directly falsifies D-A/D-H and
  `execution-model.md` §3's “tree contains exactly the completed wave” claim.
- There is no source-compatible event wait for that condition. A lobby worker's `task.done`
  updates its task file, but `task.ts` emits no lead wake. `index.ts` returns immediately for
  `PI_LOBBY_ID`, so its `agent_end` handler does not produce `crew_continue` for a lobby worker.
  Reading task JSON until it becomes terminal is polling, prohibited by NFR-003, and the existing
  lead turn has no completion promise to await. The proposed “stopped-but-incomplete, wait” is
  therefore not executable as written. The three-repeat guard does not repair it: it tracks
  repeated ready signatures whenever the lead ends a turn and stops after three.
- Consequently, the revision's load-bearing snapshot can race live edits. `review-wave` may see
  an out-of-scope path and refuse it, or capture a partial diff that looks in-scope but is torn;
  the lead's risk-check rerun can run concurrently with that worker. This **invalidates the
  design**, not merely its telemetry claim. The minimum correct fix is a source-level
  all-assignment barrier: retain/observe both direct and lobby assignments, wait for every member
  of the dispatched cohort to reach a terminal board state, and emit an event-driven wake to the
  lead before boundary capture. It must also interlock continuation while a held dependent is
  pending review. Without changing the substrate, the only safe local fallback is to prohibit
  lobby assignment for this workflow and await the complete direct batch; a status-reading loop
  is not NFR-003-compliant and is not an event source.
- `review-wave` itself supports the narrower RN-03 claim only under that missing premise.
  `scopeIsValid()` accepts one computed chunk plus complete integration groups, and `reviewWave()`
  rejects every changed path outside the resulting write-set union. Passing the exact completed
  chunk as both `--scope` and `--bundle` would be accepted and makes each task diff path-scoped.
  It does not accept a concurrent lobby sibling, a reset/blocked dirty task, or an undeclared
  edit; those states make the boundary call reject rather than make the tree an immutable wave.
- Removing `review-task` means the bundle builder no longer reads Crew task/progress files, so
  the original durable plan-ID↔Crew-ID lookup defect (RN-11) is genuinely gone for evidence
  generation. The claim that no map is needed **anywhere** is too broad: the retained
  materialization contract still must translate the plan `Deps` column into `task-N` dependency
  IDs, and board-derived newly-done detection needs that in-session association to name the
  plan-task chunk. It is not a new durable map requirement, but T6 must not omit the existing
  in-session mapping it says materialization retains.
- The old progress-record facts are now moot: `--evidence` is an ephemeral lead file and the
  plan no longer base64-encodes output into `task.progress`. There is no per-task-record base
  selector. RN-12 and RN-13 are therefore resolved by removal, subject to the independent
  quiet-boundary failure above.

### Required-resolution checklist

| ID | Result | Review 4 assessment |
|---|---|---|
| RN-01 | **NOT RESOLVED** | Conditional holding uses a correct dependency predicate only after a genuine boundary. The installed source returns while lobby work is live, offers no terminal-state wake, and does not make external review state scheduler-visible. Awaiting “in turn” cannot await a lobby completion event that is never delivered, and a repeated steer can still hit the repeat guard. |
| RN-02 | **PARTIALLY RESOLVED** | Replacing forged `worker` attestation with `lead-verified`/`reported-unverified` is honest progress. But the current worker prompt records only a prose “passed” progress message and `TaskEvidence.tests: [command]`; `work` returns no per-worker output, direct artifacts are not a check-output handoff, and lobby workers have no artifact output. No task changes that producer. Thus the promised command/exit/4-KiB output for non-risk tasks cannot be captured. Risk reruns also remain unsafe until RN-01 establishes a quiet isolated boundary. |
| RN-03 | **PARTIALLY RESOLVED** | A completed-wave `review-wave` scope eliminates the old single-task/sibling ambiguity, but only if it really is the entire dirty cohort. Live lobby paths and retained reset/blocked dirty paths violate that premise and are rejected as out-of-scope. |
| RN-04 | **PARTIALLY RESOLVED** | The separate leading-`./` resolver, optional flag, literal porcelain intent, and base failure sequence repair the prior two explicit contradictions. The evidence JSON is still an example, not a closed schema: required/optional fields, task-key membership, unknown keys, command/output types, integer exit range, UTF-8/byte truncation ownership, duplicate semantics, file/symlink policy, and malformed-evidence ordering are left to implementation. `changedPaths()` currently discards XY; T3 correctly says to extend it, and mapping both R/C paths to the retained record code is deterministic once that extension exists. |
| RN-06 | **PARTIALLY RESOLVED** | The described fenced-Bash extraction, continuation joining, `$VAR`/`"$VAR"` normalization, allowed/required flag tables, and flag-has-value rule are buildable; the table now correctly allows `check --json` and makes `--evidence` optional for `review-wave`. It still accepts a line with no PLAN positional (or extra positionals/duplicate flags) because it checks flags only. It cannot truthfully prove an invocation parses against the CLI until the small positional grammar is added. |
| RN-10 | **RESOLVED** | The design no longer infers a producer role from unauthenticated `task.progress`. `reported-unverified` is not an authority claim, and risk evidence is named lead-verified. |
| RN-11 | **RESOLVED** | No tool mapping is needed to make the boundary bundle; retain the already-required in-session materialization map solely for Crew dependency/board translation. |
| RN-12 | **RESOLVED** | No task-local evidence base remains. A gate commit cannot invalidate a deleted record selector. |
| RN-13 | **RESOLVED** | No base64 progress convention remains, so no retry prompt is inflated by those records. |

### Issues

#### Blocker

##### RN-01: Logic bug: the revision captures a “quiet” snapshot while lobby workers can still write
- **Severity:** Blocker
- **Location:** `approach.md` D-A/D-H; `execution-model.md` §3/§5; `plan.md` State Ownership
  Policy, T6; `crew/handlers/work.ts`, `crew/lobby.ts`, `index.ts`.
- **Problem:** The plan treats `work` returning as completion of the dispatched wave. That is true
  only for `spawnAgents` direct workers. Lobby assignment is fire-and-forget; its task is marked
  `in_progress` before its inbox assignment, excluded from the awaited list, and can continue
  editing after `work` returns. In the lobby-only case autonomous work actually stops with no
  ready task. Neither `task.done` nor lobby `agent_end` wakes the lead, and Crew continuation
  remains based on `done`, not the external verdict.
- **Why it matters:** The “immutable snapshot” can be torn or rejected, an evidence rerun can
  race mutations, and the conditional hold can either dispatch an unreviewed dependent or strand
  the run. The worked example assumes an all-direct all-done wave and is not a safe execution
  model for the configured lobby-capable substrate.
- **Correction:** Do not implement T6 as written. Add an upstream/source-supported cohort
  completion primitive and review-aware dispatch interlock, with direct and lobby fixtures. It
  needs an event-driven lead wake on terminal transition; polling the JSON board is disallowed.
  Alternatively explicitly disable lobby assignment and make the implementation prove every
  direct worker is awaited before the boundary. Then add a delayed lobby `T1 → T2` SHIP and
  NEEDS_WORK protocol case that proves no torn bundle, no premature dispatch, and no repeat-guard
  stop.
- **Decision required:** Yes.
- **Status:** NOT RESOLVED.

#### Critical

##### RN-04: Logic bug: `--evidence` remains an underspecified versioned input contract
- **Severity:** Critical
- **Location:** `plan.md` CLI Contract Mini-Spec/T3; `tools/pi-team.mjs:parseOptions`,
  `reviewWave`, and `changedPaths`.
- **Problem:** The contract says `--evidence FILE` is JSON but gives only one sample object. It
  does not say whether every scope/bundle task must be present, whether extra task IDs or fields
  are rejected, whether `command`/`outputTail` are strings, whether `exit` is an integer (and its
  range), whether `verified` is mandatory, or whether the tool trims/rejects a too-large tail.
  Nor does it place an unreadable/malformed evidence failure in the stated deterministic order.
  An implementer must also choose evidence-file realpath/symlink behavior.
- **Why it matters:** Different implementations can serialize `absent`, `reported-unverified`,
  or lead evidence differently and choose different error winners, defeating the promised stable
  CLI/JSON boundary. This remains Critical under the tooling/CLI gate.
- **Correction:** Put a versioned closed schema and resolver in the mini-spec, including all
  field types/limits, task-key relationship, unknown-key policy, null-field derivation, and an
  evidence-validation position in the error order. Add T3 fixture cases for each malformed
  branch and each competing failure.
- **Decision required:** Yes.
- **Status:** PARTIALLY RESOLVED.

#### Major

##### RN-02: Logic bug: `reported-unverified` is honest but the plan has no report to embed
- **Severity:** Major
- **Location:** approach D-D; `execution-model.md` §3; plan State Ownership Policy/T6;
  `config/pi-team/crew-worker.md`; `crew/types.ts`, `crew/handlers/work.ts`, `crew/lobby.ts`.
- **Problem:** The label does not recreate false verification, but the payload is absent from the
  current system. Workers report the command in `evidence.tests` and a generic passed progress
  line, not exit code or output. The lead-visible work result only contains ID arrays; it discards
  each direct `AgentResult.output`, and lobby paths do not create those artifacts. T6 neither
  defines a bounded reported-output producer nor owns the worker-prompt/config change needed to
  make one.
- **Why it matters:** The new evidence flag can honestly say `absent`, but it cannot satisfy the
  plan/ADR claim that every non-risk task embeds worker-reported command/exit/output. A risk check
  failure at a real boundary is likewise unspecified: does the lead reset/block immediately,
  bundle the failure, or let reviewer verdict control it? A mutating check cannot be safely
  discovered by running it in the shared worktree.
- **Correction:** Choose one explicit contract. Either add a bounded worker handoff (and say it is
  reported-unverified), with direct/lobby source and error cases, or change the goal/ADR wording
  to command-only/absent for non-risk tasks. Specify that lead risk reruns use an isolated copy
  after the actual cohort barrier, snapshot pre/post state, and define failure handling before
  review. Do not rely on `task.progress` authorship.
- **Decision required:** Yes.
- **Status:** PARTIALLY RESOLVED.

##### RN-03: Logic bug: boundary scope remains conditional on dirty-work lifecycle rules that are absent
- **Severity:** Major
- **Location:** approach D-H; `execution-model.md` §3/§5; plan T3/T6;
  `tools/pi-team.mjs:scopeIsValid`/`reviewWave`; `crew/store.ts:resetTask`/`blockTask`.
- **Problem:** `review-wave` is correctly strict: it will reject a path from any non-scope task.
  But `resetTask` and `blockTask` retain their worktree changes while changing board status, and
  a live lobby sibling retains them while the direct cohort returns. The plan has no precondition
  or recovery rule that removes those paths before declaring a completed-wave snapshot.
- **Why it matters:** The removal of `review-task` resolves only the intentional concurrent
  sibling scope problem. It does not turn a dirty tree into exactly one completed wave, so T6 can
  dead-end at `REVIEW_OUT_OF_SCOPE` in normal retry/rescue/lobby behavior.
- **Correction:** Define a verified cohort/dirty-tree invariant and explicit stop/cleanup or
  isolation procedure for reset, block, rescue, and lobby transitions. Add the lifecycle fixtures
  alongside the normal completed-wave case.
- **Decision required:** Yes.
- **Status:** PARTIALLY RESOLVED.

##### RN-06: Template lint still false-greens CLI-invalid command lines
- **Severity:** Major
- **Location:** plan.md T6; `tests/specs/skill-content-spec.sh`; current `tools/pi-team.mjs` main.
- **Problem:** The lint's table now matches actual flags, and its continuation/value checks are
  implementable. It does not require the positional PLAN that every current subcommand parses
  before options, nor reject extra positionals/duplicate flags. For example a `review-wave`
  line with all five flags and values but no plan is accepted by the proposed lint and rejected
  by the CLI.
- **Why it matters:** The stated guard can still certify a lead skill whose executable snippets
  cannot run, which is a material false-green for the only pre-run defense against skill/tool
  drift.
- **Correction:** Add subcommand positional arity and allowed flag cardinality to the concrete
  lint contract, plus mutations for missing PLAN, duplicate flag, and a value beginning `--`.
- **Decision required:** No.
- **Status:** PARTIALLY RESOLVED.

##### RN-14: T8 lacks the mandatory Break-it step
- **Severity:** Major
- **Location:** plan.md T8 TDD checklist.
- **Problem:** T8 changes the durable backlog/worklog/state closure surface but lists only
  verification and creation checks. Unlike the documented T1 human-decision and T7 generated
  `dist/` exceptions, it declares no exception and no mutation that proves its new closure
  assertion can fail.
- **Why it matters:** This violates the plan's strict Red → Green → Break-it contract and can
  pass with an invalid/missing stable calibration record or unverified closure state.
- **Correction:** Add a concrete T8 break-it (for example mutate/remove the new `TASK-XXXX`
  backlink/required status and require the relevant readiness assertion to fail), or document a
  narrow justified exception. Ensure the task names the target assertion/command rather than
  relying on a manual read.
- **Decision required:** No.
- **Status:** OPEN (new).

### Consistency, graph, and coverage sweep

- **Metrics confirmed.** The eight-task graph has depth sets `{T1,T2,T4,T5}`, `{T3}`, `{T6}`,
  `{T7}`, `{T8}` and widths `4,1,1,1,1`. Estimates sum to 175; the longest path is
  `T1→T3→T6→T7→T8 = 130`; mean is `8/5 = 1.6`, width-1 share is `4/5 = 80%`, max is 4, and
  `130/175 = 0.742…` rounds to 0.74. The sequential/schema-1 boundary statement is accurate.
- **RN-10/RN-12/RN-13 removals are consistent.** No active `review-task`, PI-TEAM progress
  record, base64 evidence, task-local base selector, or new lead ledger remains outside legitimate
  historical Review/Progress Log context. The retained plan-ID→Crew-ID mention in the older lead
  skill is a materialization fact, not a new evidence store.
- **Terminology still drifts.** `brief.md` promises the *worker's* command/exit/status in bundles,
  while the revision claims lead capture for risk tasks and unverified worker reports for others.
  The latter report has no producer. T1 simultaneously says ADR 0004's worker-evidence consequence
  is “satisfied, not amended,” although lead evidence is not worker evidence. Resolve that ADR/
  brief/approach/plan wording with the evidence decision rather than silently relabelling it.
- **`execution-model.md` agrees with T6's stated ordering but shares its false quiet-boundary
  assumption.** Its worked example is valid only when every wave worker is direct/awaited; it
  needs an explicit lobby-safe precondition or the new barrier. The T6 “wait for terminal board
  state” instruction is otherwise a forbidden polling hole, not a recovery procedure.
- **ADR 0004 ownership remains assigned** (T2 config, T3 tool evidence, T4 reviewer, T5 planner,
  T6 lead, T7 docs/render, T8 calibration); no task renumbering error was found. The unowned
  runtime barrier and worker-output production are correctness gaps within T6/RN-02, not missing
  ADR table rows.

### Implementer decisions remaining

1. A source-compatible, event-driven all-assignment boundary and conditional-hold/continuation
   interlock, including lobby completion (RN-01).
2. The actual producer, bounded schema, safe execution environment, and failed-rerun policy for
   non-risk and risk evidence (RN-02).
3. The dirty-tree lifecycle/recovery policy for reset, block, rescue, and live assignments
   relative to a completed-wave scope (RN-03).
4. The complete versioned `--evidence` JSON and failure-order contract (RN-04).

Each decision changes a production execution or CLI contract. They cannot be delegated to an
implementer. RN-06 and RN-14 are specified verification corrections and should be applied with
those decisions.

### Test adequacy assessment

- Coverage matrix complete: **No.** It lacks direct/lobby cohort completion and wake tests,
  active-lobby/torn-tree refusal, reset/blocked dirty-tree recovery, actual worker-report
  production, risk-check mutation/failure handling, closed evidence-schema errors, and T8
  break-it coverage.
- Negative/edge cases identified for each row: **No.** In particular, no row proves malformed
  evidence's error precedence, a non-risk output that is actually obtainable, or an all-lobby
  invocation that stops while work remains live.
- Bad-test avoidance addressed in approach.md: **Partly.** T3 fixture tests can prove the CLI,
  but text/template tests cannot prove a completion event or enforce a skill at runtime; the plan
  acknowledges this limit but incorrectly calls the next production run a calibration rather than
  a first correctness proof.
- E2E seed/fixture data confirmed to support scenarios: **No.** Existing fixtures model git and
  the compiler, not a direct/lobby Crew cohort, board transitions, and lead wake.
- TDD checklists include break-it step for all tasks: **No** — T8 has none.

### Summary

| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-01 | Blocker | D-A/D-H, execution model, T6 lobby boundary | Yes | NOT RESOLVED |
| RN-02 | Major | D-D/State Ownership/T6 evidence producer and rerun | Yes | PARTIALLY RESOLVED |
| RN-03 | Major | D-H/T3/T6 dirty-tree scope lifecycle | Yes | PARTIALLY RESOLVED |
| RN-04 | Critical | CLI evidence mini-spec/T3 | Yes | PARTIALLY RESOLVED |
| RN-06 | Major | T6 template lint | No | PARTIALLY RESOLVED |
| RN-10 | Critical | former progress-attestation design | Yes | RESOLVED |
| RN-11 | Blocker | former Crew-file bundle lookup | Yes | RESOLVED |
| RN-12 | Blocker | former task-record base selector | Yes | RESOLVED |
| RN-13 | Major | former base64 retry prompt record | No | RESOLVED |
| RN-14 | Major | T8 TDD checklist | No | OPEN (new) |

### Changes Applied to Plan

- None. The assignment restricts edits to `plan_review.md`; all findings are production/CLI
  contract decisions or plan corrections, not safe review-only edits.

### Review status

- Issues found this pass: **1 Blocker, 1 Critical, 4 Major** (RN-14 is new; RN-01 through RN-06
  remain as listed; RN-10 through RN-13 are resolved by the mechanism removal).
- Issues fixed this pass: **0**.
- Remaining significant issues: **6**.
- **Readiness verdict:** **Not ready for sequential execution.** Revision 4 correctly removes the
  unauthenticated progress-record/record-base machinery, but its replacement depends on a quiet
  boundary that the installed lobby-capable Crew implementation does not provide. Do not begin
  T6 or a production run until RN-01 establishes a real event-driven cohort barrier; then resolve
  the evidence, CLI, dirty-tree, and verification gaps and obtain another review pass.
- **Status: NEEDS_ANOTHER_PASS**

---

## Review 2026-08-06 (Review 5)

**Plan:** `plans/2026_08_06_continuous_crew_execution/plan.md`  
**Scope:** delta — Revision 5 Boundary Quiescence, lead-only evidence, closed `--evidence`
schema, T3/T6 lint changes, plus source and consistency re-verification  
**Handoff readiness:** No

### Source re-verification

- **The new guard is necessary but not sufficient.** `work.ts` awaits `spawnAgents` only for
  `remainingTasks`; it sends an available lobby worker an assignment after marking its board task
  `in_progress`, then excludes it from that awaited list. `review-wave --require-quiescent` can
  observe the resulting task JSON status, but neither it nor the board can observe the registry
  process. A worker can call `task.done` (which changes status to `done`) before its process exits
  or before it stops writing. Conversely a crashed/abandoned lobby worker can retain
  `in_progress` indefinitely. Thus “no task in_progress” is not proof that no process can write;
  it is only a useful refusal condition.
- **The claimed zero-lobby preflight is not available to the lead as specified.** The positive
  source claim is real: direct calls to `spawnLobbyWorker` occur in `overlay.ts` and
  `crew/spawn.ts`, no Messenger `lobby.*` action was found, and `crew/registry.ts` keeps workers
  in an extension-process `Map`. But that proves only that an operator can avoid creating lobby
  workers. It gives the lead no tool/query with which to verify zero workers. The available
  `getLobbyWorkerCount` is not public and counts only unassigned live lobby entries; an assigned
  lobby worker is not represented by an observable zero count. Its `.alive` file is also not a
  reliable assigned-worker ledger. The preflight is therefore an unverifiable operational
  assertion, not enforcement.
- **A non-quiescent refusal can strand the run.** If `work` returns after a mixed direct/lobby
  batch and the guard finds the lobby task `in_progress`, the lead has no completion promise to
  await. A lobby worker's `agent_end` returns early in `index.ts` under `PI_LOBBY_ID`, so it does
  not emit `crew_continue`; rereading task files would be timer polling. If the process crashed,
  the same status persists forever. “Route to stall recovery” names neither a wake source nor a
  permitted termination/restart/cleanup operation. This is the Review 4 blocker in a different
  form, not its resolution.
- **Current `parseOptions()` cannot implement the promised call surface without an explicit
  migration.** It treats every name supplied by its caller as required, requires a following
  non-`--` value for each, rejects unknown options, and cannot represent a valueless boolean.
  `reviewWave()` currently calls it with exactly five required value options. Adding optional
  `--evidence`, optional paired `--crew-dir`, and valueless `--require-quiescent` needs a new
  option declaration/parser (or a command-specific parser), legal partial-pair rules, and tests.
  T3 says the flags are optional and retains legacy regression cases, but does not identify this
  source change or test malformed pair/boolean forms. The compatibility claim is a desired
  outcome, not a plan-ready implementation contract.
- **`scopeIsValid()` accepts compiler chunks, not every actual boundary cohort.** An exact
  computed chunk is accepted even when it spans integration groups. A singleton retry is accepted
  only when that task itself is the complete computed chunk. For example, after retrying T1 from
  an original four-task chunk, scope `T1` fails because the function requires all IDs of some
  wave; the complete-integration-group condition only permits extras after the scope already
  contains a full wave, so it is not a general retry rule. `resetTask()` and `blockTask()` preserve dirty worktree changes while
  changing state, so a later exact completed chunk can also fail `REVIEW_OUT_OF_SCOPE`. No
  Revision 5 lifecycle cleanup/cohort rule addresses this.
- **The lead-rerun policy is not made safe by `Worker-safe: yes`.** The compiler only requires
  that string on a worker check; it neither establishes a timeout/cost bound nor says a check is
  read-only. A fixture/test command can create files or update generated output. T6 reruns every
  completed task before snapshotting, but supplies no isolated worktree or pre/post refusal
  protocol, no action if a rerun fails despite a worker pass, and no cost budget. It also says
  “every completed task,” while the evidence schema permits keys only for the current `--bundle`;
  the plan never reconciles whether this means all historical `done` tasks (quadratic repeated
  work) or only the newly completed bundle.
- **The evidence contract is substantially improved but not fully closed.** It omits whether
  `tasks` must be an object (rather than merely giving object-shaped JSON), how `outputTail`
  length is measured after lossy decoding (bytes or JavaScript code units), the allowed/resolved
  location of `FILE`, and whether `pathStatus` is per-task or manifest-wide. Duplicate raw JSON
  member names are not addressed; ordinary `JSON.parse` silently accepts them with last-key-wins,
  which conflicts with a “closed/full validation” claim unless a duplicate-detecting parser is
  chosen. The listed order ranks broad phases, but does not totally order competing evidence
  failures (e.g. non-regular file/read failure, UTF-8/JSON parse, duplicate/unknown key, wrong
  version/type, and oversize tail) or say which diagnostic is emitted. It is therefore not a
  total failure ordering for all pairs.
- **The command-template lint is still internally contradictory.** The proposed generic rule
  that every flag is followed by a value conflicts with its allowed `--require-quiescent`, whose
  syntax intentionally has no value. It does not give each flag an arity or forbid a flag token
  being consumed as another flag's value. Its stated `$VAR`/`"$VAR"` normalization also does not
  define `${VAR}` or mixed quoted path forms. Consequently the lint cannot both accept the
  required boundary command and demonstrate actual CLI validity.
- **Metrics now recompute correctly.** With T3 at 45 minutes, widths are `4,1,1,1,1`; mean is
  `8/5 = 1.6`, max is `4`, width-1 share is `4/5 = 80%`, serial is `180`, and critical path
  `T1(25) → T3(45) → T6(35) → T7(20) → T8(10)` is `135`; `135/180 = 0.75`. The sequential versus
  schema-1 gate boundary remains honestly stated.

### Resolution checklist

| Prior ID | Result | Review 5 assessment |
|---|---|---|
| RN-01 | **NOT RESOLVED** | Prohibiting lobby creation is a plausible direction, but it is not lead-observable or mechanically enforced. Board status is not a write/process barrier, and guard refusal has no event-driven recovery/wake. |
| RN-02 | **PARTIALLY RESOLVED** | Deleting `reported-unverified` correctly removes forged worker provenance and gives the lead a real way to obtain command/exit/output. The rerun safety, failure transition, bounded scope, and throughput cost remain unspecified. |
| RN-03 | **NOT RESOLVED** | The normal exact compiler chunk works, including a chunk crossing integration groups. The design still fails for a singleton retry from a multi-task chunk and dirty reset/block state; it does not define the actual cohort passed to `scopeIsValid`. |
| RN-04 | **PARTIALLY RESOLVED** | Version, required per-task fields, unknown-key rejection intent, file type, and phase ordering are material progress. Raw duplicate handling, object/byte/path semantics, `pathStatus` placement, and a genuinely total evidence-error order remain implementer decisions. |
| RN-06 | **NOT RESOLVED** | Positional and duplicate rules close the prior false-green, but a value-for-every-flag grammar rejects/misparses its own boolean guard. No flag-arity grammar or corresponding mutation cases are specified. |
| RN-14 | **NOT RESOLVED** | T8 still has no Break-it action or executable assertion for its added backlog/closure state. |

### Issues

#### Blocker

##### RN-01: Logic bug: “no `in_progress`” cannot establish or recover boundary quiescence
- **Status:** NOT RESOLVED
- **Location:** approach.md D-I; execution-model.md §3/§5; plan.md Boundary Quiescence, State
  Ownership, T6; `crew/handlers/work.ts`, `crew/handlers/task.ts`, `crew/registry.ts`, `index.ts`.
- **Problem:** Revision 5 correctly identifies the direct-versus-lobby await difference, but its
  two remedies do not create an enforceable all-writer barrier. The zero-lobby condition lives in
  an in-process registry unavailable to the lead; the task-file guard can only see status. A
  worker that calls `task.done` and continues running/editing is `done`, not `in_progress`, and
  an out-of-protocol worker can edit before it starts. More commonly, a pre-existing/mixed lobby
  worker makes the guard refuse, yet its eventual completion does not wake the lead and a crash
  leaves the status permanently non-quiescent. “Stall recovery” has no defined non-polling action.
- **Why it matters:** A snapshot and lead reruns may still race a live writer, while the safe
  refusal alternative deadlocks the run. The plan has not established the Review 4 prerequisite
  for conditional hold, evidence capture, or an immutable bundle.
- **Correction:** Do not implement T6/runtime rollout on this premise. Provide an upstream or
  source-supported, lead-observable all-assignment cohort barrier that proves process terminality
  and wakes the lead, plus review-aware continuation behavior. If choosing a no-lobby local mode,
  expose and enforce it through a real preflight/tool surface and define the observed worker
  lifecycle; a prose operator assertion and task-status scan are insufficient. Add direct,
  pre-existing-lobby, done-before-exit, hung/crashed, and completion-wake cases. Otherwise descope
  the runtime loop to a manual controlled operation and state that it does not meet NFR-003.
- **Decision required:** Yes.

#### Critical

##### RN-15: Logic bug: optional `review-wave` flags cannot be parsed by the current or specified parser
- **Status:** OPEN (new)
- **Location:** plan.md CLI Contract Mini-Spec/T3/T6; `tools/pi-team.mjs:parseOptions`,
  `reviewWave`; `tests/specs/pi-team-tool-spec.sh`.
- **Problem:** `parseOptions(values, names)` accepts only known key/value pairs and then requires
  every declared name. It cannot represent either optional `--evidence FILE` or the valueless
  `--require-quiescent`; putting `--crew-dir` in its names would make it mandatory. The mini-spec
  says the quiescence pair is used together but never defines whether either lone form is an
  argument error, nor the error precedence when it coexists with a non-quiescent crew directory.
  T3 does not name replacement of `parseOptions` or require the partial/duplicate/boolean cases.
- **Why it matters:** Existing invocations can remain valid only after a real parser change, but
  two reasonable implementations will accept different invalid inputs. This is an incomplete
  versioned CLI contract, and the lint is built atop the same missing arity model.
- **Correction:** Give each command option an explicit `{required, arity}` declaration (including
  boolean arity zero), preserve existing strict unknown/duplicate rejection, define the paired
  guard's legal combinations and argument-error precedence, and list the change in T3's
  implementation and fixture checklist. Test legacy five-flag calls, evidence-only,
  guard-plus-crew-dir, each lone pair member, duplicate flags, missing values, and a value starting
  `--`.
- **Decision required:** Yes.

##### RN-04: Logic bug: the evidence schema claims closure/total ordering but leaves material parser choices open
- **Status:** PARTIALLY RESOLVED
- **Location:** plan.md CLI Contract Mini-Spec/T3; `tools/pi-team.mjs:reviewWave`.
- **Problem:** The revision repairs most of Review 4's named gaps but not all contract branches.
  It does not state `tasks`' JSON type, evidence-file pathname/root resolution, byte measurement
  after lossy UTF-8 decoding, duplicate raw JSON member policy, or whether `pathStatus` is a task
  field or manifest field. It calls the phase sequence “deterministic failure order,” yet there is
  no total ordering or stable code for competing failures inside evidence validation. A standard
  JSON parser silently collapses duplicate keys, so “unknown keys rejected” is not enough to
  validate a closed raw input.
- **Why it matters:** This leaves externally visible acceptance/rejection and manifest shape to
  implementer discretion, contrary to the versioned CLI requirement.
- **Correction:** Specify a duplicate-detecting parsing/validation order, exact JSON object types,
  UTF-8 byte counting rule, evidence location/symlink resolution, manifest nesting, stable error
  codes, and one total list covering argument parsing, quiescence, each evidence failure, Git,
  output, scope, no-change, and oversize. Add a fixture for every adjacent pair as well as each
  malformed schema branch.
- **Decision required:** Yes.

#### Major

##### RN-02: Logic bug: lead-rerun evidence is unsafe and unbounded at the only safe boundary
- **Status:** PARTIALLY RESOLVED
- **Location:** approach.md D-D; execution-model.md §3; plan.md State Ownership, Risks, T6;
  `tools/pi-team.mjs:parseChecks`.
- **Problem:** The plan asserts that minimal checks are “cheap and worker-safe,” but the checked
  compiler records only `Worker-safe: yes`; it does not constrain mutations, time, external
  effects, or a lead execution environment. Running a mutating/slow check before bundle creation
  can dirty the tree and either change snapshot bytes, introduce an out-of-scope refusal, or hold
  the lead for N checks. It also lacks a transition for a boundary failure: whether it resets or
  blocks immediately, embeds failed evidence for review, or allows reviewer verdict to override
  it. “Every completed task” additionally conflicts with `--evidence` allowing keys only in the
  current bundle, and makes repeated work grow by all historical done tasks at every boundary.
- **Correction:** Define either a bounded lead-safe/read-only check class, with timeout and
  pre/post state behavior, or run checks in an isolated immutable copy before deciding whether to
  snapshot. Define exactly “newly completed bundle tasks” versus historical tasks and its budget,
  and specify the failed-rerun transition and ordering relative to bundle generation. Add slow,
  mutating, failure-after-worker-pass, multiple-task cost, and output-order fixtures.
- **Decision required:** Yes.

##### RN-03: Logic bug: static compiler scope does not model retries or retained dirty state
- **Status:** NOT RESOLVED
- **Location:** approach.md D-H; execution-model.md §3; plan.md T3/T6;
  `tools/pi-team.mjs:scopeIsValid`, `reviewWave`; `crew/store.ts:resetTask`, `blockTask`.
- **Problem:** The new no-`in_progress` test does not make the worktree equal a just-completed
  compiler wave. Reset/block preserve files while changing a task to `todo`/`blocked`; a later
  boundary rejects them unless scope includes those old tasks. A retry of a member of a four-task
  chunk similarly cannot call `review-wave --scope T1`: `scopeIsValid` requires the full chunk.
  The successful single-task T3 example is incidental, not a general loop invariant. Exact
  chunks that cross integration groups are accepted, but that does not solve the retry case.
- **Correction:** Define a verified dirty-tree/cohort invariant before every bundle. Either clean
  abandoned/reset paths, carry the original full chunk as scope for every retry, or introduce a
  validated cohort representation. Specify reset, cascade reset, block, rescue, retry, and group
  completion behavior, then test a singleton retry from a multi-task chunk and an unrelated
  retained dirty path.
- **Decision required:** Yes.

##### RN-06: Logic bug: the template lint cannot accept the required boolean flag
- **Status:** NOT RESOLVED
- **Location:** plan.md T6; `tests/specs/skill-content-spec.sh`.
- **Problem:** T6 says every flag has a following value while the allowed `review-wave`
  `--require-quiescent` has arity zero. The generic scan can therefore consume `--crew-dir` as
  its value or reject the valid line; it also does not define `${VAR}`, quoted-token handling, or
  an explicit no-flag-as-value check.
- **Correction:** Specify a tiny canonical tokenizer and a per-subcommand option table with zero-
  versus one-value arity and allowed cardinality. Include the guard pair in the canonical fixture
  and mutation-test missing PLAN, duplicate flag, unknown flag, omitted value, flag-as-value, a
  lone boolean, and a continuation/variable form.
- **Decision required:** No.

##### RN-14: T8 still violates the strict TDD contract
- **Status:** NOT RESOLVED
- **Location:** plan.md T8.
- **Problem:** Revision 5 does not add the Review 4-required Break-it check or a test assertion
  for the stable calibration backlog item/backlink and closure record.
- **Correction:** Add a failing readiness assertion before the document change and a T8 mutation
  that removes/corrupts the new `TASK-XXXX` backlink/status and proves that assertion fails, or
  document a narrow justified exception.
- **Decision required:** No.

##### RN-16: Logic bug: evidence provenance contradicts the accepted ADR and brief
- **Status:** OPEN (new)
- **Location:** brief.md Goals; plan.md Change Summary, T1, State Ownership, D-D; ADR 0004
  Consequences.
- **Problem:** ADR 0004 says `review-wave` should embed the **worker's** command, exit, and staged
  status. The brief repeats that worker promise. Revision 5 deliberately—and correctly—changes
  the producer to the lead rerunning a check, but T1 says the ADR consequence is “satisfied, not
  amended” and even describes lead rerun only for risk-labelled tasks while D-D/T6 require every
  task. Lead-generated evidence is not the worker's evidence. The sources now disagree on a
  load-bearing evidence contract.
- **Correction:** Have ADR 0005 explicitly amend the evidence-producer consequence to
  lead-verified boundary evidence (or restore an authentic worker producer upstream), then align
  the brief, Change Summary, T1, D-D, execution model, and reviewer wording. Do not silently
  relabel the producer to preserve an old ADR sentence.
- **Decision required:** Yes.

### Consistency, graph, and coverage sweep

- **Stale-mechanism sweep:** No active `reported-unverified`, `review-task`, `progress record`,
  `run ledger`, or `--allowed-scope` instruction remains outside legitimate historical progress
  discussion. The `review-task` mentions in approach D-D/D-H and the substrate finding are
  historical comparison, not a live command. The top-level Review 5 roll-up corrects the old
  RN-10 decision text to the actual `{lead-verified, absent}` enum.
- **Cross-artifact contradictions remain material:** the brief/ADR worker-evidence promise and
  T1's “satisfied, not amended” claim conflict with all-task lead reruns (RN-16). T1 says
  risk-only rerun while State Ownership, D-D, T6, and the execution model say every task. The
  approach, plan, and execution model consistently repeat the same unverified zero-lobby/status
  premise, so agreement among them is not evidence of correctness (RN-01).
- **ADR ownership:** config (T2), tool evidence (T3), reviewer (T4), planner (T5), lead (T6),
  docs/render (T7), and calibration (T8) still have named task owners. However, the evidence
  consequence has an incompatible owner contract, not a missing task: T1 must amend it rather
  than claim literal satisfaction (RN-16).
- **Coverage remains incomplete:** T3 fixtures cover a task JSON refusal but cannot prove no
  worker process writes; there is no source-compatible direct/lobby terminal/wake test. The plan
  lacks safety/cost/failure tests for lead reruns, reset/block/singleton-retry scope cases,
  optional-parser pair cases, duplicate JSON members, and T8's break-it mutation. Text/template
  tests cannot turn these absent runtime capabilities into proof.

### Implementer decisions remaining

1. An observable, event-driven all-assignment boundary and recovery protocol that actually proves
   no worker can write (RN-01).
2. A lead-safe, bounded, failure-defined rerun contract and exact evidence task set (RN-02).
3. A valid cohort/scope lifecycle for reset, block, rescue, and singleton retries (RN-03).
4. The closed raw evidence grammar, manifest nesting, and truly total error order (RN-04).
5. The option parser's optional/boolean/pair grammar and compatibility behavior (RN-15).
6. Whether ADR 0005 explicitly amends worker evidence to lead-verified evidence and aligns the
   brief/T1 (RN-16).

Each changes a production runtime or CLI/ADR contract, so none can be delegated to an
implementer. RN-06 and RN-14 are concrete test-plan corrections but require the surrounding
CLI grammar to be settled first.

### Trajectory assessment

**NOT CONVERGING.** Reviews 1–3 did tighten real details, but each revision replaced the prior
load-bearing mechanism with another local approximation that later source inspection invalidated:
worker evidence → unauthenticated progress records → quiet boundary → an unobservable lobby
prohibition plus status scan. Review 5 closes some prose gaps, but it exposes that the new
boundary cannot prove writer absence or recover without polling, while also adding unresolved
parser, rerun-safety, and ADR-provenance defects. This is not normal specification refinement
around a stable design; it is repeated failure against substrate reality.

Stop this runtime execution design before T3/T6 or a production run. Either descope to the
independently safe, non-runtime documentation/config/tool portions without claiming continuous
review safety, or make the required upstream all-assignment barrier, process observability,
lead wake, and review-aware dispatch interlock a prerequisite. Do not spend another pass merely
adding local prose guards to the same unavailable substrate primitive.

### Review status

- Issues found this pass: **1 Blocker, 2 Critical, 5 Major** (RN-15 and RN-16 are new; RN-01,
  RN-02, RN-03, RN-04, RN-06, and RN-14 remain significant).
- Issues fixed this pass: **0** (review-only assignment; only `plan_review.md` was modified).
- Remaining significant issues: **8**.
- **Readiness verdict for sequential execution:** **Not ready.** The complete sequential plan
  must not begin as written; in particular, do not implement T3/T6 or start a Pi-team production
  run until the blocker and the CLI/runtime contract decisions are resolved and reviewed again.
- **Status: NEEDS_ANOTHER_PASS**
