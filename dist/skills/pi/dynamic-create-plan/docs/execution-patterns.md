# Execution Patterns (Dynamic Workflow)

How implementation work is executed by the installed dynamic-workflow skills. Orchestration
is **code**, not prose instructions an agent must obey: scheduling, readiness, retry, and
escalation are ordinary JavaScript in a `workflowScript`, run through the `subagent` tool.

The workflow is **dynamic**: the composition of each wave is computed at run time from the
task graph and what has actually completed, rather than following a fixed pipeline decided in
advance. That is the distinction from the sequential OpenCode pipeline, and it is why the Pi
skills carry a `dynamic-` prefix:

| Sequential (OpenCode) | Dynamic (Pi) |
|---|---|
| `create-plan` | `dynamic-create-plan` |
| `review-plan` | `dynamic-review-plan` |
| `review-code` | `dynamic-review-code` |
| `execution-orchestrator` | `dynamic-execute-plan` |

"Code mode" is the underlying mechanism (`workflowScript`); "dynamic workflow" is what this
repo calls the process built on it. Both pipelines are supported; they do not share files.

This replaces the retired team mode (`pi-messenger` Crew). Its design investigation remains
in the engineering-agents source repository; it is provenance, not a target-repository input.

## The one engine

There is a single wave engine. It is packaged alongside each dynamic skill and is not expected
in the target repository. Patterns are configurations of it, not separate code paths:

| Pattern | Configuration | Use when |
|---|---|---|
| Solo | 1-task graph | one small change, one write-set |
| Pipeline | `maxWidth: 1` | tasks are strictly dependent |
| Wave swarm | `maxWidth: N` | tasks are mostly independent and contracts can be frozen |

## The loop lives in the parent

**The parent drives the loop and invokes one `workflowScript` per wave.** It does not hand the
whole plan to a single long-running script. Two independently verified constraints force this:

1. **Verification cannot be delegated to a child.** `gate:` implies acceptance level
   `verified`, whose structured-evidence validation short-circuits *before* the gate command's
   result is consulted, and is not tunable (evidence is a union with the level minimum). In
   testing, `gate: "true"` and `gate: "false"` were indistinguishable.
2. **Nothing applies worktree patches back.** `worktree.discard` exists; `worktree.apply` does
   not, and the script sandbox has no filesystem or shell access.

Both require the parent to act between waves, which a single script cannot pause for.

```
parent: baseline verification on the host
parent: freeze          — 1 strong child returns the interface surface + task graph
parent: contract        — 1–2 strong children author failing tests
parent: commit the red tests
loop:
  parent: compute the ready set from the DAG
  parent: write the wave script under <plan-dir>/waves/ (or dataflow.js for a DAG run)
  parent: ONE workflowScript invocation, sourced from that file
  parent: run verification on the host
  parent: review, then fix
  parent: commit the wave checkpoint
parent: final gate + fresh strong full-diff review
```

## Orchestration scripts are plan artifacts

An inline `workflowScript` argument is not a record. Before every launch, the parent writes
the exact script body into the plan directory and launches that file:

| Engine | Path |
|---|---|
| Attended DAG (`dynamic-execute-dag-plan`) | `<plan-dir>/dataflow.js` |
| Wave loop (`dynamic-execute-plan`) | `<plan-dir>/waves/wave-NN.js` |
| DAG fix/resume rounds | `<plan-dir>/dataflow.retry-N.js` or `dataflow.resume.js` |

Do not launch until that file exists. If the human has not approved this script, stop and
give them the path. Do not invent a second inline copy that can drift from the file.
See [Plan Directory Structure](plan-directory-structure.md) for the artifact list.

## The wave invocation

Each wave script only fans out and returns:

```js
return runs.all(WAVE.map(t => ({
  key: "impl-" + t.id,
  agent: t.ui ? "ui-worker" : "worker",
  model: t.class === "complex" ? STRONG : CHEAP,
  task: t.brief,
  timeoutMs: t.timeoutMs
})));
```

Non-negotiable rules, all verified against the runtime:

- **Use `runs.all`, never `runs.run`, for task fan-out — including single-task waves.**
  `runs.run` *throws* on child failure, aborting the workflow and its in-flight siblings.
  `runs.all` returns `{ ok: false }` per child and leaves siblings alone.
- **Branch on `ok`.** There is no `status` field. Result keys are
  `artifactPaths, error, key, ok, output, results`.
