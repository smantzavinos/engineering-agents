# Execution Approaches

After a reviewed `approach.md`, pick an execution approach. Discovery and Design are shared.
Planning, execution, and verification are not.

| Approach | Pi | Notes |
|---|---|---|
| [Parallel](parallel.md) | **Current** | One DAG scheduler. Optional planned fences for verify+commit. |
| Sequential | Frozen | Original TDD checklist. Installed on OpenCode only. Do not extend. |
| Team / Crew | Abandoned | Do not use. Do not mention in new Pi process. |

OpenCode trees stay on disk unchanged. New process work is Pi + Parallel only.
