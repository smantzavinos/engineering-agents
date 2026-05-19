# Verification Baseline: Repository Quality Process Foundation

**Created:** 2026-05-19
**Plan:** ../brief.md

## Summary
The repo already has working local verification commands, but the current baseline shows an important trust issue: the repo-wide `all` gate reported success during assessment even though the proof-set step emitted an environment error about the Pi module entrypoint path. Because this initiative is about making the repo itself process-ready, verification reliability is in scope and should be fixed rather than documented away.

## Observed commands and current meaning
### `./tests/run-tests.sh fast`
- Documented in: `tests/README.md`, `tests/run-tests.sh`
- Current purpose: repo-local spec checks only
- Assessment result: passed on 2026-05-19
- Notes: good candidate for the default task-completion gate while this plan is being executed

### `./tests/run-tests.sh all`
- Documented in: `tests/README.md`, `tests/run-tests.sh`
- Current purpose: repo-local specs + flake eval + Pi proof-set verification
- Assessment result: script reported overall success, but the proof-set stage printed:
  - `Unable to locate Pi module entrypoint at /nix/store/.../@mariozechner/pi-coding-agent/dist/index.js`
- Notes: this is an in-scope correctness problem for the repo's verification story

### `./tests/run-tests.sh full`
- Documented in: `tests/README.md`, `tests/run-tests.sh`
- Current purpose: `all` plus Pi CLI smoke tests
- Assessment result: not run during plan setup
- Notes: likely best documented as an optional release-smoke gate unless the repo decides it should be the canonical final gate

## Likely source of the proof-set issue
`tests/scripts/resource-snapshot.mjs` hardcodes the Pi module package path:
- `lib/node_modules/@mariozechner/pi-coding-agent/dist/index.js`

The active Pi installation used in this environment appears to use a different package namespace (`@earendil-works/pi-coding-agent` in the harness-provided docs path), which explains the failure. The script and associated fixtures likely need to support the current package name and possibly retain compatibility with the older namespace if the repo still cares about both distributions.

## Baseline implication for planning
Because repo-wide verification is part of the quality target, the plan should:
1. establish a canonical testing strategy doc,
2. treat verification-contract drift as executable behavior with regression tests,
3. fix or explicitly surface the proof-set environment failure,
4. decide and document which command is the task gate vs the final gate.

## Recommended gate policy for execution
Use `block-on-global-gate` for this plan.

Rationale:
- This work is about repo correctness and autonomous-execution trust.
- A misleading or partially broken repo-wide gate is directly related to the scope.
- Allowing scoped completion would leave the repo in a state where its own readiness signal is untrustworthy.
