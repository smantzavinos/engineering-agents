# Pi Team plan contract (schema 1)

Read this reference before authoring or validating a Pi Team plan. It is the complete mechanical
contract consumed by `pi-team check`; semantic sufficiency still requires a fresh review.

## Exact v1 grammar

A plan is UTF-8 Markdown with CRLF normalized to LF. `Plan schema: 1` is mandatory. It has one
non-empty H1, exactly the following preamble fields, then exactly these sections in this order.
Tables are single-line pipe tables with the exact headers below. Cells are trimmed; embedded,
escaped, or literal `|`, multiline cells, duplicate sections, unknown sections, and text after
`## Tasks` are invalid.

```markdown
# <title>
Plan schema: 1
Intent: <what changes, why, and what stays unchanged>
Approval: <auto | requested>

## Contracts
| ID | Behavior | Evidence |
| --- | --- | --- |

## Decisions
| ID | Decision | Resolution |
| --- | --- | --- |

## Checks
| ID | Scope | Command | Cost | Worker-safe |
| --- | --- | --- | --- | --- |

## Tasks
| ID | Deps | Lane | Estimate min | Risk labels | Integration | Deliverable | Write set | Contracts | Decisions | Check |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
```

`Intent`, all table fields other than the list fields represented by `—`, and every deliverable
are non-empty. `Approval` is exactly `auto` or `requested`.

## IDs, lists, lanes, and risk labels

- Task IDs match `T[1-9][0-9]*`; contract IDs `C[1-9][0-9]*`; decision IDs
  `D[1-9][0-9]*`; check IDs `K[1-9][0-9]*`; integration groups `G[1-9][0-9]*`.
  Each ID is unique in its table, all references resolve, and task dependencies form a DAG.
- `Deps`, `Risk labels`, `Contracts`, and `Decisions` are comma-separated unique values or `—`.
  IDs sort by their numeric suffix (so `T2` precedes `T10`).
- Allowed lanes are exactly cheap, std, complex, visual, visual-complex.
- Allowed risk labels are exactly migration, destructive, auth, api-contract.
  A risk-labelled task remains pending until the human approves it through the active `pi-team`
  profile; there is no per-task waiver.
- `Estimate min` is a positive safe integer. Every task has one integration group, bounded
  deliverable, explicit write set, resolved contracts and decisions, and one worker-safe check.

## Write-set and wave rules

`Write set` is a comma-separated list of POSIX repo-relative paths. Absolute paths, empty
segments, `.` or `..`, backslashes, NULs, globs, symlinks, and non-normalized paths are rejected.
A trailing `/` means a directory; otherwise the path is one exact file. Same-wave write sets must
be disjoint after normalized prefix comparison.

Wave = dependency depth. At each depth, task IDs use numeric order; more than four tasks are
chunked into consecutive groups of four. A task can be dispatched only in its computed wave.

## Scheduling thresholds

The estimated critical path must be `critical path <= 60% of serial estimate`. The largest task on
that path must satisfy `estimate <= max(20 minutes, 20% of critical path)`. These are mechanical
validation gates, calculated from `Estimate min` and the dependency DAG. If the largest-task gate
fails, split that task into smaller decision-complete packets; do not add artificial dependency
chains or ceremony-only tasks to manipulate the ratio.

## Check and integration rules

- A task's `Check` references exactly one row with `Scope` `worker` and `Worker-safe` `yes`.
- Each referenced integration group has exactly one `Checks` row with scope `integration:G<n>`.
- Exactly one `Checks` row has scope `final`.
- Every check has a non-empty command and cost; `Worker-safe` is exactly `yes` or `no`.
- Integration checks run once per changed normalized group digest after that group is complete.
  A spanning group waits until complete. A final check is never a worker check.

## Task packet template

The compiler creates each Crew task with this LF-terminated content. Referenced contract and
decision rows are numeric-ID sorted; a `—` list expands to `- none`.

```markdown
# Plan task <TASK_ID>

Lane: <LANE>
Estimate min: <N>
Integration: <GROUP_ID>

## Deliverable
<DELIVERABLE>

## Write set
- <PATH>

## Contracts
- <ID>: <BEHAVIOR> | Evidence: <EVIDENCE>

## Decisions
- <ID>: <DECISION> | Resolution: <RESOLUTION>

## Minimal check
<CHECK_ID>: <COMMAND>

## Worker rules
- Modify only the declared write set.
- Use structured edit/write tools; do not mutate files through bash.
- Run only the minimal check above.
- Do not commit or run broad gates.
- Record concise progress and complete the Crew task with evidence.
```
