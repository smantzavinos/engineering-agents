# Wave-Slicing Specification

**Created:** 2026-07-14
**Status:** draft (v1)
**Plan:** ./brief.md
**Approach:** ./approach.md

Wave slicing turns a plan's task graph into an ordered list of **waves**, where every task in a wave can execute concurrently and safely under the shared-tree, single-committer model. This is the load-bearing new algorithm for team-mode wave execution.

---

## 1. Purpose & contract

Given a validated plan task graph, produce an ordered list of waves `W1 … Wk` such that:

- **Correctness:** executing the waves in order, each wave's tasks in parallel, produces the same result as executing all tasks in any dependency-respecting sequential order.
- **Safety:** no two tasks in the same wave can corrupt each other in a shared working tree (they touch disjoint files).
- **Boundedness:** no wave exceeds the team's parallel-worker cap.
- **Determinism:** the same input graph always yields the same waves (so runs are reproducible and reviewable).

Slicing decides *which tasks run together*. It does not execute, commit, review, or resolve conflicts — those belong to the orchestrator/lead.

---

## 2. Inputs

A task graph derived from `plan.md`. Each task `T` provides:

| Field | Source | Meaning |
|-------|--------|---------|
| `id` | Task Graph `ID` | Stable identifier (`T1`, `T2`, …). Total order by natural number. |
| `dependsOn` | Task Graph `Depends on` | Set of task IDs that must be **committed** before `T` starts. `—`/empty = no deps. |
| `files` | **new** Task field `Touched files` | The set of paths/globs `T` will create or modify. See §5. |
| `domain` | Task detail (inferred) | `backend` \| `ui` — routes the task to a `deep` vs `visual-engineering` worker. Not used by slicing; passed through for assignment. |

Configuration:

| Param | Default | Meaning |
|-------|---------|---------|
| `MAX_PARALLEL` | `4` | Team-mode hard cap on concurrent workers. Wave width ceiling. |
| `PARALLELISM_MIN` | `1.5` | Below this score (tasks ÷ waves), recommend the sequential mode instead. |

### 2.1 Required plan-template addition
The plan template must gain a per-task `Touched files` declaration. Proposed shape in the Task Graph table and Task Details:

```
| ID | Task | Depends on | Touched files | Deliverable | Verification | Status |
|T2  | ...  | T1         | src/b.ts, src/b.test.ts | ... | ... | ⬜ |
```

and in Task Details:

```
#### T2: <name>
**Depends on:** T1
**Touched files:** `src/b.ts`, `src/b.test.ts`   <!-- explicit paths preferred; globs allowed; `(none)` if it truly writes no files; omit only if unknown -->
```

The declaration is the planner's best-effort estimate of the write set. Under-declaring is a correctness risk (two tasks may collide); over-declaring only costs parallelism. The reviewer and the live file-set announcement (workers broadcast their set before editing) are the runtime backstops.

---

## 3. Output

An ordered list of waves. Each wave is an ordered list of task IDs (ordered for deterministic assignment/reporting):

```
[
  { "wave": 1, "tasks": ["T1"] },
  { "wave": 2, "tasks": ["T2", "T3"] },
  { "wave": 3, "tasks": ["T4", "T5"] }
]
```

Plus a slicing report:

```
{
  "taskCount": 5,
  "waveCount": 3,
  "parallelismScore": 1.67,
  "recommendation": "team",          // "team" | "sequential"
  "exclusiveTasks": ["T1"],          // tasks that ran alone due to conflicts/deps
  "undeclaredFileTasks": []          // tasks treated as global-exclusive (see §5.3)
}
```

---

## 4. Algorithm

Layered topological sort with a file-disjointness constraint and a width cap. Greedy, deterministic, O(V + E + V·W) where W is average wave width.