- **Set `model` explicitly on every child.** An unresolvable default fails the child before it
  starts.
- **Never set `turnBudget`, a hard `toolBudget`, or a tight `usageBudget` on a writer.** Bound
  writers with `timeoutMs` and a narrow task. Hard caps are for read-only children only.
- **Do not define nested `async function` helpers, async arrows, or async methods** inside a
  script; they are rejected. Use top-level `await`, plain helpers, or Promise chains.
- **Await every launched promise** before returning, or the workflow rejects.
- The parent embeds task data with exact `JSON.stringify` output. Briefs carry **paths, never
  file contents** — children read files themselves.

## Failure classification is the parent's job

`ok === false` conflates several causes. Classify before spending a retry:

| `error` begins | Meaning | Action |
|---|---|---|
| `Acceptance rejected:` | paperwork, not necessarily bad work | inspect the diff before retrying |
| `Unknown subagent model` | configuration error | fix routing; do not retry |
| `Run fan-out: N/64` near the cap | spawn ceiling reached | stop and escalate |
| anything else | real failure | one strong retry, then escalate to the human |

## Runtime limits

- Per-child default timeout is **30 minutes**. Longer tasks must raise `timeoutMs` explicitly.
- `maxSubagentSpawnsPerRun` defaults to **64** and is never refunded. At roughly four spawns
  per task (implement + review + retries) a run caps near 16 tasks. Usage is reported per run.
- Mission `state.set` / `state.get` persist JSON per mission (256 KiB cap). Missing keys return
  `undefined` and vanish from JSON output — read defensively.

## Integration: shared tree

`worktree: false` is the default. Children work in the shared tree with file ownership
declared per task, so every verification runs against the accumulated tree, cross-wave
dependencies resolve naturally, and the diff the reviewer sees is the diff that ships.

Worktrees remain available for genuinely risky wide waves, but taking that option means the
parent must apply and commit patches between waves — a different architecture that must be
costed separately.

## Resume

The **wave checkpoint commit** is the primary resume mechanism; mission `state` is a secondary
cross-check. Before relaunching a wave, check `git status`: a crashed wave leaves aborted
children's partial edits on disk, and re-running on top of them can produce a false pass. The
default policy is to reset to the last checkpoint, since the wave re-runs in full.

## Verification classes

Tasks declare a verification class instead of a uniform TDD checklist. Read the target
repository's `AGENTS.md` routes to find its actual verification commands and gate roles; do not
assume a particular documentation path.

| Class | When | Implementer does | Verification |
|---|---|---|---|
| `contract` | new or changed observable behaviour | make the pre-authored failing test pass | the contract test command |
| `characterization` | refactor, no behaviour change | keep existing tests green | existing suite, scoped |
| `check` | config, wiring, generated artifacts, schema | make the structural check pass | renderer/schema/spec command |
| `none` | prose-only docs with no structural contract | nothing | the repo's existing docs spec |

Rules:

1. **Anti-tautology.** A test must be able to fail due to a change in the behaviour or artifact
   the task modifies, without a manual edit of the oracle. If it cannot, it is a `check` — or
   it is nothing. A test that only asserts a document contains a sentence someone just wrote is
   not a test.
2. **Contract-first.** Tests are authored by a **different agent than the implementer**, before
   the implementation exists. Red-before-green is observed once, by the author, with evidence.
   Implementers never author their own acceptance. Pipeline runs get a mini contract step when
   any task is class `contract`.
3. **No mandatory break-it step.** It was unverifiable and self-graded by the same context that
   wrote the test. It survives only as a reviewer-initiated, risk-triggered check when a
   reviewer suspects a test does not constrain anything.
4. **Verification is host-run by the parent**, at wave boundaries. `contract` verification also
   asserts the test files are unchanged from the frozen baseline:
   `git diff --exit-code <contract-commit> -- <test-paths> && <command>`.
5. **`none` is a legitimate answer** and must be chosen explicitly, not defaulted into.

## Target-repository integration

Use the target repository's `AGENTS.md` routes for verification commands, plan locations,
requirements, and follow-up tracking. Those policies override examples or conventions from the
engineering-agents source repository.

## Framework source references

The engineering-agents source checkout contains `docs/testing-strategy.md`, `docs/process.md`,
`plans/README.md`, and the design investigation. These explain and verify the framework itself;
they do not need to exist in a target repository.
