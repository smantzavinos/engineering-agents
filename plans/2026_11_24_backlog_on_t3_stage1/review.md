# Review ledger: Backlog automation on T3, stage 1

Plan: `plan.md` (approved 2026-11-24), interface: `launcher-contract.md`.
This plan has no diagram model, so the `architecture-model` checks and the
model verdict do not apply. Code is judged against the plan and the contract.

## code pass 1

Range: `95b362d..ece7e18` (`git diff 95b362d..HEAD -- . ':!dist'`), work steps 1–4.
Steps 5 and 6 (proj-spine, GitHub, host) are out of this diff by design.

**Verdict: changes required.** 1 blocker, 2 major, 5 minor.

### Findings

**B1 — blocker (design): a session that asks a question is never detected on T3 v0.1.10; it counts as live forever.**
Location: `scripts/session_launcher.py:116-123`; contract table in
`launcher-contract.md:63-64`; doc claim in `docs/t3/README.md:202-203`.
The probe classifies `status` `running` as `live` before it looks at
`pendingRequestCount`, and `asked` exists only under `status` `waiting`. In
the v0.1.10 server (bundled source under the t3code store path,
`libexec/t3code/apps/server/dist`), a pending approval or question does not
change the run's status. Every request node is created with
`status: "waiting", countsForRun: false` (Pi adapter included: Pi extension UI
`confirm`/`input`/`select`/`editor` become `approval_request`/`user_input_request`).
The only place a run is stored as `waiting` is turn completion, while it
waits for the checkpoint (`runtimeLayer-*.mjs`, `persistedStatus = … "completed" ? "waiting"`).
T3's own `thread start --wait` reports "needs input" as *run not ended and
`pendingRequestCount > 0`*, whatever the status (`binCli-*.mjs`, `waitForRun`).
So a waiting session shows `status: running, pendingRequestCount: 1`, and
the probe returns `live`. What breaks:
- triage: `job_triage` sees a live triage record and starts no triage for that repository again until someone opens T3 and answers or stops the thread. Nothing is printed, and no stopped alert fires;
- PR sweep: the review or fix round is "running" forever. It is never retried, and a babysit holds a WIP slot. One "running for N min" line comes after `PR_REVIEW_STUCK_MIN`;
- decision 4 ("counts as a failed dispatch, reported once with the thread link") does not happen.

I did not watch a live thread with a pending question: starting one was out
of bounds. This conclusion comes from the server source and the CLI's own rule.
Smallest fix: check `pendingRequestCount > 0` first, so it means `asked` for
every non-terminal status (`preparing`, `queued`, `starting`, `running`,
`waiting`), as the T3 CLI does. Change the contract table to match. Add the
row `{'status': 'running', 'pendingRequestCount': 1} → asked` to
`test_t3_status_table…` and a `running`+pending fixture state to the spec
fixture. The contract is approved, so the table change needs the owner's OK.

**M1 — major (design): when the T3 server is down, launches fail as ordinary failed dispatches: triage fails silently, and PR reviews are parked for 6 h after about 6 minutes of outage.**
Location: `scripts/session_launcher.py:82-93` (start failure → `RuntimeError`);
`scripts/pipeline-dispatch.py:786-787`, `scripts/pr-sweep-dispatch.py:1081-1082`, `1179-1180`
(recorded as `rec["error"]`); `docs/t3/README.md:204-207`.
Decision 5 and the doc make "server unreachable" a stopped-alert condition,
but only `probe` reaches that rule. When no session is outstanding (most of
the time for triage), the tick's only T3 call is `thread start`. It fails
with `No running T3 Code server uses …`, and the record holds `error`. I
reproduced this with a fake `t3` in non-dry runs:
- triage: every tick records an error, exits **0** and prints nothing; `job_up` runs, so no stopped alert ever fires;
- PR sweep: every due PR records one failed review per tick. After `MAX_FAILS` (3 ticks, about 6 min) each PR prints "3 review runs on … failed … retries automatically after a six-hour cooldown". One restart or crash of the bot server parks every queued review for 6 hours.

Smallest fix: when the T3 start output says no server is running, raise a
distinct error from `launch` (for example
`session_launcher.Unreachable(RuntimeError)`). Each dispatcher treats it
like an `unknown` probe: no dispatch record, or one that does not count
toward `MAX_FAILS`, and its reason goes into `probe_errors`, so the tick
exits 1, raises `job_down`, and clears with `job_up`. Update the "Server down"
bullet in the doc. This changes the line "A failed launch is handled as a
failed spawn is today" in the contract, so it needs the owner's OK.

