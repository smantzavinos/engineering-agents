# `tasks.json` — the executable task graph

`plan.md` is the human narrative. `tasks.json` is what the wave engine actually runs.
Every plan directory that will be executed must contain both, and they must agree:
`node tools/check-plan.mjs <plan-dir>` is the gate.

## Shape

```json
{
  "schema": 1,
  "maxWidth": 3,
  "models": { "cheap": "<provider/model>", "strong": "<provider/model>" },
  "tasks": [
    {
      "id": "T1",
      "title": "Short human label",
      "brief": "The full instruction handed to the implementer.",
      "deps": [],
      "writes": ["src/thing.ts", "tests/thing.spec.ts"],
      "class": "contract",
      "verify": "npm test -- thing",
      "testPaths": ["tests/thing.spec.ts"],
      "ui": false,
      "timeoutMs": 1800000,
      "requirements": ["FR-001"]
    }
  ]
}
```

## Fields

| Field | Required | Meaning |
|---|---|---|
| `schema` | yes | Format version. Currently `1`. |
| `maxWidth` | yes | Max tasks per wave. `1` makes it a pipeline. |
| `models.cheap` / `models.strong` | yes | Explicit models. There is no usable default — an unresolved model fails the child before it starts. |
| `id` | yes | Unique, `T<n>` by convention. |
| `title` | yes | Short label, used in the plan's Task Overview. |
| `brief` | yes | The actual prompt. Carries **paths, never file contents** — the implementer reads files itself. |
| `deps` | yes | IDs that must complete first. `[]` for wave-1 tasks. |
| `writes` | yes | The task's write-set. Paths or globs. |
| `class` | yes | `contract` \| `characterization` \| `check` \| `none`. |
| `verify` | unless `class: none` | The command that proves this task is done. |
| `testPaths` | when `class: contract` | The frozen test files. Verification asserts they are unchanged from the contract commit. |
| `ui` | no | `true` routes to `ui-worker`. |
| `timeoutMs` | no | Overrides the 30-minute per-child default. |
| `requirements` | no | Requirement IDs this task satisfies. |

## Rules the checker enforces

1. **The graph is valid** — unique IDs, no unknown dependencies, no cycles, every task has
   an `id` and a `brief`. Shared with the wave engine, so the plan cannot pass here and
   fail at execution.
2. **`contract` tasks declare `testPaths`.** Without them there is nothing to freeze, and
   the implementer could satisfy the task by editing the test.
3. **Every task except `class: none` declares `verify`.** "Done" must be a command.
4. **Write-sets do not collide inside a wave.** Two tasks that can run concurrently and
   write the same path will race in the shared tree. This is the check that makes parallel
   execution safe — if it fires, add a dependency or merge the tasks.
5. **`plan.md` and `tasks.json` agree.** Every ID in the plan's Task Overview exists in
   `tasks.json`, and every task in `tasks.json` appears in the overview. Drift between the
   document a human approved and the graph a machine runs is the failure mode this
   prevents.
6. **Declared models are non-empty strings**, because the engine sets `model` explicitly on
   every child.

## Choosing a class

Ask: *can this task's test fail because of a change in the behaviour or artifact the task
modifies, without someone editing the test?*

- Yes, and the behaviour is new or changed → `contract`.
- Yes, but the behaviour should not change at all → `characterization`.
- Not really — the artifact is config, wiring, generated output, or a schema → `check`.
- No, it is prose with no structural contract → `none`.

A test that only asserts a document contains a sentence someone just wrote is not a test.
Call it `none` and let the repo's existing docs spec cover the structure.
