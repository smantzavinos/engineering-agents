# Proposal: Code-Mode Execution Process

> **Status: implemented, 2026-08-18.** This document is the point-in-time proposal and is kept
> as a historical record. The accepted decision is recorded in
> [ADR 0004](../../adr/0004-replace-team-mode-with-code-mode.md); the operating contract is
> [docs/execution-patterns.md](../../execution-patterns.md). Skill names below predate the
> final `dynamic-*` naming where not otherwise corrected.

- Date: 2026-08-18
- Status: implemented (see banner above)
- Supersedes (if accepted): `docs/team-mode-execution.md`, `docs/pi-team-setup.md`, ADR 0002, ADR 0003

---

## 1. Review findings

### 1.1 Team mode failed for structural reasons, not tuning reasons

Team mode (`pi-messenger` Crew) encodes orchestration as **prose that agents must obey**:
a lead agent reads `docs/team-mode-execution.md` (154 lines), maintains a task board, honours a
"Turn-Exit Contract", nudges silent members, and never polls on a timer.

Every one of those is a control-flow invariant expressed as an instruction to a language model.
That is the defect. The failure modes observed in this repo are all consistent with it:

| Symptom | Root cause |
|---|---|
| Board polling / idle members | No scheduler exists; the lead *is* the scheduler and it is a stochastic one |
| Lead ends turn with ready work undispatched | "Turn-Exit Contract" is a prompt, not a loop condition |
| Ceremony trap on small plans (`issues_learnings.md`) | Lane/slot policy is static prose, not computed from the graph |
| Worker tool allowlist silently broke the protocol | Coordination depends on an extension tool being present in every child |
| 7 skills + 2 docs + 2 ADRs to describe one execution mode | Prose is the only place the logic can live |

The cost is visible in the artifact count: `create-team-plan`, `review-team-plan`,
`create-team-worklog`, `execution-orchestrator-team`, `pi-team-plan`, `pi-team-lead`,
`pi-team-worker` — 7 skills, ~950 lines, to express what is fundamentally a work queue.

### 1.2 Code mode removes the reason those documents exist

`pi-subagents` ≥ 0.50.0 exposes `workflowScript`: a trusted inline JavaScript body with
`runs.run(key, {...})`, `runs.all([...])`, `runs.steer(key, msg)`, `runs.status`, `emit`,
`state.get/set`, plus ordinary `await`, `Promise.race`, `Promise.all`, loops and branches.

That means scheduling, wave computation, dependency readiness, retry, escalation and fan-in
become **executable code with deterministic semantics**. Turn-exit contracts, nudge policies,
idle reporting and lane discipline stop being instructions and become `while` loops.

Two capabilities matter most for the swarm pattern:

- `gate: "<command>"` on a child — the *host* runs the verification command and records the
  result as evidence. A worker cannot claim green; the runtime proves it.
- `worktree: true` per child — each writer gets a managed git worktree branched from clean
  HEAD, with a patch + handoff manifest. Real parallel writes without file-lock prose.

### 1.3 Plans are bloated

`skills/create-plan/references/plan-template.md` is 201 lines with ~25 sections. A plan today
carries: change summary, goals, non-goals, backlog refs, requirement refs, requirement update
table, impacted surface area, context, constraints, assumptions, open questions, risk table,
decision table, task graph table, per-task detail with 7-step TDD checklist, coverage matrix,
baseline gate audit, gate policy, verification command table, completion criteria,
compatibility/migration, progress log, evidence ledger, deviations, issues, follow-ups.

Most of that is **duplicated from `brief.md` / `approach.md`** (goals, non-goals, constraints,
context, decisions, risks) or **re-derived from repo docs** (verification commands, gate roles).
The bloat is not cosmetic: it is context that every planner, reviewer and implementer child
must read, and it dilutes the part that actually drives execution.

A plan needs to answer exactly two audiences:

1. **The human approving it** — what changes, what breaks, what it costs, what is risky.
2. **The workflow script executing it** — a dependency graph of tasks with write-sets,
   acceptance, and gate commands.

Everything else belongs in `approach.md`, in repo docs, or nowhere.

### 1.4 TDD-everywhere produces tautological tests

The current contract is strict Red → Green → Break-it → Verify on *every* task. Applied to a
documentation task, the only reachable "test" is one that reads the doc and asserts a substring
is present. That test:

- cannot fail for any reason other than someone editing the file it reads
- encodes the change as its own oracle
- must be updated whenever the prose is reworded
- gives a false green on the final gate

