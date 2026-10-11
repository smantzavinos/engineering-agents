---
name: plan
description: Write a short, decisive implementation plan for one child of an epic (or for a single plan), revise it from review findings, and hand back compacted. Used by the planner subagent.
---

# Plan

Write the plan a strong engineer needs to build this child in one session without guessing, and nothing more. You will be resumed with review findings, so this session owns the plan until it is approved.

## Inputs
- `epic.md` and this child's entry;
- `PROTOTYPE.md` and the prototype diff;
- the repo's docs and rules;
- the code that will change.

Scout widely with subagents (`delegate`), and read the critical paths yourself.

## plan.md
- **Goal:** what this child delivers, and the acceptance scenarios it owns.
- **Context:** links to the code, docs and earlier decisions that matter.
- **Design:** the key decisions and why. Name rejected alternatives when the choice isn't obvious.
- **Changes:** by area or module, what changes and where. Enough to start, not a script.
- **Tests:** what to add and at which level, mapped to acceptance scenarios and to the risky logic.
- **Gates:** the repo commands to run at the end.
- **Done when:** observable criteria.
- **Risks:** what could go wrong, and how to handle it.

Aim for under 150 lines.

## Revising
For each finding in `review.md`, either fix it, or reject it with a one-line reason under the finding. If unsure, ask the oracle; its ruling settles the finding.

## Handoff
1. Commit `plan.md` and your `review.md` responses.
2. `self_compact`, with a note listing the plan path, the key decisions and anything still open.
3. After compaction, reply in at most 10 lines: a summary, the decisions the orchestrator should know, and the open risks.

## Do
- Make the decisions. A plan that defers design to the implementer is not done.
- Follow the repo's patterns. Say where you deliberately depart from them, and why.

## Don't
- Restate repo rules or docs. Link them.
- Write task tables, execution tiers or step-by-step checklists.
- Plan beyond this child. Flag cross-child issues to the orchestrator.