**M2 — major (tests): dispatcher-level contracts are untested. These mutations all leave every suite green.**
Location: `tests/specs/pipeline-dispatch-spec.sh:323-351`,
`tests/specs/pr-sweep-dispatch-spec.sh:294-322` (dry runs only),
`tests/scripts/test_pr_sweep_dispatch.py:361-395` (prompt text only).
I applied each mutation to a scratch copy and ran both specs plus `test_pr_sweep_dispatch` and `test_session_launcher`:
1. PR sweep: `down = bool(probe_errors) or config_error …` → `down = config_error …`. The stopped alert for `unknown` is never raised. **Green.**
2. Pipeline: `if probe_errors:` → `if probe_errors and DRY:`. Non-dry `unknown` exits 0 with no alert. **Green.**
3. Both: `probe(ENV, pid, None if DRY else STATE)` → `probe(ENV, pid, STATE)`. A dry run writes dead markers. **Green.**
4. Both: `title=` and `checkout=` in `spawn` replaced with wrong values. The T3 title, the T3 project, and the checkout that gets `PIPELINE_GIT_NAME`/`EMAIL` are all wrong. **Green.**

The contract names each of these: the stopped alert via `job_down`, dry runs, the
title and project, and the identity "with a spec case" (plan, Work step 2). The
launcher unit tests take `checkout` and `title` as given, so they cannot see
the dispatcher passing the wrong ones.
Fix: in each spec, add one non-dry `unknown` → `🛑 … stopped` → `live` → `✅ … runs again`
case (the pipeline spec already has `real()`), and one dry `dead` case that
asserts no `dead-t3-threads/` dir. Add one non-dry spawn per dispatcher with
a fake `t3` that records its argv and stdin (extend
`tests/spec-fixtures/session-launcher/t3` to accept `thread start`). Assert the
project path, the title, and that `PIPELINE_GIT_NAME` landed in that checkout's local config.

**m1 — minor: the "waiting for an answer" line repeats every 6 h, for as long as the thread waits.**
`scripts/pipeline-dispatch.py:592-595`, `scripts/pr-sweep-dispatch.py:430-432`.
The line goes through `fresh_lines`, so `DEDUPE_TTL` (6 h) applies. `asked` is
not remembered, so every tick probes the thread again. That includes old records
reached through `live_authors` (babysit and work records of closed PRs and
items) and all triage records when none is live. Plan decision 4 and the doc
(`docs/t3/README.md:202`) say once. This is reachable only after B1 is fixed.
Fix: report once per handle through `reported` (a `asked:<handle>` key), or have the doc say
"every 6 hours until you answer or stop the thread".

**m2 — minor: the doc says to stop a session in T3, which the tick then retries.**
`docs/t3/README.md:210-211` ("Running threads finish; stop one in the T3 server").
A stopped thread is `interrupted`, so it is `dead` with no result file. The next
tick counts it as failed and starts a new session: triage on every tick, the
PR sweep up to `MAX_FAILS`. Say so, and name the way to stop the bots on one
item (label or board column) or for good (the timers).

**m3 — minor (unverified risk): continuing a thread after a server restart can race the dead marker.**
`scripts/session_launcher.py:155-158` (marker written for any `dead`).
T3 defaults `continueThreadsAfterServerUpdate` to true. On a graceful
restart, running threads get a "continue where you left off" run after
startup. If a probe lands after startup reconciliation ends the old run and
before the continuation run exists, it reads `interrupted`. The probe then
writes the permanent marker, and the dispatcher retries alongside the
continued thread. I did not measure the window. Fix: the doc decides for the
bot server. Either set `continueThreadsAfterServerUpdate` off, so a restart
means dead and retried, or keep it on and say that a restart can double a
session.

**m4 — minor: `launch` parses all of stdout as one JSON object.**
`scripts/session_launcher.py:91`. v0.1.10 prints only the JSON. But if any
version or setting adds a notice line on stdout, every successful start
raises. Each tick then records a failure and starts *another* real thread:
triage every tick, a review up to 3 times. Fix: parse the last non-empty
stdout line, or scan the lines for a JSON object with `threadId`.

**m5 — minor (tests): the timeout test patches `subprocess.run` for the whole process.**
`tests/scripts/test_session_launcher.py:250-255`. The test passes only while
the probe uses `subprocess.run`, so a switch to `Popen.communicate` with the
same behaviour breaks it. Fix: a fake `t3` that sleeps, with the module's
timeout patched down. The contract leaves the timeout unspecified, so the
test may set it.

### Details (checked, no finding)

