---
name: plan
description: Write the plan for one piece of work — a short plan.md and a diagram model built from the project's pattern catalog — revise it from review findings, and hand back. Used by the plan-author subagent.
compatibility: pi
---

# Plan

Write what a strong engineer needs to build this in one session without guessing, and what a human needs to approve it in minutes: a model they can read as a tour, and a short `plan.md`. You will be resumed with review findings, so this session owns the plan until it is approved.

`architecture-model` holds the rules this skill relies on: what goes in the model and what in `plan.md`, pattern states, code references and the commands. Read it first.

## Inputs
- the agreed scope in your task, or `epic.md` and this child's entry, with the plans, models and ledgers of the children it depends on. A dependency that isn't built yet is represented by its approved plan: plan against that, and expect a scout to check the plan once the code is integrated;
- `PROTOTYPE.md` and the prototype diff;
- the project's path file, its catalog docs and profile (`architecture-model` → The files);
- the repo's docs and rules, and the code that will change.

Scout widely with subagents (`delegate`), and read the critical paths yourself.

## The model
`model.c4ish.json` beside `plan.md`, written as `c4ish guide` says, against the project's profile: set the model's `profile` to the profile's path relative to the model, so that `validate` and the checks judge it by the same one.
- **What it shows:** every element the work adds, changes or removes, and the unchanged context one hop from them. Product concepts when the user sees a difference, and the engineering elements that implement each.
- **Each element** has a change state. Each new or modified one that lives in code has a pattern state; reused context names its pattern when the catalog has one, and otherwise says `pattern: null`. Each new, modified or removed one has a code reference, at least to its path.
- **Choosing a pattern:** start from the chooser table of the catalog area. Read the entry and its golden example before you draw the element, and draw it as the entry's "In a plan model" says.
- **Relationships:** each data relationship says who enforces it.
- **Contracts:** every interface two elements build against, as named clauses. The access rule is the clause named `access`.
- **Notes:** a risk or open question about one element or connector, attached to it.
- **Scenarios:** each acceptance scenario by id and title. The detail stays in `plan.md`.
- **Ids are stable.** Give an id to every part, tie and note whose text may change. Ids never change after approval.

**No pattern fits:**
- *A one-off:* mark it bespoke with a one-line reason. First search the code for `@pattern bespoke` doing the same job. If there is one, this is the second use: propose a pattern that covers both, add the earlier code to the model as a reused element with a code reference, and plan its retag. That edit is allowed outside the claim.
- *A shape that will be reused:* propose a pattern. At plan time you write its `proposedPatterns` entry in the model, and in `plan.md` → Design what it goes through, what it protects against and its numbered requirements, with the element that will be its golden example. The implementer writes the catalog entry, the profile entry and any rule, in the form the catalog contract gives; list those files under Changes outside the model. The human approves the proposal with the plan.

**The tour:** one tour, id `review`, in the order a reviewer should look: what changes for the user, the main flows, the patterns in use, each proposed pattern and bespoke element, what is removed, then the risks. Every scenario is walked by a step that actually shows it. One to three sentences a step, stating nothing that isn't in the model or `plan.md`.

**Before handoff:** `c4ish validate --strict` prints `0 error(s), 0 warning(s)`. Then open the tour pages and read them as the human will.

## plan.md
- **Goal:** what this delivers, the acceptance scenarios it owns, and an estimate in changed lines with the implementer's hours for it. For a single plan there is no epic, so this section also carries what was agreed with the human:
  - scope in and out, and disposal;
  - the full-gate commands, the test map and the smoke set;
  - budget and autonomy limits, and an escalation implementer if one was named.
- **Context:** links to the code, docs and earlier decisions that matter.
- **Design:** the key decisions and why, rejected alternatives when the choice isn't obvious, and each departure from the prototype with its reason. Then a link to the model: it is the Changes section.
- **Changes outside the model** (this exact heading): one list item per path or glob, starting with it in backticks. Migrations, configuration, dependency bumps, build and CI, docs, test infrastructure, and every catalog, rule or profile file a proposal adds or changes. A catalog, rule or profile file changed without being listed here stops the build for re-approval.
- **Scenarios:** each with its id, as in the model, and what must be observed.
- **Tests:** the contracts each scenario and each risky piece of logic needs proven, and the owning layer for each (`test-quality`), including the tests each pattern's entry asks for. This is the test budget: code review rejects new tests that don't trace to it, so keep it complete and lean.
- **Gates (T1):** the commands, run once at the end of implementation:
  - typecheck and build for the touched packages;
  - lint and format on the changed files, and the project's pattern rules on them;
  - units selected against the base commit, plus a whole-package rerun when its config, test setup or a shared module changes;
  - E2E: this plan's scenario specs, the test-map specs for the changed paths, and the smoke set. Without a test map, name the specs for the paths you expect to change.

  **Widen** T1 to the whole affected packages and all mapped specs when the work touches schema, migrations, seed data, authorization or visibility, the shared shell, dependencies or build config. **Escalate** to full gates when it touches test infrastructure. Say which applies, and why.
