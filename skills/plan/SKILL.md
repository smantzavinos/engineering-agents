---
name: plan
description: Write a short, decisive implementation plan for one child of an epic (or for a single plan), revise it from review findings, and hand back. Used by the plan-author subagent.
harnesses: [pi]
---

# Plan

Write the plan a strong engineer needs to build this child in one session without guessing, and nothing more. You will be resumed with review findings, so this session owns the plan until it is approved.

## Inputs
- `epic.md` and this child's entry; the previous child's `plan.md` and ledger, for what it left behind;
- `PROTOTYPE.md` and the prototype diff;
- the repo's docs and rules;
- the code that will change.

Scout widely with subagents (`delegate`), and read the critical paths yourself.

## plan.md
- **Goal:** what this child delivers, and the acceptance scenarios it owns. For a single plan there is no epic, so this section also carries scope in/out, disposal, gates, budget and autonomy limits as agreed with the human.
- **Context:** links to the code, docs and earlier decisions that matter.
- **Design:** the key decisions and why. Name rejected alternatives when the choice isn't obvious.
- **Changes:** by area or module, what changes and where. Enough to start, not a script.
- **Tests:** what to add and at which level, mapped to acceptance scenarios and to the risky logic. Name the E2E specs this child's changes touch; the epic may run only those per child.
- **Gates:** the repo commands to run at the end, per `epic.md`.
- **Done when:** observable criteria.
- **Risks:** what could go wrong, and how to handle it.
- **Handoff:** a few lines for the implementer, written last: what review settled, where you were unsure, what to watch.

Aim for under 150 lines.

## Judgment calls
- **Course-setting decisions**, the ones that shape most of the remaining children: consult the oracle first. Take a clearly better option and record it. If there is none, say so in your reply; the orchestrator stops for the human.
- **Sizing:** if this child can't be built in one implementer session or its diff won't be reviewable, or if it is trivially small, say so with a proposed split or merge. Don't silently plan half of it.

## Revising
For each finding in `review.md`, either fix it, or reject it with a one-line reason under the finding. If the reviewer has already disputed a rejection, or you're unsure, ask the oracle; its ruling settles the finding.

## Handoff
1. Commit `plan.md` and your `review.md` responses.
2. Reply in a few lines: a summary, sizing or course-setting flags, and the open risks.

Everything the next session needs is on disk, so you can be resumed or replaced. Call `self_compact` only when a context warning asks for it, and say so in your reply.

## Do
- Make the decisions. A plan that defers design to the implementer is not done.
- Follow the repo's patterns. Say where you deliberately depart from them, and why.

## Don't
- Restate repo rules or docs. Link them.
- Write task tables, execution tiers or step-by-step checklists.
- Plan beyond this child. Flag cross-child issues to the orchestrator.
