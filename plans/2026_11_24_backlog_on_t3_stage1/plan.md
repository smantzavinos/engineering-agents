# Backlog automation on T3, stage 1: board sync, triage and PR sweep for proj-spine

|              |  |
|--------------|--|
| **Created**  | 2026-11-24 |
| **Status**   | Approved by the owner, 2026-11-24 |
| **Source**   | Thread "Backlog Automation Process Review"; ADR 0007, 0008, 0009 |
| **Branch**   | `t3/review-backlog-process-design` |

## Goal

Run the board jobs that need no change to the development process on
`globusmedical/proj-spine`, without Hermes: systemd timers run the existing
no-LLM ticks, and each session a tick starts is a thread in a T3 server that
serves this one board. Nothing learns or changes by itself: behavior comes only
from the scripts, prompts and skills at a pinned revision of this repo.

Stage 1 covers board sync, unheard, triage and the PR sweep (review and fix
bots). Work items (`Up next` pickup) stay off until stage 2.

## What was checked (T3 v0.1.10)

- `t3 thread start <project> <message|-> --provider --model --title --json`
  returns `{threadId, projectId, runId}` at once. `--worktree <ref> --branch
  <name>` creates a new worktree; the CLI cannot bind an existing one.
- `t3 thread show <id> --json` returns `status` (`preparing`, `queued`,
  `starting`, `running`, `waiting`, `completed`, `failed`, `interrupted`,
  `cancelled`, …), `pendingRequestCount`, `pendingBackgroundTasks`,
  `runtimeMode` and `worktreePath`.
- A probe thread started from the CLI ran with `runtimeMode: full-access` and
  reached `completed`. Whether full access is a server default or was
  inherited is not known.
- `--base-dir` (or `T3CODE_HOME`) selects the server's data directory, so a
  second server is separate from the desktop app's.
- The CLI has no flag for thinking level, runtime mode or skills.
- Hermes coupling in `scripts/`: `spawn()` and `alive()` in the two
  dispatchers, `HERMES_HOME` as the default state path, and one
  `hermes sessions rename` line in `pr-sweep-prompts/review.md`.
- proj-spine (checked 2026-11-24): no GitHub Project is linked to it. `main`
  has no required-signatures rule, and its rules include a Copilot code
  review. `gh` holds two accounts; the active one, `smantzavinos-globus`, has
  the `project` scope.
