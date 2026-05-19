# Approach

**Created:** 2026-05-19
**Plan:** ./brief.md
**Based on:** ./findings/

## Solution Model

### Components
- **Pi launch wrapper** — replaces the upstream `pi` binary on the user PATH with a repo-owned wrapper that detects interactive session launches, runs a best-effort stale-status check, writes an atomically-created per-launch status snapshot under a dedicated startup-status directory, exports the snapshot path to the child Pi process, and then `exec`s the real upstream Pi binary. When the wrapper intentionally skips checks, it clears the snapshot environment variable so later Pi code cannot consume stale state.
- **Managed package install-state manifest** — activation-time artifact written under `~/.pi/agent/` that records the install facts needed for later comparison: source type/spec, package IDs, package name, dedupe key/materialized source identity, npm installed version, and resolved git commit/ref classification captured at install time.
- **Shared package-status engine** — one machine-readable checker used by both startup warning flow and the manual `check-updates` command. It reads the install-state manifest, performs npm/git remote comparisons, classifies each managed source as `current`, `stale`, or `unknown`, and emits structured JSON plus a concise text summary.
- **Startup notifier extension** — a small repo-owned Pi extension installed directly into `~/.pi/agent/extensions/` that reads only the wrapper-exported per-launch snapshot on `session_start`, ignores missing/stale/unreferenced files, shows an immediate in-TUI warning via `ctx.ui.notify(...)`, and sets a session footer/status summary while stale or unknown managed sources exist.
- **Manual operator command** — the existing `check-updates` surface, corrected so it is installable/on-PATH for repo users and backed by the same status engine for display/reporting. In this work, `check-updates --dry-run` (or default invocation) is the supported inspection path; `--update` remains a legacy npm-declaration rewrite convenience only and is never implied for git or `unknown` results.
- **Test coverage layers** — offline shell specs for classification logic and manifest/schema behavior, plus narrow integration/smoke coverage for wrapper + Pi startup visibility.

### How They Fit Together
1. **Home Manager activation** continues to install managed package sources and compile facade packages, but also writes a new install-state manifest after installation completes.
2. The install-state manifest becomes the authoritative local input for stale checking. It records the installed state that runtime facade metadata does not preserve today.
3. The repo-owned `pi` wrapper runs only for interactive Pi session launches: plain `pi` with no output-oriented subcommand, plus any explicitly documented interactive launch form. It bypasses checks for help/version/list and any other invocation pattern treated as noninteractive or script-facing; unknown patterns fail open to “skip the warning” rather than polluting CLI output.
4. Before invoking the real Pi binary, the wrapper calls the shared status engine in `startup` mode with strict time and concurrency limits. The engine dedupes checks by underlying managed source, performs npm/git remote comparisons, and writes an atomically-created per-launch snapshot file such as `~/.pi/agent/startup-status/<launch-id>.json`.
5. The wrapper exports the exact snapshot path (or clears it when skipping checks) into the launched Pi process and then `exec`s the real Pi binary unchanged.
6. On Pi `session_start`, the startup notifier extension reads only the wrapper-exported snapshot path, validates that the referenced file exists and is fresh enough to belong to this launch, renders stale and unknown sources distinctly, and then marks the snapshot consumed (delete or consume-once tombstone) so later sessions cannot replay it.
7. The manual `check-updates` command calls the same status engine in `manual` mode to show the same stale/unknown classification with fuller detail. Its supported role in this work is inspection/status only; startup warnings point users to `check-updates --dry-run` for details and to the existing repo/Home Manager apply flow for actually picking up updated declarations or package revisions.

This keeps the detection logic repo-owned, non-blocking, and shared, while also making the warning visible inside Pi rather than only as pre-launch shell output.

