# Coding Rules

## Documentation and Planning Artifacts
- Prefer updating the canonical doc for a rule instead of scattering the same guidance across multiple files.
- Keep routing documents concise and link outward to the detailed source of truth.
- Treat `plans/` artifacts as execution records: do not silently rewrite completed history.

## Shell and CLI Conventions
- Write shell scripts with `set -euo pipefail` unless a documented reason requires different behavior.
- Prefer portable Bash patterns already used in `tests/` and `scripts/`.
- Keep command surfaces stable; if a wrapper script exists, document and use it instead of inventing a new top-level command.

## Verification Rules
- Dynamic-workflow plans declare a verification class per task (`contract`,
  `characterization`, `check`, `none`); see `docs/testing-strategy.md`. Contract tests are
  authored by an agent other than the implementer, observed red once, and frozen.
- There is no mandatory break-it step. A reviewer may demand one for a specific test that
  looks like it cannot fail; an implementer never self-administers it.
- Verification runs on the host, at wave boundaries, by the orchestrating parent. It is never
  delegated to the child that did the work.
- Sequential OpenCode plans keep strict TDD: failing test first, minimal fix, break-it check,
  restore the passing state.
- Use the repo's documented verification commands according to the selected execution mode.
- Do not mark work done with unverified changes or with unrelated edits mixed into the same checkpoint.