- The Pi renderings of `backlog`, `triage-backlog`, `pull-request` and
  `babysit-pr` point to `software-development` ("Decide, don't ask", "Finish
  in task") and `review-code`, which are not rendered for Pi. `backlog` also
  names `gem-project.py` where it means `gh-project.py`.

## Decisions

1. **Launcher setting.** `PIPELINE_LAUNCHER=hermes|t3` (default `hermes`,
   unchanged). Launch and liveness move out of the two dispatchers into one
   module, `scripts/session_launcher.py`.
2. **T3 launch.** `t3 thread start --json --provider <P> --model <M> --title
   <name> <checkout> -` with the rendered prompt on stdin. The thread runs in
   the project folder; stage 1 needs no T3 worktree, because the review and
   fix prompts already make their own worktrees from the checkout and triage
   only reads.
3. **Session handle.** The dispatch record's `pid` holds a process id for
   Hermes and `t3:<thread id>` for T3. `alive()` accepts both;
   `pipeline_runtime.live_authors` stops casting it to an integer.
4. **Liveness for T3.** Live while `status` is `preparing`, `queued`,
   `starting` or `running`, or `waiting` with background tasks pending.
   `waiting` with a pending request means the session asked something: it
   counts as a failed dispatch, reported once with the thread link. The result
   file stays the only proof of a finished session.
5. **Server unreachable is not "dead".** When `t3 thread show` fails, the
   session counts as live and the tick reports through the existing stopped
   alert. Otherwise a server restart would retry every running session.
6. **Prompts.** The session-rename step in `review.md` becomes a variable the
   launcher fills (empty for T3). Each prompt already names its skills, which
   replaces Hermes's `-s`.
7. **Skills on Pi.** "Decide, don't ask" and "Finish in task" move to a
   reference file packaged with `backlog`, `triage-backlog`, `pull-request`
   and `babysit-pr`, and `software-development` points to it. The
   `review-code` mention in `pull-request` gets a Pi wording. Fix
   `gem-project.py` in `backlog`.
8. **One T3 server per board.** `t3 serve --base-dir <dir> --port <port>
   --no-browser` as a systemd user service. Each repository of the board is a
   project in it, on a clone the bots own (never
   `/home/spiros/code/proj-spine`, which is a working checkout).
9. **Timers.** systemd user timers: board sync 5 min, unheard 5 min, triage
   15 min, PR sweep 2 min. Not scheduled in stage 1: the work tick, hygiene
   and the digest (both only print). Tick output goes to the journal.
10. **Bot identity is configuration.** Three settings, so a bot account can
    replace the owner's later without a code change:
    - *GitHub account:* a token for one named account, given to the ticks
      (`GH_TOKEN_FILE`) and to the T3 server's environment, so the sessions
      use it too. Never the `gh` keyring's active account, which changes with
      `gh auth switch`.
    - *Logins:* for now `PIPELINE_OWNERS` and `PIPELINE_BOT_LOGINS` name the
      same account, with `PIPELINE_SHARED_ACCOUNT=1` and the `/devbot` handle.
    - *Commit author:* new `PIPELINE_GIT_NAME` and `PIPELINE_GIT_EMAIL`. When
      set, a dispatcher writes them to the checkout's local git config before
      it starts a session, so every worktree of that clone commits as the
      bot. An email no GitHub account has verified shows on GitHub without
      the owner's avatar. For proj-spine: `devbot (Spiros Mantzavinos)`,
      `smantzavinos+devbot@globusmedical.com`.
11. **Start on this workstation**, with proj-spine alone;
    `spine-web-frontend` joins the `repositories` map once proj-spine runs.
    Sessions run at each model's default thinking level.
12. **Docs.** A new `docs/t3/README.md` holds the T3 setup (server, timers,
    environment file). `docs/hermes/` stays as it is. ADR 0010 records the
    launcher choice and the "no learning" rule.

## Work

1. **Tests first** (an agent other than the implementer): cases in
   `tests/specs/pipeline-dispatch-spec.sh`, `pr-sweep-dispatch-spec.sh` and
   `tests/scripts/` with a fake `t3` binary, for decisions 2 to 6. The Hermes
   cases stay green untouched.
2. `scripts/session_launcher.py`; both dispatchers and
   `pipeline_runtime.py` use it; the `review.md` variable; the commit-author
   settings (decision 10), with a spec case.
3. Skills: the shared reference, the Pi wording, `skill-resources.json`,
   `node tools/render-skills.mjs --write`.
4. `docs/t3/README.md` with unit templates and the environment file; ADR
   0010; route it from `AGENTS.md` and `docs/references/delivery-pipeline.md`
   (Runtime paragraph).
5. proj-spine, on a branch there: `pr-review-hooks.md`, a task-tracking doc
   routed from `AGENTS.md` (assess-repo, Option B). A new organization
   project under `globusmedical`, created by hand and linked to the
   repository, then `gh-project.py fields` and `labels`.
6. On the host: the bot clone, the token file, the T3 server, then
   `PIPELINE_DRY=1` and `PR_SWEEP_DRY=1` runs of every tick. Before the
   timers go on, one probe thread on the bot server confirms that a session
   sees the server's `GH_TOKEN`, runs with full access, and commits as the
   bot. First live run on one test issue and one test PR.

Gates: `bash tests/specs/pipeline-dispatch-spec.sh`,
`bash tests/specs/pr-sweep-dispatch-spec.sh`,
`bash tests/specs/skill-render-spec.sh`, then `./tests/run-tests.sh fast`;
a fresh review at the end.

## Corrections after approval (review pass 1)

Both keep what decisions 4 and 5 intend; the wording above is the approved
text, and `launcher-contract.md` holds the corrected rules.

- **Decision 4.** T3 keeps a run `running` while a question or an approval is
  pending; only `pendingRequestCount` goes above 0. So "asked" is any
  unfinished status with a pending request, not `waiting` alone. Without this
  a session that asks would count as running for good.
- **Decision 5.** The rule covered only the check of a running session. A tick
  now also asks the server before its other work (`check`), so an outage
  stops the job with the alert and uses up no retries. Without this, three
  ticks of an outage would park every due PR for six hours.
- **Decision 10.** The setup puts `GH_TOKEN` in a `secrets.env` that every
  unit loads, not `GH_TOKEN_FILE`, which only the two dispatchers read.

## Step 5 results (2026-11-25)

The owner said go for steps 5 and 6 on 2026-11-25.

- **Board:** organization project `globusmedical` number 15, "Spine Backlog"
  (https://github.com/orgs/globusmedical/projects/15), private, linked to
  `globusmedical/proj-spine`. `gh-project.py fields` and `labels` ran;
  `check` reports `ok: true` with no items. No issue was added.
- **Board config:** [board.proj-spine.json](board.proj-spine.json), with the
  paths of the layout in `docs/t3/README.md`. It becomes
  `~/devbot/proj-spine/board.json` on the host.
- **proj-spine:** draft PR globusmedical/proj-spine#46 (branch
  `t3/board-task-tracking`), stacked on #45, the tip of the repository's
  readiness work. That branch already had `pr-review-hooks.md`; the PR adds
  `docs/3_process/task_tracking.md`, its route in `AGENTS.md`, and the
  pr-tracking rows for the labels and the sweep.
- **Found for the host's environment file:** `PR_HUMAN_CHECKS=pr-ready / Require Label`.
  It is the only required check on `main`, and it needs the `ready for merge`
  label, which only a person adds.
- **Step 6 (host)** is proposed in a separate thread of the dotfiles project.
  The dotfiles flake pins engineering-agents at `42befcb`; the bots need a
  revision that holds this branch, so the branch has to be pushed first.

## Not in this plan

- Work items: the submodule worktree question and the Pi `work-item` bridge
  to `scope` and `run-plan` (stages 2 and 3).
- A Nix module for the server and timers; the units are written by hand first.
- Notifications beyond the board and the threads. A tick that fails shows only
  in the journal.
- Periodic review of threads to propose instruction changes.

## Open questions

None. Steps 5 and 6 change proj-spine, GitHub and this workstation; each
starts only when the owner says so.