## Key Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| Where startup detection begins | Pure Pi extension hook, shell wrapper only, wrapper + Pi notifier | Wrapper + Pi notifier | The repo does not currently own startup launch, so a wrapper is the most reliable way to trigger a check. A Pi notifier is still needed because pre-launch shell output can be easy to miss once the TUI starts. | Adds one repo-owned wrapper package and one tiny direct extension, but gives dependable launch-time detection plus visible in-TUI warning. | Pi later exposes a documented first-class startup-warning API that makes the extra notifier unnecessary. |
| Which installs are in v1 scope | All repo-installed resources, managed `piPackages` only | Managed `piPackages` only | The stale-warning regression comes from the managed facade wrapper path, and only managed packages already have a declaration/update-check model. Direct cloned installs like `agent-kit` and `visual-explainer` use different metadata and would expand scope materially. The human explicitly approved this narrowing during design. | Startup warnings cover the managed package set only; direct repo-installed resources remain an explicit follow-up and must be described as such in user-facing wording. | Users need repo-wide source drift detection beyond managed packages, or direct installs become part of the managed package model. |
| What local state drives comparisons | Facade package metadata only, declarations only, activation-time install-state manifest | Activation-time install-state manifest | Existing facade metadata preserves `source.spec` but not npm installed version or resolved git commit. Git branch/default-branch freshness cannot be determined reliably without persisting install-time resolution. | Activation must write a new manifest/schema, and planning must add tests for it. In return, startup checks use stable local facts rather than trying to reverse-engineer synthetic facades. | Upstream Pi or the wrapper compiler later preserves equivalent installed-version/resolved-ref metadata directly. |
| How startup state is correlated to one Pi launch | Single fixed file, timestamp-only latest file, per-launch file passed through environment | Per-launch file passed through environment | A single shared file can race across concurrent launches and can be replayed accidentally. Passing an exact snapshot path from wrapper to child Pi process creates an unambiguous contract. | The wrapper and notifier need a small launch-ID/snapshot lifecycle contract, including consume-once cleanup. | Pi later exposes a safer native session metadata channel for startup extensions. |
| How shared logic is structured | Keep all logic in `check-updates.sh`, add a machine-readable shared checker with thin frontends | Add a machine-readable shared checker with thin frontends | Startup flow needs structured results, time-budgeted mode, and deduped source-level classification. Extending the existing bash-only script would keep parsing/formatting tightly coupled and make testing harder. | One new shared checker module is introduced, and `check-updates` becomes a frontend rather than the sole implementation. | The existing shell script is refactored into a robust machine-readable core without needing a separate module. |
| How git staleness is defined | Manual-update only, branch-sensitive custom rules per spec, fixed policy by spec class | Fixed policy by spec class: no-ref → default branch HEAD; branch ref → that branch HEAD; pinned commit/tag → default branch HEAD | This matches the accepted product decision that pinned refs still count as stale when upstream advances, while keeping the rule explainable and testable. | Pinned refs off the default branch may warn even when intentionally pinned for stability. That tradeoff is accepted to maximize visibility. | The product decision on pinned refs changes, or the repo begins declaring explicit tracking refs distinct from install pins. |
| How startup latency is controlled | Fully synchronous unbounded check, cached historical results, strict time-budgeted fresh check | Strict time-budgeted fresh check | The brief requires startup alerts, non-blocking behavior, and distinct unknown results. A fresh check with hard deadlines and parallel source probing preserves those semantics without introducing a broader caching/history feature. | Slow/offline remotes become `unknown` for that launch instead of delaying Pi. Planning must define concrete deadlines/concurrency. | Measured startup cost is too high even with deadlines, at which point a bounded cache may become necessary. |
| Which Pi invocations get startup warnings | All invocations, runtime detection inside Pi only, interactive-launch-only wrapper rule | Interactive-launch-only wrapper rule | Help/list/version and other output-oriented commands must stay script-clean. Failing open to “skip warning” on unknown argv patterns is safer than polluting noninteractive output. | Some niche interactive launch forms may temporarily miss the warning until explicitly mapped. | Users rely on alternate interactive invocation patterns that the wrapper initially skips. |
| How user-facing results are grouped | Per facade package ID, per underlying source with package fan-out | Per underlying source with package fan-out | Shared git sources such as `pi-ext-leader-key` and `pi-ext-review` intentionally map multiple package IDs to one source. Checking and summarizing per source avoids duplicate remote work and duplicate warnings. | The checker and notifier must map one source result back to one or more package IDs for actionable messaging. | Managed packages stop sharing materialized sources, or users need strictly per-package reporting despite duplicate source checks. |
| What manual workflow contract startup warnings rely on | Preserve current ambiguous helper behavior, inspection-only supported path with explicit npm-only legacy update mode, redesign update workflow | Inspection-only supported path with explicit npm-only legacy update mode | The plan is about notification, not update orchestration. To avoid contradictory guidance, startup messaging must promise only inspection plus the existing repo/Home Manager apply path. | `check-updates --dry-run` becomes the supported diagnostic command; `--update` stays available only as a legacy npm declaration rewrite convenience and must never be implied for git or `unknown` results. Dry-run/status mode should stay informational, with non-zero exits reserved for actual tool/config failures rather than stale findings. | The repo later chooses to redesign or broaden the update workflow itself. |

