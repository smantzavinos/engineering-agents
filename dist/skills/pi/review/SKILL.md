---
name: review
description: Fresh-context review of an epic, a plan with its model, or a code diff against the approved model. Finds what matters, checks earlier findings, owns the verdict on the model checks, and records results in the review ledger. Used by reviewer subagents; never by the author.
compatibility: pi
---

# Review

You have no history with this work. Judge it against what it was meant to do. Find what would hurt: wrong behavior, missing scope, poor design, missing tests, risk. Skip everything else.

A plan's design is a model built from the project's pattern catalog. `architecture-model` holds the rules you judge by: what belongs in the model and in `plan.md`, pattern states, the checks, deviation classes, approval lines and the commands. Read it first.

## Modes
- **epic:** `epic.md` against `PROTOTYPE.md`. Check that:
  - the scope is complete, and the gaps the prototype skipped are addressed;
  - each child is a distinct workstream: it has its own goal and could be approved and shipped alone. Work divided only to keep plans small is a major; so is one design cut across children;
  - each child has declared dependencies and, with a worktree pool, a claim;
  - each contract that crosses children is named with the child that owns it, and each pattern a child is expected to propose is claimed by one child;
  - each dependency is needed for built behaviour. A dependency that lengthens the longest chain only for a contract, which an earlier child the dependent already depends on could deliver, is a major;
  - groups have at most `maxLanes` members, `maxLanes` is at most the pool size, and members' claims don't overlap;
  - every acceptance scenario has an owner;
  - gates, budgets and pre-authorizations are explicit enough to run unattended.
