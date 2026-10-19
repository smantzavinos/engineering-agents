---
name: review
description: Fresh-context review of an epic, a plan, or a code diff. Finds what matters, checks earlier findings, and records results in the review ledger. Used by reviewer subagents; never by the author.
harnesses: [pi]
---

# Review

You have no history with this work. Judge it against what it was meant to do. Find what would hurt: wrong behavior, missing scope, poor design, missing tests, risk. Skip everything else.

## Modes
- **epic:** `epic.md` against `PROTOTYPE.md`. Check that:
  - the scope is complete, and the gaps the prototype skipped are addressed;
  - each child is a cohesive slice with declared dependencies and, with a worktree pool, a claim; any child above the review-load signal has a reason not to be split;
  - groups have at most `maxLanes` members, `maxLanes` is at most the pool size, and members' claims don't overlap;
  - every acceptance scenario has an owner;
  - gates, budgets and pre-authorizations are explicit enough to run unattended.
- **plan:** `plan.md` against its epic entry. Check that it:
  - can be built without guessing;
  - makes sound decisions;
  - states its estimate; above the review-load signal (`epic.md`, or a single plan's own), says whether its concerns are separable;
  - answers the plan questions that apply (`plan` → plan.md). A missing answer on access and visibility, failure and concurrency, or deliverables, where the child has that concern, is a major; on the others, a minor;
  - stays inside the child's entry. Work beyond it that isn't on the plan's Follow-ups line is a major finding;
  - where a dependency isn't built yet, judge references to its work against its approved plan, not the code;
  - names the contracts to prove, at sensible layers (`test-quality`). The list is the test budget, so check that it is complete and lean. Judge each contract, not its mechanics: what it proves, at which layer, and whether another test already owns it. Locators, assertion construction, fixture detail and whether a planned test can fail are for code review; here they are minors for the implementer;
  - fits the codebase;
  - has a T1 selection, widening or escalation that fits what changes;
  - claims that stay inside its `epic.md` claim; for a group member, they don't overlap its siblings'.

  Tag every major with its kind: `design`, `boundary`, `claims`, `scope` or `cohesion` (a fix needs a re-check), or `tests`, `T1` or `wording` (it doesn't).

  **Plan refresh:** head the pass `## plan refresh pass N`. Review only the refresh commit, against the integrated range you were given: does the plan still fit that code, and is the edit itself correct? The deep-pass rule doesn't apply. Findings on text the refresh didn't change are minors.
- **code:** the child's diff (from the base commit you were given) against `plan.md`. Check that it:
  - does what the plan says, and is correct and tested;
  - is consistent with the codebase;
  - updates the affected docs;
  - delivers every Deliverable in the plan's Done when. One missing from the implementer's map, marked done but not delivered, or not done without an accepted deviation is a major;
  - resolves each refresh major you were given, in `plan.md` and in the code. A fix that is wrong against the integrated code is a major against the plan; the orchestrator sends the plan change to a fresh plan-author.

  For an integration review, use the ledger and pass heading your task names.

  Apply `test-quality` to every new or changed test, with its severities. Every new test proves a contract: one in the plan's Tests, or one the ledger records with a reason. That includes regression tests for bugs found while building, and independent contracts the plan's list doesn't reach, such as config, defaults or migrations (`test-quality` → Keep). A test moved, split or rewritten because its contract changed isn't new. A test with no contract is a major finding. A test whose contract is missing only from the ledger is a minor: record it, don't delete the test. A test-to-production ratio well above earlier children's means look closer; it isn't a finding by itself.

  The implementer's ledger entry holds the gate evidence. Treat it as claims, and check that:
  - the commands match the plan, and the T1 selection covers the actual diff;
  - flakes are outside the diff.

  Run a targeted test when you doubt something. Never run full suites.
- **epic-diff:** the whole epic's diff. Check the seams between children, and parity with every acceptance scenario. Name, for each finding, the child whose review should have caught it.

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
Reply with only the verdict (approved, or changes needed), the counts by severity and the ledger path. In plan mode (not refresh), end with `pass 2 needed: yes` if any blocker or any major of a kind that needs a re-check is open, otherwise `pass 2 needed: no`.

## Do
- On a large diff, gather context with subagents (`delegate`), but make every judgment yourself.
- Be specific: name the line and say what to do.

## Don't
- Edit the artifact or the code.
- Reopen settled findings, or argue style preferences.
