---
name: run-plan
description: Build one approved plan to a PR without supervision — one implementer, fresh code review, the model checks, gates — stopping only when the build needs the human to re-approve a change to what they approved. Use after `scope` records the approval.
compatibility: pi
---

# Run plan

You drive the build; you don't do it. The implementer builds, fresh reviewers judge, helpers run gates and checks, and the oracle breaks ties. You sequence them, keep state, bound them, and decide when to stop. Run until the PR is ready or a stop condition fires.

Roles: `implementer`, `reviewer`, `oracle`, plus the fast `helper`. Follow [`delegate` → Launching a role](../delegate/references/launching-a-role.md) for background launches, continuation and completion.

`architecture-model` holds the rules for the model, the checks, deviation classes, approval lines and the commands. Read it first.

## Start
1. **Refuse a plan that isn't approved.** `plan.md` must hold an `Approved:` line naming a commit in this branch's history that contains the model, the path file and the profile. Don't judge it by eye: run `model-check approved` with the fixed `--model` and `--project`. On a first start it must exit 0. Exit 2 is a stop: approval happens in `scope`.
2. Read `state.json` (Recovery → reconcile). It holds each approval as the session that received it recorded it: date and commit. The lines in `plan.md` must match these exactly; a line with no record is a stop. Reviewers are given the record.
3. The build runs in the work-branch worktree `state.json` names, one writer at a time. Its HEAD is the base commit. Record it, with the estimate and the budget from `plan.md` → Goal.
4. **The baseline.** `state.json` holds the full-gate digest `scope` recorded, and the commit it ran on. If it is missing, or code outside the plan directory changed since that commit, run a `helper` on the full gates now and wait for its digest. Never start the implementer while full gates run in its worktree.

There is no plan loop here and no parallel work: one implementer builds the whole plan.

## Code in submodules
Where the plan lives in one repository and the code in git submodules of it, read `architecture-model` → `references/repositories.md` first. Then:
- **Start:** `state.json` names each repository the plan changes, with its branch, base commit and baseline. Each must be on its branch, clean, and at the commit the root points to; if not, stop. A baseline that is missing or stale is rerun for that repository;
- **every launch** carries each repository's base commit. A handed-over state is one root commit: record that id, and give reviewers ranges as root commits;
- **T1 and full gates** run per repository, with that repository's commands. Never run two gate helpers in one repository at once;
- approval lines, `state.json` and the ledger are committed in the root only;
- **Close:** the final state is one root commit that pins every changed submodule. With the plan's pre-authorization, push every branch and hand the set to `pull-request` (one PR per changed submodule and one in the root; submodules merged first, by each repository's own method, squash included). Record each repository's branch and pinned commit for it.

## State
`state.json` in the plan directory is your memory. Update it after every step, and commit it between steps, when no one is writing in the worktree. Record the launcher and the IDs it returns on every launch and continuation (`delegate` → Launching a role). It holds:
- the approvals (date, commit, what a re-approval changed), the base commit, the estimate and the budget;
- the latest implementer run id; per review pass its start, end, reviewed commit, majors by kind, and the `model-check` result the reviewer reported;
- each T1 run (commit, tree, command lines, workers, result, duration, log path), `codePass2Skipped`, the baseline gate digest, flakes, the start and end of each phase;
- stops (reason, time, what the human decided), and **launches**: every run when you launch it (run id, agent, phase, start), marked consumed when you have read its result.

## Build loop
1. **Implement.** Launch role `implementer` (`implement` skill) with the plan directory, the path file and the base commit. It builds everything, tags the code, brings the model in line, runs the model checks and the fast gates, records the rest of T1, commits, writes its ledger entry and replies. A reply that says it stopped for re-approval goes to Re-approval.
2. **Review and T1,** launched together on the implementer's commit:
   - a fresh `reviewer` (`review` skill, code mode) with the plan directory, the path file, the base commit, the approvals from `state.json` and, after pass 1, the range from the commit the previous pass reviewed to the implementer's tip;
   - a T1 `helper` with the ledger's recorded command lines and an E2E worker count. It boots and stops its own services, and reruns each failure alone: one that passes alone and lies outside the diff is a flake; one in the baseline digest is baseline; anything else is red. It writes nothing tracked, and replies with a digest and the log path.
3. Record both results. Then:
   - the reviewer replied `re-approval needed` → Re-approval;
   - review approved and T1 green → Close;
   - otherwise continue the same `implementer` with the ledger path, the pass number and, if T1 is red, the digest and log path.
4. Every fix pass counts toward the pass cap, including one for T1 failures alone. After a fix pass the next review runs, unless all of these hold: the reviewer replied `pass 2 needed: no`; the implementer fixed every major and rejected none; every T1 fix touched only tests or fixtures; and the fixes changed no model, tag or deviation record. Then only the T1 helper runs; green means approved, and a red T1 means another fix pass. Append `approved after fixes, no pass 2` to the ledger and record `codePass2Skipped`.

