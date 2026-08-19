# Execution Approaches

After a reviewed `approach.md`, pick an execution approach. Front door is
`/discovery` then `/design`, or `/discover-and-design` when the work is already
well-posed. The model does not auto-invoke those skills.
Planning, execution, and verification are not.

| Approach | Pi | Notes |
|---|---|---|
| [Parallel](parallel.md) | **Current** | One DAG scheduler. Optional planned fences for verify+commit. |
| Sequential | Frozen | Original TDD checklist. Installed on OpenCode only. Do not extend. |
| Team / Crew | Abandoned | Do not use. Do not mention in new Pi process. |

Pi skills keep the historical `dynamic-*` names. They implement Parallel.
`dynamic-execute-dag-plan` is removed. OpenCode trees stay on disk unchanged.
