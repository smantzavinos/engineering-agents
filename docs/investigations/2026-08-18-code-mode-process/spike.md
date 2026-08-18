# T0 Spike — workflowScript on the real runtime

- Date: 2026-08-18
- Runtime: Pi 0.84.2 (Bun-built), Node wrapper, `.pi-dev` sandbox
- Method: `scripts/pi-dev.sh --verify` then `pi -p --no-session` against the sandbox
- Purpose: verify every behaviour the wave engine depends on **before** writing it (T6)

Status legend: **V** = verified by execution, **S** = verified by reading source, **U** = unresolved.

---

## F1 (V) — v0.50.0 is unusable on this Pi build. Pin moved.

```
Workflow failed: NotImplementedError: node:v8 createHook is not yet implemented in Bun.
    at createHook (node:v8:116:12)
```

Pi 0.84.2 is Bun-built. v0.50.0's workflow engine hard-requires
`node:v8 promiseHooks.createHook` for child-launch tracking, which Bun does not implement.
**Every `workflowScript` call fails.** The proposal's original pin choice (the v0.50.0 release
tag) would have made the entire code-mode plan non-functional.

Fixed upstream in `19a4e60` "preserve workflow scripts on Bun" (#1170), which replaces promise
hooks with acorn static parsing, and `b6a69ec` "fall back to manifest resolution for workflow
parser entry" (#1214). Both are post-release, unreleased.

**Pin: `3847deeaa6e814c328ff4964fc28d7c2e6f9fc9b`** (main, includes both). Accepted risk:
unreleased. Revisit at 0.51.0.

Two consequential dependency changes came with the version move:

| Change | Effect |
|---|---|
| pi manifest entrypoint `./src/extension/index.ts` → `./index.ts` | proof-set fixture, ok-snapshot fixture, `flake.nix` shape check |
| new runtime deps `yaml@2.8.3` (0.50.0), `acorn@8.18.0` (Bun fix) | must be vendored in `managed-packages/package.json`; without `yaml`, `pi doctor` fails to load the extension entirely |

## F2 (V) — There is no `status` field. `ok` is the success flag.

Observed result keys: `artifactPaths, error, key, ok, output, results`.
`hasStatusField: false` on every child.

The first draft of the engine branched on `r.status !== "completed"`, which is always true —
it would have classified 100% of successful work as failed and escalated everything.

## F3 (V) — `runs.run` throws; `runs.all` collects.

```json
{ "threw": true,
  "caught": "Run 'solo' failed: … Acceptance rejected: …",
  "returnedOk": null }
```

`runs.all` returned `[{ok:false},{ok:false}]` for the same failure, and a sibling failure did
not reject the batch or harm the other child.

**Engine consequence: use `runs.all` for everything, including single-task waves.** It is the
only call shape that yields inspectable failures instead of an exception that aborts the
workflow and its in-flight siblings.

## F4 (V) — Mission `state` works.

`state.set("done", ["T1","T2"])` → `state.get("done")` round-trips; `missionAvailable: true`;
mission recorded and completed. Missing keys return `undefined` (and drop out of JSON
serialization — read them defensively).

## F5 (V) — **`gate:` cannot be the engine's integrity mechanism.**

This is the most important finding and it changes the architecture.

`gate: "<cmd>"` normalizes to `acceptance: { level: "verified", verify: [...] }`. The
acceptance layer validates the child's **structured evidence report** and short-circuits
*before* the host gate result is ever consulted. Three successive rejections were observed,
each a different layer, none of which reached the gate command:

| Attempt | Rejection |
|---|---|
| plain task | `Structured acceptance report not found.` |
| + acceptance-report block | `Required criterion 'criterion-1' was not reported.` |
| + all criteria reported | `commands-run evidence missing from child report.` |

`gate: "true"` and `gate: "false"` produced **identical `ok:false`** in every attempt. The gate
command's exit status never discriminated.

Source confirms this is not tunable (S): `acceptance.ts:384` computes evidence as the *union*
of the level's required evidence and any explicit evidence, so `evidence: []` cannot reduce
below what `verified` demands. Host-run verification is inseparable from the child's
structured-report contract.

**Consequences:**

1. A cheap worker that does the work correctly but writes a sloppy acceptance report **fails
   the run**. The parent cannot distinguish "implementation wrong" from "paperwork wrong"
   without string-matching `Acceptance rejected:` in `error`.
2. Per-child `gate` is therefore unsuitable as the wave engine's proof-of-done.
3. **The parent must run verification on the host, between waves.**

### Architectural consequence: one workflow invocation per wave

The engine becomes a parent-driven loop over wave-sized workflow invocations, rather than one
script containing the whole wave loop:

```
parent: baseline gate (host bash)
parent: freeze + contract invocation  → commit red tests
loop:
  parent: compute ready set
  parent: ONE workflowScript invocation for that wave (runs.all, no gate:)
  parent: run verification on host (real bash, real exit codes)
  parent: reviewers + fixes
  parent: commit wave checkpoint
```

This converges with the §5b worktree finding: oracle showed that if worktrees are ever used,
patches must be applied and committed by the parent *between* waves, which a single
long-running script cannot pause for. Two independent lines of evidence now point at the same
shape. Per-wave invocation also gives natural crash boundaries and makes `state` a
belt-and-braces record rather than the sole resume mechanism.

Cost: the parent stays in the loop, so this is less "fire and forget" than the original
sketch. Benefit: verification is real host execution the parent observes directly, integration
is continuous, and commits happen at wave boundaries.

## F6 (V) — Non-blocking environment notes

- Flake default subagent model is `zai-coding-plan/glm-5.2`; only `github-copilot` is authed in
  the sandbox, so unqualified children fail with
  `Unknown subagent model … in the active Pi model registry`. Engine children must carry an
  explicit `model`, or routing must be repo-configured.
- Spawn accounting is reported per run (`Run fan-out: 2/64 used, 62 remaining`), confirming the
  64-spawn ceiling is real and observable.
- `acorn` is **not** referenced anywhere in v0.50.0 source (S) — it only becomes a dependency
  via the Bun fix. Oracle's acorn-resolution concern applies to the new pin, and `b6a69ec` is
  the reason the pin is at main rather than at `19a4e60`.

## F7 (U) — Unresolved

Whether a **real** implementation task (one that genuinely changes files and runs commands, so
`changedFiles` / `commandsRun` are naturally non-empty) satisfies the acceptance contract
cleanly. All probes used a deliberately trivial no-op task, which is pathological for an
evidence-based gate. F5's architectural conclusion does not depend on this — the
short-circuit ordering and the indistinguishability of paperwork failure from work failure are
established regardless — but the *frequency* of false failures with cheap models is not yet
measured.

Resolve during the first real wave; instrument by classifying `error` strings that begin
`Acceptance rejected:` separately from other failures.

---

## Changes required to the proposal

| § | Change |
|---|---|
| §5 P3 | Wave loop moves from inside one script to a parent-driven loop of per-wave invocations |
| §5 sketches | `runs.all` everywhere; branch on `!r.ok`; explicit `model` per child |
| §5b | Host verification is parent-run between waves, not per-child `gate:` |
| §5b self-defending gates | Frozen-test diff check moves to the parent's host command, where it actually runs |
| §5c | `state` demoted to secondary record; wave-boundary commits are the primary resume mechanism |
| §7 rule 4 | Rewrite: the gate is host-run **by the parent**, not via child `gate:` |
| §8 | Pin rationale replaced by F1 |
