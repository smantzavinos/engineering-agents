# ADR 0010: Board automation on T3, without Hermes

Status: Accepted
Date: 2026-11-24

## Context

The board ticks and the PR sweep ([ADR 0008](0008-board-pipeline-from-gm-agent-pipeline.md))
were written for Hermes: its cron runs the ticks, and each session is a
`hermes chat --oneshot` process. Nothing in them needs Hermes. The ticks call
no model, a session gets everything in its prompt, and all state is in GitHub,
the state directory and committed files. Hermes also learns between sessions,
which the owner does not want for bots that act on a team's board.

## Decision

- **Launcher setting.** `PIPELINE_LAUNCHER` selects how a tick starts a
  session: `hermes` (default, unchanged) or `t3`. Launching and the liveness
  check live in `scripts/session_launcher.py`, used by both dispatchers.
- **T3 sessions are threads.** With `t3`, a session is a thread started by the
  T3 command line in the repository's project. The dispatch record holds
  `t3:<thread id>`. A thread that waits for an answer counts as a failed
  dispatch. When the server cannot be asked, the session counts as running and
  the tick reports a stopped job, so a server restart does not retry every
  running session. The result file stays the only proof of a finished session.
- **Ticks are systemd timers**, not T3 scheduled tasks: a scheduled task starts
  a model turn on every run, and a tick must cost nothing when nothing is due.
- **One T3 server per board**, with its own data directory, and clones only
  the bots use.
- **Identity is configuration:** the GitHub token, the logins, and the commit
  author (`PIPELINE_GIT_NAME`, `PIPELINE_GIT_EMAIL`).
- **No learning.** Bot behavior comes only from the scripts, prompts and
  skills at the installed revision. Any later job that reads past sessions may
  propose changes for a person to review and commit; it never applies them.
- **Owner policy is a shared reference.** "Decide, don't ask" and "Finish in
  task" are in `docs/references/owner-policy.md`, packaged with the board and
  PR skills, so the Pi renderings no longer cite a skill Pi does not have.

Setup: [docs/t3/README.md](../t3/README.md).

## Consequences

Sessions are visible and can be steered in T3. A tick failure shows only in
the journal; no notification is sent. The T3 command line cannot set the
thinking level, so sessions use each model's default. The work tick is not
supported on T3 until a Pi `work-item` exists that drives `scope` and
`run-plan` from a board item ([ADR 0007](0007-frontier-pipeline-on-pi.md)
lists that as not done). The Hermes runtime keeps working as documented in
`docs/hermes/`.
