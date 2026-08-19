---
name: dynamic-execute-plan
description: Execute an approved Parallel plan. Freeze contracts, then run each planned fence group as a DAG workflowScript with host-run verification and a checkpoint commit after the group. Use after plan review passes and the human has approved.
compatibility: pi
---

# Parallel: Execute Plan

Drive an approved plan to a verified implementation. **You own the loop.**
Children implement. You generate the DAG script, persist it, launch it, verify
on the host, and commit. You never delegate verification.

Read [docs/approaches/parallel.md](docs/approaches/parallel.md) first. Runtime
limits are in [docs/execution-patterns.md](docs/execution-patterns.md). Both
are installed skill resources. If they are missing, stop; do not recreate them
in the target repo.

There is no separate "attended DAG" skill. The scheduler is always a DAG.
Fences are the planned cuts in `tasks.json`.

## Inputs

- A plan directory containing `plan.md` and `tasks.json`.
- The repo's verification commands, from the canonical docs `AGENTS.md` points to.
- Out-of-scope follow-ups go through the repo's documented follow-up mechanism.
- Confirmation that the human approved the plan. If unclear, **stop and ask**.

## Preconditions

```bash
PLAN_DIR="plans/<slug>"
WAVE_MODULE="$HOME/.pi/agent/skills/dynamic-execute-plan/workflows/wave.mjs"
git status --porcelain            # must be clean; refuse to start on a dirty tree
node "$HOME/.pi/agent/skills/dynamic-create-plan/tools/check-plan.mjs" "$PLAN_DIR"
```

Record the **baseline**: run the repo's verification command and note what
already fails.

```bash
BASE="$(git rev-parse HEAD)"
```

## Phase 1 — Freeze interfaces

One strong child returns the shared signatures, file paths, and data shapes.
It writes no implementation.

subagent({
  agent: "planner",
  task: "Read PLAN_DIR/plan.md and tasks.json. Produce the interface surface the tasks share: exact function/type signatures, file paths, and data shapes crossing task boundaries. Write it to PLAN_DIR/interfaces.md. Do not implement anything."
})

Review the result yourself.

## Phase 2 — Contract

For every task of class `contract`, a **different agent than the implementer**
authors the failing test. Observe red once, here.

subagent({
  agent: "planner",
  task: "Author the failing tests for the tasks listed as class \"contract\" in PLAN_DIR/tasks.json, against the interfaces in PLAN_DIR/interfaces.md. Write tests only — no implementation. Each test must be able to fail because of a change in the behaviour it covers, without a manual edit of the test. Run them and report the exact red output.",
  skill: "dynamic-create-plan"
})

Confirm red yourself, then commit. This commit is the frozen baseline:

```bash
git add -A && git commit -m "test: freeze contracts for <plan>"
CONTRACT="$(git rev-parse HEAD)"
```

Tasks of class `characterization`, `check`, or `none` skip this phase.

## Phase 3 — Fence groups

Resolve groups with `resolveFenceGroups` (missing `fenceGroups` ⇒ one group
`all`). For **each group, in order**:

**1. Generate and persist the script.**

```bash
node -e '
  const { buildGroupScript, resolveFenceGroups } = await import(process.argv[1]);
  const fs = await import("node:fs");
  const doc = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
  const groupId = process.argv[3];
  const group = resolveFenceGroups(doc).find((g) => g.id === groupId);
  const tasks = doc.tasks.filter((t) => group.tasks.includes(t.id));
  const script = buildGroupScript(tasks, {
    cheapModel: doc.models.cheap,
    strongModel: doc.models.strong,
    freezeCommit: process.argv[4] || "",
  });
  fs.writeFileSync(process.argv[5], script);
' "$WAVE_MODULE" "$PLAN_DIR/tasks.json" "<group-id>" "$CONTRACT" "$PLAN_DIR/dataflow.<group-id>.js"
```

The file is raw JavaScript. Commit it as an orchestration record. Tell the
human the path. **Do not launch until they approve this file** unless they
already approved this exact file.

**2. Launch that file's contents** as `workflowScript` in one `subagent` call.
Do not hand-author a second inline copy. Every child already has an explicit
`model` from the generator.

**3. Verify on the host.** You run this, not a child.

```bash
git diff --exit-code "$CONTRACT" -- <frozen test paths> && <group verification>
```

The `git diff` half is not optional for `contract` tasks.

**4. Classify any failure** with `classifyFailure` before a retry:

| Class | Meaning | Action |
|---|---|---|
| `acceptance` | reporting/paperwork | inspect the diff before retrying |
| `model` | configuration error | fix routing; do not retry |
| `spawn-budget` | fan-out ceiling | stop, escalate |
| `failure` | real failure | retry the **failed branch** once with the strong model, then escalate |

Do not re-run a whole group because one leaf failed unless the host verify
fails for the accumulated tree.

**5. Review, then checkpoint.**

subagent({
  agent: "code-reviewer",
  task: "Review the diff for fence group <id> against PLAN_DIR/plan.md and tasks.json. Report correctness, scope creep, undeclared writes, and any test that cannot fail for a reason other than an edit to itself.",
  skill: "dynamic-review-code"
})

Apply fixes yourself, then commit the group (implementation + `dataflow.<id>.js`
+ review notes). That commit is the resume point.

Before relaunching a crashed group, check `git status`. Default policy: reset
to the last checkpoint and re-run the group.

## Phase 4 — Final gate

After the last group:

1. Run the repo's final verification command on the host.
2. Delegate a **fresh-context** `oracle` review of `BASE..HEAD` with
   `dynamic-review-code`.
3. Fix until the final review is clean, then mark the plan complete.

## What you must not do

- Do not compute a ready-set wave or apply `maxWidth`.
- Do not launch an inline script that is not the file on disk.
- Do not let a child `git commit` or run host verification as the proof.
- Do not skip a planned fence because "someone is watching."
- Do not invent extra fences at execute time. If the cuts are wrong, stop and
  re-plan.
