# Crew execution model

**Source inspected:** `/tmp/pi-github-repos/nicobailon/pi-messenger` (TypeScript extension). Line citations below are relative to that source root.

## Summary: relative to driving `pi-subagents` ourselves

| Area | What Crew gives us | What we lose / must not assume |
|---|---|---|
| Launch | Native `pi` child processes in JSON mode, agent-defined system prompt/model/tools, concurrency, cancellation, and a warm-lobby option. | Crew is not a `pi-subagents` launcher (`crew/handlers/plan.ts:599`). Its normal work workers explicitly use `--no-session`; there is no worker-session resume API. |
| Retry | Prior task spec, last review feedback, and up to 30 progress-log lines are injected into the next prompt (`crew/prompt.ts:62-87`). | A `NEEDS_WORK` retry is a **fresh process**, not a resumed worker/session. Any in-memory context is lost. **Critical for remediation design.** |
| Edit control | Workers load the pi-messenger extension, whose `tool_call` hook blocks edits that conflict with another worker's reservation (`crew/agents.ts:244-245`; `index.ts:1177-1199`). | Reservation is prompted, not required before a worker's own edit (`crew/agents/crew-worker.md:50-60`). The gate protects conflicts only; it is not an edit-gated watchdog equivalent. |
| Visibility | In-memory live tool/token telemetry; optional JSONL/input/output/metadata debug artifacts; task state/progress; and an append-only activity feed. | No Crew `status.json`; no persistent per-task tool-count record; no stored monetary cost; lobby executions do not receive the standard artifacts. |
| Completion observation | A durable `task.done` feed record and task JSON state can be file-watched. | No documented external completion hook/callback. Internal live-worker listeners are process-local, and `agent_end` intentionally ignores Crew workers. |
| Task packet | `task.create({ title, content })` stores `content` as the task spec and includes it in the worker prompt. | It is task-spec content embedded in Crew's generated prompt, not a replacement for the fixed system prompt or an arbitrary raw `pi -p` body. |

## 1. Actual worker launch — confirmed `pi --mode json` subprocess

**Confirmed, with an important qualifier:** the standard `work` path builds `AgentTask`s and calls `spawnAgents` (`crew/handlers/work.ts:172-204`). `runAgent` executes Node `child_process.spawn`, not `pi-subagents`:

```text
pi --mode json --no-session -p [model/provider flags] [thinking] [tools/extensions]
   --extension <pi-messenger extension dir>
   --append-system-prompt <temporary 0600 .md file>
   <generated task prompt>
```

* Base flags are exactly `--mode json --no-session -p` (`crew/agents.ts:211-215`); command is `pi` except `pi.cmd` on Windows (`crew/agents.ts:65-67`). Therefore this **is** a Pi JSON-mode subprocess, and it explicitly disables session persistence/resume.
* The resolved model becomes `--model`, or `--provider <provider> --model <rest>` for `provider/model` strings (`crew/agents.ts:69-75`, `214-215`).
* Frontmatter tools are split into recognized built-ins passed as `--tools a,b` and path-like entries passed as `--extension`; Crew always adds its own extension so the worker can call `pi_messenger` (`crew/agents.ts:225-245`). The model/tool behaviors are covered by `tests/crew/model-override.test.ts:83-152`.
* The Markdown body of `crew-worker.md` becomes `agentConfig.systemPrompt` (`crew/utils/discover.ts:89-110`), is copied to a private temporary file, and supplied with `--append-system-prompt` (`crew/agents.ts:247-255`). The generated task packet is the final positional `-p` prompt argument (`crew/agents.ts:255`).
* The process runs in project `cwd`, with piped stdout/stderr. Worker-role processes receive `PI_CREW_WORKER=1` and a generated `PI_AGENT_NAME`; `config.work.env` is merged in (`crew/agents.ts:257-271`). Stdout JSONL is parsed as Pi events (`crew/agents.ts:280-315`).

There is a second, distinct convenience path in `crew/spawn.ts`: it first assigns an already-running lobby worker, otherwise calls `spawnWorkerForTask` (`crew/spawn.ts:45-80`). That function creates a lobby `pi` process using the **same** `--mode json --no-session -p` base flags (`crew/lobby.ts:55-117`) and sends an assignment via a JSON inbox message (`crew/lobby.ts:223-267`). A lobby worker is warm process reuse, not Pi-session resume.

## 2. Model override precedence

The actual precedence is:

```text
task.model
  > params.model (the `work`-wave override)
  > active Team role model
  > crew config models.worker
  > invoking session model
  > crew-worker frontmatter model
```

`work.ts` resolves the role and passes the six values in that order (`crew/handlers/work.ts:174-194`); `resolveModel` returns the first defined value with `??` (`crew/agents.ts:54-63`). The requested chain is therefore **not quite correct**: **role beats config**, and the invoking session model sits between config and agent frontmatter. The tests assert the complete order (`tests/crew/model-override.test.ts:70-80`).

