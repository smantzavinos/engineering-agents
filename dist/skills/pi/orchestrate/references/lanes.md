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
Integrate a group once, when every member's code is approved, in the idle work-branch worktree. A member still in code review after the others are approved can be left for later: integrate the rest, and integrate it alone when it is approved.
1. Record the work-branch commit (the group base), then merge the lane branches in child order.
2. A helper runs one T1 on the merged tree, against the group base, covering every member's changes.
3. **Clean merges and green T1:** the group is integrated. No integration review: each member's code review already covered its diff, and the epic-diff review checks the seams.
4. **A merge conflicts:** abort it. The **integrator** is the implementer of the member being merged, resumed in its lane worktree. It merges the work branch, with the members already merged, into its lane branch and resolves the conflict there. Then continue merging.
5. **T1 is red:** reset the work branch to the group base. A helper traces the failure to a member; if unclear, take the last member in child order. Its implementer is the integrator: in its lane worktree it merges the other members' lane branches, fixes the failure and runs the group's T1. Then merge the group again, that lane last.
6. An integrator appends `## integration` to its own ledger. A fresh reviewer then reviews only the integrator's changes, in code mode, against the members' plans. The normal pass cap applies.

## Claims
- Each group member's claims are in `epic.md`.
- A plan that must change files outside its claim, except the merge-friendly files the epic names, stops that lane. The child then runs serially after the group, or is re-scoped under Decisions.

## Checkpoints in lane mode
- Checkpoint fixes happen on the checkpoint branch (`checkpoint-failures.md`), never in a lane worktree.
- A paused lane merges the work branch into its lane branch once the checkpoint branch has merged, then continues.
