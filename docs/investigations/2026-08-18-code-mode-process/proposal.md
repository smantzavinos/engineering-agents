# Proposal: Code-Mode Execution Process

- Date: 2026-08-18
- Status: draft for discussion (no implementation yet)
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

**Pi discoverable (4):** `discovery`, `design`, `execute-plan` (new), `assess-repo`

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

### API correction (oracle review, verified against source)

The first draft of these sketches was written against an imagined API. Verified against
`pi-subagents@c091da1` (`src/workflows/scripted-workflow.ts:464-476`):

```ts
interface WorkflowScriptChildResult {
  key: string; ok: boolean; agent?: string; runId?: string;
  output: string; error?: string; detached?: boolean;
  structuredOutput?: unknown; artifactPaths: string[]; results?: unknown[];
}
```

- There is **no `status` field**. The success flag is `ok`.
- `runs.run` **throws** on failure (`scripted-workflow.ts:845-849`: `deliver` wraps with
  `collectFailure` false and raises ``Run '<key>' failed: …``). An uncaught throw ends the
  workflow and aborts in-flight siblings.
- `runs.all` sets `collectFailure: true` per item, so each child resolves independently as
  `{ ok: false }`. **One failure does not reject the batch or harm siblings.**
- Every launched promise must be awaited before return, or the workflow rejects
  (`scripted-workflow.ts:664`).

Consequence: **the engine uses `runs.all` for everything, including single tasks**, because it
is the only call shape that yields inspectable failures instead of an exception. `runs.run` is
reserved for steps where a throw genuinely should abort the run.

Agent names: this repo sets `subagents.disableBuiltins: true`, so the roster is
`worker`, `ui-worker`, `code-reviewer`, `plan-reviewer`, `planner`, `researcher`, `oracle`,
`vision`. There is no `reviewer`. Per-item `context` is not in the documented item shape
`{agent, task, worktree?, gate?}` — set `context` at the top level only.

### P1 — Solo-gated (replaces "simple change")

A one-task graph through the same engine. No separate code path.

### P2 — Pipeline (replaces sequential plan execution)

The wave engine with `maxWidth: 1`. Tasks run in dependency order, each gated, each reviewed,
with one bounded retry:

```js
const [r] = await runs.all([{
  key: "t" + t.id, agent: t.agent, task: t.brief, gate: t.gate
}]);
if (!r.ok) {
  const [retry] = await runs.all([{
    key: "t" + t.id + "-retry", agent: "worker", model: STRONG,
    task: "Previous attempt failed:\n" + (r.error ?? r.output) + "\n\nTask:\n" + t.brief,
    gate: t.gate
  }]);
  if (!retry.ok) { emit({ task: t.id, escalate: true }); break; }
}
```

**Red-before-green in P2/P1.** P3 gets it free from a separate contract author. P2 does not,
and that is exactly the sequential work this repo does most. So P2 keeps a **mini contract
step**: when any task in the graph is class `contract`, one contract-author child runs before
the pipeline, authors the failing tests, and the parent commits them. Implementers never
author their own acceptance in any pattern.

### P3 — Wave swarm (replaces team mode)

Four phases. **Phase 0 is new** — without a recorded baseline, a pre-existing red gate is
discovered mid-wave and misattributed to a child.

**Phase 0 — Baseline.** Parent runs the final gate on the host and records status. A red
baseline stops the run or is explicitly accepted.

**Phase 1 — Freeze (1 strong agent, serial).** Architect child returns structured output: the
interface surface, the task graph with write-sets, acceptance per task. Expensive thinking,
done once.

**Phase 2 — Contract (1–2 strong agents, parallel).** Test authors write executable acceptance
into test files nobody else owns, run them, record red. **The parent then commits the red
tests before Phase 3 launches.** Uncommitted contract tests are invisible to worktree children
and poison gate memoization in shared-tree mode.

**Phase 3 — Waves (N cheap agents, parallel).** Ready set from the DAG, launched with
`runs.all`, each child file-owned and gated on its own contract command.

```js
const done = new Set(await state.get("done") ?? []);   // resume
let remaining = TASKS.filter(t => !done.has(t.id));

while (remaining.length) {
  const ready = remaining.filter(t => t.deps.every(d => done.has(d)));
  if (!ready.length) throw new Error("stuck: " + remaining.map(t => t.id).join(","));

  const wave = ready.slice(0, MAX_WIDTH);
  const results = await runs.all(wave.map(t => ({
    key: "impl-" + t.id,
    agent: t.ui ? "ui-worker" : "worker",
    model: t.class === "complex" ? STRONG : CHEAP,
    task: t.brief,
    gate: t.gate,                 // self-defending; see 5b
    timeoutMs: t.timeoutMs        // default is 30 min per child; long tasks must opt up
  })));

  const ok = results.filter(r => r.ok);
  const failed = results.filter(r => !r.ok);

  const reviews = await runs.all(ok.map((r, i) => ({
    key: "rev-" + wave[i].id, agent: "code-reviewer",
    task: "Review against acceptance:\n" + wave[i].acceptance + "\n\n" + r.output
  })));

  for (const r of ok) done.add(r.key.replace("impl-", ""));
  await state.set("done", [...done]);        // per-wave checkpoint
  await state.set("artifacts", ARTIFACTS);   // per-child paths, for crash recovery

  if (failed.length) { /* one STRONG retry each, then escalate */ }
  remaining = remaining.filter(t => !done.has(t.id));
  emit({ done: done.size, failed: failed.length });
}
```