```
function sliceWaves(tasks, MAX_PARALLEL):
    # 1. Validate the graph
    assertAcyclic(tasks)                 # cycle => hard error, cannot slice (see §6.1)
    assertDepsExist(tasks)               # dependsOn must reference real task ids

    committed = {}                       # ids placed in PRIOR waves (not the current one)
    waves = []

    while committed.size < tasks.size:
        # 2. Ready set: deps all satisfied by prior waves, not yet placed
        ready = [ t for t in tasks
                    if t.id not in committed
                    and t.dependsOn ⊆ committed ]

        if ready is empty:
            raise DeadlockError            # should be impossible post-acyclic check (see §6.1)

        # 3. Deterministic candidate order:
        #    (a) unlock the most downstream work first, then
        #    (b) lowest id for stable tie-break
        ready.sort(by = [ -downstreamCount(t), naturalId(t.id) ])

        # 4. Greedily fill one wave under disjointness + width cap
        wave = []
        usedFiles = ∅
        for t in ready:
            if wave.size == MAX_PARALLEL: break
            if fileSet(t) is GLOBAL:                       # undeclared => exclusive
                if wave.isEmpty(): wave = [t]; usedFiles = GLOBAL
                break                                      # nothing else can share this wave
            if disjoint(fileSet(t), usedFiles):
                wave.append(t)
                usedFiles = usedFiles ∪ fileSet(t)
            # else: t stays for a later wave

        # 5. Emit the wave; only now are its tasks "committed" for dependency purposes
        waves.append(wave)
        committed = committed ∪ { t.id for t in wave }

    return waves
```

Key subtlety: a task's dependencies must be satisfied by tasks placed in **strictly earlier** waves, never by a task in the *same* wave — because same-wave tasks run concurrently and one cannot consume another's committed output. This is why `committed` is updated only *after* a wave is emitted (step 5), not while filling it.

`downstreamCount(t)` = number of tasks transitively reachable from `t` in the dependency DAG (how much work completing `t` unlocks). Precompute once.

---

## 5. File-set overlap (§ safety core)

The disjointness check is what makes shared-tree parallel execution safe. It must be conservative: a false "disjoint" causes a real content race; a false "overlap" only costs parallelism.

### 5.1 Normalization
- Resolve to repo-root-relative POSIX paths.
- Strip trailing slashes; collapse `.`/`..`.
- A directory entry `src/foo/` means "any path under `src/foo/`".

### 5.2 Overlap predicate (v1, conservative)
Two file sets **overlap** if any pair `(a, b)` with `a ∈ A`, `b ∈ B` satisfies any of:
- `a == b` (same path), or
- `a` is a path-prefix of `b` or vice-versa (`src/foo` vs `src/foo/bar.ts`), or
- both are globs whose **literal (non-wildcard) prefixes** are in a prefix relationship (e.g. `src/api/**` vs `src/api/users.ts` → overlap; `src/api/**` vs `src/web/**` → disjoint).

Full glob-vs-glob intersection is undecidable in general; v1 deliberately uses the literal-prefix heuristic and errs toward "overlap". Precise glob intersection is a documented follow-up (see §8).

### 5.3 Undeclared / unknown file sets
- A task with **no `Touched files` declaration** is treated as `GLOBAL` (touches everything) → it runs **alone** in its own wave. This is the safe default and creates a natural incentive for planners to declare files to gain parallelism.
- A task explicitly declaring `(none)` (a verification-only or docs-noop task that writes nothing) has an **empty** file set → it is disjoint with everything and freely co-schedulable.

---

## 6. Edge cases

### 6.1 Cycles / deadlock
- `assertAcyclic` runs first. A cycle is a plan defect → hard error with the offending cycle reported; slicing cannot proceed. (This is a plan-review miss and should be routed back to review, not worked around.)
- If `ready` is ever empty while tasks remain despite an acyclic graph, that is an internal invariant violation → `DeadlockError`. Post-acyclic-check it should be unreachable.

### 6.2 Everything conflicts
If all tasks share files, each wave has width 1 and the slice degenerates to a sequential order. `parallelismScore → 1.0` → recommendation `sequential`.

### 6.3 A dependency was deferred by width/file cap
Handled naturally: a task whose dependency is not yet in `committed` simply isn't in `ready` next round; it waits until the dependency lands in a wave.

