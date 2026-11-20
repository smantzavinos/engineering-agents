---
name: architecture-model
description: The shared rules for a plan whose design is a diagram model built from the project's pattern catalog — what goes in the model and what in plan.md, pattern states and code tags, the checks that tie the model to the code, deviation classes, approval lines, and the commands. Read by plan authors, implementers, reviewers and the sessions that run them.
harnesses: [pi]
---

# Architecture model

A plan's design is a model: a JSON file the diagram tool (`c4ish`) validates and draws as diagrams and a guided tour. The human approves the plan from the tour. The code carries pattern tags, and the model is checked against the code before review and at close.

This skill holds the rules every role shares. `plan`, `implement`, `review`, `scope` and `run-plan` say what each role does with them.

## The files

| File | Holds |
|---|---|
| The **path file**, named in the project's agent guide | Where the catalog docs, the profile and the rules live, and what the checks leave out. Format, and what a catalog entry holds: [references/pattern-catalog.md](references/pattern-catalog.md) |
| `plan.md` | Why, what proves it, and the approval lines |
| `model.c4ish.json`, beside `plan.md` | What is built and how the pieces connect. Committed |
| `review.md`, beside `plan.md` | The ledger: findings, gate evidence, deviations |

Diagrams and tour pages are generated when needed and never committed. After the PR the model is a review record; nobody maintains it.

`c4ish guide` is the reference for writing a model: fields, code reference forms, the tour and what counts as covered. Read it before writing or editing one. Don't restate it.

## One home per kind of content

| Content | Home |
|---|---|
| What is built in code: elements, change state, pattern state, code references, relationships, who enforces each data relationship | Model |
| Interfaces: arguments, results, access rule, limits, failure behaviour | Model contracts, as named clauses. The access rule is always the clause named `access` |
| A risk or open question about one element or connector | A model note attached to it |
| Each scenario's id and title | Model, so a tour step can name it |
| Changes with no place in the picture: migrations, configuration, dependency bumps, build and CI, docs, test infrastructure, catalog, rule and profile files | `plan.md` → Changes outside the model |
| Why: decisions, rejected alternatives, deviations from the prototype | `plan.md` → Design |
| Risks with no place in the picture: rollout, schedule, environment | `plan.md` → Risks |
| Scenario detail, tests, gates, claims, budget, done-when, handoff | `plan.md` |
| The order to look in, and what to notice | Tour narration, one to three sentences a step. It states nothing new |

Nothing is stated twice. No notes file beside the model.

## Pattern states

Every new, modified or reused element that lives in code (a code or data kind in the profile) is in exactly one state. Containers, product concepts and removed elements have none.

| State | Meaning | In the model | Tag on the code | Code review |
|---|---|---|---|---|
| Catalogued | Follows a catalog pattern | `pattern: <id>` | `@pattern <id>` | With a passing rule: skip only what the entry says the rule proves, and read the rest. No rule: a normal read against the golden example |
| Partial fit | Follows it except where stated | The id, `patternFit: partial`, and what differs | `@pattern <id> partial: R4` | Full read of what differs. The rule skips it |
| Proposed | No pattern fits and the shape will be reused; this plan adds it to the catalog | `proposedPatterns` and the id | `@pattern <id>` | Full read. The entry, rule and golden example are in the diff |
| Bespoke | No pattern fits; a one-off | `bespoke: <reason>` | `@pattern bespoke: <what it is>` | Full read |

- A part of an element may state its own pattern, fit or bespoke reason; it is then judged by its own.
- `pattern: null` means "no pattern applies". On an element the build creates or changes it fails the check.
- Untagged changed code is unknown, and gets a full read.
- Tag forms and where a tag goes: the catalog contract → Tags. A tag is added only to a definition the plan creates or changes.
- **A tag agrees with the model** when it names the element's pattern and its further patterns, says `partial` exactly when the model does, and says `bespoke` exactly when the model does.

## Code references

Each new, modified or removed element that lives in code names its definition in `code`: `path#Name`, `path#Outer.Inner`, a label where the code declares no name, or the path alone for a whole file (`c4ish guide` → Code references). A reference is a name, not a line number. One that spans several definitions lists several, or puts them on parts. At plan time the path is enough; the implementer makes each exact before handoff.

## The checks

