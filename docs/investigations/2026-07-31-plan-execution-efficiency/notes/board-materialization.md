VERDICT: **FEASIBLE-WITH-CAVEATS** — Code that can import Crew’s store can create a plan record with `store.createPlan()` and then create tasks with `store.createTask()` without invoking the planner. The public `pi_messenger` action surface has no non-LLM `plan.create` action, so `task.create` alone remains blocked until a plan record is supplied. [crew/store.ts:84-98] [crew/handlers/task.ts:90-96] [crew/handlers/plan.ts:293-317]

## 1. `task.create` parameter surface

`action: "task.create"` is routed as group `task`, operation `create`, then dispatched to `taskCreate`. The registered tool marks `action` as an optional string, but this invocation requires that literal action to reach the handler. [crew/index.ts:43-47] [crew/index.ts:167-174] [crew/handlers/task.ts:38-40] [index.ts:437-440]

### Public registered-tool fields relevant to this action

| Parameter | Type | Optional at tool schema? | Runtime behavior in `task.create` |
|---|---|---:|---|
| `action` | `string` | Yes | Must be `"task.create"` to select this handler. [index.ts:437-440] [crew/index.ts:43-47] |
| `title` | `string` | Yes | **Required by handler**; a falsy value returns `missing_title`. [index.ts:449-450] [crew/handlers/task.ts:85-88] |
| `content` | `string` | Yes | Passed as the task description/spec content. [index.ts:460-460] [crew/handlers/task.ts:115-119] |
| `dependsOn` | `string[]` | Yes | Each supplied ID must already resolve to a task. [index.ts:450-450] [crew/handlers/task.ts:98-106] |
| `role` | `string` | Yes | Canonicalized; with an active Team, an unknown non-blank role is rejected. [index.ts:451-452] [crew/handlers/task.ts:108-111] |
| `riskLabels` | `string[]` | Yes | Normalized and persisted as task field `risk_labels`; it can drive derived approval. [index.ts:452-452] [crew/handlers/task.ts:113-119] |

The internal `CrewParams` type additionally declares optional `approval: TaskApproval`, and the handler consumes it as an override of Team-derived approval. `approval` is **not** declared in the registered tool schema shown above; therefore it is a runtime/internal surface rather than a documented registered-tool field. `TaskApproval` is either `{ required: false, status: "not_required" }` or `{ required: true, status: "pending" | "approved" | "rejected" }`, optionally with `plan`, `feedback`, `decided_by`, and `decided_at` strings. [crew/types.ts:36-48] [crew/types.ts:98-103] [crew/handlers/task.ts:113-119] [index.ts:437-488]

**Direct answers:**

* **Per-task `model`: no through `task.create`.** The registered tool and `CrewParams` expose optional `model: string`, but describe it as a work-wave override; `taskCreate` does not read or pass it to `store.createTask`. The store *can* persist `options.model`, and work later gives persisted `task.model` highest model priority. [index.ts:471-474] [crew/types.ts:121-124] [crew/handlers/task.ts:85-119] [crew/store.ts:174-194] [crew/handlers/work.ts:175-184]
* **`riskLabels`: yes**, exact camel-case parameter name `riskLabels`; it becomes persisted snake-case `risk_labels`. [index.ts:452-452] [crew/handlers/task.ts:113-119] [crew/types.ts:57-58]
* **`skills`: no through `task.create`.** It is absent from both the registered tool schema and `CrewParams`, and `taskCreate` does not pass it. The lower-level store accepts `options.skills`, and the LLM plan materializer is the production caller that supplies it. [index.ts:437-488] [crew/types.ts:87-145] [crew/handlers/task.ts:115-119] [crew/store.ts:174-194] [crew/handlers/plan.ts:455-460]
* **`role`: yes**, exact parameter name `role`. [index.ts:451-452] [crew/handlers/task.ts:108-119]

## 2. What creates the plan record

`task.create` calls `store.getPlan(cwd)` and returns `error: "no_plan"` if it receives no parsed record. `getPlan` is exactly a JSON read of `<cwd>/.pi/messenger/crew/plan.json`. [crew/handlers/task.ts:90-96] [crew/store.ts:24-26] [crew/store.ts:80-82]

The record-producing primitive is `store.createPlan(cwd, prdPath, prompt?)`. It writes `plan.json` with `prd`, optional truthy `prompt`, ISO `created_at`/`updated_at`, and zero `task_count`/`completed_count`; the store test round-trips this function and asserts the initial counters. [crew/store.ts:84-98] [crew/types.ts:15-22] [tests/crew/store.test.ts:16-25]

**Production action trace (exhaustive for non-test TypeScript call sites):** `crew/handlers/plan.ts` is the only production caller of `store.createPlan`; its `plan` action first requires a discovered `crew-planner`, then writes the record, then invokes `spawnAgents` for that planner. Thus the supplied public action has no non-LLM plan-creation branch. [crew/handlers/plan.ts:293-300] [crew/handlers/plan.ts:317-347] [crew/store.ts:84-98]

**Non-LLM paths:**

1. **Programmatic store API:** an embedding/local script may call `store.createPlan(cwd, prdPath, prompt?)`, then call `store.createTask(...)` directly. Neither store function invokes an agent. [crew/store.ts:84-98] [crew/store.ts:174-214]
2. **Direct file fallback:** write a valid `plan.json` at the path above. `getPlan` only JSON-parses the file; `task.create` only tests whether the parsed result is truthy. This bypasses the public-action blocker but also bypasses store helper behavior. [crew/store.ts:44-50] [crew/store.ts:80-82] [crew/handlers/task.ts:90-96]