The rule being violated is simple, and it should be stated explicitly in the testing doc:

> **A test must be able to fail for a reason other than someone editing the file the test reads.**

If no such failure mode exists, the correct verification is a *check* (schema valid, renderer
clean, links resolve, spec suite green), not a test.

### 1.5 The break-it check should be deleted

Break-it is a manual, per-task mutation test performed by the implementing agent on its own
work. It is:

- **unverifiable** — the agent reports it did it; there is no artifact
- **self-graded** — the same context that wrote the test judges whether it failed correctly
- **redundant under contract-first** — if the test is authored before the implementation exists,
  red-before-green is observed *for free* and by a different agent
- **not applicable** to the majority of tasks (config, docs, refactors, wiring)

The genuine signal break-it was chasing — "does this test actually constrain anything?" — is
better obtained by (a) contract-first authorship by a different agent, and (b) reviewer scan for
tautological assertions, which `review-code` already does.

Recommendation: remove break-it entirely. Do not replace it with a mutation-testing tool unless
one already runs in CI cheaply.

### 1.6 Extension surface is oversized

20 managed Pi packages are declared in `nix/modules/pi/config.nix`. Several are redundant with
`pi-subagents` ≥ 0.50: it ships a native prompt-workflow adapter (`/prompt-workflow`), a native
supervisor channel (`contact_supervisor` / `subagent_supervisor`), a fleet inspector, missions
and schedules. `pi-messenger` exists only to serve team mode, which this proposal removes.

### 1.7 Skill surface pollutes every prompt

23 canonical skills are discoverable, meaning their names + descriptions occupy the system
prompt of every session, and the model may load any of them speculatively. Only 3–4 are true
entry points. Pi supports `disable-model-invocation: true` in skill frontmatter: the skill stays
loadable via `/skill:<name>` but disappears from the system prompt.

---

## 2. Core reframe

> **Control flow is code. Skills are content contracts.**

| Concern | Today | Proposed |
|---|---|---|
| What order things run in | prose in orchestrator skills | `workflowScript` |
| Who runs next when X finishes | prose "Turn-Exit Contract" | `Promise.race` / ready-set loop |
| Retry / escalation | prose escalation table | `for` loop with model swap |
| Proof a task is done | agent self-report + worklog prose | `gate:` command run by the host |
| Execution ledger | agent-authored `worklog.md` | workflow trace + `emit()` + mission `state` |
| What a good plan looks like | prose in `create-plan` skill | still a skill (correct) |
| What a good review looks like | prose in `review-*` skills | still a skill (correct) |

Skills survive where they define **quality of content**. Skills die where they define
**sequence of operations**.

---

## 3. Target extension set

Keep (7):

| Package | Why |
|---|---|
| `pi-subagents` | the execution engine; everything below assumes ≥ 0.50 |
| `pi-preset` | mode switching (`/preset discovery|design|execute`) |
| `pi-web-access` | research (`researcher` role, librarian skill) |
| `pi-hooks` | repo-local automation hooks |
| `pi-guardrails` | write-path safety |
| `pi-powerline-footer` | status surface, mutually exclusive with zentui |
| `pi-mcp-adapter` | MCP servers in use |
| `pi-agent-guidance` | **DECIDED: keep.** This is what injects `~/.pi/agent/CODEX.md` / `CLAUDE.md` / `GEMINI.md` per active provider, on top of Pi's own `AGENTS.md` loading. It is live right now — the provider-specific guidance block in the current session comes from it. |

Keep — quality of life (**DECIDED: keep all**):
`pi-btw`, `pi-auto-rename`, `pi-ding`, `pi-notify`, `pi-subdir-context`, `pi-ext-leader-key`

Remove (4):

| Package | Reason |
|---|---|
| `pi-messenger` | team mode is being removed; Crew is the thing that failed |
| `pi-prompt-template-model` | `pi-subagents` ships a native `/prompt-workflow` adapter |
| `pi-ext-review` | `reviewer` subagent + `review-code` skill covers it |
| `pi-interactive-shell` | overlapping delegation surface; `workflowScript` + `bash` covers the real cases |
| `pi-zentui` | already excluded (mutually exclusive with powerline) |
| `pi-gitnexus` | already excluded by default |

Net: 20 → 16 declared. Each removal is a `nix/modules/pi/config.nix` deletion plus a
`flake.nix` shape-check update plus a `tests/specs/pi-module-content-spec.sh` update.

