---
name: scope
description: Turn a prototype into an agreed plan with the human — one plan with a diagram model they approve from a guided tour, or, rarely, an epic of distinct plans — and record the approval. Interactive; the human approves the result.
compatibility: pi
---

# Scope

You are the orchestrator, working with the human.
- **Input:** a prototype branch and its `PROTOTYPE.md`.
- **Output:** an approved `plan.md` with its model, which `run-plan` builds without further questions. Rarely, an approved `epic.md`, which `run-epic` runs.

The prototype defines the behavior. Every accepted demo behavior becomes an acceptance scenario. Your job is to find what the prototype skipped and agree how the real build handles it. That usually means error paths, permissions, lifecycle, data changes and docs.

`architecture-model` holds the rules for the model, the approval lines and the commands. Read it first. For every launch or continuation, follow [`delegate` → Launching a role](../delegate/references/launching-a-role.md) and record the returned launcher IDs in `state.json`.

## Before you start
The project's agent guide must name a path file, and the catalog docs and the profile it lists must exist and be committed. If not, stop: `assess-repo` says what is missing, and `map-patterns` writes the catalog. A plan can't be approved without them.

A plan uses approved catalog entries. If it needs an entry that is still a draft (`proposed` in the profile), get the human's approval of that entry and commit it before the plan's approval.

## Steps
1. Read `PROTOTYPE.md` and the prototype diff. Launch `helper` for codebase scouting and `researcher` for external dependencies.
2. Propose the scope: what's in, what's out, and the gaps the prototype skipped. Ask only questions whose answers change the plan, and batch them.
3. Choose the shape:
   - **one plan** (the default), as large as the work needs. Never divide work to meet a size number: each extra plan adds a fixed cost, and cuts one design into pieces the human has to hold together;
   - an **epic**, only when the work holds genuinely distinct workstreams: parts with their own goal that could each be approved and shipped alone.
4. Choose disposal: wipe-and-rebuild (default), or clean up the prototype in place when its structure is sound.
5. Create the work branch (off the default branch, or off the prototype for clean-up in place) and copy `PROTOTYPE.md` into the plan directory. Plans and approvals are committed there. The branch must hold the path file, the catalog and the profile: if it was cut from an older commit, merge the default branch now. Record the branch and its worktree path in `state.json`.
6. Launch `helper` to run the full gates on that branch as the baseline, in the background. It writes nothing tracked. When it replies, write its digest and the commit it ran on into `state.json`.
7. Run the plan loop, then the approval gate.

## Code in submodules
Where the plan lives in one repository and the code in git submodules of it, read `architecture-model` → `references/repositories.md` first. Then:
- **Before you start:** the agent guide names, for each submodule the work touches, how to add it, its default branch and its gates. If not, stop.
- **Step 5:** add each of those submodules to the worktree and give it a branch at the commit the root points to. To start one from a newer commit, move its pointer in a root commit now. Record each repository's path, branch and base commit in `state.json`. A submodule the plan loop adds later gets the same, before the approval.
- **Step 6:** the baseline is one full-gate run per repository, each digest recorded with its repository.
- **The plan-author's task** carries the gate commands per repository.
- **Recording the approval:** also check that each submodule the plan changes is clean, on its branch, and at the commit HEAD points to. That commit is its base; record it.

## Plan loop
There is no `epic.md` for one plan, so the agreed scope, scenarios, gates, budget and autonomy limits go into `plan.md` itself.
1. Launch role `plan-author` (`plan` skill), writing `plan.md` and `model.c4ish.json` at the plan directory root. Its task carries the agreed scope, the path file, and:
   - the full-gate and T1 commands with measured durations, the test map and the smoke set;
   - the budget: wall time and cost, from the implementer hours for the estimate × 1.5 plus a fixed cost;
   - the review-load estimate: the changed lines a reviewer can judge in one pass (default about 7k, not counting generated files). It is recorded, not a limit. Above it the code is reviewed in groups (`run-plan`);
   - autonomy: what the human wants to decide personally, and what the build may do without asking (push the branch, open the PR, file tracker items);
   - an escalation implementer, if the human names one.
2. Launch a fresh `reviewer` (`review` skill, plan mode) with the plan directory.
3. Changes needed: continue the same `plan-author` with the ledger path and pass number, then review again with a fresh reviewer. Skip the re-review only when the reviewer replied `pass 2 needed: no`, and the plan-author fixed every major, rejected none, and reports that no fix changed a contract.
4. Repeat until the review is clean, or the human explicitly accepts what remains, noted in the ledger. The human owns this gate, so the pass cap does not apply.

Relay the human's feedback at any point by continuing the same `plan-author`.

## Approval gate
When the review is clean, generate the tour pages in a directory outside the repo (`c4ish tour <model> --out <dir>`) and give the human:
- the command that opens the tour in the viewer, and the path of the static pages;
- the link to `plan.md`;
- a short list, read from the model: the scenarios, each proposed pattern, each bespoke element with its reason, and any open question notes.

