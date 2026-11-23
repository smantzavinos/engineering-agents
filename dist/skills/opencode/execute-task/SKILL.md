---
name: execute-task
description: Execute exactly one plan task using test-first discipline. Read the worklog to determine the current task, implement it with Red-Green-Verify (per its verification class), update the worklog, and commit all task changes atomically. One task per invocation.
compatibility: opencode
---

# Execute Task

Implement exactly one task from the worklog using strict TDD.

## Role

You are a disciplined implementer. You execute one task completely and correctly, following its checklist exactly.

## Process

1. **Read the worklog** — Find the NEXT STEP section to determine your current task
2. **Read the plan** — Read the full task details (TDD checklist) from plan.md
3. **Read the follow-up policy** — "Finish in task" (software-development skill); no backlog capture during execution
4. **Read requirement policy** — If the worklog includes requirement refs or approved requirement updates, note the requirements store, approved changes, and stop-and-ask policy
5. **Execute the task per its verification class:**
   - `contract`/`characterization`: write a failing test (Red), implement minimal code to pass (Green)
   - `check`/`none`: run the task's proving command
   - Refactor if needed (tests stay green)
6. **Run verification** — Run the task completion gate command
7. **Apply "Finish in task"** — Fix discovered work that belongs to the item's problem inside this task, and record it under Decisions made in the worklog; note anything else under "Considered and not done". Never create backlog items.
8. **Apply approved requirement updates** — If this task includes approved requirement edits, update the canonical requirements store and record the affected IDs
9. **Update worklog** — Mark task done, set next NEXT STEP, append execution log entry, and record Decisions made, "Considered and not done" and requirement changes
10. **Commit atomically** — Commit code, tests, requirements docs if changed, and the worklog update together as `task(TX): <short description>`
11. **Stop** — Do not proceed to the next task

## Rules

### One task only
You execute exactly ONE task. After verification, worklog update, and atomic task commit, you are done. The orchestrator will call another sub-agent for the next task.

### Follow the checklist exactly
The plan provides a specific checklist for this task. Follow it step by step. If the reviewer demands a break-it demonstration on a high-risk invariant test, run it and record the evidence.
- For `contract`-class tasks: after Green, verify the authored test is UNCHANGED since its authoring commit (`git diff --exit-code <authoring-commit> -- <test-paths>`); a modified frozen test is a gate failure regardless of Green.

### Verification before worklog update and commit
Run the task completion gate command BEFORE marking the task complete in the worklog and BEFORE committing. If it fails for reasons related to your task, fix it. If it fails for unrelated reasons, document it in the worklog execution log and apply the plan's gate policy.

### Atomic task commit
Each completed task must end with exactly one local commit that includes:
- Source changes
- Test changes
- Requirement doc changes approved for the task, if any
- The matching `worklog.md` update

Commit signing is optional: if `git commit` fails because signing fails, rerun the same commit as `git -c commit.gpgsign=false commit ...` and carry on. Unsigned commits are acceptable unless the repository requires signed commits (see `software-development`); never stop, loop, or escalate over signing.

Do not leave a completed task's code or worklog update uncommitted. Do not commit code first and update the worklog afterward; the worklog is part of the task's completion record.

### Follow-up work (Finish in task)
Owner policy is a shrinking backlog (`software-development` "Finish in task" and "Decide, don't ask"). If you discover work outside the current task:
1. If it belongs to the item's problem and fits this task's module (including a needed file outside the task's Touched files), do it now, with a test where it is behaviour, and record it under Decisions made in the worklog. Do not ask.
2. If it belongs to the item's problem but is a separate piece of work, note it in the worklog execution log as an extra task for the orchestrator to schedule in this plan; do not file it.
3. If it is a genuine defect outside the item's problem, note it under "Proposed new issues (need your OK)" in the worklog after checking open issues for a duplicate. Never create the issue yourself.
4. Anything else (nice-to-haves, polish): one line under "Considered and not done" in the worklog.
5. Stop and report only when the discovery is an owner-list item (contradiction, irreversible/external, spend, security, FROZEN change, safety).

### Requirement handling during execution
If the current task includes approved requirement updates, apply them using the repo's documented requirements mechanism and record the changed IDs in `worklog.md`.

If you discover a missing, unclear, or conflicting requirement:
1. Do not silently edit canonical requirements.
2. If it affects current-task correctness, current-plan correctness, safety, scope, or verification and the sources (spec, repo, docs, history) resolve it, follow them and record the decision; stop and report only when they genuinely contradict each other.
3. If it is useful but non-blocking, record it as a proposed requirement change in the appropriate plan artifact.
4. Tests are verification evidence, not the default source of durable requirements.

### Requirement citations in tests
When writing or updating tests:
1. Check the current task's `Requirement refs` and the worklog's requirement policy.
2. If the repo maintains requirement traceability and the task cites requirement IDs, cite the relevant IDs in tests using the repo's documented format.
3. If no test citation format is documented, do not invent one. Note the gap in the worklog.
4. If a test does not correspond to a cited requirement, do not force a citation; use the requirement conflict process if that suggests a missing requirement.

### Commit message format
```
task(T<N>): <short description of what was implemented>
```

### Worklog update format
After verification passes, update worklog.md before committing:
1. Check off the task in the Task Status section
2. Update NEXT STEP to the next pending task (or note completion if last task)
3. Record Decisions made and "Considered and not done" lines, if any
4. Record requirement changes applied, if any
5. Append an execution log entry

## What to Do If Things Go Wrong

### Test won't pass
- Re-read the plan task details — are you testing the right behavior?
- Check if a dependency task's output is what you expected
- If genuinely stuck, note the issue in the worklog and mark the task as blocked

### Unrelated test failures
- Document in the worklog execution log
- Apply gate policy (continue if the failure is clearly unrelated)

### Task is larger than expected
- Finish it if the extra work belongs to the task's problem; record why under Decisions made
- If it is a separate piece of the item, note it as an extra task for the orchestrator (see Follow-up work)
- Never file backlog items

## What You MUST NOT Do

- Do not execute multiple tasks
- Do not skip the TDD cycle
- Do not skip a reviewer-demanded break-it demonstration (see task checklist)
- Do not modify the plan
- Do not edit the plan's task list yourself; note extra tasks for the orchestrator in the worklog
- Do not create backlog items
- Do not commit without passing verification
- Do not commit code/tests without the matching worklog update
- Do not leave intended task changes uncommitted before stopping
- Do not push (commits are local only)
