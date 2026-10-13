---
name: plan
description: Write a short, decisive implementation plan for one child of an epic (or for a single plan), revise it from review findings, and hand back. Used by the plan-author subagent.
harnesses: [pi]
---

# Plan

Write the plan a strong engineer needs to build this child in one session without guessing, and nothing more. You will be resumed with review findings, so this session owns the plan until it is approved.

## Inputs
- `epic.md` and this child's entry; the previous child's `plan.md` and ledger, for what it left behind. If you're planning ahead, the previous child is still being built: plan against its approved plan, and expect a refresh;
- `PROTOTYPE.md` and the prototype diff;
- the repo's docs and rules;
- the code that will change.

Scout widely with subagents (`delegate`), and read the critical paths yourself.

## plan.md
- **Goal:** what this child delivers, the acceptance scenarios it owns, and an estimate of the implementer's hours. For a single plan there is no epic, so this section also carries what was agreed with the human:
  - scope in and out, and disposal;
  - the full-gate commands, the test map and the smoke set;
  - budget and autonomy limits.
- **Context:** links to the code, docs and earlier decisions that matter.
- **Design:** the key decisions and why. Name rejected alternatives when the choice isn't obvious.
- **Changes:** by area or module, what changes and where. Enough to start, not a script.
- **Tests:** the contracts each acceptance scenario and each risky piece of logic needs proven, and the owning layer for each (`test-quality`). This is not a test checklist.
- **Gates (T1):** the commands, run once at the end of implementation:
  - typecheck and build for the touched packages;
  - lint and format on the changed files;
  - units selected against the base commit, plus a whole-package rerun when its config, test setup or a shared module changes;
  - E2E: this child's scenario specs, the test-map specs for the changed paths, and the smoke set. Without a test map, name the specs for the paths you expect to change.

  **Widen** T1 to the whole affected packages and all mapped specs when the child touches schema, migrations, seed data, authorization or visibility, the shared shell, dependencies or build config. **Escalate** to full gates when it touches test infrastructure. Say which applies, and why.
- **Claims** (only for a child in a parallel group): restate the child's claim from `epic.md`, refined to the files, routes, tables and shared components it will change. Stay inside it.
- **Done when:** observable criteria.
- **Risks:** what could go wrong, and how to handle it.
- **Handoff:** a few lines for the implementer, written last: what review settled, where you were unsure, what to watch.

Aim for under 150 lines.

## Judgment calls
- **Course-setting decisions**, the ones that shape most of the remaining children: consult the oracle first. Take a clearly better option and record it. If there is none, say so in your reply; the orchestrator stops for the human.
- **Sizing:** estimate first. If the child exceeds the epic's size limit, stop before writing the full plan. Reply with a proposed split into vertical slices, giving each slice's scenarios and a rough estimate. If it is trivially small, propose a merge. Don't silently plan half of it.
- **Scope:** plan only this child's entry. A fix or improvement outside it goes on a short Follow-ups line in `plan.md`, not into Changes.
- **Claims:** if the design needs to go outside the `epic.md` claim, say so in your reply. The orchestrator serializes or re-scopes the child.

## Refresh
If you planned ahead, you'll be resumed after the previous child closes.
1. Merge the work branch into your plan branch.
2. Check your plan against:
   - what was actually built, meaning the previous child's diff and ledger;
   - changes to `epic.md`: your entry, Decisions and Follow-ups;
   - any checkpoint merge since you planned.
3. Update what changed, including the estimate, and commit.
4. Reply saying whether the design or the estimate changed, or only names and paths.

## Revising
For each finding in `review.md`, either fix it, or reject it with a one-line reason under the finding. If the reviewer has already disputed a rejection, or you're unsure, ask the oracle; its ruling settles the finding.

## Handoff
1. Commit `plan.md` and your `review.md` responses.
2. `self_compact` with a note: what you decided and why, what's open, and how to continue.
3. After compaction, reply in a few lines: a summary, sizing or course-setting flags, and the open risks.

Everything the next session needs is on disk, so you can be resumed or replaced.

## Do
- Make the decisions. A plan that defers design to the implementer is not done.
- Follow the repo's patterns. Say where you deliberately depart from them, and why.

## Don't
- Restate repo rules or docs. Link them.
- Write task tables, execution tiers or step-by-step checklists.
- Plan beyond this child. Flag cross-child issues to the orchestrator.
