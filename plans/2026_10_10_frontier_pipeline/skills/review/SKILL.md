---
name: review
description: Fresh-context review of an epic, a plan, or a code diff. Finds what matters, checks earlier findings, and records results in the review ledger. Used by reviewer subagents; never by the author.
---

# Review

You have no history with this work. Judge it against what it was meant to do. Find what would hurt: wrong behavior, missing scope, poor design, missing tests, risk. Skip everything else.

## Modes
- **epic:** `epic.md` against `PROTOTYPE.md`. Check that:
  - the scope is complete;
  - the children and their order make sense;
  - every acceptance scenario has an owner;
  - the gaps the prototype skipped are addressed.
- **plan:** `plan.md` against its epic entry. Check that it:
  - can be built without guessing;
  - makes sound decisions;
  - has tests covering the scenarios and the risky logic;
  - fits the codebase.
- **code:** the child's diff against `plan.md`. Check that it:
  - does what the plan says, and is correct and tested;
  - is consistent with the codebase;
  - updates the affected docs.

  Read the gate evidence. Run targeted tests only when you doubt a claim.
- **epic-diff:** the whole epic's diff. Check the seams between children, and parity with every acceptance scenario.

## Earlier passes
Read `review.md` first. For each earlier finding, decide whether it is fixed, rejected for a good reason, or still open. Oracle rulings are settled.

After pass 1, raise a new finding only if it is a blocker or major, or if a fix caused it.

## Findings
Append `## <mode> pass N` to `review.md`. Each finding has an ID, a severity, a location, the problem and a suggested fix. Severities:
- **blocker:** wrong, unsafe, or missing required scope.
- **major:** will cause real problems, and must be fixed before approval.
- **minor:** worth fixing if it's cheap.

Don't record nits. The work is approved when no blocker or major finding remains open.

## Reply
Reply with only the verdict (approved, or changes needed), the counts by severity and the `review.md` path.

## Do
- On a large diff, gather context with subagents (`delegate`), but make every judgment yourself.
- Be specific: name the line and say what to do.

## Don't
- Edit the artifact or the code.
- Reopen settled findings, or argue style preferences.
