# `tasks.json` — the executable task graph

`plan.md` is the human narrative. `tasks.json` is what the Parallel executor
runs. Every plan directory that will be executed must contain both, and they
must agree:

`node "$HOME/.pi/agent/skills/dynamic-create-plan/tools/check-plan.mjs" <plan-dir>`

The checker is an installed skill resource; do not add it to the target
repository. Direction lives in [docs/approaches/parallel.md](../docs/approaches/parallel.md).

## Shape

```json
{
  "schema": 1,
  "models": { "cheap": "<provider/model>", "strong": "<provider/model>" },
  "fenceGroups": [
    { "id": "shared", "tasks": ["T1", "T2", "T3", "T4"] },
    { "id": "collect", "tasks": ["T5"] }
  ],
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

Omit `fenceGroups` for the default: one group containing every task.

`maxWidth` is ignored if present. Do not use it to invent fences.

## Fields

| Field | Required | Meaning |
|---|---|---|
| `schema` | yes | Format version. Currently `1`. |
| `models.cheap` / `models.strong` | yes | Explicit models. An unresolved model fails the child before it starts. |
| `fenceGroups` | no | Ordered verify+commit cuts. Each group runs as a DAG, then the parent host-verifies. |
| `fenceGroups[].id` | when groups present | Unique group name. Becomes `dataflow.<id>.js`. |
| `fenceGroups[].tasks` | when groups present | Task ids in this group. Every task id appears in exactly one group. |
| `id` | yes | Unique, `T<n>` by convention. |
| `title` | yes | Short label, used in the plan's Task Overview. |
| `brief` | yes | The actual prompt. Carries **paths, never file contents**. |
| `deps` | yes | IDs that must complete first. Intra-group deps are promise joins. |
| `writes` | yes | The task's write-set, using the limited path dialect below. |
| `class` | yes | `contract` \| `characterization` \| `check` \| `none`. |
| `verify` | unless `class: none` | The command that proves this task is done. |
| `testPaths` | when `class: contract` | The frozen test files. |
| `ui` | no | `true` routes to `ui-worker`. |
| `timeoutMs` | no | Overrides the 30-minute per-child default. |
| `requirements` | no | Requirement IDs this task satisfies. |

## Write-set path dialect

Write specs are repository-relative POSIX paths. A literal path owns that path
and its descendants. The only wildcard is `*`; it must occupy a whole path
segment. The checker rejects absolute paths, parent traversal, `**`,
partial-segment patterns such as `*.ts`, `?`, character classes, and braces.

Dynamic route segments (e.g. `[id]`) are not expressible. Use a whole-segment
`*` for that segment; if the wildcard then collides with a sibling file under
the checker's conservative model, add a **scheduling-only dependency** between
the two tasks and label it as such in `plan.md` — the files are disjoint; the
edge exists only to satisfy the checker.

## Rules the checker enforces

1. **The graph is valid** — unique IDs, no unknown dependencies, no cycles,
   every task has an `id` and a `brief`.
2. **`fenceGroups`, when present** — unique group ids, every task in exactly
   one group, no unknown ids, no dependency on a task in a later group.
3. **`contract` tasks declare `testPaths`.**
4. **Every task except `class: none` declares `verify`.**
5. **Write-sets do not collide inside a fence group** unless one task
   transitively depends on the other. Different groups may share a path.
6. **`plan.md` and `tasks.json` agree** on task IDs.
7. **Declared models are non-empty strings.**

## Shared spec files

One frozen spec file may back several tasks when each task verifies against a
scope of it (a describe title grepped by the task's `verify` command). Pin the
titles in `interfaces.md` and keep scopes mutually exclusive: no test title
inside one task's scope may contain another task's grep substring
(no-cross-substring rule), or one task's verify will run another's tests.