`plan.md` is not required to pass `task.create`; it is separately read as the plan spec and its absence is only a validation warning. [crew/store.ts:161-168] [crew/store.ts:590-594]

## 3. On-disk store and direct-write requirements

**Paths and formats:**

* Crew root: `<cwd>/.pi/messenger/crew`; plan: `plan.json` (pretty-printed JSON); optional plan spec: `plan.md`. [crew/store.ts:24-30] [crew/store.ts:53-58] [crew/store.ts:80-98] [crew/store.ts:161-168]
* Tasks: one pretty-printed JSON object at `tasks/task-N.json`; normal creation also writes `tasks/task-N.md` containing either the description or `*Spec pending*`. Optional progress is `tasks/task-N.progress.md`; optional block context is `blocks/task-N.md`. [crew/store.ts:174-206] [crew/store.ts:285-303] [crew/store.ts:402-408]

**Plan JSON schema:** `prd: string`, optional `prompt: string`, `created_at: string`, `updated_at: string`, `task_count: number`, and `completed_count: number`. [crew/types.ts:15-22] [crew/store.ts:84-96]

**Task JSON schema for a newly created todo:** `id: string` (`task-N`), `title: string`, `status: "todo"`, `depends_on: string[]`, `created_at: string`, `updated_at: string`, and `attempt_count: number`; optional persisted fields include `model`, `role`, `risk_labels`, `approval`, and `skills`. The complete lifecycle type also permits milestone and completion/assignment/evidence fields. [crew/store.ts:174-200] [crew/types.ts:28-72]

**Can it be written directly? Yes, with these invariants:**

1. Use matching `tasks/task-N.json` filenames and `id: "task-N"` values. The allocator finds the largest numeric `task-N.json` filename and returns the next number; task listing sorts by numeric ID. The code does not require contiguity, but sequential numeric IDs preserve normal allocation and display order. [crew/id-allocator.ts:14-28] [crew/store.ts:266-283] [tests/crew/store.test.ts:65-99]
2. Keep `depends_on` as existing task IDs. A healthy graph has no orphans or cycles; `validatePlan` detects both only when explicitly called, and `crew.validate` is the action that invokes it. [crew/store.ts:531-580] [crew/handlers/status.ts:258-275] [tests/crew/store.test.ts:433-459]
3. Use only `"todo"`, `"in_progress"`, `"done"`, or `"blocked"` for `status`. This is the declared enum; the runtime normalizer preserves raw status rather than validating it. [crew/types.ts:28-28] [crew/store.ts:234-244]
4. Synchronize plan counters: `task_count` must equal the number of task JSON files/tasks, and `completed_count` must equal tasks whose status is `done`; mismatches are warnings from `validatePlan`. Store creation increments `task_count` after writing the task. [crew/store.ts:200-212] [crew/store.ts:596-604] [tests/crew/store.test.ts:471-485]
5. Include the `.md` task spec and `plan.md` if a warning-free validation result is required; missing/pending specs do not make the plan invalid. [crew/store.ts:202-206] [crew/store.ts:582-594] [tests/crew/store.test.ts:461-469]

**Residual implementation caveat (inference):** direct parallel writers can race on ID selection because ID allocation scans the current files before `createTask` writes the new one; no shared lock is present in that sequence. Use serialized creation or an external lock. [crew/id-allocator.ts:14-28] [crew/store.ts:181-200]

## 4. Dependency validation by `task.create`

`task.create` performs only a per-ID existence lookup for supplied `dependsOn`; it has no cycle-detection or graph-validation call. Because every submitted dependency must already exist, normal sequential calls must be made in dependency/topological order, but that is an effect of the existence check rather than a cycle validator. [crew/handlers/task.ts:98-106] [crew/handlers/task.ts:115-119] [crew/store.ts:531-580]

In strict dependency mode, start—not creation—requires every dependency to be `done`; advisory mode skips that start gate. [crew/task-actions.ts:44-59] [tests/crew/task-actions.test.ts:52-77]

## 5. Bulk/batch creation

There is **no generic non-LLM batch `task.create` action**: the task dispatcher exposes singular `create`, and the task-action helper’s action union has no create or batch member. [crew/handlers/task.ts:38-70] [crew/task-actions.ts:7-29]

Two specialized multi-create flows exist, neither is a general board-materialization API:

* The LLM plan handler parses planner output and loops over `store.createTask`, then resolves dependencies and writes the plan spec. This is the planner-dependent bulk path. [crew/handlers/plan.ts:450-485]
* `task.split` requires an existing task and at least two `subtasks`; it loops over them, gives each the parent’s dependencies/metadata, then rewires dependents and turns the parent into a milestone. [crew/handlers/task.ts:194-207] [crew/handlers/task.ts:220-270]

## Review findings

* **Blocker — public API:** no public non-LLM plan-creation action exists; the only production `createPlan` call is within the LLM planning action, while `task.create` rejects a missing plan. [crew/handlers/plan.ts:293-347] [crew/handlers/task.ts:90-96]
* **Major — task metadata gap:** `task.create` cannot persist per-task `model` or `skills`, even though the store supports both and work honors persisted `task.model`. [crew/handlers/task.ts:115-119] [crew/store.ts:174-194] [crew/handlers/work.ts:175-184]
* **Major — direct-write integrity:** direct files are viable but schema/count/graph checks are not enforced at read time; validation is a separate explicit action/function. [crew/store.ts:234-244] [crew/store.ts:531-610] [crew/handlers/status.ts:258-275]