- **plan:** `plan.md` and `model.c4ish.json` against the agreed scope (the task, or the epic entry). Read the model as the human will: run `c4ish validate --strict`, generate the tour pages outside the repo (`architecture-model` → Commands) and walk them, then read the JSON for what the pictures don't show. Check the model:
  - it validates with no errors and no warnings, and the tour points at every review item;
  - it is right and complete against the code: an element or connection the work needs and the model lacks is a major. Validation can't see this; scout the code;
  - every new or modified element that lives in code has a pattern state, and every new, modified or removed one has a code reference, at least to its path. A missing one is a major. Reused context that follows a catalog pattern and doesn't name it is a minor;
  - each pattern fits: the element is what the catalog entry describes and is drawn as the entry's "In a plan model" says. A partial fit names the requirement it misses;
  - each bespoke reason holds. One that an existing pattern, or existing `@pattern bespoke` code doing the same job, answers is a major;
  - each proposed pattern is worth one (the shape will be reused). Its requirements in `plan.md` → Design can be checked on one definition, the element named as its golden example can meet them all, and its catalog, rule and profile files are listed under Changes outside the model. The files themselves are written in the build;
  - no pattern the model uses is a draft entry: one the profile marks `proposed` and this plan doesn't propose. A draft in use is a major until the human approves the entry;
  - every scenario is walked by a tour step that actually shows it;
  - contracts can be implemented as written, every access rule is a clause named `access`, and every data relationship says who enforces it;
  - context is one hop from what changes: no inventory of the system, and nothing the change touches left out;
  - nothing is stated in two homes. A repeat is a minor; a contradiction is a major.

  Check that the plan:
  - can be built without guessing;
  - makes sound decisions;
  - states its estimate. Size alone is never a finding;
  - answers the plan questions where they are drawn, with a pointer in `plan.md` (`plan` → plan.md). A missing answer on access and visibility, failure and concurrency, or deliverables, where the plan has that concern, is a major; on the others, a minor;
  - lists under Changes outside the model every change with no place in the picture;
  - stays inside the child's entry. Work beyond it that isn't on the plan's Follow-ups line is a major finding;
  - where a dependency isn't built yet, judge references to its work against its approved plan, not the code;
  - names the contracts to prove, at sensible layers (`test-quality`). The list is the test budget, so check that it is complete and lean. Judge each contract, not its mechanics: what it proves, at which layer, and whether another test already owns it. Locators, assertion construction, fixture detail and whether a planned test can fail are for code review; here they are minors for the implementer;
  - fits the codebase;
  - has a T1 selection, widening or escalation that fits what changes;
  - claims that stay inside its `epic.md` claim; for a group member, they don't overlap its siblings'.

  Tag every major with its kind: `design`, `boundary`, `claims`, `scope` or `cohesion` (a fix needs a re-check), or `tests`, `T1` or `wording` (it doesn't). A major about the model is `design` or `boundary`.

  **Plan refresh:** head the pass `## plan refresh pass N`. Review only the refresh commit, against the integrated range you were given: does the plan still fit that code, and is the edit itself correct? The deep-pass rule doesn't apply. Findings on text the refresh didn't change are minors.
- **code:** the diff (from the base commit you were given) against `plan.md` and the model. First the model checks, then the code.

  **The model checks.** The implementer's ledger entry records its `model-check` runs. Treat them as claims, and own the verdict:
  - run `model-check all` yourself with the fixed command (`architecture-model` → Commands), on the commit you review. A different result from the recorded one is a major;
  - **approval lines:** the check prints the lines it relied on. Confirm each against the approvals your task gives, as the session that received them recorded them: date, commit, and in an epic who approved. A line you can't confirm is a blocker;
  - check 2: any failure is a major;
  - **unaccounted lines:** read every run of them. Accept it as glue, or raise the missing element as a major. A run in a file the plan didn't list under Changes outside the model must be noted under Details in the ledger; judge whether it belongs in this plan;
  - check 3: a difference with no recorded deviation is a major. A re-approval difference is a stop: record it as a blocker headed `re-approval`, and say so first in your reply;
  - **each recorded deviation:** is it right, and is its class right? One recorded in too low a class is a major. Raise a model change to re-approval when it loosens what the human approved in a way the comparison can't see: a limit raised in a clause's text, or more changed in a listed catalog file than the plan proposed;
  - the model still validates, and still tells the truth about the code it points at.

  **Read by pattern state.** For each changed definition, find its element and its tag:
  - *catalogued, with a rule that passes:* skip only what the entry says the rule proves. Read the logic, the contract and the tests;
  - *catalogued, no rule:* read against the entry's requirements and its golden example. A requirement missed under a full-fit tag is a major; a missed convention is a minor;
  - *partial fit, proposed, bespoke or untagged:* read in full. For a proposal, also judge the entry, the rule and the golden example in the diff against the catalog contract and the requirements the human approved, and check that the pattern left the model's `proposedPatterns` when its profile entry landed;
  - *a golden example whose code changed:* it still meets every requirement of its entry, and has every test the entry asks for. If not, a major;
  - a definition that copies shared code instead of going through it is a major, whatever its tag.

  Run the project's pattern rules on the changed files when the ledger doesn't show them passing on this tree.

  Check that the diff:
  - does what the plan and the model say, and is correct and tested;
  - is consistent with the codebase;
  - updates the affected docs;
  - delivers every Deliverable in the plan's Done when. One missing from the implementer's map, marked done but not delivered, or not done without an accepted deviation is a major;
  - resolves each refresh major you were given, in `plan.md` and in the code. A fix that is wrong against the integrated code is a major against the plan; the orchestrator sends the plan change to a fresh plan-author.

  For an integration review, use the ledger and pass heading your task names.

  **A large diff** (above the plan's review-load estimate) is read in groups when your task says so: you are given one container's files, or the last group (shared files, unaccounted lines, tests, docs), and add your own section to the ledger. The last reviewer reads the joins: the contracts between groups, the deviations and the model checks, and gives the single verdict. This is untested; say in your reply what the grouping hid.

  Apply `test-quality` to every new or changed test, with its severities. Every new test proves a contract: one in the plan's Tests, or one the ledger records with a reason. That includes regression tests for bugs found while building, and independent contracts the plan's list doesn't reach, such as config, defaults or migrations (`test-quality` → Keep). A test moved, split or rewritten because its contract changed isn't new. A test with no contract is a major finding. A test whose contract is missing only from the ledger is a minor: record it, don't delete the test. A test-to-production ratio well above earlier children's means look closer; it isn't a finding by itself.

  Tag every major with its kind. A major is `tests`, `T1` or `wording` only if its fix can't change production behaviour. Tag every other one (wrong behaviour, a missing deliverable, docs, design, boundaries, claims, scope, a merge error) `design`, `boundary`, `claims`, `scope` or `cohesion`: its fix needs a re-check.

  The implementer's ledger entry holds the gate evidence. Treat it as claims. In a child's own passes, T1's unit and E2E tests run in a helper beside you, and their results reach the orchestrator, not you. Check that:
  - the fast gates ran, and the recorded T1 command lines cover the actual diff and match the plan;
  - in integration and checkpoint-fix reviews, which still get implementer-run T1, flakes are outside the diff.

  While a T1 helper runs in your worktree, don't run tests: record a doubt as a minor that names the check, and the next T1 run includes it. Otherwise run a targeted test when you doubt something. Never run full suites.
- **epic-diff:** the whole epic's diff. Check the seams between children (each cross-plan contract against its owner's model), and parity with every acceptance scenario. Name, for each finding, the child whose review should have caught it.

## Code in submodules
Where the plan lives in one repository and the code in git submodules of it (`architecture-model` → `references/repositories.md`), in code mode:
- first confirm the state was handed over: every submodule the plan changes is clean and at the commit the root commit under review points to. If not, record a blocker headed `not handed over`, and read nothing further;
- the diff is each repository's own: in a submodule, from its base (your task gives it) to the commit the root points to; after pass 1, between the commits the two root commits of your range point to;
- run `model-check` from the root, and record in your pass the submodule commits it printed. They must be the ones the root commit points to;
- gate evidence is per repository: check each repository's recorded command lines against its diff;
- you commit only the ledger, in the root.

## Earlier passes
Read the ledger first. For each earlier finding, verify in the artifact or diff, not in the response, whether it is fixed, rejected for a good reason, or still open. Oracle rulings are settled. If you disagree with a rejection, say so once; the author must then take it to the oracle.

In code mode after pass 1, review only the range you were given, and verify each open finding there. For a merge in the range, review only its conflict resolution (`git show --remerge-diff <merge>`), not the incoming changes.

Pass 1 is the deep pass: be complete, so later passes confirm rather than discover. After pass 1, raise a new finding only if it is a blocker or major, or if a fix caused it. In plan mode, a new major after pass 1 must concern design, boundaries (including a missing contract for authorization, visibility or data integrity), claims, scope or cohesion. Other Tests-list and T1 findings after pass 1 are minors.

## Findings
Append `## <mode> pass N` to the ledger (`review.md` in the child directory, or at the plan root for epic and epic-diff modes). Each finding has an ID, a severity, a location, the problem and a suggested fix. Severities:
- **blocker:** wrong, unsafe, or missing required scope.
- **major:** will cause real problems, and must be fixed before approval.
- **minor:** worth fixing if it's cheap.

Don't record nits. The work is approved when no blocker or major finding remains open. Commit the ledger, staging only that file.

## Reply
Reply with only the verdict (approved, or changes needed), the counts by severity and the ledger path. In code mode, add the `model-check` result and the approval lines you confirmed; if a re-approval difference is open, say `re-approval needed` first, with the differing items. In plan and code mode (not refresh), end with `pass 2 needed: yes` if any blocker or any major of a kind that needs a re-check is open, otherwise `pass 2 needed: no`.

## Do
- On a large diff, gather context with subagents (`delegate`), but make every judgment yourself.
- Judge the design from the model and the tour first. That is what the human approves from.
- Be specific: name the line and say what to do.

## Don't
- Edit the artifact, the model or the code. Never write an approval line.
- Skip code because it is tagged. A tag earns a skip only through a rule that passes.
- Reopen settled findings, or argue style preferences.
