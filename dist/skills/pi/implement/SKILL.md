---
name: implement
description: Build an entire approved plan and its model top to bottom, tag the code with its patterns, keep the model in line with what is built, pass the quality gates and the model checks, fix review findings, and hand back. Used by the implementer subagent.
compatibility: pi
---

# Implement

Build the whole plan in one pass, as a senior engineer would. Settle the details, write the code and its tests, then prove it with the gates. You will be resumed with review findings, so this session owns the code until it is approved, unless the orchestrator hands it to an escalation implementer.

The plan's design is a model the human approved. `architecture-model` holds the rules this skill relies on: pattern states and tags, code references, the checks, deviation classes and the commands. Read it first.

## Inputs
`plan.md` (including its Handoff section), `model.c4ish.json` beside it, the `review.md` ledger (including any `## refresh scout` note on what changed since the plan was written), the project's path file and catalog, the base commit, and the baseline gate digest in `state.json`. Tests follow `test-quality`.

## Build
- Implement all of it: every new, modified and removed element of the model, and everything under the plan's Changes outside the model. Write the tests the plan calls for alongside the code. Each contract the plan names gets proof at its owning layer.
- **Build from the catalog.** Before you build an element, read its pattern's entry and golden example. Meet every numbered requirement, go through the shared code the entry names, and add the tests the entry asks for. Never copy shared code into the element.
- **Tag every definition you create or change** with its element's pattern state (`architecture-model` → Pattern states), as the catalog contract → Tags says: one line, `@pattern` first on its comment line, directly above the definition, or as the first comment of a file that is one definition. Tag nothing else.
- **A proposed pattern:** write its catalog entry, its profile entry and any rule the plan lists, with the element the plan names as its golden example. In the commit that adds the profile entry, remove the pattern from the model's `proposedPatterns`.
- While building, run only T0 checks:
  - tests related to the files you changed;
  - one E2E spec by name, with one worker, against a warm harness if the repo has one (otherwise cold);
  - an incremental typecheck.

  Keep built artifacts and services warm between runs; cold boots are the largest cost. Before trusting a warm server, check that it was built from the current source, and rebuild or restart it if not. Stale code passes tests.
- **When the build departs from the model,** act by the deviation's class (`architecture-model` → Deviations):
  - *detail:* do the right thing, note it, and keep the code references right;
  - *model change:* update the model in the same commit as the code, and record it under Deviations in your ledger entry with the reason;
  - *re-approval:* commit your work and the changed model, then stop and reply with what differs and why. When the difference is a catalog, rule, profile or path file the plan doesn't list, add it to the plan's Changes outside the model in that commit. The human decides; you may be resumed to continue, to change the model, or to build what was approved.
- A shape nobody planned is built bespoke and recorded as a model change, with a follow-up to propose a pattern. Don't stop to propose one, and don't add a catalog entry the plan doesn't list.
- When `plan.md` is wrong outside the model: in a detail, do the right thing and note it; in substance, stop and report, with what you found.
- Commit in logical units with conventional messages.
- If a context warning asks you to compact, commit first, then `self_compact` with a note that names the next step.

## Model checks
After the build and before the gates:
1. Make every code reference exact: the name of the definition, not only its path. Bring the model in line with what you built, run `c4ish validate --strict` on it, and commit.
2. Start your ledger entry (Handoff, step 2) with its heading and its `### Deviations` list, and commit it. The check reads the list from the ledger, so it comes first.
3. Run `model-check all` with the fixed command (`architecture-model` → Commands), on a clean tree. Fix what it reports in the code, the tags or the model:
   - a failure of check 2 is yours to fix: a wrong reference, a missing or disagreeing tag, a change state the code doesn't bear out;
   - a difference check 3 calls unrecorded is a model change to record, after you have decided it is right;
   - a re-approval difference is a stop, as above. Never edit the model or the plan to hide one.
4. Read the unaccounted lines it lists. Each run of lines is one of three things:
   - glue: leave it;
   - an element the model is missing: add the element, as a model change;
   - a change outside the model that the approved plan didn't list (a migration, configuration, a CI file): note it under `### Details` with its path. Don't invent an element for it, and don't edit the plan's list: the check reads the approved one.
5. Run it again after any later commit that changes code, tags, the model or a Deviations list. The run you record is the last one, on the commit you hand over; only the ledger changes after it.

Never write or edit an `Approved:` or `Re-approved:` line.