- **Claims** (in an epic with a worktree pool): the child's claim from `epic.md`, refined to directories, routes and tables. The files come from the model's code references. Stay inside it.
- **Done when:** observable criteria, and the **Deliverables**: the outcomes the build must contain (scenarios, specs, UI behaviours), not tasks. The implementer maps each to its evidence.
- **Risks:** only those with no place in the picture: rollout, schedule, environment.
- **Handoff:** a few lines for the implementer, written last: what review settled, where you were unsure, what to watch.

The plan questions (`references/plan-questions.md`) are answered where they are drawn. `plan.md` gives each one line pointing at the ids, or "n/a":
- **Access and visibility:** the `access` clauses, the enforcement on each data relationship, and each guard's owning test.
- **Failure and concurrency:** contract clauses and notes.
- **Limits and load,** for read-heavy features: a `limits` clause or a note.
- **Assumptions checked against the code** (Context, Gates), **Departures from the prototype** (Design) and **Deliverables** (Done when) stay in `plan.md`.

Aim for under 120 lines. If `plan.md` describes an element, a connection or an interface, move it to the model.

## Code in submodules
Where the plan lives in one repository and the code in git submodules of it (`architecture-model` → `references/repositories.md`):
- every code reference, and every item under Changes outside the model, is a path from the root, the submodule's path first;
- `plan.md` → Goal lists the repositories the plan changes, and Gates gives the T1 commands for each;
- you write only in the root: `plan.md`, the model and your ledger responses;
- if the design needs a submodule the scope didn't name, say so in your reply, so it gets a branch and a base before the approval.

## Judgment calls
- **Course-setting decisions**, the ones that shape most of the remaining work: consult the oracle first. Take a clearly better option and record it. If there is none, say so in your reply; the session that started you stops for the human.
- **Sizing:** record the estimate. A plan is as large as the work needs: never propose a split to meet a size number. Say so in your reply if the work holds parts with their own goal that could each be approved and shipped alone; that is the only reason to divide it.
- **Scope:** plan only what you were given. A fix or improvement outside it goes on a short Follow-ups line in `plan.md`.
- **Claims:** if the design needs to go outside the `epic.md` claim, say so in your reply.

## Refresh
A fresh session, started in the child's worktree when the scout found integrated changes the plan relies on.
1. Read the `## refresh scout` note in the ledger, the plan, the model and the ledger.
2. Check the plan and the model against what the note names: the integrated code, `epic.md` changes and any checkpoint merge.
3. Update what changed, including the estimate and any code reference that moved. The plan is already approved, so a change to the model is a deviation: append `## plan refresh` to the ledger with a `### Deviations` list of what you changed and why (`architecture-model` → Deviations). Commit it all as one refresh commit. Its review covers only that commit.
4. Reply with the refresh commit, the old and new estimate in lines and hours, and whether claims, scenarios or anything on the re-approval list (`architecture-model` → Deviations) changed. Don't `self_compact`; refreshes are short.

## Revising
For each finding in `review.md`, either fix it, or reject it with a one-line reason under the finding. If the reviewer has already disputed a rejection, or you're unsure, ask the oracle; its ruling settles the finding. Validate the model again after every change. Your reply lists the findings you rejected, and says whether any fix changed a contract (an interface, data shape, access rule or scenario).

## Handoff
1. Commit `plan.md`, the model and your `review.md` responses. No rendered diagrams or tour pages.
2. `self_compact` with a note: what you decided and why, what's open, and how to continue.
3. After compaction, reply in a few lines: a summary, the validate result, each proposed pattern and bespoke element, sizing or course-setting flags, and the open risks.

Everything the next session needs is on disk, so you can be resumed or replaced.

## Do
- Make the decisions. A plan that defers design to the implementer is not done.
- Build from the catalog. A bespoke element or a proposed pattern needs a reason a reviewer can check.

## Don't
- State anything in two homes, or restate repo rules, docs or catalog entries. Link them.
- Write task tables, execution tiers or step-by-step checklists. The Deliverables list of outcomes is not one.
- Write an `Approved:` line, or change a catalog entry without proposing it.
- Plan beyond what you were given. Flag issues outside it in your reply.
