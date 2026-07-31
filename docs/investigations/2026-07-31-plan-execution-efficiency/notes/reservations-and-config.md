# Pi Messenger reservations and Crew configuration

Source inspected: `/tmp/pi-github-repos/nicobailon/pi-messenger` (package version `0.15.0`).

## A. File reservations

### 1. Enforcement: blocking, but only for covered tool calls

Reservations are **enforced rather than merely advisory** for structured `edit` and `write` calls. The enforcement hook in `index.ts:1177-1199`:

- ignores every tool except `edit` and `write` (`index.ts:1178`);
- extracts `event.input.path` (`index.ts:1180-1182`);
- asks `store.getConflictsWithOtherAgents(...)` for conflicts (`index.ts:1184`); and
- returns `{ block: true, reason: ... }` on the first conflict (`index.ts:1187-1198`).

`store.ts:616-639` scans other live registrations and applies `pathMatchesReservation` to each reservation.

**Important limitation (severity: high):** this does **not** enforce reservations against `bash`. A command such as `sed -i file`, `perl -pi`, `python -c ...`, `cat > file`, or any shell redirection runs through the `bash` tool and is not examined by the reservation hook. The earlier activity hook recognizes bash only for status tracking (`index.ts:768-775`); it does not block it. Reservations therefore protect only structured `edit`/`write`, not arbitrary filesystem writes performed by bash or by another uninstrumented process.

### 2. Message received by a blocked agent

The extension returns the framework block reason assembled at `index.ts:1193-1198`:

```text
<requested path>
Reserved by: <agent> (in <folder> [on <git branch>])
Reason: "<reservation reason>"       # only when a reason was supplied

Coordinate via pi_messenger({ action: "send", to: "<agent>", message: "..." })
```

The `Reason:` line is conditional. The actual tool-call framework is responsible for surfacing this returned `reason` to the agent; the extension supplies no separate error object or custom message beyond that string.

### 3. Cross-process behavior, shared state, and races

Reservations are shared across worker processes through registration JSON files:

- default shared base: `~/.pi/agent/messenger`;
- override: `PI_MESSENGER_DIR`; and
- registration directory: `<base>/registry` (`index.ts:125-130`).

Each process writes its own `<base>/registry/<agent-name>.json`; `executeReserve` updates `state.reservations` and persists it via `store.updateRegistration` (`handlers.ts:496-522`; `store.ts:419-444`). Other processes read these registration files in `getActiveAgents` (`store.ts:167-240`) and verify the peer PID is alive. Thus, with the same `PI_MESSENGER_DIR`, enforcement works across separate processes in normal operation.

There is no lock or atomic replace around reservation/registration updates. The `swarm.lock` in `store.ts:101-157` protects claims/completions only, not registry writes. `updateRegistration` and `flushActivityToRegistry` both do read-modify-`writeFileSync` (`store.ts:419-444`, `446-465`). Consequences:

- **Lost-update window (severity: medium):** a periodic activity flush can read an old registration while a reservation update is writing, then write back a version without the newly added reservation (or vice versa).
- **Partial-read window (severity: medium):** direct `writeFileSync` truncates/re-writes the JSON in place. A peer reading during that interval can get malformed JSON; `getActiveAgents` ignores malformed registrations (`store.ts:213-215`), temporarily hiding the reservation.
- **Staleness window (severity: low/medium):** the agent list is cached per process for 1,000 ms (`store.ts:41-45`, `167-184`), so a newly added/released reservation may not be observed immediately.

There is no reservation-specific inter-process atomicity. A different `PI_MESSENGER_DIR` means a different mesh/state store.

### 4. Reservation granularity and sentinel paths

`executeReserve` stores each supplied string unchanged (`handlers.ts:496-522`). Matching is implemented by `lib.ts:325-330`:

- pattern ending in `/`: lexical directory-prefix match (`filePath.startsWith(pattern)`), including the directory itself;
- any other pattern: exact string equality only;
- no glob expansion, path normalization, canonicalization, or wildcard semantics.

Therefore reservations are exact files or slash-terminated directory prefixes—not general globs. Relative and absolute spellings do not automatically match each other.

An arbitrary sentinel such as `.locks/e2e` **can be stored as a reservation**, but it is not a general mutex. It only blocks another agent's structured `edit`/`write` call whose `path` is exactly `.locks/e2e` (or paths under it if the reservation is `.locks/e2e/`). It does not block unrelated writes, bash commands, or an agent that merely reserves the same sentinel. It can serve as a voluntary mutex only if participants coordinate around attempting a covered operation on that exact sentinel and account for the registry race windows above.

## B. Crew configuration

### 5. Full Crew schema and defaults

The Crew loader is `crew/utils/config.ts`. The `CrewConfig` interface is at `crew/utils/config.ts:34-75`; defaults are at `crew/utils/config.ts:77-97`. User configuration is nested under `crew`.

