# Lanes: parallel children

Read this when `epic.md` declares parallel groups. If the repo has no worktree pool (`epic.md` Gates says which repo support exists), run every child serially.

## Starting lanes
- Run up to `maxLanes` children of one group at once. Each child gets a pool worktree, on its own branch off the same work-branch commit. Its plan-author, implementer, reviewers and helpers all launch with their cwd in that worktree.
- **Before each lane starts,** check:
  - free memory, about 6 GB per lane;
  - disk, against the repo's floor in `epic.md` Gates.
- **Planning ahead** (orchestrate → Plan ahead): group members plan in their own lane worktrees. The child after the group plans ahead in the planning worktree.
- **E2E workers:** split the machine-wide budget (`epic.md`, default cores ÷ 4) across the running lanes and the checkpoint run. Pass each lane its E2E worker count in the task.
- **Rate limits:** on model rate-limit errors, drop one lane until the next group.

## The pool
The pool is created once with the repo's worktree tooling, then reused.
- **To reuse a worktree:**
  - switch it to a new branch at the base;
  - reinstall only if the lockfile changed;
  - reset the test data.
- **Never reuse** a dirty worktree, or one whose child is not yet integrated.
- Each worktree has its own ports. Processes are touched only through their own worktree's ports.
- Subagents inherit this session's environment, and per-worktree settings such as ports are not reloaded for a lane's directory. Every lane task says to load the lane worktree's own environment and check its port before running services, unless the repo's tooling already refuses a mismatched port.

## Integrating
A group integrates once, when every member's code is approved and Checkpoints step 2 allows every member to integrate. Until then, no member counts as integrated, for Close steps 4–7 or for Plan ahead. A checkpoint named after a group member runs after the group's last member; for Checkpoints step 2 the group counts as one child.

Integrate on an integration branch, so the work branch only moves forward.
- **Worktree:** the checkpoint worktree if it holds no checkpoint branch that is running or waiting to merge. Otherwise a pool worktree that is clean and holds no unintegrated child. If neither exists, wait. Prepare it as The pool says, and give every task there that worktree's environment and ports.
- **Work branch:** from step 1 until step 6, commit only your own files to it. A green checkpoint waits, and Close step 3 merges it afterwards.
- **State:** record the worktree and each step under the group in `state.json`.
1. Create `integration/<group>` at the work-branch tip; that commit is the group base. Merge the lane branches into it in child order.
2. **A merge conflicts:** abort it. Resume that member's implementer in its lane worktree. Its task: merge the integration branch into the lane branch, resolve, commit, and name the merge commit in `## integration`. The group T1 follows, so it runs no T1. Then merge its lane again and continue.
3. **Group T1:** a helper runs the union of the members' Gates, with selection from the group base. Any member's widening or escalation applies to the group. Pass it an E2E worker count. A failure that passes alone and lies outside the group's diff, or that is in the baseline, is not red (`implement` → Gates).
4. **T1 is red:** a helper traces the failure to a member; if that's unclear, take the last member in child order. Its implementer gets the group base as its new base. In its lane worktree it merges the integration branch, fixes the failure, runs the group T1, adds the path the members' T1 missed to the test map, and names the commit it merged in `## integration`. Merge its lane into the integration branch; the tree now matches its green lane tip, so T1 doesn't rerun. Each red T1 after a fix counts as a pass toward the cap.
5. **Integration review:** only when an integrator changed something. A fresh reviewer, in code mode, against the members' plans, gets every integrator's range: `git show --remerge-diff <merge>` for a conflict, and from the merged commit to the lane tip for a fix, plus any review-fix commits since the last pass. It heads its passes `## integration pass N` in the ledger of the member concerned. Fixes go on the lane a finding is about. Merge that lane again and rerun the group T1. The normal pass cap applies.
6. **Integrated:** every lane is merged, the group T1 is green, and any integration review is approved. Merge the integration branch into the work branch, and record the end time.

## Claims
- Each group member's claims are in `epic.md`.
- A plan that must change files outside its claim, except the merge-friendly files the epic names, stops that lane. The child then runs serially after the group, or is re-scoped under Decisions.

## Checkpoints in lane mode
- Checkpoint fixes happen on the checkpoint branch (`checkpoint-failures.md`), never in a lane worktree.
- A paused lane merges the work branch into its lane branch once the checkpoint branch has merged, then continues.