**Phase 4 — Integration.** Parent runs the final gate on the host, launches one fresh strong
reviewer over the full diff, and commits. Children never commit.

Why this beats team mode: the ready set is computed, not negotiated. No board, no claim
protocol, no lane discipline, no nudge policy. A stuck child is `{ ok: false }`, not a silent
member.

**Known limits** (verified): per-child default timeout is 30 minutes
(`async-execution.ts:139`); `maxSubagentSpawnsPerRun` defaults to 64 and claims are never
refunded, so at ~4 spawns/task a run caps near 16 tasks. Both must be documented in
`docs/execution-patterns.md`.

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

### Self-defending gates

The gate is host-run and a child cannot fake its result (`acceptance.ts:164`). But nothing
stops a cheap worker from **editing the contract test** until it passes. File ownership stated
in a task brief is prose an LLM must obey — precisely the failure mode §1.1 diagnoses in team
mode, reintroduced at the one boundary that matters most.

So every `contract`-class gate is compiled as:

```
git diff --exit-code <contract-commit> -- <test-paths> && <test command>
```

and "diff test files against the frozen baseline" goes on the reviewer checklist.

---

## 5c. What replaces `worklog.md`

**DECIDED: `worklog.md` and `create-worklog` are retired from Pi** (retained for OpenCode).

The worklog existed to make a ralph loop resumable and observable. Both needs survive; the
prose file does not. Three mechanisms replace it, and each is strictly more durable because
none of them depend on an agent remembering to write a file:

| Worklog job | Replacement | Durability |
|---|---|---|
| "what is done, what is next" across a crash | `state.set("done", [...])` after each wave; on restart `state.get("done")` and skip completed tasks | mission-scoped JSON on disk, survives session loss, 256 KiB cap |
| live progress during the loop | `emit({ wave, done, failed })` streams to the parent; FleetView shows children | in-flight |
| durable record of what happened | parent writes `run-summary.md` **once at the end** and commits it with the work | git |
| per-task evidence | `gate` results recorded as `evidenceStatus: verified` by the runtime | run artifacts |

The resume story is better than the worklog's, but **not** as originally claimed. Verified:
mission state is genuinely durable — atomic write per `set` under a file lock, merge-latest,
256 KiB cap (`src/missions/workflow-state.ts:13,222,251-253`), stored under
`~/.pi/agent/missions/projects/<hash>/<id>/state.json`, so it survives session loss.

**The partial-work hazard the first draft missed.** State resumes at wave boundaries; the
*working tree does not*. On a mid-wave crash, in-flight children are aborted but their edits
are already on disk, while `state` still says the wave is unfinished. Resume then relaunches
those tasks on top of their own orphaned partial edits — and a retry can pass its gate against
a predecessor's half-work. Gate memoization makes this worse: "an unchanged tree does not
rerun the same command", so a no-op retry can be marked verified.

Three mitigations, all required:

1. Record **per-child** completion to `state` as each child resolves, not per-wave.
2. `execute-plan` performs **resume-time reconciliation**: check `git status` before
   relaunching, and apply a stated discard/keep policy for uncommitted partial edits.
3. The engine must actually call `state.get("done")` at startup. The first draft's skeleton
   declared `const done = new Set()` and never read state — the headline durability claim
   existed only in prose.

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
4. **The gate is host-run and self-defending.** `gate:` executes on the host and child-reported
   success does not count (`acceptance.ts:164`). `contract`-class gates additionally assert the
   test files are unchanged from the frozen baseline — see §5b.
5. **`none` is a legitimate answer** and must be explicitly chosen, not defaulted into.

Consequence for this repo specifically: doc-only tasks stop generating tests. The existing
`tests/specs/repo-readiness-docs-spec.sh` remains the structural check for routing/anchors,
which is a real check — it fails when a route is missing, not when prose changes.

---

## 8. Prerequisites and risks