- **Hermes path with `PIPELINE_LAUNCHER` unset.** Unchanged:
  - the argv lists, `cwd` (pipeline: worktree or checkout; sweep: `None`), `env` (`env_clean()` / filtered `ENV`), `stdin` DEVNULL, `stdout`/`stderr` to the log, `start_new_session`, `close_fds`;
  - the PID returned and the `/proc/<pid>/cmdline` rule;
  - `live_authors` keys, which are ints for Hermes records;
  - exit codes and printed lines: probe sets stay empty, and the sweep's new `lines` expression reduces to the old one;
  - the review prompt: rendering the old and the new `review.md` with the same fields gives byte-identical text. No other prompt used `{hermes}`.

  One change: a probe result is cached for the rest of the process, so a
  Hermes session that ends mid-tick is noticed one tick later. This is
  conservative and accepted.
- **T3 `unknown`.** Non-dry runs with a fake `t3` give one `🛑 … stopped`,
  then silence, then `✅ … runs again` in both dispatchers, and exit 1 while
  down. Dry runs print the reason and exit 1. Triage short-circuits on the
  first `unknown`. Other PRs are still swept.
- **The remembered-dead cache.** One marker file per thread, written by
  atomic replace with the same content, so overlapping writers are harmless.
  Only `t3:` handles get markers, only when the probe says `dead`, and never
  in a dry run. Markers sit under the caller's own state dir, so a thread
  probed by both dispatchers is cached twice, which is harmless. Nothing
  prunes the markers; they grow like `dispatches.jsonl`. Archived threads
  still answer `thread show` and are judged by status. Deleted threads print
  `no longer available` and count as `dead`. I confirmed both messages,
  that one and "No running T3 Code server …", on the installed CLI.
- **Commit identity.** Written with `git config --local -- key value` (tried
  on git 2.54) to `CHECKOUT` (pipeline, per repository in fan-out) or to
  `checkout_of(repo)` (sweep), before the session, and never in a dry run,
  because `spawn` returns before `launch`. A failed write raises. The spawn is
  recorded as failed and retried. In the sweep it counts toward `MAX_FAILS`,
  and the error shows in the "runs failed" line. In triage it is silent; see M1.
- **Owner policy.** `docs/references/owner-policy.md` matches the text in
  `software-development` at `95b362d`. Three wordings changed: the header,
  "the stage skills" became "a skill", and "the human gates under Autonomy
  defaults" became "the human gates of the process in use (the board gates;
  in `software-development`, Autonomy defaults)". The meaning is the same.
- **Skill renderings.** `node tools/render-skills.mjs --check` is up to date,
  and `skill-render-spec.sh` gives 138/0. In all three harness renderings,
  every skill that cites `owner-policy.md` packages it. `gem-project.py` is
  fixed.
- **Tests run here:** `test_session_launcher`, `test_pipeline_runtime` and
  `test_pr_sweep_dispatch` (70 OK), `pipeline-dispatch-spec.sh` (88/0),
  `pr-sweep-dispatch-spec.sh` (84/0).

### Not checked

- No live T3 thread with a pending question or approval was observed (B1 is
  inferred from the v0.1.10 source). The same goes for the timing of restart
  continuation (m3) and whether `thread show` on a just-started thread can
  ever read `idle`. The source shows the start returns a `runId`, and a new
  run is `queued` or active.
- The host step: the systemd units, the session's environment and full access.
- `./tests/run-tests.sh fast`, `hermes-docs-spec.sh` and `repo-readiness-docs-spec.sh` were not rerun.
- Side effect: one read-only `t3 thread show` with a made-up `T3CODE_HOME`
  made the CLI create `/tmp/nonexistent-t3home/`. Scratch dirs for the
  mutation runs are under `/tmp/tmp.*`. My shell could not delete either.

## code pass 2

Range: `ece7e18..HEAD` (`7e0c6a3`; `git diff ece7e18..HEAD -- . ':!dist'`).
Fresh reviewer. No diagram model, so no model checks.

**Verdict: approved.** No blocker or major is open. 3 new minors (n1–n3);
m4 is partly open (minor); m3 is unchanged on purpose.

### Pass-1 findings

- **B1 — resolved.** `session_launcher.py:138-144` returns `asked` when
  `pendingRequestCount > 0` and the status is `preparing`, `queued`,
  `starting`, `running` or `waiting`. It returns `dead` for any finished
  status, pending or not. This matches the v0.1.10 CLI
  (`binCli-DdqfONEU.mjs` `waitForRun`: the run has not ended and
  `thread.pendingRequestCount > 0` means `needs_input`). `thread show` reads
  the same `t3_thread_read` thread object (`readLatestMessages`), and a
  read-only `thread show --json` on the running server prints
  `pendingRequestCount` at that level. The unit table covers every active
  status with a pending request, and every finished status with 0 and 1. The
  spec fixture's `asked` state is now `running` with a pending request. Undoing
  the fix makes `test_t3_status_table…` and 4 checks in each spec fail.