**A diff above the plan's review-load estimate** is reviewed in groups. Divide the changed files by container, from the model's code references: a file whose definitions belong to one container goes to that group; shared files, unaccounted lines, tests and docs form a last group. Launch one fresh reviewer per group, one after another, each adding its own section to the ledger. A last fresh reviewer reads the joins and gives the single verdict (`review` → A large diff). Later passes are not grouped: one fresh reviewer reads the fix range. This is untested: record in `state.json` how it went.

## Re-approval
The implementer, or a code review, found a difference only the human can accept (`architecture-model` → Deviations). The implementer has committed its work and the changed model.
1. Write the tour of what differs from the latest approval: `c4ish diff <model> --base <latest approval commit> --out <file outside the repo>`.
2. Stop for the human. Give them the command that opens that tour, the differing items in a line each, and the implementer's reason. Record the stop.
3. The human:
   - **approves:** add `Re-approved: YYYY-MM-DD <full commit id>` to `plan.md`, naming the commit that holds the changed model, with one line on what changed. Commit it in the worktree the build runs in, while the implementer is stopped, and record it in `state.json`. You received the approval, so you write the line; no subagent does. Resume the same implementer;
   - **asks for changes:** resume the implementer to change the model, then show the tour again;
   - **rejects:** resume the implementer to build what was approved. If that can't be built, the plan is wrong in substance: stop, and tell the human to reopen `scope` (`scope` → Reopened after a build stop). The branch, the code and `state.json` stay.

## Close
1. A `helper` runs the full gates once on the final tree. Failures go back to the same implementer, inside the Build loop.
2. A `helper` reruns `c4ish validate --strict` and `model-check all` on the final commit, with the fixed command. A re-approval verdict goes to Re-approval, never to a fix pass. Anything else it reports that the last review didn't see goes back through the Build loop: a fix pass, then a review.
3. Prepare the review record for the PR, generated outside the repo tree:
   - **approved versus shipped:** `c4ish diff <model> --base <first approval commit>`, as its summary and as a tour. Mark each difference the human re-approved, from the `Re-approved:` lines;
   - **the as-built tour:** `c4ish tour` on the final model;
   - the recorded deviations, from the ledger.
4. Commit your files. Hand to the PR process (`pull-request`) with the approved-versus-shipped summary and the deviations as text for the PR body, and the two commands that regenerate the tours. The pages are not committed or attached. Pushing and opening the PR need the plan's pre-authorization; otherwise stop and tell the human it is ready.

## Bounds
- Every review is a new session. Every implementer call resumes the same session, except an escalation.
- A loop not approved after pass 4 stops.
- **Escalation:** if the plan names an escalation implementer and the code review isn't approved at pass 2, the fixes go to a fresh escalation implementer with the same plan, base commit and ledger. From then on it is the implementer: record its run id.
- Every launch gets a deadline: the implementer from the budget in `state.json`, reviewers and helpers shorter. Use the launcher's timeout if supported; otherwise record the deadline and enforce it when reconciling the run.
- A build over its wall-time or cost budget stops. Time stopped for the human doesn't count.

## Recovery
- **On start, after compaction, or after a crash,** reconcile: read `state.json`, `git status` and `git log`, then check every launch not yet consumed. Finished: consume its result. Still running: wait. Dead: resume an implementer; for a reviewer or helper, discard its uncommitted ledger edit and relaunch it fresh.
- Never start a writer while the last writer isn't confirmed stopped.
- A run that ends right after the implementer called `self_compact`, without a reply: resume it with "Continue from your note."
- An implementer that times out, crashes or hangs: resume it with "you were interrupted; check `git status` and the ledger, then continue". If continuation is rejected, launch a fresh `implementer` on the plan directory, and record the fallback. Record each restart in `stops`.
- A dirty tree at the start of a step belongs to an interrupted session. Resume that session to commit or discard. Never commit code yourself. Your own files are yours to commit, and never to discard.
- An environment failure (service, port, disk, credentials, a missing `c4ish`) that survives the implementer's one retry is a stop, not a review pass.

## Stop for the human only when
- The build needs re-approval, or a rejected re-approval can't be built as approved.
- A discovery contradicts the agreed scope or a premise of the prototype.
- An action is destructive or irreversible, or touches shared infrastructure, production data, or pushes and merges the plan did not pre-authorize.
- The loop hits its cap, the build exceeds its budget, or an environment failure persists.
- A gate failure can't be fixed and isn't in the baseline digest.

Otherwise, decide, and record tricky decisions in `state.json`: the options, the choice, why, and whether the oracle was consulted.

## Do
- Pass paths, not pasted content. Subagents read files themselves.
- Keep what you take in small: verdicts, counts, paths and short summaries.
- `self_compact` when your context grows large, with a note naming this skill's path, what is in flight and its run id. Re-read this skill after compaction.

## Don't
- Plan, implement or review yourself, or edit the model.
- Write an approval line the human didn't give you in this session.
- Rerun gates the implementer or a T1 helper already ran. A gate whose tree (ignoring your own files and the plan directory) and exact command line (ignoring the E2E worker count) match a passing run in the ledger or `state.json` is never rerun.
- Ask the human anything the oracle can answer.
