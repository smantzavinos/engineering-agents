---
name: implement
description: Build an entire approved plan top to bottom, pass the quality gates, fix review findings, and hand back. Used by the implementer subagent.
harnesses: [pi]
---

# Implement

Build the whole plan in one pass, as a senior engineer would. Settle the details, write the code and its tests, then prove it with the gates. You will be resumed with review findings, so this session owns the code until it is approved.

## Inputs
`plan.md` (including its Handoff section), the child's `review.md` ledger, the base commit, and the baseline gate digest in `state.json`.

## Build
- Implement all of it. Write the tests the plan calls for alongside the code. Each acceptance scenario this child owns gets a test.
- While building, run only targeted checks: the test file you're working in, one E2E test by name, a typecheck. Keep built artifacts and services warm between runs where the repo allows; cold boots were the single largest cost in the old process.
- When the plan is wrong:
  - in a detail: do the right thing and note it;
  - in substance: stop and report, with what you found.
- Commit in logical units with conventional messages.
- If a context warning asks you to compact, commit first, then `self_compact` with a note that names the next step.

## Gates
1. At the end, run every gate the plan lists, once, fast gates first. Have a subagent run long suites and digest the logs (`delegate`).
2. Fix the failures and rerun only what failed.
3. Finish with one full green pass.

A failure that passes alone *and* lies outside what you changed is a flake: record it and move on. A failure already in the baseline digest is not yours unless the plan says so. Anything else you fix. An environment failure (service won't boot, port taken, disk full) gets one retry, touching only processes you started; if it persists, report it instead of spending more time.

## Offload
Your context is the expensive part. Delegate scouting, log reading, claim checks and mechanical sweeps. For example, once you've adopted a new component at one call site, hand the pattern, your example and the remaining sites to a fast subagent, then review its diff.

## Review findings
- Fix every blocker and major finding. Fix minor ones when it's cheap.
- You may reject a finding with a one-line reason under it. If the reviewer has already disputed your rejection, or you're unsure, ask the oracle and record its ruling under the finding. Rulings are final.
- Rerun only the gates the fix affects.

## Handoff
1. Leave the tree clean, with everything committed.
2. Append `## implementation` (or `## fix pass N`) to `review.md`: commands run, pass/fail and duration per gate, flakes and baseline failures seen, log paths, deviations from the plan, follow-ups, and what the reviewer should look at closely. Commit it. The reviewer treats these as claims to check, so be exact.
3. Reply in a few lines: a summary and the ledger path.

## Do
- Match the codebase's existing patterns.
- Update the docs the change affects, in this same child.

## Don't
- Run the full test suite mid-build.
- Expand scope. Note follow-ups in your handoff.
- Weaken, skip or delete tests to get green.
- Kill processes you didn't start.