## What Changes vs What Stays
- **Changes:**
  - `home.packages` stops exposing the upstream `pi` binary directly and instead exposes a wrapped `pi` launcher that delegates to the real binary.
  - Home Manager activation writes a managed-package install-state manifest alongside the existing declarations/report artifacts.
  - A new shared status engine is added and becomes the single source of stale/unknown/current classification.
  - A small repo-owned startup notifier extension is installed directly under `~/.pi/agent/extensions/` and consumes a per-launch snapshot passed from the wrapper.
  - The packaged `check-updates` command is fixed to use the correct declaration path, installed for repo users, and backed by the shared status engine for reporting.
  - Tests expand to cover manifest generation, source classification, launch-snapshot lifecycle, startup-mode time-budgeting, and TUI warning visibility.
- **Stays:**
  - Pi core remains unchanged.
  - Managed facade package compilation under `~/.pi/agent/packages` remains the runtime package-loading model.
  - The update/install pipeline remains outside this plan’s scope; the work restores detection and notification only.
  - Unmanaged direct installs (`agent-kit`, `visual-explainer`, similar direct clones/symlinks) remain outside v1 stale-warning coverage, per the approved design-time scope clarification.
  - Startup warning failures never block or alter normal Pi startup.

## Requirements Alignment

No canonical repo requirement IDs for this feature were discovered during research. This approach therefore aligns directly to the accepted brief plus one explicitly approved design-time scope clarification: in this plan, “supported plugin install types used by this repo” means the managed `piPackages` install types (`npm`, `git`, and any future `local` entry that participates in that managed model), not direct-cloned/symlinked resources that bypass the managed package system.

| Requirement | How the approach satisfies or changes it |
|-------------|------------------------------------------|
| Brief goal: startup-time warning for out-of-date managed plugins | The wrapper triggers a launch-time status check and the notifier extension surfaces results inside Pi on `session_start`. |
| Approved scope clarification: v1 covers managed `piPackages` install types only | The approach limits detection to the wrapper-managed package model and explicitly excludes direct cloned/symlinked installs that use separate metadata paths. |
| Brief goal: non-blocking startup | Startup mode uses strict deadlines and maps failures to `unknown`, never startup failure. |
| Brief goal: cover git-based installs | The install-state manifest persists resolved git install facts, and the shared status engine compares them to current remote refs. |
| Brief goal: distinguish stale vs unknown | The status engine classifies sources as `stale`, `current`, or `unknown`; the notifier renders stale and unknown separately. |
| Brief goal: actionable next step | Startup messages point to a fixed, installed `check-updates --dry-run` command plus the existing Home Manager apply flow. |
| Brief constraint: no Pi core changes | All behavior is implemented in the repo’s Nix module, wrapper, helper, and direct extension. |
| Likely-overlooked need: test coverage across install types | The approach adds offline classification tests and targeted integration/smoke coverage for startup visibility. |
| Likely-overlooked need: partial failure visibility | Unknown status is a first-class output state and is shown distinctly from confirmed stale results. |

## Requirement Change Proposal

### Add
- none

