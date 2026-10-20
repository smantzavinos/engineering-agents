# Checkpoint failures

Read this when a checkpoint run (`orchestrate` → Checkpoints) reports a failure. Everything here happens on the checkpoint branch, in the checkpoint worktree. The work branch and running children stay untouched until the checkpoint is green. The one exception is the merge into a stopped child (orchestrate → Where work runs).

1. **Triage.** A failure already in the baseline is not a regression. For any other failure, a helper reruns it alone:
   - **It passes alone:** record a flake. A second sighting of the same flake puts it on the epic's Quarantine list, with an expiry. It also gets a tracker item if the epic pre-authorizes filing; otherwise it goes under Follow-ups.
   - **It fails on the base branch's tip:** it is a base-side failure. Add it to the baseline and record a follow-up.
   - **Otherwise:** bisect the commits since the last green checkpoint, running only the failing tests, to find the culprit.
2. **Fix.** Spawn a fresh implementer in the checkpoint worktree, on the checkpoint branch. A resumed session would still be in its old worktree. Give it the failure digest and the culprit's plan and ledger:
   - for a lane-merge commit: the merged children's plans and ledgers;
   - for the checkpoint's own base-merge commit, or at epic close: the last integrated child's plan and ledger.

   It fixes the failure, runs T1 plus the failing tests, adds the path T1 missed to the test map, and appends `## checkpoint fix` to the culprit's ledger. A fresh reviewer then reviews the fix (code mode, from the checkpoint commit), with the normal pass cap.
3. **Recheck.** Rerun the full gates on the checkpoint branch's tip. When it is green, merge as Checkpoints step 2 says. Record the regression in `state.json`.
4. **Running children.**
   - **If one builds on the broken code,** steer it now with the failure digest: "Don't fix this failure; it is being fixed on the checkpoint branch. Commit, stop, and reply." Don't resume it until the checkpoint branch has merged:
     - a lane child then merges the work branch into its lane branch;
     - without a pool, a stopped child gets the fix through that merge.

     Then continue with its new base (orchestrate → Where work runs).
   - **Others** go on untouched. Epic-close fixes aren't paused (`orchestrate` → Epic close).