- **M1 — resolved.** `check` runs in each non-dry tick, after results are
  delivered and before any session, label or move (pipeline
  `pipeline-dispatch.py:1309-1311`; sweep `pr-sweep-dispatch.py:1339-1346`).
  Walked and re-run by hand with a fake `t3` (scratch dir, two
  repositories):
  - the pipeline (single repository, and each fan-out child): `code=1`,
    `job_down`, nothing labeled, moved or recorded; `job_up` on the next
    good tick that runs;
  - the PR sweep, all repositories down: one `🛑 PR sweep stopped`, exit 1,
    no start, no record, no label;
  - the PR sweep, one of two repositories not a project: that repository
    skipped, one error line, exit 1, the other repository swept, no stopped
    alert (the contract's "reports the repository");
  - quiet hours: `check` still runs, so an outage now raises the stopped
    alert in quiet hours too. A healthy quiet tick reports no recovery; the
    first non-quiet good tick does. I accept this; see Details.
- **M2 — resolved.** Each of the four mutations, in a scratch copy, fails
  the matching spec:
  - sweep `down` without `probe_errors`: 2 failures;
  - pipeline `if probe_errors and DRY`: 3 failures;
  - dry runs writing dead markers: 2 failures in each spec;
  - a wrong `title=` or `checkout=` in either `spawn`: 1 to 5 failures each,
    including the author identity in the right checkout.
- **m1 — resolved.** `pipeline_runtime.asked_notices` adds `asked:<handle>`
  to `reported` on the first non-dry tick. Dry runs print every time and
  store nothing. With `reported.add` removed, the "stays silent after the old
  dedupe TTL" case fails in both specs.
- **m2 — resolved.** `docs/t3/README.md` says a thread stopped in T3 is
  retried, and points to the pipeline's labels and commands; "Stop
  everything" no longer says to stop a thread in T3.
- **m3 — unchanged on purpose.** Not measured. I could not show it is worse
  than a rare duplicate session: the continued thread's result is still
  delivered (`deliver` does not depend on `alive`).
- **m4 — partly open (minor), see n1.** A notice before the JSON works
  (unit-tested, and the contract wording). A line after it still fails.
- **m5 — resolved.** Both timeout tests use a fake that prints, then hangs,
  with `T3_TIMEOUT` patched to 2 s. They no longer depend on
  `subprocess.run` being the call.

### New findings

**n1 — minor: a line after the start JSON still fails a start that made a thread.**
`scripts/session_launcher.py:108-116`. The loop decodes from a line that
starts with `{` through the end of stdout, so any trailing line breaks
`json.loads`. Checked: `'{"threadId":"a"}\nNotice: update\n'` raises
`T3 thread start failed`, and the dispatcher records a failed spawn and starts
another real thread on a later tick. This is m4's failure mode for a trailing
notice. v0.1.10 prints only the JSON, and the contract names only lines before
it, so it stays minor. Pretty-printed JSON, CRLF, blank trailing lines, and a
notice that contains `{` before the JSON all parse. Fix: use
`json.JSONDecoder().raw_decode(text_from_that_line)` and ignore what follows,
and add the trailing-notice case to the existing notice test.

**n2 — minor: `hygiene` now fails when T3 is down, though it starts no session.**
`scripts/pipeline-dispatch.py:1310-1311` call `check` for every job.
`job_hygiene` only reads the board and PRs. With `PIPELINE_LAUNCHER=t3` in the
loaded env and the server down, the weekly board check prints nothing but
`🛑 hygiene dispatch stopped …` and records `health/hygiene` as down. It is run
by hand (`docs/t3/README.md` Units), so the cost is a confusing message. Fix:
`if not DRY and job != "hygiene":`. Alternatively, say in the contract that
`check` guards only jobs that start sessions.

**n3 — minor (doc): "stopped alert, repeated hourly" is wrong for one PR sweep repository.**
`docs/t3/README.md:206-211`. In the PR sweep, a single repository whose
`check` fails, out of several, gets no stopped alert. It gets one plain error
line, repeated at most every `DEDUPE_TTL` (6 h), and the tick still says
`runs again` when the others work (re-run by hand, see M1). The pipeline
alerts per repository, because each fan-out child keeps its own health. Also,
ADR 0010:25 says "asks the server before it does anything else": it does so
after delivering finished results. Fix: one clause for the sweep's case, and
"before it starts or changes anything" in the ADR.

### Details (checked, no finding)

- **`asked:` keys in `reported`.** Both sets already hold synthetic keys
  (`err:`, `wt:`, `ci:`, `stuck:` …). No code in either dispatcher, or
  elsewhere under `scripts/`, iterates, prunes or compares `reported` as file
  names; result delivery only tests membership of `f.name`. If `reported.json`
  is corrupt, both fallbacks rebuild from result names, so a still-probed asked
  handle is announced once more. The other synthetic keys work the same way,
  and the sweep's docstring says so.
- **`check` cost.** `t3 thread list` pages through the project's threads (100
  per MCP call) and prints about 1 KB per thread. On the running server, a
  6-thread project took about 0.6 s. A missing project exits 1 with
  `No T3 Code project matches …` in about 0.6 s. `thread start` resolves its
  project with the same `resolveProject`, so `check` and `launch` agree on
  what counts as a project. Its failures (non-zero exit, timeout, missing
  binary) all raise `RuntimeError` naming T3, and all are unit-tested. `check`
  uses `{**os.environ, **ENV}`. `launch` uses `child_env`, which is built
  from the same `os.environ`, so both reach the same `T3CODE_HOME`.
