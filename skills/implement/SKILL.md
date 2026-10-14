---
name: implement
description: Build an entire approved plan top to bottom, pass the quality gates, fix review findings, and hand back. Used by the implementer subagent.
harnesses: [pi]
---

# Implement

Build the whole plan in one pass, as a senior engineer would. Settle the details, write the code and its tests, then prove it with the gates. You will be resumed with review findings, so this session owns the code until it is approved, unless the orchestrator hands it to an escalation implementer.

## Inputs
`plan.md` (including its Handoff section), the child's `review.md` ledger, the base commit, and the baseline gate digest in `state.json`. Tests follow `test-quality`.

## Build
- Implement all of it. Write the tests the plan calls for alongside the code. Each contract the plan names gets proof at its owning layer.
- While building, run only T0 checks:
  - tests related to the files you changed;
  - one E2E spec by name, against a warm harness if the repo has one (otherwise cold);
  - an incremental typecheck.

  Keep built artifacts and services warm between runs; cold boots are the largest cost. Before trusting a warm server, check that it was built from the current source, and rebuild or restart it if not. Stale code passes tests.
- When the plan is wrong:
  - in a detail: do the right thing and note it;
  - in substance: stop and report, with what you found.
- Commit in logical units with conventional messages.
- If a context warning asks you to compact, commit first, then `self_compact` with a note that names the next step.

## Gates
1. At the end, run T1 once, with the plan's Gates commands.
   - **Selection:** compute it from `git diff <base>`, excluding the orchestrator's `state.json` and `epic.md`, not from the plan's guess at the changed paths. Selection flags default to uncommitted changes, which select nothing after a commit.
   - **E2E specs:** the test map gives the specs for the changed paths. The plan supplies the rest.
   - **Whole package:** rerun a package's units in full when its config, test setup or a shared module changed.
   - **Run settings:** retries off, the E2E worker count your task gives, fast gates first.
   - **Delegation:** a helper runs the long suites and digests them (`delegate`). Write the ledger entry while it runs; don't wait idle.
2. Fix the failures. Rerun only what failed and what the fix touches.
3. Don't do a final full pass. Full gates run at the epic's checkpoints, off your critical path. The exception is a plan that escalates this child.

A failure that passes alone *and* lies outside what you changed is a flake: record it and move on. A failure already in the baseline digest is not yours unless the plan says so. The same goes for a failure you were told is being fixed on a checkpoint branch. If you are steered to stop, commit and reply. Anything else you fix. An environment failure (service won't boot, port taken, disk full) gets one retry; if it persists, report it instead of spending more time.

Processes: touch only processes bound to your worktree's ports, never others. Helpers stop the servers they start, unless you tell them to leave them warm for you.

## Offload
Your context is the expensive part. Delegate scouting, log reading, claim checks and mechanical sweeps.
- **Example:** once you've adopted a new component at one call site, hand the pattern, your example and the remaining sites to a fast subagent, then review its diff.
- **Size:** delegate only errands worth about 5 minutes or more of your own time. Batch sweeps, and keep errand prompts short: point to the plan and your example rather than restating them.
- **No bookkeeping:** skip task-list and other bookkeeping tools; the ledger is the record.

## Review findings
- Fix every blocker and major finding. Fix minor ones when it's cheap.
- You may reject a finding with a one-line reason under it. If the reviewer has already disputed your rejection, or you're unsure, ask the oracle and record its ruling under the finding. Rulings are final.
- Rerun only the gates the fix affects.
- You may be resumed to integrate a merge or to merge a checkpoint branch, or started fresh to fix a checkpoint regression on the checkpoint branch. If you're given a new base, compute T1 from it from then on. Do what the task says (`orchestrate`, `references/lanes.md`); by default:
  - work on the branch you're given;
  - run T1 plus any failing tests, unless the task says another run follows;
  - add the path T1 missed to the test map;
  - append `## integration` or `## checkpoint fix` to the ledger named, with the commits a reviewer needs.

## Handoff
1. Leave the tree clean, with all your work committed. Only the orchestrator's files may stay modified.
2. Append `## implementation` (or `## fix pass N`) to `review.md` with:
   - the commands run, with pass/fail and duration per gate;
   - the T1 selection and why each spec was picked;
   - test lines vs production lines added, and the tests removed or consolidated;
   - every contract you proved that the plan didn't list, and why, including regression tests for bugs found while building or fixing;
   - flakes and baseline failures seen, and log paths;
   - deviations from the plan, follow-ups, and what the reviewer should look at closely.

   Commit it. The reviewer treats these as claims to check, so be exact.
3. `self_compact` with a note: what you built, any deviations, what's fragile, and how to continue.
4. After compaction, reply in a few lines: a summary and the ledger path.

## Do
- Match the codebase's existing patterns.
- Update the docs the change affects, in this same child.

## Don't
- Stage, stash or revert the orchestrator's `state.json` or `epic.md`. Stage your own paths, never everything.
- Run full suites mid-build.
- Expand scope. Note follow-ups in your handoff.
- Weaken, skip or delete tests to get green.