### 6.4 Wide ready set beyond the cap
If more than `MAX_PARALLEL` file-disjoint tasks are ready, the greedy fill takes the top `MAX_PARALLEL` by candidate order; the rest roll to subsequent waves. Deterministic because the order is deterministic.

### 6.5 Domain mix within a wave
Slicing ignores `domain`; a wave may contain both backend and UI tasks. Assignment maps each to the correct worker type (`deep` / `visual-engineering`) within the 4-worker budget. If a wave has more same-domain tasks than same-domain workers, the lead either adds a member (within bounds) or lets a worker take a second task after finishing its first (still within the concurrency cap).

---

## 7. Mode-selection gate

After slicing, compute `parallelismScore = taskCount / waveCount`:
- `score ≥ PARALLELISM_MIN (1.5)` **and** `taskCount ≥ 3` → recommend **team mode**.
- otherwise → recommend **sequential mode** (the coordination overhead won't pay off; e.g. a deep `T1→T2→T3→T4` chain scores 1.0).

The recommendation is advisory; the human/orchestrator makes the final call. This keeps the fast lane from being *slower* than sequential on narrow graphs.

---

## 8. Worked example

Plan task graph:

| ID | Depends on | Touched files |
|----|------------|---------------|
| T1 | —          | `src/a.ts` |
| T2 | T1         | `src/b.ts` |
| T3 | T1         | `src/c.ts` |
| T4 | T1         | `src/b.ts` (overlaps T2) |
| T5 | T2, T3     | `src/d.ts` |

`downstreamCount`: T1→4, T2→1 (T5), T3→1 (T5), T4→0, T5→0.

**Round 1:** committed = {}. ready = [T1]. Wave 1 = **[T1]**. committed = {T1}.

**Round 2:** ready = [T2, T3, T4] (all deps = {T1} ⊆ committed). Order by (−downstream, id): T2(−1), T3(−1), T4(0) → `T2, T3, T4`.
Fill: add T2 (`b`); T3 (`c`) disjoint → add; T4 (`b`) overlaps used `b` → skip. Width 2 ≤ 4. Wave 2 = **[T2, T3]**. committed = {T1, T2, T3}.

**Round 3:** ready = [T4 (dep {T1} ok), T5 (deps {T2,T3} ok)]. Order: both downstream 0 → id order `T4, T5`.
Fill: add T4 (`b`); T5 (`d`) disjoint → add. Wave 3 = **[T4, T5]**. committed = all.

**Result:** `[[T1], [T2,T3], [T4,T5]]`. Report: taskCount 5, waveCount 3, parallelismScore ≈ **1.67**, recommendation **team**, exclusiveTasks [T1].

Note T4 (`src/b.ts`) safely runs in wave 3 even though T2 also touched `src/b.ts` in wave 2 — cross-wave file reuse is fine because T2 is already committed. Disjointness is only required **within** a wave (concurrent writers), never across waves.

---

## 9. Testability (for the eventual build)
The algorithm is pure (graph in → waves out) and deterministic, so it is unit-testable offline with fixtures — matching the repo's offline-shell-spec preference (`tests/specs/`). Suggested cases:
- Linear chain → N waves of 1, recommendation sequential.
- Wide independent fan-out (all deps on T1, disjoint files) → one wide wave capped at 4, remainder in a second wave.
- File-overlap forcing serialization of two otherwise-parallel tasks.
- Undeclared file set → exclusive wave.
- `(none)` file set → co-scheduled freely.
- Cycle → hard error.
- Cross-wave file reuse (the T4 case above) → allowed.
- Determinism: shuffled input task order yields identical waves.

---

## 10. Open questions
- Precise glob-vs-glob intersection (v1 uses literal-prefix heuristic; §5.2).
- Should `Touched files` support an explicit "read-only" set distinct from the "write" set, to allow a reader and a writer of the same file to co-run? (v1 treats any declared path as a write.)
- Should slicing be static (planner writes waves into `plan.md`) or dynamic (orchestrator computes at execution time)? Static aids review; dynamic adapts to runtime rebalancing (§7 of approach, issue #7).
