---
name: dynamic-review-code
description: Post-implementation review of a Parallel-plan diff against the plan. Checks that the work delivers what tasks.json specified, that tests genuinely constrain, and that frozen contracts were not edited. Produces code_review.md. Called per fence group and again at the final gate.
compatibility: pi
disable-model-invocation: true
---

# Parallel: Review Code

Review what was actually written against what the plan asked for.

You are called in two situations, and they are different jobs:

- **Per fence group** — review this group's diff with the plan in hand.
- **Final gate** — review the whole diff `BASE..HEAD` with fresh eyes. If you are the final
  reviewer, you have not watched the groups, and that is the point: you are the check on
  everyone who convinced themselves along the way.

## Inputs

- Plan directory: `plan.md`, `tasks.json`.
- The diff range to review, and which task IDs it covers.
- `code_review.md` if a previous pass exists.

## Process

1. Read `tasks.json` for the tasks in scope: their briefs, classes, `writes`, `verify`
   commands and `testPaths`.
2. Read the diff.
3. Check each criterion below.
4. Write findings to `code_review.md`. **Do not fix the code yourself** — the orchestrator
   applies fixes, so review and repair stay separate.

## Criteria

### 1. Frozen contracts were not edited
For every `contract` task, the files in `testPaths` must be unchanged since the contract
commit. If a test was modified in the same fence group that made it pass, that is **Critical**,
regardless of how reasonable the modification looks. The whole value of freezing is that this
is not a judgement call.

### 2. Tests genuinely constrain
For each test in the diff, ask: *can this fail because of a change in the behaviour it covers,
without someone editing the test?*

Reject as inadequate:
- assertions that a symbol exists, as the sole coverage of behaviour
- assertions that a file contains a string the same change just wrote
- tests whose oracle is derived from the implementation's own output
- a test that passes identically before and after the change

If you suspect a test does not constrain anything, **say so and ask for a break-it
demonstration** on that specific test. This is the only place break-it is legitimate: demanded
by a reviewer, on a specific suspicion. It is never a routine self-administered checkbox.

### 3. The work matches the task
- Every task in scope is actually implemented, not stubbed or partially done.
- Nothing outside the task's declared `writes` was modified. An undeclared file change is at
  least **Major** — it means the write-set was wrong, which means the parallelism safety
  analysis was wrong.
- No scope creep: work nobody asked for is a finding, even if it is good.

### 4. Correctness
- Error paths, boundaries, and empty/null cases.
- Concurrency and ordering assumptions, especially anything touched by parallel tasks.
- Resource handling and cleanup.
- Security-sensitive changes: input handling, authz, secrets, injection.

### 5. Consistency
- Follows existing repo patterns and per-directory `AGENTS.md` rules.
- Documentation updated where behaviour changed.
- Requirement references honoured if the repo maintains requirements.

## Severity

| Severity | Meaning |
|---|---|
| **Critical** | Wrong, unsafe, or a frozen contract was edited. Must fix before proceeding. |
| **Major** | Likely bug, inadequate test, or an undeclared write. |
| **Minor** | Style, naming, or a non-blocking improvement. |

Calibration:
- A frozen test file modified by the implementing fence group: **Critical**.
- A `contract` task whose test cannot fail: **Critical** — it is worse than no test, because
  it reports success.
- Behaviour changed with no corresponding test change: **Major**.
- A file written outside the declared write-set: **Major**.

## Output

Write `code_review.md`: findings ordered by severity, each naming the task ID, the file, what
is wrong, and what would make it right. End with a verdict — **clean**, or **N Critical / M
Major outstanding** — and state plainly whether the diff is safe to build on.

If you are the final reviewer, also state what you could not verify and what residual risk
you would want a human to know about.

## What you must not do

- Do not edit source or tests.
- Do not re-run the whole plan's verification; the orchestrator runs commands on the host.
- Do not accept "the tests pass" as evidence a test is adequate. That is the question, not the
  answer.