| Exact key path | Type / allowed shape | Default |
|---|---|---|
| `crew.models.planner` | optional string | unset (model fallback chain applies) |
| `crew.models.worker` | optional string | unset |
| `crew.models.reviewer` | optional string | unset |
| `crew.models.analyst` | optional string | unset |
| `crew.thinking.planner` | optional string | unset (agent/frontmatter fallback) |
| `crew.thinking.worker` | optional string | unset |
| `crew.thinking.reviewer` | optional string | unset |
| `crew.thinking.analyst` | optional string | unset |
| `crew.concurrency.workers` | number | `2` |
| `crew.concurrency.max` | number | `10` (runtime also clamps to hard max 10) |
| `crew.truncation.planners` | `{ bytes?: number, lines?: number }` | `{ bytes: 204800, lines: 5000 }` |
| `crew.truncation.workers` | same | `{ bytes: 204800, lines: 5000 }` |
| `crew.truncation.reviewers` | same | `{ bytes: 102400, lines: 2000 }` |
| `crew.truncation.analysts` | same | `{ bytes: 102400, lines: 2000 }` |
| `crew.artifacts.enabled` | boolean | `true` |
| `crew.artifacts.cleanupDays` | number | `7` |
| `crew.memory.enabled` | boolean | `false` |
| `crew.planSync.enabled` | boolean | `false` |
| `crew.review.enabled` | boolean | `true` |
| `crew.review.maxIterations` | number | `3` |
| `crew.planning.maxPasses` | number | `1` |
| `crew.work.maxAttemptsPerTask` | number | `5` |
| `crew.work.maxWaves` | number | `50` |
| `crew.work.stopOnBlock` | boolean | `false` |
| `crew.work.env` | optional `Record<string,string>` | unset (no extra environment entries) |
| `crew.work.shutdownGracePeriodMs` | optional number | `30000` |
| `crew.dependencies` | `"advisory"` or `"strict"` | `"advisory"` |
| `crew.coordination` | `"none"`, `"minimal"`, `"moderate"`, or `"chatty"` | `"chatty"` |
| `crew.messageBudgets.none` | number | `0` |
| `crew.messageBudgets.minimal` | number | `2` |
| `crew.messageBudgets.moderate` | number | `5` |
| `crew.messageBudgets.chatty` | number | `10` |

`models.*` and `thinking.*` are optional in the source schema and are absent from `DEFAULT_CONFIG`; the runtime resolves model/thinking fallbacks elsewhere. The loader deep-merges nested objects (`crew/utils/config.ts:107-126`).

### 6. `dependencies`: advisory versus strict

The scheduling branch is explicit in `crew/store.ts:479-489`:

- `advisory` (`{ advisory: true }`): returns every `todo` non-milestone task, even if dependencies are not done (`store.ts:480-482`);
- `strict` (`{ advisory: false }`): builds the done-task set and requires every `depends_on` ID to be done (`store.ts:483-488`).

Callers pass the mode from config, for example normal work scheduling at `crew/handlers/work.ts:68-70` and wave continuation at `crew/handlers/work.ts:320`. Manual `task.start` also branches at `crew/task-actions.ts:44-55`: strict rejects unmet dependencies with `error: "unmet_dependencies"`; advisory allows the start. Strict therefore gates both automatic ready-task scheduling and manual starts, while advisory permits parallel work ahead of dependencies (with the coordination prompts intended to manage that state).

### 7. Config precedence and exact paths

There are two related config loaders; do not conflate them:

**Crew config (`crew/utils/config.ts:129-145`):**

1. built-in defaults;
2. user file: `~/.pi/agent/pi-messenger.json`, using its `crew` object (`crew/utils/config.ts:133-135`);
3. project file: `<cwd>/.pi/messenger/crew/config.json` (`getCrewDir` is `crew/store.ts:24-26`; loader reads `config.json` at `crew/utils/config.ts:137-141`);
4. in-memory coordination override, if set (`crew/utils/config.ts:142-144`).

This Crew loader **does not read** `~/.pi/agent/settings.json`.

**Messenger/general config (`config.ts:128-208`):**

1. defaults;
2. `~/.pi/agent/settings.json` → top-level `"messenger"` object;
3. `~/.pi/agent/pi-messenger.json`;
4. project `<cwd>/.pi/pi-messenger.json`.

Because the merge is in that order (`config.ts:142-147`), effective precedence is highest to lowest: project `./.pi/pi-messenger.json` > user extension file `~/.pi/agent/pi-messenger.json` > settings `~/.pi/agent/settings.json` `messenger` > defaults. This second loader is what the tests cover (`tests/config.test.ts:35-54`).

### 8. Ready-to-paste requested config

Place this in either `~/.pi/agent/pi-messenger.json` (user-wide) or `<project>/.pi/messenger/crew/config.json` (project-only). For the user-wide file, the `crew` wrapper is required:

```json
{
  "crew": {
    "concurrency": {
      "workers": 4
    },
    "dependencies": "strict",
    "review": {
      "enabled": true,
      "maxIterations": 3
    },
    "work": {
      "maxAttemptsPerTask": 2
    }
  }
}
```

## Package/version constraints

`package.json:2-3` reports `pi-messenger` version `0.15.0`. There is no `engines` field. All peer dependencies are unconstrained (`"*"`): `@earendil-works/pi-ai`, `@earendil-works/pi-agent-core`, `@earendil-works/pi-coding-agent`, `@earendil-works/pi-tui`, and `typebox` (`package.json:43-48`). Thus the package metadata supplies no peer-version pin for selecting a compatible release; the only listed development dependency is `vitest: ^2.1.8` (`package.json:50-51`).