| Item | Detail |
|---|---|
| **Version bump required** | `nix/modules/pi/config.nix` pins `pi-subagents` at commit `c940fe20` (v0.34.0). `workflowScript` requires ≥ 0.50.0. This is the gating prerequisite for everything above. |
| **Breaking API change** | 0.50 removed top-level `chain` / `tasks` / `parallel`. The `{{delegate:...}}` macro and `harnesses/pi.json` role map must be re-expressed. Single `{agent, task}` still works, so the minimum migration is small; the recommended migration is workflowScript everywhere. |
| **OpenCode divergence** | `workflowScript` is Pi-only. The render pipeline currently produces both. Either OpenCode skills keep the prose orchestration (drift), or OpenCode support for execution patterns is explicitly dropped and `harnesses/opencode.json` covers only the content skills. **Needs your decision.** |
| **Script trust** | `workflowScript` is trusted inline JS with no fs/shell. Scripts must be repo-reviewed artifacts under `workflows/`, not model-improvised strings, or the determinism benefit is lost. |
| **Worktree cost** | `worktree: true` requires clean git state and branches per child. Good for wide waves, overhead for narrow ones. Default it off; enable when the plan declares colliding write-sets. |
| **Cheap-model ceiling** | The swarm assumes a frozen contract makes tasks decision-complete. Where it isn't, cheap workers fail the gate and cost a strong retry. Mitigate by making phase 1 return the interface surface explicitly, and by classing tasks `mechanical` / `standard` / `complex` in `tasks.json`. |
| **Budget guidance** | Per upstream docs: do **not** set `turnBudget` / hard `toolBudget` / tight `usageBudget` on writers. Bound writers with `timeoutMs` and narrow tasks. Hard caps only on read-only children (P4). |

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
| T1 | Bump `pi-subagents` pin to v0.50.0+ (`c091da1…`, or a post-release commit carrying the acorn parser-entry fix), update `installSpec` + hashes | — | check |
| **T0** | **SPIKE — execute a real `workflowScript` on the pinned install.** Verify: `runs.run` throw shape, `runs.all` `{ok:false}` collection, gate pass/fail → `evidenceStatus`, mission `state` kill/resume, per-child timeout, spawn budget. Write findings to `spike.md`. **T6 does not start until this exists.** | T1 | — |
| T2 | Remove 4 extensions from `config.nix`; update `flake.nix` shape checks + `pi-module-content-spec.sh` | — | check |
| T3 | Delete `.pi/messenger/`, `config/pi-team/team-profile.json`, `agents/pi-team-reviewer.md`, `docs/pi-team-setup.md` | T2 | check |
| **T3b** | **Wiring:** remove the messenger/team-profile symlink from `makePiConfig`; drop `pi-team-reviewer` from the `piAgents` roster; rewrite the `pi-module-content-spec.sh` assertions that currently *require* those (lines ~43–56) | T3 | check |
| T4 | Renderer: per-harness `hiddenSkills` → inject `disable-model-invocation` | — | contract |
| T5 | Retag 7 skills `harnesses: [opencode]`; delete 3 `pi-team-*` skills | T4 | check |
| **T5b** | **Wiring:** update the `piSkills` roster in `config.nix` (17 explicit names; retagged skills would otherwise become dangling symlinks that `ln -s` creates without error) | T5 | check |
| T6 | Wave engine `workflows/wave.js` + `docs/execution-patterns.md`; shared-tree default, self-defending gates, per-child state, documented 30-min/64-spawn limits | T0 | contract |
| T7 | New `execute-plan` skill (discoverable): reads `tasks.json`, embeds via `JSON.stringify`, runs Phase 0 baseline, performs resume-time `git status` reconciliation | T6 | check |
| T8 | Slim `plan-template.md` 201 → ~50 lines; `tasks.json` schema; update `create-plan` | — | check |
| **T8b** | **Drift check:** spec asserting `plan.md` task IDs ≡ `tasks.json` IDs | T8 | contract |
| T9 | Rewrite `docs/testing-strategy.md` verification classes; remove mandatory break-it | — | check |
| T10 | Update `review-plan` / `review-code` for classes, anti-tautology rule, frozen-test-diff check — **via `{{note:}}` macros to preserve OpenCode dist bytes** | T9 | check |
| T11 | Rewrite `docs/process.md` §4B–8B; delete `docs/team-mode-execution.md`; supersede ADR 0002/0003; add ADR 0004 | T3, T6 | check |
| **T11b** | Update `docs/orchestration.md` (three-mode contract; never mentioned in the first draft) and `docs/coding-rules.md` break-it references | T11 | check |
| T12 | Update `AGENTS.md` routes, `plans/README.md`, `agents/preset.jsonc` execute preset, `agents/planner.md` + `agents/code-reviewer.md` TDD wording | T11b | check |
| T13 | `node tools/render-skills.mjs --write`; commit `dist/`; assert OpenCode dist unchanged vs `main` | T5b, T7, T10 | check |
| T14 | Final gate `./tests/run-tests.sh all` + `./scripts/pi-dev.sh --verify` | all | — |

18 tasks. T1→T0 is a hard serial prefix; T2/T4/T8/T9 are independent after that. Dogfood the
engine on T8–T12 only if T0 and T6 both came back clean.