### Update
- Scope clarification for this approved plan: “supported plugin install types used by this repo” refers to install types that participate in the managed `piPackages` model. Direct cloned/symlinked resources installed outside that model are excluded from v1 stale-warning coverage and should be described separately if addressed later.

### Remove
- none

## Boundary Definitions
- The **Pi launch wrapper** decides only whether this invocation is an interactive startup that should trigger status evaluation. It does not parse extension metadata, perform its own remote-comparison logic, or mutate declarations.
- The **install-state manifest writer** records install facts after activation. It does not classify staleness, render warnings, or fetch update details for the user.
- The **shared status engine** computes source status and writes structured output. It does not install packages, rewrite declarations, or depend on Pi UI runtime.
- The **startup notifier extension** renders only the snapshot path handed to the current Pi process by the wrapper. It does not perform network calls, discover package state on its own, or decide update policy.
- The **manual `check-updates` frontend** is an operator-facing reporting surface. Dry-run/default mode is the supported inspection contract for this work; any retained `--update` behavior is explicitly npm-only legacy convenience and must still consume the same classification core for status display.
- **Managed-package warning scope** ends at the `piPackages`-driven install model. Direct clones/symlinks installed outside that model are explicitly not checked in this version.
- **Interactive startup warnings** apply to normal Pi session launch only. Help/list/noninteractive CLI commands must not gain warning noise that pollutes scriptable output.
- **Launch snapshot ownership** belongs to exactly one wrapper invocation and one child Pi process. Snapshots must be consume-once or freshness-bounded so they cannot be replayed by later sessions.

## Design Tenets
Non-negotiable principles that must hold even if implementation details change:
- **One classification engine** — startup warnings and manual checks must use the same stale/unknown/current logic.
- **Source truth over facade truth** — stale checking must use original source provenance plus persisted install state, never the synthetic facade package version.
- **Best-effort startup only** — stale detection must never block Pi startup; all failures degrade to `unknown`.
- **Source-level dedupe** — remote checks run once per managed source, not once per facade package ID.
- **Notification, not orchestration** — this work surfaces stale state and next steps only; it does not redesign update application.

## Invariants & Safety Properties
Conditions that must remain true throughout and after implementation:
- Every checked managed source is classified as exactly one of `current`, `stale`, or `unknown`.
- `stale` and `unknown` are rendered as distinct user-visible categories.
- The startup path always launches the real Pi binary even when the status engine times out, errors, or finds malformed status state.
- Noninteractive/help/list Pi invocations remain free of stale-warning chatter.
- Shared-source managed packages perform a single remote probe and produce deterministic grouped output for all affected package IDs.
- User-visible version/ref details must never be sourced from the synthetic facade `package.json` value `0.0.0-generated`.
- The startup notifier reads only a wrapper-provided per-launch snapshot and does not perform remote checks inside the Pi process.
- Concurrent Pi launches cannot overwrite each other’s startup-status evidence or cause one session to display another session’s warning.

## Deviation Protocol
If reality forces a change from this approach during implementation:
- **Preserve:** one shared classification engine, persisted install-state input, non-blocking startup, distinct stale vs unknown handling, and managed-package-only scope.
- **Can change safely:** exact file names, manifest field names, checker implementation language/layout, notifier UI API choice (`notify` vs status line vs both), and concrete timeout/concurrency defaults.
- **Record:** deviations in `plan.md` → Implementation Notes → Deviations.

## Testing Philosophy

### What good tests look like for this change
- Fixture-driven tests assert **classification behavior**, not just file existence: npm stale/current/unknown, git branch/default-head stale, pinned-ref stale, deleted-ref unknown, timeout/auth/offline unknown.
- Manifest tests assert the new install-state artifact contains the local facts the checker needs: dedupe key, package fan-out, npm installed version, and resolved git install commit/ref class.
- Wrapper tests assert interactive launches trigger status generation while help/list/noninteractive invocations do not, and that skipped launches clear any snapshot environment variable.
- Launch-snapshot lifecycle tests assert concurrent launches get distinct snapshot paths and that consumed/expired snapshots are ignored rather than replayed.
- Startup-notifier integration tests assert that a prepared launch snapshot yields visible stale/unknown messaging inside Pi without requiring live network access.
- Manual command tests assert `check-updates` reports the same classification as startup mode for the same prepared fixture state and that dry-run remains informational while real tool/config failures still surface as errors.

