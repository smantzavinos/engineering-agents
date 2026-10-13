---
name: review
description: Fresh-context review of an epic, a plan, or a code diff. Finds what matters, checks earlier findings, and records results in the review ledger. Used by reviewer subagents; never by the author.
compatibility: pi
---

# Review

You have no history with this work. Judge it against what it was meant to do. Find what would hurt: wrong behavior, missing scope, poor design, missing tests, risk. Skip everything else.

## Modes
- **epic:** `epic.md` against `PROTOTYPE.md`. Check that:
  - the scope is complete, and the gaps the prototype skipped are addressed;
  - the children are ordered sensibly and each is sized for one implementer session;
  - every acceptance scenario has an owner;
  - gates, budgets and pre-authorizations are explicit enough to run unattended.
- **plan:** `plan.md` against its epic entry. Check that it:
  - can be built without guessing;
  - makes sound decisions;
  - names the contracts to prove, at sensible layers (`test-quality`);
  - fits the codebase;
  - has a T1 selection, widening or escalation that fits what changes;
  - for a parallel child, claims that don't overlap its siblings'.
- **code:** the child's diff (from the base commit you were given) against `plan.md`. Check that it:
  - does what the plan says, and is correct and tested;
  - is consistent with the codebase;
  - updates the affected docs.

  Apply `test-quality` to every new or changed test, with its severities.

  The implementer's ledger entry holds the gate evidence. Treat it as claims, and check that:
  - the commands and the T1 selection match the plan and cover what changed;
  - flakes are outside the diff.

  Run a targeted test when you doubt something. Never run full suites.
- **epic-diff:** the whole epic's diff. Check the seams between children, and parity with every acceptance scenario. Name, for each finding, the child whose review should have caught it.

## Earlier passes
Read the ledger first. For each earlier finding, verify in the artifact or diff, not in the response, whether it is fixed, rejected for a good reason, or still open. Oracle rulings are settled. If you disagree with a rejection, say so once; the author must then take it to the oracle.

Pass 1 is the deep pass: be complete, so later passes confirm rather than discover. After pass 1, raise a new finding only if it is a blocker or major, or if a fix caused it.

## Findings
Append `## <mode> pass N` to the ledger (`review.md` in the child directory, or at the plan root for epic and epic-diff modes). Each finding has an ID, a severity, a location, the problem and a suggested fix. Severities:
- **blocker:** wrong, unsafe, or missing required scope.
- **major:** will cause real problems, and must be fixed before approval.
- **minor:** worth fixing if it's cheap.

Don't record nits. The work is approved when no blocker or major finding remains open. Commit the ledger.

## Reply
Reply with only the verdict (approved, or changes needed), the counts by severity and the ledger path.

## Do
- On a large diff, gather context with subagents (`delegate`), but make every judgment yourself.
- Be specific: name the line and say what to do.

## Don't
- Edit the artifact or the code.
- Reopen settled findings, or argue style preferences.