| Check | Proves | Run with | When |
|---|---|---|---|
| 1. Valid, covered, walked | The model is well formed, the tour points at every review item, and every scenario is walked by a step | `c4ish validate --strict` | Plan author before handoff; plan reviewer |
| 2. Model to code | Each element's code changed as its change state says, its tags agree, no tag sits on code the model doesn't own, and every changed line outside the model is listed | `model-check code` | Implementer before handoff; code reviewer; a helper at close |
| 3. Approved versus shipped | Every difference from the approved model is recorded as a deviation, and none needs re-approval | `model-check approved` | The same three |

- A valid model can still be wrong or incomplete. Checks 2 and 3 and the reviewer close that gap.
- Check 2 lists **unaccounted lines**: changed production lines that no code reference owns. The reviewer reads all of them.
- The implementer's recorded results are claims. The code reviewer owns the verdict on checks 2 and 3.

## Deviations

A deviation is a difference from the approved model in what check 3 compares. It does not compare titles, descriptive text, code references, views, layout, tours or narration.

| Class | What changed | What happens |
|---|---|---|
| **Detail** | Nothing compared: internals, private names, file layout, code references, tests | Build it, note it in the ledger, update the references |
| **Model change** | Anything compared that is not on the re-approval list | Update the model in the same commit as the code, and record it under Deviations. The code reviewer judges each, and may raise one to re-approval |
| **Re-approval** | Anything on the list below | Stop for the human |

**Re-approval** is needed for:
- a data element, a container or a product element added or removed, or one whose kind changes into or out of those;
- enforcement on a data relationship or tie moved down the order `platform`, `platform-correlated`, `derived`, `our-code`, `nothing`; or a new one enforced by `our-code` or `nothing`;
- a contract or a clause removed, or the `access` clause added or changed;
- a catalog, rule, profile or path file changed that the approved `plan.md` → Changes outside the model doesn't list;
- a scenario removed, or one that can't be delivered as approved.

When a difference fits both lists, re-approval wins.

**Model changes** include: a component added, split, merged or dropped; a change state that flips (planned reused, built modified); a new bespoke or partial-fit element; one catalogued pattern swapped for another; a relationship added, removed or rerouted without lowering enforcement; fields, indexes or ties changed without lowering enforcement; a clause added, or one other than `access` changed; a library added; a golden example changed; a scenario added.

**Recording.** The ledger has a section headed exactly `Deviations`, at any heading level. One list item per differing item, starting with its key in backticks, as the tool names it:

```
### Deviations
- `element:collector` dropped; nothing calls it after the page reads landed
- `relationship:mergeIndexes` rerouted through the summary query
```

`plan.md` → Changes outside the model has the same form: one list item per path or glob, starting with it in backticks.

## Approval lines

- `Approved: <date> <commit>` in `plan.md` names the commit that holds the approved model. `Re-approved: <date> <commit>` follows a re-approval, with what changed.
- Checks 2 and 3 are judged by the latest of them: the path file, the profile and Changes outside the model are read at that commit, never from the working copy.
- **Only the session that receives the human's approval writes one:** `scope` at the gate, `run-plan` at a re-approval stop. A plan-author, implementer, reviewer or helper never writes or edits one.
- The check can't tell who wrote a line, so it prints the lines it relied on. The code reviewer confirms each against what the human approved.

## Commands

`<plan>` is the plan directory; `<skill>` is this skill's directory.

```sh
c4ish validate <plan>/model.c4ish.json --strict      # until: 0 error(s), 0 warning(s)
c4ish view <plan>/model.c4ish.json --tour            # the tour, in the viewer
c4ish tour <plan>/model.c4ish.json --out <dir>       # the tour as static pages
c4ish diff <plan>/model.c4ish.json --base <commit> --out <file>   # a tour of only what differs
node <skill>/tools/model-check.mjs all --model <plan>/model.c4ish.json --project <path file>
```

- Generated files (tour pages, diagrams, a differences tour) go outside the repo tree. They are never committed, and an untracked file in the tree counts as a change.
- `model-check` takes `code`, `approved` or `all`. It reads `plan.md` and `review.md` beside the model. Exit 0 is a pass, 1 a failure or a re-approval difference, 2 an error. `--json` prints the full result.
- The command is fixed: `--model` is the plan's own model and `--project` is the path file the agent guide names. Anything else is not the check.
- It runs only on an approved plan. `--no-approval` is a trial on an unapproved plan, judged by the working copy and marked as one. A trial is never evidence.
- It needs `c4ish` on the path. When either is missing, stop and report; don't work around it.

## Don't
- State anything in two homes.
- Write a tag the model doesn't agree with, or leave the model behind the code.
- Change a catalog, rule, profile or path file the approved plan doesn't list.
- Loosen a rule, a tag or the model to make a check pass.