- **Hermes path with `PIPELINE_LAUNCHER` unset.** `launch`'s Hermes branch,
  `spawn` argv, cwd, env and prompt templates are not in this range. `check`
  returns early. `asked_lines` stays empty, so `notices == []`. The sweep's new
  `lines` expression reduces to the old one in every branch (down, quiet,
  errors). The new loop condition `not config_error` with an inner
  `if not quiet` skips the same work as the old `if not quiet` loop. Exit
  codes do not change.
- **Quiet hours.** Both dispatchers now call `check` in quiet hours. An
  outage at night therefore alerts (hourly), where the PR sweep was silent
  before. Quiet hours are defined as "start no session"
  (`delivery-pipeline.md` §Quiet hours), not silence, so I accept this.
- **Tests.** The new cases assert outcomes the contract names: exit code,
  alert text, CLI argv for start and list, ledger and state snapshots, gh
  mutations, the git config of the right checkout. None pins internals except
  the patched `T3_TIMEOUT` name, which the contract leaves to the test.
  Further mutations each fail a spec:
  - B1 reverted;
  - `check` removed from either dispatcher;
  - `check` after the work (pipeline and sweep);
  - `check` in dry runs (sweep);
  - `check` before delivery (pipeline);
  - whole-stdout parsing in `launch`.

  The two specs and the unit files passed in 3 runs, 2 of them in parallel
  with each other. `tick-at` patches `time.time` only inside the test
  process. Still untested: one of several PR sweep repositories failing
  `check` (also untested for other per-repository errors before this
  change; verified by hand above).
- **Runs here at HEAD:** `pipeline-dispatch-spec.sh` 128/0,
  `pr-sweep-dispatch-spec.sh` 124/0, `hermes-docs-spec.sh` 66/0, the three
  unit files (76 OK), `./tests/run-tests.sh fast` passed.

### Not checked

- The host step (units, session environment, full access) and live T3
  threads: I started no thread and watched no real pending request. B1 is
  confirmed from the CLI source plus the field on a real `thread show`.
- Whether `t3 serve … <board>/repos` turns the `repos` directory into a
  project. If it does, a clone never added would resolve to it through
  `resolveProject`'s "path inside a project" rule, and both `check` and
  `start` would accept it. This is outside the range (setup doc, step 6).
- `skill-render-spec.sh` was not run on its own (it is part of the fast run).
- Scratch copies for the mutations are under `/tmp/tmp.*`, with
  `/tmp/mut_run.sh`. Nothing was written to the repository except this
  ledger.

### After pass 2 (orchestrator)

The three new minors were fixed after the verdict; no further review pass was
run for them.

- **n1 — fixed.** `launch` decodes the JSON object and ignores lines after it
  (`scripts/session_launcher.py`); `test_t3_start_accepts_a_notice_after_the_json`
  covers it, and the contract says "before or after".
- **n2 — fixed.** The `hygiene` job does not call `check`
  (`scripts/pipeline-dispatch.py`); the contract says so.
- **n3 — fixed.** `docs/t3/README.md` describes the partly failing PR sweep;
  ADR 0010 says "before it starts or changes anything".
- **m3 — not changed.** Not measured; the cost is a rare duplicate session.
- **Still untested:** one of several PR sweep repositories failing `check`
  (checked by hand in pass 2).
