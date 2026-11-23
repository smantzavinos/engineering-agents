# ADR 0008: Adopt the board-pipeline improvements from gm-agent-pipeline

Status: Accepted

Date: 2026-11-23

Requirement refs: FR-001, OPR-001

## Context

Daniel Gehriger ran this repo's delivery pipeline and PR automation on a
GitHub Project board for several months (`gm-agent-pipeline`). His changes
fall into two groups. Most of them are generic: one place where people find
everything waiting for them, plain-language bot comments, a tolerant command
parser, a tracker adapter with guards, a script-only board sync, a stricter PR
sweep, and a capture policy that keeps the backlog from growing. The rest is
specific to his company: Sonar, Windows paths, publishing through the GitHub
API, a `ready for merge` label, shared repositories, safety wording, Confluence,
model failover, Jira and running everything as Hermes profiles.

The owner approved adopting all the generic improvements on 2026-11-23. The
contract is `plans/2026_11_23_board_pipeline_adoption/plan.md`.

## Decision

1. **One human queue.** The statuses `Clarification needed`, `Awaiting
   approval` and `Blocked` become one status, `Your turn`. A display-only
   `Waiting for` field says what the person has to do (`💬 answer`,
   `👍 approve`, `🛠️ unblock`, `⚖️ decide on PR`, `🔀 merge PR`; `⏳ Bot's turn`
   while a reply waits for the dispatcher). No bot reads it: the kind of wait
   comes from the newest bot marker or the PR labels. A `Backlog` status holds
   issues nobody asked to work on.
2. **Board names.** Statuses and fields keep their internal names in scripts,
   skills and markers, and get friendlier names on the board (`Icebox` →
   `Later`, `Track` → `Size`, `Origin` → `Source`, `Autonomy` → `Bot
   approvals`). The tools accept both.
3. **Commands.** Every reply starts with `<handle> <verb>` (default handle
   `/devbot`). One parser, `scripts/commands.py`, serves every script and
   tolerates common slips; a first line ending in `?` is a question.
4. **PR labels say who acts next.** `review-bot:*`, `fix-bot:*` and
   `needs-human:*` replace the `pr:*` labels; the sweep renames old labels on
   sight. Unresolved review threads, red CI and merge conflicts send a PR back
   to the fix bot; a result counts only with verification logs.
5. **Tools.** `scripts/gh-project.py` is the GitHub Project adapter with
   guards (audit comments on moves into `Your turn`, `Done` and `Canceled`;
   owner-only moves). `scripts/board-sync.py` keeps the board consistent
   without an LLM. `scripts/post-comment.py` checks every bot comment against
   `docs/references/comment-style.md`.
6. **Policies.** "Decide, don't ask": agents fill gaps the sources answer and
   record them as decisions; they ask only about the owner list. "Finish in
   task": agents add no backlog item without the owner's approval; minor
   findings left undone are listed, out-of-scope defects are proposed. The plan
   gate is held only when the plan departs from the approved design.

Left out: everything specific to his company (listed above), the Hermes-only
runner scripts, and his instance and runtime modules. Babysit rounds still
publish with git (fast-forward push; merge by default, rebase only on
`fix rebase`).

## Consequences

- Boards that used the old statuses run `gh-project.py fields`, `labels` and
  `migrate-your-turn` once. Old PR labels keep working and are renamed.
- The dispatchers import `commands.py` and `comment_style.py` from their own
  directory, so installing copies all of `scripts/*.py` and the prompt
  directories, not one file.
- Sessions post through `post-comment.py`; it warns before
  `COMMENT_STYLE_ENFORCE_FROM` and refuses afterwards.
- `tests/scripts/` holds the ported unit tests; the dispatcher and board-tools
  specs run them in the fast suite.

## Not done

- Following PR cards on the board, cleaning workflow labels off merged PRs and
  assigning PRs automatically (board-sync features tied to his setup).
- Required-vs-advisory checks stay `TASK-0006`; `PR_HUMAN_CHECKS` covers only
  checks a person satisfies.
