# A plan across several repositories

For a project whose plan lives in one repository (the **root**) and whose code lives in git submodules of it. One plan can change several submodules. It is still one plan, one model, one ledger and one approval.

Each skill says what its role does. This file holds the rules they share. Nothing here applies to a project with no submodules.

## What the project's agent guide names

For each submodule a plan may touch:
- how to add it to a worktree of the root (a fresh worktree usually has none checked out);
- its default branch, and where its pull requests go;
- its gates: the T1 and full-gate commands, run inside it.

If the guide doesn't name these for a submodule the work needs, stop and ask.

## Where things live

| Thing | Where |
|---|---|
| `plan.md`, the model, `review.md`, `state.json`, approval lines | The root, in the plan directory |
| The path file and the profile | The root |
| Catalog docs and rules | The root, or a submodule when the path file's globs say so |
| Code, and its tests | The submodules |

Every path is written from the root, the submodule's path first: a code reference in the model, an item under Changes outside the model, a glob in the path file.

## Branches

- The root has the work branch. Each submodule the plan touches gets its own branch, created inside it at the commit the root points to. A submodule is checked out on no branch, so create the branch before the first commit there.
- **A submodule's base is the commit the root points to at the approval commit.** To start from a newer commit, move the pointer in a root commit before the approval.
- `state.json` records, for each repository: its path, its branch and its base commit, and its baseline gate digest.
- A submodule the plan didn't name and the build turns out to need is added the same way, and recorded. That alone is not a deviation.
- Never touch a submodule the plan doesn't change: no branch, no commit, no pointer move.

## A handed-over state is one root commit

Whoever hands work over (the implementer to review, the build to the pull requests) does this, in order:
1. Commit in each submodule, on its branch. Leave each one clean.
2. Make one root commit that moves each changed submodule's pointer to its branch tip, and holds the model and the ledger.

That root commit's id names everything: the reviewer, the checks and `state.json` use it alone. A submodule that is dirty, or sits at a commit the root doesn't point to, means the state was not handed over; a reviewer who finds one raises a blocker and reads nothing further.

Between two root commits, a submodule's range is between the two commits they point to (`git ls-tree <root commit> <submodule path>`).

## The checks

- Run `c4ish` and `model-check` from the root, with the fixed command. They read each submodule through the commits the root points to.
- Every submodule the plan touches is checked out. So is any other submodule whose pointer moved since the approval: without it the check exits 2 and names it.
- What changed inside a submodule counts as changed lines, under its path. A pointer moving does not.
- The check prints the submodule commits it compared. The ledger entry records them with the run.
- Merging the root's default branch into the work branch after the approval brings in other people's pointer moves, and their changes then count as unaccounted lines. Don't, unless a step of the process says to.

## Gates and review

- Gates run per repository, with that repository's commands. Test selection inside a submodule is computed from its own base commit. A gate's tree is the tree of the repository it ran in.
- The baseline is one full-gate run per repository the plan touches.
- The reviewer reads each repository's diff from its base to the commit the root points to, and the root's own diff. One ledger, in the root.

## Pull requests

One pull request per changed submodule, and one in the root. The set, the links between them, the merge order and the last pointer move are in the PR review contract (`pull-request` → A change across several repositories).

- A repository may merge by squash. The commit the root pins at the end is then a new one that holds the reviewed tree; the contract's tree check confirms it before the pointer moves.
- The checks compare a submodule by the two commits the root points to. Those need not be related: only both must be in the local repository.
- The ledger and the root's earlier commits keep naming the branch commits that were reviewed. After a squash those are off the target branch; the host keeps them under the pull request's head ref, so fetch that ref to read one.
- The model checks run on the work branch before the merge, never on a target branch after it. After a squash merge of the root, the approval commits are likewise under the root pull request's head ref.

## Don't

- Hand over a state that is not one root commit.
- Rewrite a submodule branch (amend, rebase, squash) once the root has pinned a commit of it: the root's history and the ledger name those commits. A squash by the host at the merge is not that: it adds a commit to the target branch and leaves the branch's commits as they are.
- Move a pointer of a submodule the plan doesn't change.
- Put a plan, a model or a ledger in a submodule.
