# Board Automation on T3 (no Hermes)

How to run the board jobs of [the delivery pipeline](../references/delivery-pipeline.md)
and [PR automation](../hermes/pr-automation.md) without Hermes: systemd timers
run the tick scripts, and every session a tick starts is a thread in a T3 Code
server that serves one board. The decision is [ADR 0010](../adr/0010-board-automation-on-t3.md).

The label machine, the commands and the board rules do not change; they are in
the two documents above. Only the runtime differs:

| | Hermes | T3 |
|---|---|---|
| Tick | `hermes cron --no-agent` | systemd user timer |
| Session | `hermes chat --oneshot` process | thread in the board's T3 server (`PIPELINE_LAUNCHER=t3`) |
| Session handle in `dispatches.jsonl` | process id | `t3:<thread id>` |
| Where a tick's output goes | the Hermes delivery | the journal (`journalctl --user -u devbot-…`) |
| Skills | canonical tree in the session | the Pi installation of the server's user |

**Nothing learns.** A session gets only its rendered prompt and the installed
skills. What the bots do changes when someone changes the scripts, prompts or
skills in git and installs that revision, and in no other way. A tick calls no
model.

## Scope

Supported: board sync, unheard, triage and the PR sweep (review and fix bots).
The work tick (`pipeline-dispatch.py work`) is not scheduled: its session runs
the `work-item` skill, which is not rendered for Pi.

## One server per board

A board is the unit: it has one WIP limit, one owner list and one bot identity.
Each board gets its own directory, T3 server and timers. The layout below is a
convention; every path is set in the environment file.

```text
~/devbot/<board>/
  env                  settings (below)
  secrets.env          GH_TOKEN=…, mode 0600
  board.json           GH_PROJECT_CONFIG (project number, repositories, owners)
  engineering-agents/  checkout of this repo at the revision in use (scripts, prompts)
  repos/<repo>/        one clone per repository of the board, used by the bots only
  state/               board-sync, pipeline, pr-automation
  t3/                  the server's data directory (T3CODE_HOME)
```

- **Bot clones.** Never point the bots at a checkout a person works in: they
  fetch, create worktrees and write the local git identity there.
- **Revision.** The scripts come from `engineering-agents/` in the board
  directory; the skills come from the Pi installation (Home Manager). Update
  both to the same revision.

## Identity

Three settings; replacing the owner's account with a bot account later changes
values only.

| What | Setting | Note |
|---|---|---|
| GitHub account | `GH_TOKEN` in `secrets.env`, loaded by every unit | The ticks and the server get the same token, so sessions use it too. Do not rely on the `gh` keyring: its active account changes with `gh auth switch`. `gh auth token --user <login>` prints a keyring token for one account. The account needs the `repo` and `project` scopes. |
| Who the bots listen to and post as | `PIPELINE_OWNERS`, `PIPELINE_BOT_LOGINS`, `PIPELINE_SHARED_ACCOUNT`, `PR_AGENT_HANDLE` | While the bots use the owner's account: owners and bot logins name the same login, `PIPELINE_SHARED_ACCOUNT=1`, handle `/devbot`. |
| Commit author | `PIPELINE_GIT_NAME`, `PIPELINE_GIT_EMAIL` | Written to the clone's local git config before each session, so every worktree of the clone commits under that name. An email no GitHub account has verified shows without an avatar. |

Pushing uses the clone's remote, so its URL must be one the account can push
to (an SSH key of that account, or HTTPS with `gh auth setup-git`).

## Environment file

`~/devbot/<board>/env` (systemd `EnvironmentFile` syntax: no variable
expansion, absolute paths). The script headers list every setting; these are
the ones this runtime needs.

```ini
PATH=/etc/profiles/per-user/<you>/bin:/run/current-system/sw/bin:/usr/bin:/bin

# launcher
PIPELINE_LAUNCHER=t3
T3CODE_HOME=/home/<you>/devbot/<board>/t3
PIPELINE_SESSION_PROVIDER=pi
PR_SESSION_PROVIDER=pi
PIPELINE_TRIAGE_MODEL=<provider/model>
PR_REVIEW_MODEL=<provider/model>
PR_BABYSIT_MODEL=<provider/model>

# board
GH_PROJECT_CONFIG=/home/<you>/devbot/<board>/board.json
PIPELINE_REPO=<owner>/<repo>
PIPELINE_CHECKOUT=/home/<you>/devbot/<board>/repos/<repo>
PIPELINE_LIST_CMD="python3 /home/<you>/devbot/<board>/engineering-agents/scripts/gh-project.py list"
PIPELINE_MOVE_CMD="python3 /home/<you>/devbot/<board>/engineering-agents/scripts/gh-project.py move {number} {status}"
PR_SWEEP_CHECKOUT_ROOT=/home/<you>/devbot/<board>/repos

# identity
PIPELINE_OWNERS=<login>
PIPELINE_BOT_LOGINS=<login>
PIPELINE_SHARED_ACCOUNT=1
PR_AGENT_HANDLE=/devbot
PIPELINE_GIT_NAME="devbot (<Owner Name>)"
PIPELINE_GIT_EMAIL=<owner>+devbot@<domain>

# state
BOARD_SYNC_STATE=/home/<you>/devbot/<board>/state/board-sync
PIPELINE_STATE=/home/<you>/devbot/<board>/state/pipeline
PR_SWEEP_STATE=/home/<you>/devbot/<board>/state/pr-automation
```