Caveat: although `Task` has an optional `model` field (`crew/types.ts:50-73`), the public `task.create` parameters do not expose a model field: its schema exposes `content` but not task model (`index.ts:449-473`), and the handler passes only role/risk/approval metadata to `createTask` (`crew/handlers/task.ts:108-119`). Thus ordinary `task.create` cannot set the highest-priority value without another writer changing the task JSON.

## 3. `NEEDS_WORK` retry lifecycle — fresh worker, never resumed

**Answer: fresh process.** This is decisive.

1. `spawnAgents` does not yield a worker result until its child `close` handler executes (`crew/agents.ts:322-371`); `work` awaits all those results before reviewing (`crew/handlers/work.ts:197-204`, `259-269`). The original worker has already exited when the review decision is made.
2. On `NEEDS_WORK`, Crew calls `store.resetTask`, emits `task.review`, removes the task from `succeeded`, and records it as failed (`crew/handlers/work.ts:280-286`). `resetTask` returns the task to `todo`, clears start/completion/assignee/summary/evidence, and deliberately retains `attempt_count` (`crew/store.ts:429-472`).
3. Autonomous continuation sends the parent session a steer message to call `work` for the next wave (`index.ts:1124-1133`). That next `work` builds a new `AgentTask` and calls `spawnAgents` again (`crew/handlers/work.ts:172-204`), whose child command includes `--no-session` (`crew/agents.ts:211-215`). There is no session ID, resume flag, or existing child process passed through this chain.

The replacement packet is intentionally re-anchored rather than resumed: it includes review feedback (`crew/prompt.ts:62-75`), retained progress log (`crew/prompt.ts:77-87`), and displays the retry attempt number (`crew/prompt.ts:44-55`). This is usable remediation context, but not worker/session continuity.

## 4. Telemetry and artifacts

### Persistent task-level files

All task state is under `<project>/.pi/messenger/crew/`:

| Path | Format and fields | Limits |
|---|---|---|
| `tasks/<task-id>.json` | JSON task record: status, `model` if pre-populated, dependencies, `created_at`, `updated_at`, `started_at`, `completed_at`, `assigned_to`, `summary`, evidence, `blocked_reason`, attempt/review counts, and last review (`crew/types.ts:50-81`; `crew/store.ts:174-214`, `359-415`). | No process duration, cost, tokens, tool count, exit status, or artifact links. Reset clears `started_at`/`completed_at`, so it is not a per-attempt history (`crew/store.ts:429-447`). |
| `tasks/<task-id>.md` | Markdown task specification. `content` is written below the `# title` heading (`crew/store.ts:202-206`). | Durable across reset. |
| `tasks/<task-id>.progress.md` | Append-only Markdown lines: `[ISO timestamp] (agent) message` (`crew/store.ts:289-299`). | Worker-authored/system progress only; no automatic tool telemetry. |
| `blocks/<task-id>.md` | Markdown block title, reason, and timestamp when blocked (`crew/store.ts:402-415`). | Only for blocked tasks. |
| `../feed.jsonl` (that is, `<project>/.pi/messenger/feed.jsonl`) | Append-only JSONL `{ ts, agent, type, target?, preview? }` (`feed.ts:4-5`, `41-51`, `78-90`). `task.done` is emitted only after `completeTask` succeeds (`crew/handlers/task.ts:485-510`). | It records logical completion/activity, not process exit, cost, or usage. |

### Standard direct-worker debug artifacts

Artifacts are enabled by default for seven-day cleanup (`crew/utils/config.ts:77-97`) and are written under:

```text
<project>/.pi/messenger/crew/artifacts/
  <runId>_crew-worker_<index>_input.md
  <runId>_crew-worker_<index>_output.md
  <runId>_crew-worker_<index>.jsonl
  <runId>_crew-worker_<index>_meta.json
```

The filename construction is exact in `crew/utils/artifacts.ts:17-32`; `<runId>` is a random eight-character UUID prefix created once per `spawnAgents` call (`crew/agents.ts:136-149`). These are **per worker run**, not task-ID-named. The input artifact contains the generated task packet (`crew/agents.ts:199-208`), so it can be correlated to a task by its embedded `Task ID`; the metadata itself has no `taskId`.

* `*_input.md`: `# Task for <agent>` plus generated prompt.
* `*.jsonl`: compacted Pi JSON-mode events. It preserves raw tool/message event content except it removes streaming `message_update.message` and nested `partial` payloads (`crew/agents.ts:286-315`; `crew/utils/progress.ts:127-141`). This is sufficient to derive tool-start/end counts and inspect provider usage events after the fact.
* `*_output.md`: the latest assistant text captured from `message_end` events (`crew/agents.ts:289-291`, `335-348`).
* `*_meta.json`: exactly `{ runId, agent, index, exitCode, durationMs, tokens, truncated, error }` (`crew/agents.ts:335-347`). `tokens` is the sum of each `message_end` input and output usage, while cache-read/write are not included in that total (`crew/utils/progress.ts:88-95`).

