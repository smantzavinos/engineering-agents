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
Integrate lanes in child order, as they close, in the idle work-branch worktree.
1. Merge the lane branch.
2. A helper runs that child's T1 on the merged tree.
3. If the merge conflicts, abort it. If T1 is red, reset the work branch to its commit before the merge. Either way, the **integrator** is the implementer of the child being merged, resumed in its lane worktree.
   - It merges the work branch into its lane branch and resolves the conflict there.
   - It runs T1 for both children.
   - It appends `## integration` to its own ledger.
4. A fresh reviewer reviews the integration in code mode, against both plans, from the work-branch commit before the merge. The normal pass cap applies.
5. Then merge again.

## Claims
- Each group member's claims are in `epic.md`.
- A plan that must change files outside its claim, except the merge-friendly files the epic names, stops that lane. The child then runs serially after the group, or is re-scoped under Decisions.

## Checkpoints in lane mode
- Checkpoint fixes happen on the checkpoint branch (`checkpoint-failures.md`), never in a lane worktree.
- A paused lane merges the work branch into its lane branch once the checkpoint branch has merged, then continues.
