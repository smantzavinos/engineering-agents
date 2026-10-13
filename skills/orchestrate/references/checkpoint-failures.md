# Checkpoint failures

Read this when a checkpoint run (`orchestrate` → Checkpoints) reports a failure.

1. **Triage.** A failure already in the baseline is not a regression. For any other failure, a helper reruns it alone:
   - **It passes alone:** record a flake. A second sighting of the same flake puts it on the epic's Quarantine list, with an expiry. It also gets a tracker item, if the epic pre-authorizes filing; otherwise it goes under Follow-ups.
   - **It fails on the base branch's tip:** it is a base-side failure. Add it to the baseline, and record a follow-up.
   - **Otherwise:** bisect the commits since the last green checkpoint, running only the failing tests, to find the culprit.
2. **Route.**
   - **Culprit:**
     - normally, the culprit child's implementer fixes it;
     - for a merge commit, the implementer of the child merged last;
     - at epic close, the last child in child order.
   - **Running children:** decide for each one.
     - If it builds on the broken code, pause it while the fix runs, in the culprit's worktree or one that `lanes.md` names.
     - Otherwise, resume its implementer with the finding. It records the finding as a carried-over blocker in its own ledger.
   - **The fix:**
     - the fixer runs T1 plus the failing tests;
     - it adds the path T1 missed to the test map;
     - it appends `## checkpoint fix` to the culprit's ledger;
     - a fresh reviewer reviews it (code mode, from the commit before the fix), with the normal pass cap.
   - **Recheck:** rerun the checkpoint on the fixed commit. Record the regression in `state.json`.