Live, process-local telemetry is a map keyed by `cwd::taskId`, updated on each parsed JSONL event and removed on child close (`crew/live-progress.ts:12-30`; `crew/agents.ts:302-325`). Available fields are agent/name/task ID/start time plus `status`, current tool/argument preview, recent tool entries with start/end milliseconds, `toolCallCount`, tokens, `durationMs`, and error (`crew/live-progress.ts:3-10`; `crew/utils/progress.ts:7-25`, `62-97`). It is not written to disk. `toolCallCount` is also absent from `*_meta.json`; only the JSONL can reconstruct it after exit.

**Lobby limitation:** `spawnLobbyWorker` parses JSONL into live progress but does not invoke the artifact helpers or write close metadata (`crew/lobby.ts:139-202`). Do not assume the four artifact files exist for lobby-assigned tasks.

### Can it compute wall-clock and cost?

* **Wall-clock:** **partially yes.** Direct-worker `*_meta.json.durationMs` is an exact child-process elapsed time. Current task JSON can also give `completed_at - started_at` for the final lifecycle. Neither is a durable, task-keyed per-attempt ledger: metadata needs input-prompt/index correlation, and a reset erases task timestamps.
* **Cost:** **no.** Crew writes no cost field, price table, resolved-model value, or cache-token totals in metadata. JSONL may contain cache usage (`crew/utils/progress.ts:33-39`), but monetary cost requires external provider/model pricing and model attribution. This is a **major telemetry gap** if cost is an acceptance metric.
* **Exit status:** available for standard direct worker runs in `*_meta.json.exitCode`; absent from task JSON and not persisted for lobby runs. **Tool counts:** available live and derivable from JSONL, but not persisted in task JSON or metadata.
* **No `status.json`:** the only artifact paths Crew constructs are the four above (`crew/utils/artifacts.ts:27-32`). Its live state is an in-memory map, not a status file (`crew/live-progress.ts:12-13`).

## 5. Supplying a self-sufficient task packet

**Yes, through `task.create`'s `content`.** The tool schema declares `content` as task-spec content (`index.ts:460-461`); `taskCreate` passes it directly to `store.createTask` (`crew/handlers/task.ts:85-119`), which writes it to `tasks/<task-id>.md` (`crew/store.ts:202-206`). `buildWorkerPrompt` then embeds the complete spec under `## Task Specification` (`crew/prompt.ts:108-114`).

Therefore `content` can be a self-sufficient implementation/remediation packet. It will still be wrapped by Crew with its fixed assignment/mission, role, review, prior-progress, dependency, coordination, plan, and skills sections (`crew/prompt.ts:44-136`) and the fixed `crew-worker` system prompt. It cannot replace those layers or directly choose arbitrary Pi flags.

## 6. Completion hook/event

**There is no public completion-hook interface in the inspected Crew code.** The usable observation points are:

1. **Durable, external:** watch or poll `<project>/.pi/messenger/feed.jsonl` for `{ type: "task.done", target: "<task-id>" }`. The event shape/path is defined in `feed.ts:41-51`, and `task.done` is logged after state completion in `crew/handlers/task.ts:505-510`.
2. **Durable state:** watch `tasks/<task-id>.json` for `status: "done"` and `completed_at`; `completeTask` performs that write (`crew/store.ts:372-399`).
3. **Internal only:** `onLiveWorkersChanged` fires on every update and removal, not a completion-only event (`crew/live-progress.ts:19-29`, `51-57`). `spawnAgents` accepts an optional `onProgress(results)` callback after each child result (`crew/agents.ts:43-47`, `162-167`), but `work.ts` does not supply one (`crew/handlers/work.ts:197-204`).

Do not use Pi's `agent_end` as the worker-completion hook: the extension explicitly returns early for `PI_CREW_WORKER`/lobby processes (`index.ts:998-1001`). Also distinguish a worker's `task.done` from final acceptance: automatic review can subsequently emit `task.review` and reset the task on `NEEDS_WORK` (`crew/handlers/work.ts:259-286`).

## Review findings and residual risks

* **Critical design finding:** build remediation around a fresh, self-sufficient retry packet. Crew cannot resume the failed worker's Pi session.
* **Major telemetry finding:** standard artifacts provide direct-run duration and exit code but no canonical task-attempt key, persisted tool count, resolved model, or monetary cost. Lobby work has less persistence still.
* **Major control finding:** the reservation hook prevents conflicting edits but does not enforce “must reserve before any edit.”
* **Operational risk:** treat `task.done` as worker-declared completion; wait for `task.review`/final task state when auto-review is enabled.