### Bad-test avoidance
What would count as insufficient or brittle testing:
- Tests that only assert the wrapper script or notifier extension exists.
- Tests that inspect only facade `package.json` and therefore pass while stale classification is wrong.
- Live-network tests as the primary proof of git/npm staleness behavior.
- Smoke tests that only run `pi --help` or `pi list` and declare startup warning behavior covered.
- Tests that assert one message string without validating the underlying stale vs unknown classification.

## Patterns to Follow
- Follow the existing Home Manager activation pattern in `nix/modules/pi/default.nix` for writing generated runtime artifacts under `~/.pi/agent/`.
- Follow the existing structured warning/report pattern from `nix/modules/pi/compile-managed-packages.mjs` and `managed-packages.report.json` when defining status/diagnostic payloads.
- Follow the existing flake overlay packaging pattern in `flake.nix` when exposing repo-owned helper binaries.
- Follow the existing direct extension installation pattern already used for agent-kit resources in `nix/modules/pi/default.nix` for the startup notifier extension.
- Follow the offline shell-spec pattern in `tests/specs/compiler-contract-spec.sh` for deterministic classification and manifest tests.
- Follow the warning-shape validation pattern in `tests/scripts/resource-snapshot.mjs` if startup warning payloads become part of snapshot/integration assertions.

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|-----------|
| Launch wrapper computes status but the user never sees it clearly once Pi enters TUI | The feature technically runs but fails the user-visible warning goal | Use a small startup notifier extension inside Pi so the result is shown in the TUI, with wrapper output only as a fallback rather than the primary surface. |
| Startup latency becomes noticeable on slow or failing remotes | Users perceive Pi startup as degraded | Run checks per deduped source in parallel with strict per-source and overall startup budgets; classify over-budget cases as `unknown` and continue. |
| Git freshness is wrong because the repo does not preserve resolved installed commit today | Git packages continue to be misclassified or skipped | Persist resolved git install commit/ref class at activation time and make that manifest the only local source of truth for later comparisons. |
| Shared sources create duplicate or noisy warnings | Users see repeated warnings for one underlying source | Deduplicate checks by materialized source and render one grouped result listing all affected package IDs. |
| One launch reads another launch’s snapshot | Users see stale or incorrect warnings, especially under concurrent starts | Use per-launch snapshot files passed via environment to the child Pi process, enforce freshness/consume-once semantics, and test concurrent launch behavior explicitly. |
| Startup and manual status semantics drift | Users see contradictory stale results depending on surface | Route both startup mode and `check-updates` through the same shared status engine and shared result schema, and make `check-updates --dry-run` the only startup-referenced operator path. |
| Warning text points to a broken or unavailable helper | Users know something is wrong but cannot inspect details | Package/install `check-updates` for repo users and bake in the correct declaration path so the warned command works as shown. |
| Unmanaged direct installs are assumed covered when they are not | Users over-trust the warning surface | Scope the notifier text and docs to “managed plugins” and document unmanaged direct installs as explicitly deferred. |
| New warning behavior pollutes scripted `pi` command output | Existing tests or user scripts break | Restrict wrapper-triggered warning evaluation/rendering to interactive Pi session launches and keep noninteractive/help/list invocations clean. |

## Open Questions (to resolve during planning)
- What exact manifest schema and file names should be used for install-state and launch-status artifacts under `~/.pi/agent/`?
- What concrete timeout, concurrency, and retry values satisfy startup-latency goals without overproducing `unknown` results?
- What exact argv patterns should be whitelisted as documented interactive launches beyond plain `pi`?
- How should grouped warnings format shared-source packages so the message is concise but still makes affected package IDs obvious?
- How aggressively should consumed/expired launch snapshots be garbage-collected from the startup-status directory?
