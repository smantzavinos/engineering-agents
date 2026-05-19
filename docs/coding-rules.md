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
- TDD is mandatory for non-trivial changes: create a failing test first, implement the minimal fix, run a break-it check, and restore the passing state.
- Use the repo's documented fast-feedback command during the task loop and the package-wide gate before marking a task complete.
- Do not mark work done with unverified changes or with unrelated edits mixed into the same checkpoint.