The models are Pi model ids as the server lists them. Sessions run at each
model's default thinking level; the T3 command line has no setting for it.

## Units

All are systemd **user** units in `~/.config/systemd/user/`. `<board>` is
written out in each file; a second board gets its own set.

The server:

```ini
# devbot-<board>-t3.service
[Unit]
Description=T3 Code server for the <board> board bots

[Service]
EnvironmentFile=%h/devbot/<board>/env
EnvironmentFile=%h/devbot/<board>/secrets.env
ExecStart=/usr/bin/env t3 serve --base-dir %h/devbot/<board>/t3 --port <port> --no-browser %h/devbot/<board>/repos
Restart=on-failure

[Install]
WantedBy=default.target
```

One service and one timer per tick, all of this shape:

```ini
# devbot-<board>-pr-sweep.service
[Unit]
Description=<board>: PR sweep tick
After=devbot-<board>-t3.service

[Service]
Type=oneshot
EnvironmentFile=%h/devbot/<board>/env
EnvironmentFile=%h/devbot/<board>/secrets.env
ExecStart=/usr/bin/env python3 %h/devbot/<board>/engineering-agents/scripts/pr-sweep-dispatch.py
TimeoutStartSec=15min
```

```ini
# devbot-<board>-pr-sweep.timer
[Timer]
OnBootSec=3min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
```

| Unit name ends in | Script and arguments | Every |
|---|---|---|
| `board-sync` | `board-sync.py` | 5 min |
| `unheard` | `unheard.py` | 5 min |
| `triage` | `pipeline-dispatch.py triage` | 15 min |
| `pr-sweep` | `pr-sweep-dispatch.py` | 2 min |

Not scheduled: `pipeline-dispatch.py work` (see Scope), `pipeline-dispatch.py
hygiene` and `board-sync.py --digest`; the last two only print, so run them by
hand when wanted. A tick that is still running when its timer fires again is
not started twice.

## Bring-up

1. Create the board directory, the clones, `board.json` and the two
   environment files. Prepare the board and labels with `gh-project.py fields`
   and `gh-project.py labels`, and onboard each repository with `assess-repo`.
2. Start the server (`systemctl --user enable --now devbot-<board>-t3`) and add
   each clone as a project: `T3CODE_HOME=… t3 project add <clone>`.
3. Probe once before any timer is on. Start a thread on the bot server that
   reports its GitHub login and git identity, then read it:

   ```sh
   export T3CODE_HOME=~/devbot/<board>/t3
   t3 thread start --json --provider pi --model <model> --title "identity probe" \
     ~/devbot/<board>/repos/<repo> \
     'Run `gh api user --jq .login` and `git config user.name`, and reply with both outputs only.'
   t3 thread show --json <thread id>
   ```

   The reply must name the bot's account, and `runtimeMode` must be
   `full-access`: a session that waits for a permission can never finish.
   The git name is the bot's only after a tick has started one session, so
   check it again then.
4. Dry-run every tick with the environment loaded (`PIPELINE_DRY=1` for
   `pipeline-dispatch.py`, `PR_SWEEP_DRY=1` for the sweep, `--dry` for
   `board-sync.py` and `unheard.py`) and read what each would do.
5. Enable the timers. Try one test issue and one test PR first.

## Operating

- **What waits for you** is on the board (`Your turn`) and in the PR labels, as
  with Hermes. Every session is a thread in the board's server, titled with
  its item or PR; open the server's address to read or steer one.
- **A session that asks a question** (or waits for a permission) counts as
  failed. The first tick that sees it prints one line with the thread link,
  once, and the usual retry rules apply. Answering it later in T3 lets that
  thread finish; its result is still delivered.
- **Server down, or a clone that is not a project in it:** each tick asks the
  server first. When it cannot, the tick does nothing for that repository:
  no label, no record, no retry used up. It exits 1 and prints a stopped
  alert (repeated hourly), then one line when it works again. In a PR sweep
  over several repositories where only some fail, the others are swept and
  each failing one gets a plain error line (at most every six hours) instead
  of the stopped alert. When the server stops answering about one running
  session, that session counts as running, so nothing is retried, and the
  stopped alert is raised.
- **Stopping a thread in T3 does not stop the bots:** the next tick counts the
  session as failed and starts another under the usual retry rules. To take a
  PR or an item away from the bots, use the labels and commands of the
  pipeline.
- **Failures** of a tick are in the journal only:
  `journalctl --user -u 'devbot-<board>-*' --since today`, and
  `systemctl --user list-timers 'devbot-*'` for the schedule.
- **Stop everything:** `systemctl --user stop 'devbot-<board>-*.timer'`.
  Threads that are running finish their work.
- **Session records:** `state/*/dispatches.jsonl`, the prompt and launch output
  under `state/*/logs/`, the result under `state/*/results/`.
