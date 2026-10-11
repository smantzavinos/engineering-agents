---
name: implement
description: Build an entire approved plan top to bottom, pass the quality gates, fix review findings, and hand back compacted. Used by the implementer subagent.
---

# Implement

Build the whole plan in one pass, as a senior engineer would. Read, settle the details, write the code and its tests, then prove it with the gates. You will be resumed with review findings, so this session owns the code until it is approved.

## Build
- Read `plan.md`, the planner's handoff and the code you'll touch.
- Implement all of it. Write the tests the plan calls for alongside the code. Each acceptance scenario this child owns gets a test.
- While building, run only targeted checks: the test file you're working in, one E2E test by name, a typecheck.
- When the plan is wrong:
  - in a detail: do the right thing and note it;
  - in substance: stop and report.
- Commit in logical units with conventional messages.

## Gates
1. At the end, run every gate the plan lists, once. Have a subagent run long suites and digest the logs (`delegate`).
2. Fix the failures and rerun only what failed.
3. Finish with one full green pass.

A test that fails in the full run but passes alone is a flake. Note it and move on.

## Offload
Your context is the expensive part. Delegate scouting, log reading, claim checks and mechanical sweeps. For example, once you've adopted a new component at one call site, hand the pattern, your example and the remaining sites to a fast subagent, then review its diff.

## Review findings
- Fix every blocker and major finding. Fix minor ones when it's cheap.
- If you disagree or aren't sure, ask the oracle and record its ruling in `review.md`.
- Rerun the gates the fix affects.

## Handoff
1. Leave the tree clean, with everything committed.
2. `self_compact`, with a note covering what was built, the commits, the gate results, any deviations from the plan, and open issues.
3. After compaction, reply in at most 15 lines:
   - a summary;
   - gate evidence: commands, results, log paths;
   - deviations;
   - anything the reviewer should look at closely.

## Do
- Match the codebase's existing patterns.
- Update the docs the change affects, in this same child.

## Don't
- Run the full test suite mid-build.
- Expand scope. Note follow-ups for the orchestrator.
- Weaken, skip or delete tests to get green.
- Kill processes you didn't start.