## Code in submodules
Where the plan lives in one repository and the code in git submodules of it, read `architecture-model` → `references/repositories.md` first. Then:
- work in each submodule on the branch `state.json` names. A submodule the build needs and the plan didn't name: add it as the agent guide says, branch it at the commit the root points to, note it under `### Details`, and name it in your reply;
- **a handover is one root commit:** commit in each submodule, then make one root commit that moves those pointers and holds the model and the ledger. Do this before every `model-check` run, and before every reply. "A clean tree" means clean in every repository;
- in the root, stage your own paths and the pointers of the submodules you changed, nothing else;
- gates run per repository, with test selection from that submodule's base commit in `state.json`. Record each gate with its repository and that repository's `HEAD^{tree}`;
- record in the ledger the submodule commits the check printed;
- never amend, rebase or squash a submodule commit the root has pinned. (A squash at the merge is the host's, later, and fine.)

## Gates
1. At the end, run T1's fast gates (builds, typecheck, lint and format on changed files, and the project's pattern rules on them) with the plan's Gates commands. For the rest of T1 (unit and E2E tests), record in the ledger the exact command lines, with an explicit base and spec list and retries off but no E2E worker count (the helper sets it), and why each spec was picked. Don't run them: a helper runs them beside the code review. When your task says to run T1 yourself (integration, checkpoint fix), run all of it.
   - **Selection:** compute it from `git diff <base>`, excluding the orchestrator's `state.json` and `epic.md`, not from the plan's guess at the changed paths. Selection flags default to uncommitted changes, which select nothing after a commit.
   - **E2E specs:** the test map gives the specs for the changed paths. The plan supplies the rest.
   - **Whole package:** rerun a package's units in full when its config, test setup or a shared module changed.
   - **Run settings:** retries off, fast gates first; when you run T1 yourself, the E2E worker count your task gives.
2. Fix what the fast gates find. After a review, fix the findings and any T1 failures you are given, run the fast gates for the fixes, and record the remaining command lines for them: what failed and what the fixes touch. Never rerun a gate whose tree (`HEAD^{tree}`, ignoring the orchestrator's files and plan directories) and exact command line match a passing run in the ledger.
3. Don't do a final full pass. Full gates run at the plan's close or at the epic's checkpoints, off your critical path. The exception is a plan that escalates this child: record the full-gate command lines too, and the helper runs them.

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
- You may be resumed to integrate a merge or to merge a checkpoint branch, or started fresh to fix a checkpoint regression on the checkpoint branch. If you're given a new base, compute T1 from it from then on. Do what the task says (`run-epic`, `references/lanes.md`); by default:
  - work on the branch you're given;
  - run T1 plus any failing tests, unless the task says another run follows;
  - add the path T1 missed to the test map;
  - append `## integration` or `## checkpoint fix` to the ledger named, with the commits a reviewer needs.

## Handoff
1. Leave the tree clean, with all your work committed. Only the orchestrator's files may stay modified.
   Stop the services you started on the worktree's ports.
2. Append `## implementation` (or `## fix pass N`) to `review.md` with:
   - the gates you ran, with pass/fail and duration per gate, and per gate the exact command line (including selection) and `HEAD^{tree}` it ran on;
   - the model checks: the exact `validate` and `model-check` command lines, the commit each ran on and the result, with the count of unaccounted lines and what you judged them to be;
   - `### Deviations`: one list item per model change, starting with its key in backticks, then the reason. Then `### Details`, in words: details, unlisted changes outside the model, and any change to a golden example's code;
   - the T1 command lines you recorded for the helper, and why each spec was picked;
   - for a fix pass, which T1 failures you fixed, and whether each fix touched only tests or fixtures;
   - test lines vs production lines added, and the tests removed or consolidated;
   - every contract you proved that the plan didn't list, and why, including regression tests for bugs found while building or fixing;
   - flakes and baseline failures seen, and log paths;
   - each Deliverable from the plan's Done when, with the file or test that delivers it, or *not done* with the reason. No extra test runs for this;
   - follow-ups, including any bespoke shape worth proposing as a pattern, and what the reviewer should look at closely.

   Commit it. The reviewer treats these as claims to check, so be exact.
3. `self_compact` with a note: what you built, any deviations, what's fragile, and how to continue.
4. After compaction, reply in a few lines: a summary and the ledger path.

## Do
- Follow the catalog. Where it is silent, match the codebase's existing patterns.
- Update the docs the change affects, in this same plan.
- Keep the model true: a reviewer and the human read it as what was built.

## Don't
- Stage, stash or revert the orchestrator's `state.json` or `epic.md`. Stage your own paths, never everything.
- Run full suites mid-build.
- Expand scope. Note follow-ups in your handoff.
- Weaken, skip or delete tests to get green.
- Change a tag, a rule, the model or a catalog file to make a check pass.
- Retag code you didn't create or change, except where the plan says so.