Approving the plan approves every proposed pattern and catalog change in it. Say so.

The human:
- **approves:** record it (below);
- **approves with changes, or asks for changes:** continue the same `plan-author`, launch one more fresh reviewer, and show the tour again;
- **rejects:** go back to step 2 with what they said. The branch and the baseline stay: don't repeat steps 5 and 6.

**Recording the approval.** You received it, so you write it; no subagent does.
1. Check that the tree is clean, and that `plan.md`, the model, the path file and the profile are each in the tree of HEAD (`git cat-file -e HEAD:<path>`). HEAD is then the commit that holds the approved model.
2. Add the line `Approved: YYYY-MM-DD <full commit id>` to `plan.md`, naming that commit. Record the same date and commit in `state.json` under approvals; `run-plan` and the code reviewer check the line against it. Commit both.
3. Run the check on the approval alone: `model-check approved` with the fixed `--model` and `--project` (`architecture-model` → Commands). It must exit 0 and print the line you wrote. If it doesn't, fix what it names before you tell the human anything.
4. The baseline digest is in `state.json`. If the baseline helper is still running, wait for it.
5. Tell the human how to start the build: `run-plan` with the plan directory. Then stop. `scope` doesn't continue into the build.

## Reopened after a build stop
`run-plan` sends the human back here when the approved plan can't be built as approved. The branch, the built code, the ledger and `state.json` stay.
1. Skip steps 1, 4, 5 and 6. Agree with the human what changes (step 2).
2. Run the plan loop on the existing plan: a fresh plan-author, given the build's ledger and the reason for the stop, changes `plan.md` and the model. Then a fresh plan review.
3. Show the human what differs from the last approval (`c4ish diff <model> --base <latest approval commit> --out <file outside the repo>`), and the whole tour if they ask.
4. On approval, record it as above, with the line `Re-approved: YYYY-MM-DD <full commit id>` and one line on what changed. Then tell the human to start `run-plan` again.

## Epic
Rare. An epic is distinct plans, not one design in slices. Write `epic.md` with the human, get a fresh review (`review` skill, epic mode), resolve the findings with them, and on approval commit it with `state.json` (the baseline digest in it, as in step 6), and tell them to start `run-epic`. Each child's plan and model are written during the run.

`epic.md` holds:
- **Goal:** one paragraph. **Scope:** in and out.
- **Acceptance scenarios:** those from `PROTOTYPE.md` plus agreed additions, each mapped to the child that delivers it.
- **Children, numbered:** `NN_slug`, with its goal, the children it depends on, when it's done, and a rough estimate in changed lines. Each is a workstream with its own goal, ending in a scenario that can be tested. No contract-only children: a contract a later child needs goes in the earliest child it already depends on.
- **Cross-plan contracts:** each interface that crosses children, and the child that owns it. The clauses live in the owner's model; a child that uses the contract copies it into its own model as reused, and the owner's copy wins. No detailed model for the whole epic. Add a small overview model of how the plans connect only when it helps.
- **Proposed patterns:** each new pattern a child is expected to propose, claimed by one child, so two plans written at once don't propose the same shape.
- **Claims** (with a worktree pool): the directories, routes, tables and shared components each child may change. Children whose claims overlap never run at once.
- **Parallel groups:** children that build at the same time and integrate together. Members' claims don't overlap, except for the merge-friendly files the epic names; they have no dependency among them; none changes test infrastructure or schema a sibling reads. Set `maxLanes` (default 4; at most the pool size and memory ÷ 6 GB) and the machine-wide E2E worker budget (default cores ÷ 4).
- **Disposal and branch.**
- **Gates:** the T1 and full-gate commands with measured durations, the test map and smoke set, which repo support exists (test map, smoke set, warm harness, parallel E2E, worktree pool, checkpoint worktree), and the disk floor.
- **Checkpoints:** where the full gates run in the background, each named after a child: after foundation children, before fan-outs, after children that widen T1, no more than about a day apart. Epic close is always one.
- **Escalation implementer** (optional).
- **Review-load estimate** and an initial implementer-hours-per-1k-lines rate. Never a reason to split a child.
- **Budget:** wall time and cost per child.
- **Autonomy:** what the human decides personally, including whether they approve each child's plan from its tour or leave that to review. **A child that changes the catalog always stops for the human**, whatever this says.
- **Decisions**, **Follow-ups**, **Quarantine:** the run appends to these.

Keep it to a few pages.

## Do
- Push back on scope creep, and raise gaps the human hasn't considered.
- Show the tour, not the JSON. The human approves from the pictures and a short `plan.md`.
- Tell the human plainly what the tour doesn't show: the tests list, the gates and Changes outside the model are in `plan.md`.

## Don't
- Write the plan or the model yourself, or task lists, implementation detail or test checklists.
- Record an approval the human didn't give in this session, or record it before everything it relies on is committed.
- Start the build.