---

## 4. Skill discoverability and the OpenCode boundary

**DECIDED: OpenCode is left byte-identical.** It has no code-mode concept and is not updated
this round. That constrains *how* skills are removed and hidden, because both harnesses render
from the same canonical source.

Two renderer facts govern this:

- `harnesses: [...]` frontmatter is **stripped at render time** ("applicability is build-time
  only"). Setting `harnesses: [opencode]` removes a skill from Pi while leaving
  `dist/skills/opencode/**` byte-identical.
- `disable-model-invocation:` is *not* stripped. Putting it in canonical frontmatter would leak
  into OpenCode output.

So:

**Retire from Pi, keep for OpenCode** — retag `harnesses: [opencode]`, do not delete:
`execution-orchestrator`, `execute-task`, `create-worklog`, `create-team-plan`,
`review-team-plan`, `create-team-worklog`, `execution-orchestrator-team`

OpenCode keeps its existing sequential + team process, unchanged and unrendered-differently.
Pi loses all of it.

**Delete outright (Pi-only already, no OpenCode consumer):**
`pi-team-plan`, `pi-team-lead`, `pi-team-worker`

**Small renderer change required.** To hide skills from Pi's system prompt without touching
OpenCode, add a per-harness `hiddenSkills: [...]` key to `harnesses/pi.json`; the renderer
injects `disable-model-invocation: true` only for harnesses that list the skill. ~15 lines in
`tools/render-skills.mjs` plus a `skill-content-spec.sh` assertion.

**Pi discoverable (4):** `discovery`, `design`, `dynamic-execute-plan` (new), `assess-repo`

**Pi slash-only (`/skill:<name>`):** `research`, `create-plan`, `review-plan`,
`review-approach`, `review-code`, `review-epic`, `configure-pi`, `configure-opencode`,
`create-skills`, `create-new-repo-docs`

Pi surface: 23 → 14 skills, 4 discoverable. OpenCode surface: unchanged (20).

---

## 5. The pattern library

The replacement for "sequential mode vs team mode" is a small library of named workflow
patterns, each a real `.js` file the parent embeds into `workflowScript`. They live in
`workflows/` and are documented in one doc, `docs/execution-patterns.md`.

**DECIDED: ship one engine now, not five patterns.**

P2 and P3 are not two engines — P2 is the wave engine with `maxWidth: 1` and the contract
phase skipped. Building P3 delivers both; building P2 alone delivers neither. P1 is a
one-task graph. So the build is: **one wave engine**, P4/P5 deferred.

| Pattern | Status this round |
|---|---|
| P1 Solo-gated | falls out as a 1-task graph; documented, no extra code |
| P2 Pipeline | **shipped** as the engine with `maxWidth: 1`, `contract: false` |
| P3 Wave swarm | **shipped** — the engine |
| P4 Fan-in analysis | deferred; `design`/`research` keep their current subagent calls |
| P5 Council | deferred; needs `runs.steer`, which is post-v0.50.0 |

Selection is by **shape of the work**, not by "how fast do I want it":

| Pattern | Use when | Parallelism |
|---|---|---|
| P1 Solo-gated | 1–3 tasks, one write-set, low risk | none |
| P2 Pipeline | tasks are strictly dependent (each needs the prior output) | none |
| P3 Wave swarm | tasks are mostly independent, contracts can be frozen up front | wide |
| P4 Fan-in analysis | research, multi-angle review, option comparison | wide, read-only |
| P5 Council | one hard decision, want adversarial pressure | wide + `steer` |

### API facts (verified by execution in T0 — see `spike.md`)

The first draft of these sketches was written against an imagined API. Corrected against source
and then **confirmed by running it** on the pinned build:

```ts
interface WorkflowScriptChildResult {
  key: string; ok: boolean; agent?: string; runId?: string;
  output: string; error?: string; detached?: boolean;
  structuredOutput?: unknown; artifactPaths: string[]; results?: unknown[];
}
```

- There is **no `status` field**. The success flag is `ok`. Observed keys at runtime:
  `artifactPaths, error, key, ok, output, results`.
- `runs.run` **throws** on failure — observed: `Run 'solo' failed: …`, with no value returned.
- `runs.all` collects `{ ok: false }` per child. **One failure does not reject the batch or harm
  siblings** — observed both children returning independently.
- Every launched promise must be awaited before return, or the workflow rejects
  (`scripted-workflow.ts:664`).
- Mission `state.set` / `state.get` round-trips. Missing keys return `undefined` and drop out of
  JSON serialization — read them defensively.

Consequence: **the engine uses `runs.all` for everything, including single tasks**, because it
is the only call shape that yields inspectable failures instead of an exception. `runs.run` is
reserved for steps where a throw genuinely should abort the run.

Agent names: this repo sets `subagents.disableBuiltins: true`, so the roster is
`worker`, `ui-worker`, `code-reviewer`, `plan-reviewer`, `planner`, `researcher`, `oracle`,
`vision`. There is no `reviewer`. Every child needs an **explicit `model`** — the flake default
is `zai-coding-plan/glm-5.2`, and an unresolvable model fails the child before it starts. Per-item
`context` is not in the documented item shape `{agent, task, worktree?, gate?}` — set `context`
at the top level only.

### P1 — Solo-gated (replaces "simple change")

A one-task graph through the same engine. No separate code path.

### P2 — Pipeline (replaces sequential plan execution)

The wave engine with `maxWidth: 1`. Same parent-driven loop as P3, one task per wave.

**Red-before-green in P2/P1.** P3 gets it free from a separate contract author. P2 does not,
and that is exactly the sequential work this repo does most. So P2 keeps a **mini contract
step**: when any task in the graph is class `contract`, one contract-author child runs before
the pipeline, authors the failing tests, and the parent commits them. Implementers never
author their own acceptance in any pattern.

### P3 — Wave swarm (replaces team mode)

**The wave loop lives in the parent, not inside one script.** T0 established two independent
reasons (see `spike.md` F5 and §5b): host verification cannot be delegated to a child `gate:`,
and any worktree patch application must happen between waves. Both require the parent to act
between waves, which a single long-running script cannot pause for.

So the engine is a parent-driven loop over **wave-sized workflow invocations**:

```
parent: Phase 0 — baseline gate on the host           (real bash, real exit code)
parent: Phase 1 — freeze         (one workflowScript invocation, 1 strong child)
parent: Phase 2 — contract       (one workflowScript invocation, 1–2 strong children)
parent: commit the red tests
loop:
  parent: compute ready set from the DAG + committed state
  parent: Phase 3 — ONE workflowScript invocation for that wave
  parent: run verification on the host
  parent: review + fix
  parent: commit wave checkpoint
parent: Phase 4 — final gate + fresh strong full-diff review
```

Each wave invocation is a small script. All it does is fan out and return:

```js
return runs.all(WAVE.map(t => ({
  key: "impl-" + t.id,
  agent: t.ui ? "ui-worker" : "worker",
  model: t.class === "complex" ? STRONG : CHEAP,   // explicit; no flake default
  task: t.brief,
  timeoutMs: t.timeoutMs                            // default is 30 min per child
})));
```

The parent then, in ordinary tool calls:

```
for each result:  r.ok ? accept : classify(r.error)
run the wave's verification command on the host
git commit the wave checkpoint
```

**Failure classification is the parent's job.** `r.ok === false` conflates several causes, and
the parent must separate them before spending a STRONG retry:

| `error` begins | Meaning | Action |
|---|---|---|
| `Acceptance rejected:` | paperwork, not necessarily bad work | inspect the diff before retrying |
| `Unknown subagent model` | config error | fix routing, do not retry |
| `Run fan-out: N/64` near cap | spawn ceiling | stop, escalate |
| anything else | real failure | one STRONG retry, then escalate |

Why this still beats team mode: the ready set is computed, not negotiated. No board, no claim
protocol, no lane discipline, no nudge policy. A stuck child is `{ ok: false }`, not a silent
member. What is given up versus the original sketch is fire-and-forget autonomy — the parent
stays in the loop. What is gained is verification by real host execution the parent observes
directly, continuous integration, and commits at every wave boundary.

**Known limits** (verified): per-child default timeout is 30 minutes; `maxSubagentSpawnsPerRun`
defaults to 64, is never refunded, and is reported per run (`Run fan-out: 2/64 used`). Both must
be documented in `docs/execution-patterns.md`.

---

## 5b. Integration model: shared tree, not worktrees

**DECIDED: `worktree: false` is the default.** This is the single most important correction
from review.

`worktree: true` looked like free parallel-write safety. Verified, it is not:

- Nothing applies patches back. Only `worktree.discard` exists in the tool schema
  (`schemas.ts:275`); there is no `worktree.apply`. The child captures
  `git diff --cached <base>` to a patch file and leaves it in `artifactPaths`.
- The script **cannot** apply them — the sandbox is `vm.createContext` with no fs, shell, or
  host globals (`scripted-workflow.ts:387`).
- So "Phase 4: parent reviews the full diff" describes a diff that does not exist. The host
  tree contains none of the children's work.
- Worse, **cross-wave dependencies break**: wave N+1 children branch from a HEAD without wave
  N's work. Fixing that requires parent apply+commit *between* waves, which a single workflow
  invocation cannot pause for.
- The original note "worktree: true when write-sets collide" was backwards. Colliding
  write-sets are where worktrees defer an N-way textual conflict to the parent. Disjoint
  write-sets are where a shared tree is already safe.
- Per-child gates run *inside* the child's worktree, so green gates prove nothing about
  integration.

Shared tree instead: file ownership from `tasks.json` `writes`, every gate runs against the
accumulated tree (continuous integration for free), cross-wave deps work, and resume sees real
state. Worktrees stay available as an opt-in for genuinely risky wide waves, and if that is
ever taken it becomes one workflow invocation per wave with a parent apply+commit step — a
different architecture that must be costed separately.

### Verification is parent-run, not a child `gate:`

The first draft made per-child `gate:` the proof-of-done. **T0 proved that does not work.**

`gate:` normalizes to `acceptance: { level: "verified", … }`, and the acceptance layer
validates the child's structured evidence report and short-circuits *before* the host gate
result is consulted. `gate: "true"` and `gate: "false"` were indistinguishable across three
successive rejection layers (`Structured acceptance report not found` → `Required criterion
'criterion-1' was not reported` → `commands-run evidence missing from child report`). It is not
tunable: `acceptance.ts:384` computes evidence as the *union* of the level minimum and anything
explicit, so `evidence: []` cannot reduce it.

The practical failure mode: a cheap worker that does the work correctly but writes a sloppy
report fails the run, and the parent cannot tell that apart from bad code without
string-matching the error.

So the parent runs verification itself, on the host, between waves — real bash, real exit
codes, directly observed. Child `gate:` may still be used opportunistically on high-value
single children, but nothing in the process depends on it.

**Frozen-test protection moves with it.** The concern is unchanged — a cheap worker can edit the
contract test until it passes — but the check now runs where it actually executes, as part of
the parent's wave verification:

```
git diff --exit-code <contract-commit> -- <test-paths> && <wave verification command>
```

and "diff test files against the frozen baseline" stays on the reviewer checklist.

---

## 5c. What replaces `worklog.md`

**DECIDED: `worklog.md` and `create-worklog` are retired from Pi** (retained for OpenCode).

The worklog existed to make a ralph loop resumable and observable. Both needs survive; the
prose file does not. Three mechanisms replace it, and each is strictly more durable because
none of them depend on an agent remembering to write a file:

**Revised after T0.** With the wave loop in the parent, the primary resume mechanism is the
**wave-boundary git commit**, not mission `state`. State is a useful secondary record (verified
working: `set`/`get` round-trips, mission-scoped JSON on disk, 256 KiB cap) but it is no longer
load-bearing, which removes the partial-work hazard below as a single point of failure.

| Worklog job | Replacement | Durability |
|---|---|---|
| "what is done, what is next" across a crash | the last wave checkpoint commit; `state.set("done", [...])` as a secondary cross-check | git, plus mission-scoped JSON |
| live progress during the loop | `emit({ wave, done, failed })` streams to the parent; FleetView shows children | in-flight |
| durable record of what happened | parent writes `run-summary.md` **once at the end** and commits it with the work | git |
| per-task evidence | `gate` results recorded as `evidenceStatus: verified` by the runtime | run artifacts |

The resume story is better than the worklog's, but **not** as originally claimed. Verified:
mission state is genuinely durable — atomic write per `set` under a file lock, merge-latest,
256 KiB cap (`src/missions/workflow-state.ts:13,222,251-253`), stored under
`~/.pi/agent/missions/projects/<hash>/<id>/state.json`, so it survives session loss.

**The partial-work hazard.** A mid-wave crash aborts in-flight children but leaves their edits
on disk. Resuming would relaunch those tasks on top of their own orphaned partial edits, and a
retry could pass verification against a predecessor's half-work. Per-wave invocation bounds
this to a single wave's worth of damage, and the wave-boundary commit gives an exact,
inspectable rollback point (`git reset --hard` to the last checkpoint).

Three mitigations, all required:

1. `dynamic-execute-plan` performs **resume-time reconciliation**: check `git status` before
   relaunching a wave, and apply a stated discard/keep policy for uncommitted partial edits.
   Default is discard-to-last-checkpoint, since the wave will be re-run in full.
2. Record completed task IDs to `state` at each wave boundary as a cross-check against the
   commit log.
3. Never resume into a dirty tree without an explicit decision.

One real loss to accept: the worklog's free-text "issues encountered / deviations" narrative.
That moves into `run-summary.md` and, when it should outlive the plan, `docs/issues_learnings.md`.

---

## 6. Slimmed plan

`plan.md` keeps only what the human approver needs:

```markdown
# Plan: <slug>
Pattern: P3 (wave swarm) | Waves: 3 | Tasks: 11 | Est. width: 4

## What changes
## What must not break
## Risks that could stop this
## Frozen decisions (only ones NOT already in approach.md)
## Task graph            <- the table; one row per task
## Verification          <- final gate command, from docs/testing-strategy.md
## Open questions        <- must be empty before approval
```

Everything else is deleted: goals/non-goals (brief), context/constraints/assumptions
(approach), decision table (approach), coverage matrix (folded into per-task acceptance),
baseline gate audit (a command the workflow runs, not a table a human fills), progress log /
evidence ledger / deviations / issues (workflow trace), requirement update table (a task row).

Alongside it, the plan emits `tasks.json` — the machine input:

```json
{
  "pattern": "P3",
  "maxWidth": 4,
  "finalGate": "./tests/run-tests.sh all",
  "tasks": [
    {
      "id": "T3",
      "brief": "…self-contained instruction, no plan.md read required…",
      "deps": ["T1"],
      "writes": ["nix/modules/pi/config.nix"],
      "class": "mechanical",
      "verification": "check",
      "acceptance": "…observable statement…",
      "gate": "bash tests/specs/pi-module-content-spec.sh"
    }
  ]
}
```

**Embedding constraints** (verified: sandbox has no fs/shell/host globals,
`scripted-workflow.ts:387`). The parent must embed `tasks.json` as a JS literal, so:

- embed via exact `JSON.stringify` output only — a stray quote or backtick in a task string
  is a syntax error that kills the whole workflow;
- briefs carry **paths, never file contents** (children read files themselves), which also
  bounds prompt size as task count grows;
- a **drift check is mandatory**: a spec asserting `plan.md` task IDs ≡ `tasks.json` task IDs.
  Splitting human prose from machine graph *will* drift otherwise — this repo already
  drift-tests `dist/` for exactly this reason.

`tasks.json` and a fenced block inside `plan.md` satisfy the no-fs constraint equally; the
separate file is chosen for schema validation, and the drift check is what makes it safe.

Also retained from the old template: a **baseline gate status** line. Phase 0 records it, so a
pre-existing red gate is never misattributed to a child.

`workflowScript` has **no filesystem access** — the parent reads `tasks.json` with the `read`
tool and embeds it as a literal in the script. This is a hard constraint on the design and the
reason the graph must be a separate machine-readable file rather than parsed out of prose.

Target: plan template drops from 201 lines to ~50, and each task's `brief` becomes the only
context a cheap implementer needs.

---

## 7. Verification policy (replaces TDD-everywhere)

Each task declares a **verification class**. This replaces the uniform TDD checklist.

| Class | When | What the implementer does | `gate` |
|---|---|---|---|
| `contract` | new/changed observable behaviour | make the pre-authored failing test pass | the contract test command |
| `characterization` | refactor, no behaviour change | keep existing tests green | existing suite, scoped |
| `check` | config, wiring, generated artifacts, schema | make the structural check pass | renderer/schema/spec command |
| `none` | prose-only docs with no structural contract | nothing | repo's existing docs spec, unchanged |

Rules:

1. **Anti-tautology rule.** A test must be able to fail due to a change in the behaviour or
   artifact the task modifies, **without a manual edit of the oracle**. If it cannot, it is a
   `check`, not a `contract` — or it is nothing.
   (The earlier phrasing — "fail for a reason other than someone editing the file the test
   reads" — mis-keys the causal link: a test reading a *generated* file such as `dist/` cannot
   fail when only the canonical source changes, which is the change that matters. This is a
   reviewer checklist item, not a class-demoting axiom, and it carries the same self-graded
   character §1.5 objects to in break-it. Keep it honest about that.)
2. **Contract-first, not test-first-per-task.** Tests are authored by a different agent than
   the implementer — P3 Phase 2, or P2's mini contract step. Red-before-green is observed once,
   by the author, with evidence. Implementers never author their own acceptance in any pattern.
3. **Break-it is removed as a mandatory per-task step.** It survives only as a *reviewer-
   initiated, risk-triggered* option when a reviewer suspects a test does not constrain
   anything. It is never self-administered by the implementer.
4. **The gate is host-run by the parent.** Verification executes in the parent's own shell
   between waves, not through a child `gate:` — see §5b for why the child-side mechanism cannot
   carry this. `contract`-class verification additionally asserts the test files are unchanged
   from the frozen baseline.
5. **`none` is a legitimate answer** and must be explicitly chosen, not defaulted into.

Consequence for this repo specifically: doc-only tasks stop generating tests. The existing
`tests/specs/repo-readiness-docs-spec.sh` remains the structural check for routing/anchors,
which is a real check — it fails when a route is missing, not when prose changes.

---

## 8. Prerequisites and risks

| Item | Detail |
|---|---|
| **Version pin — DONE (T1 + T0)** | Pinned to `3847deeaa6e814c328ff4964fc28d7c2e6f9fc9b` (main). **Not the v0.50.0 tag**: that release's workflow engine hard-requires `node:v8 promiseHooks.createHook`, which Bun-built Pi 0.84.2 does not implement, so every `workflowScript` call fails outright. The pin carries `19a4e60` (Bun fallback) and `b6a69ec` (acorn manifest resolution). Accepted risk: unreleased main; revisit at 0.51.0. |
| **Vendored deps — DONE** | 0.50.0 added `yaml@2.8.3`; the Bun fix added `acorn@8.18.0`. Both now in `managed-packages/package.json`. Without `yaml` the extension does not load at all. The pi manifest entrypoint also moved to `./index.ts`. |
| **Peer compatibility** | requires `@earendil-works/pi-ai >= 0.80.0`; the flake ships Pi 0.84.2. Verified by a clean `pi doctor` load in the sandbox. |
| **`gate:` cannot carry verification** | Verified negative in T0. Acceptance-evidence validation short-circuits before the gate command result is consulted, and is not tunable. Verification is parent-run on the host between waves — see §5b. |
| **Breaking API change** | 0.50 removed top-level `chain` / `tasks` / `parallel`. Single `{agent, task}` **is still supported**, so the `{{delegate:...}}` macro and `harnesses/pi.json` role map keep working unchanged. Only the new engine uses `workflowScript`. Much smaller than first assessed. |
| **OpenCode** | **DECIDED: untouched.** Enforced by `harnesses: [opencode]` retagging plus per-harness `hiddenSkills` in the renderer, so `dist/skills/opencode/**` stays byte-identical. T13 asserts this against `main`. |
| **Script trust** | `workflowScript` is trusted inline JS with no fs/shell/host globals. Scripts must be repo-reviewed artifacts, not model-improvised strings, or the determinism benefit is lost. |
| **Worktrees** | Default off. Nothing applies patches back (`worktree.discard` exists, `worktree.apply` does not), and the script cannot. See §5b. |
| **Cheap-model ceiling** | Two mechanisms: a task that is not decision-complete, and a child that does the work but fails the acceptance-report contract. The parent must classify `Acceptance rejected:` separately from real failure before spending a STRONG retry. Frequency is unmeasured — instrument during the first real wave (`spike.md` F7). |
| **Budget guidance** | Do **not** set `turnBudget` / hard `toolBudget` / tight `usageBudget` on writers. Bound writers with `timeoutMs` and narrow tasks. Hard caps only on read-only children. Per-child default timeout is 30 min; `maxSubagentSpawnsPerRun` is 64 and never refunded. |
| **Model routing** | Every engine child needs an explicit `model`. The flake default (`zai-coding-plan/glm-5.2`) is not resolvable in every environment and fails the child before it starts. |

---

## 9. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | OpenCode | **`dist/skills/opencode/**` stays byte-identical.** Scoped to dist bytes only — shared canonical docs will describe code-mode, and retained OpenCode-only skills keep their legacy TDD contract inside the skill itself. T10 must route Pi-only wording through `{{note:}}` macros or it violates this. |
| 2 | Pattern count | **One wave engine.** P3 is the engine, P2 is `maxWidth: 1`, P1 is a 1-task graph. P4/P5 deferred. |
| 3 | Worklog | **Retire from Pi.** Replaced by mission `state` (resume), `emit` (live), `run-summary.md` (durable). |
| 4 | Plan approval gate | **Keep the human stop** between plan and execution. |
| 5 | Extensions | Keep all QoL (`pi-btw`, `pi-auto-rename`, `pi-ding`, `pi-notify`, `pi-subdir-context`, `pi-ext-leader-key`) and `pi-agent-guidance` (it is live — provider-specific `CODEX.md`/`CLAUDE.md` loading). Remove 4: `pi-messenger`, `pi-prompt-template-model`, `pi-ext-review`, `pi-interactive-shell`. |
| 6 | Requirements / backlog | **No change.** Orthogonal. |
| 7 | Sequencing | **One branch, one pass.** No staged layers. |

---

## 10. Work breakdown (single branch)

Branch: `code-mode-process`. Revised after oracle review: added T0 (spike), split out the
wiring tasks the first draft silently assumed, and moved the integration decision earlier.

| # | Task | Deps | Class |
|---|---|---|---|
| ~~T1~~ **done** | Pin → `3847dee`; vendor `yaml` + `acorn`; entrypoint `./index.ts`; fix `pi-vendor-spec` comment-blindness | — | check |
| ~~T0~~ **done** | SPIKE — findings in `spike.md`. Changed the pin and moved verification to the parent. | T1 | — |
| T2 | Remove 4 extensions from `config.nix`; update `flake.nix` shape checks + `pi-module-content-spec.sh` | — | check |
| T3 | Delete `.pi/messenger/`, `config/pi-team/team-profile.json`, `agents/pi-team-reviewer.md`, `docs/pi-team-setup.md` | T2 | check |
| **T3b** | **Wiring:** remove the messenger/team-profile symlink from `makePiConfig`; drop `pi-team-reviewer` from the `piAgents` roster; rewrite the `pi-module-content-spec.sh` assertions that currently *require* those (lines ~43–56) | T3 | check |
| T4 | Renderer: per-harness `hiddenSkills` → inject `disable-model-invocation` | — | contract |
| T5 | Retag 7 skills `harnesses: [opencode]`; delete 3 `pi-team-*` skills | T4 | check |
| **T5b** | **Wiring:** update the `piSkills` roster in `config.nix` (17 explicit names; retagged skills would otherwise become dangling symlinks that `ln -s` creates without error) | T5 | check |
| T6 | Wave engine + `docs/execution-patterns.md`: parent-driven loop, per-wave `workflowScript` invocation, `runs.all` + `!r.ok`, explicit per-child model, parent-run host verification, error-classification table, documented 30-min/64-spawn limits | T0 | contract |
| T7 | New `dynamic-execute-plan` skill (discoverable): reads `tasks.json`, embeds via `JSON.stringify`, Phase 0 baseline, per-wave verify + commit, resume-time `git status` reconciliation | T6 | check |
| T8 | Slim `plan-template.md` 201 → ~50 lines; `tasks.json` schema; update `create-plan` | — | check |
| **T8b** | **Drift check:** spec asserting `plan.md` task IDs ≡ `tasks.json` IDs | T8 | contract |
| T9 | Rewrite `docs/testing-strategy.md` verification classes; remove mandatory break-it | — | check |
| T10 | Update `review-plan` / `review-code` for classes, anti-tautology rule, frozen-test-diff check — **via `{{note:}}` macros to preserve OpenCode dist bytes** | T9 | check |
| T11 | Rewrite `docs/process.md` §4B–8B; delete `docs/team-mode-execution.md`; supersede ADR 0002/0003; add ADR 0004 | T3, T6 | check |
| **T11b** | Update `docs/orchestration.md` (three-mode contract; never mentioned in the first draft) and `docs/coding-rules.md` break-it references | T11 | check |
| T12 | Update `AGENTS.md` routes, `plans/README.md`, `agents/preset.jsonc` execute preset, `agents/planner.md` + `agents/code-reviewer.md` TDD wording | T11b | check |
| T13 | `node tools/render-skills.mjs --write`; commit `dist/`; assert OpenCode dist unchanged vs `main` | T5b, T7, T10 | check |
| T14 | Final gate `./tests/run-tests.sh all` + `./scripts/pi-dev.sh --verify` | all | — |

18 tasks; **T0 and T1 are complete**. T2/T4/T8/T9 are independent. Dogfood the engine on
T8–T12 only after T6 lands clean.
