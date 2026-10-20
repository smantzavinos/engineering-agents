# Lanes

Read this when the repo has a worktree pool (`epic.md` Gates says which repo support exists). Then every child runs as a lane; a child in no group is a group of one. Without a pool, children run one at a time in the work-branch worktree.

## Starting lanes
- **A unit** (a group, or a child in no group) **starts** when every child its members depend on is integrated, each member's plan is approved, and a pool worktree is free for each member. Its members start together, each in its own pool worktree, on its own lane branch off the same work-branch commit. Its implementer, reviewers and helpers all launch with their cwd in that worktree.
- **Order:** ready units start in child-number order. While the lowest-numbered ready unit waits for worktrees or lane capacity (count, memory), no later unit starts.
- **Claims:** a unit whose claims overlap those of a running unit waits until that unit integrates.
- **Running:** a lane counts as running until it is integrated, and holds its worktree until then.
- **Before each lane starts,** check:
  - free memory, about 6 GB per lane;
  - disk, against the repo's floor in `epic.md` Gates.
- **Lane count:** at most `maxLanes` lanes run at once (at most the pool size). If no lane is running and the next ready unit still can't start, split its group into groups that fit and record it under Decisions. If not even one member can start (memory, disk), stop for the human as an environment failure.
- **E2E workers:** when a T1 or checkpoint run starts, give it an even share of the machine-wide budget (`epic.md`, default cores ÷ 4) across the runs then in flight, including it, but no more than the budget not already held, and at least 1. Pass that count in its task. An implementer that runs T1 itself (integration, checkpoint fix) gets its count at launch and holds it until it replies. Targeted checks while building use one worker.
- **Rate limits:** on model rate-limit errors, drop one lane until the next unit starts, or until no lane is running.

## The pool
The pool is created once with the repo's worktree tooling, then reused.
- **Checks:** test-service ports outside the OS ephemeral range (or reserved from it), `GIT_OPTIONAL_LOCKS=0` in the dev environment, and merge-friendly files for anything every child edits (`assess-repo`). Missing ones go under `epic.md` Decisions as known risks.
- **To reuse a worktree:**
  - switch it to a new branch at the base;
  - reinstall only if the lockfile changed;
  - reset the test data.
- **Never reuse** a dirty worktree, or one whose child is not yet integrated.
- Each worktree has its own ports. Processes are touched only through their own worktree's ports.
- Subagents inherit this session's environment, and per-worktree settings such as ports are not reloaded for a lane's directory. Every lane task says to load the lane worktree's own environment and check its port before running services, unless the repo's tooling already refuses a mismatched port.

## Integrating
A unit integrates once, when every member's code is approved. Until then, no member counts as integrated.

**Group of one, plain merge:** if the work branch has changed since the lane's base only in your own files and plan directories, merge the lane branch into the work branch and you're done. The lane's own T1 is the proof. Otherwise use the steps below.

Integrate on an integration branch, so the work branch only moves forward.
- **Worktree:** the checkpoint worktree if it holds no checkpoint branch that is running or waiting to merge. Otherwise a pool worktree that is clean and holds no unintegrated child. If neither exists, wait. Prepare it as The pool says, and give every task there that worktree's environment and ports.
- **Work branch:** from step 1 until step 6, commit only your own files to it. A green checkpoint waits, and Close step 2 merges it afterwards.
- **State:** record the worktree and each step under the group in `state.json`.
1. Create `integration/<group>` at the work-branch tip; that commit is the group base. Merge the lane branches into it in child order.
2. **A merge conflicts:** abort it. Resume that member's implementer in its lane worktree. Its task: merge the integration branch into the lane branch, resolve, commit, and name the merge commit in `## integration`. The group T1 follows, so it runs no T1. Then merge its lane again and continue.
3. **Group T1:** a helper runs the union of the members' Gates, with selection from the group base. Any member's widening or escalation applies to the group. Pass it an E2E worker count. A failure that passes alone and lies outside the group's diff, or that is in the baseline, is not red (`implement` → Gates). Skip a gate whose tree and command line match a passing run (`orchestrate` → Don't).
4. **T1 is red:** a helper traces the failure to a member; if that's unclear, take the last member in child order. Its implementer gets the group base as its new base. In its lane worktree it merges the integration branch, fixes the failure, runs the group T1, adds the path the members' T1 missed to the test map, and names the commit it merged in `## integration`. Merge its lane into the integration branch; the tree now matches its green lane tip, so T1 doesn't rerun. Each red T1 after a fix counts as a pass toward the cap.
5. **Integration review:** only when an integrator changed something. A fresh reviewer, in code mode, against the members' plans, gets every integrator's range: `git show --remerge-diff <merge>` for a conflict, and from the merged commit to the lane tip for a fix, plus any review-fix commits since the last pass. Its task names the ledger, that of the last integrator's member in child order, and the heading `## integration pass N`. Fixes go on the lane a finding is about. Merge that lane again and rerun the group T1. The normal pass cap applies.
6. **Integrated:** every lane is merged, the group T1 is green, and any integration review is approved. Merge the integration branch into the work branch, and record the end time.

## Claims
- Every child has a claim in `epic.md`; within a group, claims don't overlap.
- A child (A) that must change files outside its claim, except the merge-friendly files the epic names, reports it. So does a child that must change a contract an earlier child delivered: every unintegrated child whose entry records a dependency for that contract counts as claiming it.
  - If no unintegrated child that isn't ordered with A (neither depends on the other) claims those files, widen A's claim under Decisions; A continues.
  - Otherwise, with B the child that claims them, record under Decisions:
    - **B has not started:** B gets a dependency on A and leaves its group if it has one. Widen A's claim; A continues.
    - **B is running or finished:** A gets a dependency on B and leaves its group if it has one. A keeps its lane and worktree and waits; once B integrates, A merges the work branch into its lane (`orchestrate` → Merging into an unfinished child) and continues. Widen A's claim under Decisions.

## Checkpoints in lane mode
- Checkpoint fixes happen on the checkpoint branch (`checkpoint-failures.md`), never in a lane worktree.
- A paused lane merges the work branch into its lane branch once the checkpoint branch has merged, then continues.
