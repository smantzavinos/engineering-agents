---
name: create-worklog
description: Create a worklog.md execution log from a reviewed plan. The worklog serves as the single entry point for each implementation iteration — read it first, do one task, update it, advance. Use after plan review passes.
compatibility: opencode
---

# Create Worklog

Create an execution worklog from a reviewed plan.

## Role

You produce the durable execution tracking document that implementation sub-agents will use to know what to do next.

## Inputs

- Plan directory path
- Read: `plan.md` (for task list and verification commands)
- Read: Repo test architecture docs (for exact verification commands if plan references them)
- Read: Repo task-tracking/backlog docs if available (stable ID format only; follow-ups follow "Finish in task")
- Read: Repo requirements docs if available and the plan cites or updates requirements

## Process

0. **Verify the gate** — Read `plan_review.md`; abort unless its latest pass
   reports zero Blocker/Critical/Major findings AND the human approval is
   recorded (plan approval is a human gate — if absent, stop and present the
   plan). Carry the confirmed execution mode into the worklog header.
1. **Read plan.md** — Extract task list, verification commands, gate policies
2. **Read repo test docs** — Get exact commands (referenced in AGENTS.md / test architecture docs)
3. **Read repo task-tracking docs** — Get backlog store, stable ID format, default capture status, and critical-item policy if documented
4. **Read repo requirements docs** — If the plan cites or updates requirements, capture the requirements store, ID/reference format, test citation format, approval source, and apply-approved-change procedure
5. **Baseline gate audit** — If the plan includes a Baseline Gate Audit section, carry its results into the worklog. If no baseline audit has been done yet, the worklog must instruct the implementer to run all gates before T1 and record results.
6. **Write worklog.md** — Using the template in [references/worklog-template.md](references/worklog-template.md)
7. **Update state.json** — Set `{ "phase": "ready", "status": "active" }`

## Quality Rules

### Verification commands must be exact
Copy exact commands from plan.md or repo docs. Do NOT invent commands.

### The worklog must be self-sufficient
An implementation sub-agent should be able to read ONLY the worklog and know:
- What task to do next
- What verification commands to run
- What the completion criteria are
- Where to find the plan for detailed instructions

### Task list must match plan exactly
Extract tasks from plan.md in order. Don't reword, reorder, or add tasks.

### Prerequisites must be documented
The worklog must include environment setup needed before implementation:
- Required services (db, redis, docker) with start/stop commands
- Required env vars (names only, no secrets)
- Runtime versions
- How to start/stop services

Get this from repo docs, CI workflow files and build scripts; record anything you had to infer.

### Gate policy must be explicit
The worklog must state the plan's chosen unrelated failure policy (`block-on-global-gate` | `allow-scoped-completion` | `split-follow-up`) and include instructions for what the implementer should do if a broader gate fails for reasons unrelated to their task.

### Gate rationale must be explained
The worklog must include a brief note explaining what the task completion gate catches that fast-feedback commands miss (e.g., type mismatches between packages, missing exports, interface drift, cross-module integration issues). This teaches the implementer WHY the gate matters.

### Follow-up policy must be explicit ("Finish in task")
The worklog must state the owner's follow-up policy (`software-development` "Finish in task" and "Decide, don't ask") and give implementers these sections to fill:
- `Decisions made` — numbered, each with its source; includes extra work done because it belonged to the item
- `Extra tasks for the orchestrator` — work that belongs to the item but did not fit its task
- `Considered and not done` — one line each; never filed
- `Proposed new issues (need your OK)` — only genuine defects outside the item, after a duplicate search; never created by an implementer

Implementers never create backlog items, and stop only for owner-list items (contradiction the sources cannot resolve, irreversible or external action, spend, security, a FROZEN change, safety).

### Requirement change policy must be explicit when relevant
If the plan cites or updates requirements, the worklog must tell implementers:
- Where canonical requirements live
- Which requirement updates are approved by the plan
- How to apply approved requirement edits
- What requirement IDs/reference format to record in the worklog
- What test citation format to use when tasks cite requirement IDs
- What to do if execution reveals a missing, unclear, or conflicting requirement

If no repo requirements mechanism is documented, write that explicitly and instruct implementers to ask before editing canonical requirements.

## Output

Write `worklog.md` in the plan directory. The worklog is designed for one-task-per-sub-agent-call execution.

## What You MUST NOT Do

- Do not implement code
- Do not modify source files
- Do not invent verification commands
- Do not reorder or reinterpret plan tasks
