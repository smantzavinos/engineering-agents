# Launcher contract (plan decisions 1 to 6 and 10)

The interface the contract tests pin and the implementation meets. The test
author and the implementer both work from this file; neither changes it.

## Module `scripts/session_launcher.py`

Standard library only, importable by both dispatchers (they already add
`scripts/` to `sys.path` for `pipeline_runtime`).

```python
kind(env) -> "hermes" | "t3"
launch(env, *, hermes_argv, prompt_file, title, checkout, log_file,
       cwd=None, model="", provider="", child_env=None) -> int | str
check(env, checkout) -> None
probe(env, handle, state_dir=None) -> {"state": ..., "link": str, "detail": str}
alive(env, handle, state_dir=None) -> bool
rename_step(env, *, hermes_bin, number, short_head) -> str
```

`env` is a mapping (the dispatcher's `ENV`).

### `kind`

`PIPELINE_LAUNCHER`, default `hermes`. Any other value than `hermes` or `t3`
raises `ValueError` whose message names `PIPELINE_LAUNCHER`.

### `launch`

Both launchers, first: when `PIPELINE_GIT_NAME` or `PIPELINE_GIT_EMAIL` is
set, write each one that is set to the local git config of `checkout`
(`user.name`, `user.email`). A failure here raises; no session starts.

- **hermes:** start `hermes_argv` detached exactly as today
  (`cwd=cwd`, stdin closed, stdout and stderr to `log_file`, `env=child_env`,
  new session). Returns the process id (int). The dispatcher builds
  `hermes_argv`, so the Hermes command line does not change.
- **t3:** run
  `<T3_BIN> thread start --json [--provider P --model M] --title <title> <checkout> -`
  with the text of `prompt_file` on stdin and `env=child_env`.
  `T3_BIN` defaults to `t3`. `--model` is passed when `model` is set;
  `--provider` only together with `--model`. No `--worktree`, no `--wait`.
  The command's output goes to `log_file`. Returns `"t3:" + threadId` from
  the JSON object on stdout; other lines on stdout before it (a notice, a
  warning) do not make a successful start look failed. A non-zero exit, or output without a `threadId`, raises
  `RuntimeError` carrying the end of the output. Which server is used comes
  from the environment (`T3CODE_HOME`); the launcher adds no flag for it.

### `check`

Whether the launcher can start a session for `checkout` right now.

- **hermes:** nothing; returns.
- **t3:** one `<T3_BIN> thread list --json --project <checkout>` call. A
  non-zero exit, a timeout or a missing binary raises `RuntimeError`; the
  message names T3 and carries the end of the output (for example
  `No running T3 Code server uses …` or `No T3 Code project matches …`).

### `probe` and `alive`

The handle says which launcher made it, whatever `PIPELINE_LAUNCHER` is now.

- An int, or a string of digits: `live` when `/proc/<pid>/cmdline` contains
  `hermes`, else `dead` (today's rule).
- `t3:<thread id>`: one `<T3_BIN> thread show --json <thread id>` call.

The command prints one JSON object with the thread's fields under `thread`
(checked on T3 v0.1.10):
`{"thread": {"status": …, "pendingRequestCount": …, "pendingBackgroundTasks": […], "blockedOnThreadWait": …, "link": …}, "messages": […]}`.
Output without a `thread` object that has a `status` is not an answer:
`unknown`.

| `thread show` gives | state |
|---|---|
| `pendingRequestCount` > 0 and `status` `preparing`, `queued`, `starting`, `running` or `waiting` | `asked` |
| `status` `preparing`, `queued`, `starting` or `running` (nothing pending) | `live` |
| `status` `waiting` and background tasks pending (`pendingBackgroundTasks` not empty) or `blockedOnThreadWait` true | `live` |
| any other `status` (`completed`, `failed`, `interrupted`, `cancelled`, `idle`, other `waiting`, a status not listed here), whatever `pendingRequestCount` is | `dead` |
| non-zero exit whose output says the thread is `no longer available` | `dead` |
| any other failure: non-zero exit, no JSON, binary missing, timeout | `unknown` |

The first row is T3's own rule (`thread start --wait` exits 2): a question or
an approval does not change the run's status; it stays `running` and only
`pendingRequestCount` goes above 0.

`link` is the thread's `link` field when the call returned one, else `""`.
`detail` is the end of the command's output for `unknown`, else `""`.

`alive` is true for `live` and `unknown`, false for `dead` and `asked`.

Calls are limited: within one process a handle is asked about once. With
`state_dir`, a handle once seen `dead` is remembered there and never asked
about again by later processes. `asked` and `unknown` are not remembered.

### `rename_step`

- **hermes:** the sentence that ends `pr-sweep-prompts/review.md` today
  ("Last step: run `<hermes> sessions list …` … rename it …"), with
  `hermes_bin`, `number` and `short_head` filled in.
- **t3:** the empty string. The thread already has its title.

`review.md` carries `{rename_step}` in that place; with the Hermes launcher
the rendered prompt is the same text as before.

## Dispatchers (`pipeline-dispatch.py`, `pr-sweep-dispatch.py`)

- `spawn()` calls `launch`; the dispatch record's `pid` holds what it
  returned. The T3 title is the session name the pipeline dispatcher already
  builds; for the PR sweep it is `PR #<n> <kind> @<short head> <repo>`.
  The T3 project is the repository's checkout.
- `alive(pid)` uses `probe`, with the dispatcher's state directory.
- `pipeline_runtime.live_authors` keeps the handle as it is (no `int()`), so
  T3 sessions count toward the WIP limit.
- **`asked`:** the session counts as not running, so the existing
  failed-dispatch handling applies. The tick prints one line that contains
  `waiting for an answer`, the handle and the thread link. A handle is
  reported once: the first tick that is not a dry run prints the line, later
  ticks do not, however long the thread waits. A dry run prints it every
  time and remembers nothing.
- **`unknown`:** the session counts as running: nothing is retried or
  reported as failed. The tick finishes its other work, exits 1 and reports
  through the stopped alert (`pipeline_runtime.job_down`); the reason names
  T3 and carries `detail`. Under `PIPELINE_DRY=1` / `PR_SWEEP_DRY=1` the
  reason is printed and the exit code is 1.
- **`check` first.** A tick that is not a dry run calls `check` once for each
  repository's checkout, after it has delivered finished results and before
  it looks at that repository's sessions or starts one. When it raises, that
  repository's tick fails through the dispatcher's existing error path, so
  the stopped alert applies (the pipeline job stops; the PR sweep reports the
  repository, and stops when every repository fails). Nothing is labeled,
  moved, recorded or counted as a failed dispatch for that repository in
  that tick, and the next tick tries again. So an outage of the T3 server
  costs no retries. Dry runs do not call `check`.
- A failed `launch` is handled as a failed spawn is today (recorded on the
  dispatch record, retried on a later tick).
- Dry runs start nothing and write no git config.
- With `PIPELINE_LAUNCHER` unset, every existing spec passes unchanged.
