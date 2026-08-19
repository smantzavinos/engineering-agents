# Execution Patterns

Runtime constraints for Pi Parallel execution. The approach itself —
scheduler, fences, planning, verification classes — lives in
[approaches/parallel.md](approaches/parallel.md).

"Code mode" is the mechanism (`workflowScript`). Parallel is the process.

## The loop lives in the parent

**The parent drives the loop and invokes one `workflowScript` per fence group.**
It does not hand the whole plan to a single long-running script. Two independently
verified constraints force this:

1. **Verification cannot be delegated to a child.** `gate:` implies acceptance
   level `verified`, whose structured-evidence validation short-circuits *before*
   the gate command's result is consulted. In testing, `gate: "true"` and
   `gate: "false"` were indistinguishable.
2. **Nothing applies worktree patches back.** `worktree.discard` exists;
   `worktree.apply` does not, and the script sandbox has no filesystem or shell
   access.

```
parent: baseline verification on the host
parent: freeze interfaces
parent: freeze contracts (different agent than implementers)
parent: commit the red tests
for each planned fence group:
  parent: generate + persist dataflow.<group>.js
  parent: ONE workflowScript invocation, sourced from that file
  parent: run verification on the host
  parent: review, then fix
  parent: commit the group checkpoint
parent: final gate + fresh strong full-diff review
```

Generate scripts with `buildGroupScript` in `workflows/wave.mjs`. Do not
hand-author a second inline copy. Do not compute ready-set waves or `maxWidth`.

## Sandbox rules

- **Use `runs.all`, never `runs.run`, for task fan-out.** `runs.run` throws on
  child failure and aborts in-flight siblings.
- **Branch on `ok`.** There is no `status` field.
- **Set `model` explicitly on every child.**
- **Never set `turnBudget`, a hard `toolBudget`, or a tight `usageBudget` on a
  writer.** Bound writers with `timeoutMs` and a narrow task.
- **Do not define nested `async function` helpers, async arrows, or async
  methods** inside a script. Use top-level `await`, plain helpers, or Promise
  chains.
- **Await every launched promise** before returning.
- Embed task data with exact `JSON.stringify`. Briefs carry **paths, never file
  contents**.

## Failure classification

| `error` begins | Meaning | Action |
|---|---|---|
| `Acceptance rejected:` | paperwork | inspect the diff before retrying |
| `Unknown subagent model` | configuration | fix routing; do not retry |
| `Run fan-out: N/64` near the cap | spawn ceiling | stop and escalate |
| anything else | real failure | retry the failed branch once, then escalate |

## Runtime limits

- Per-child default timeout is **30 minutes**.
- `maxSubagentSpawnsPerRun` defaults to **64** and is never refunded.
- Shared tree (`worktree: false`) is the default. Write-set collisions are a
  plan-time error inside a fence group.

## Resume

The **fence-group checkpoint commit** is the resume point. Before relaunching a
group, check `git status`. Default: reset to the last checkpoint and re-run the
group.

## Target-repository integration

Use the target repository's `AGENTS.md` for verification commands, plan
locations, requirements, and follow-up tracking. These files do not need to exist in a target repository.
