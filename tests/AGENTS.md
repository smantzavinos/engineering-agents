# Tests Directory Guide

Read this file before adding or changing specs, fixtures, or test runners in `tests/`.

## Shell Spec Style
- Keep shell specs small, deterministic, and readable.
- Use `set -euo pipefail`, source `tests/lib/common.sh`, and prefer helper assertions over repeated ad hoc shell logic.
- Assert durable behavior and key anchors, not fragile formatting trivia.
- Print PASS/FAIL output that makes the broken contract obvious.

## Fixture Patterns
- Keep fixtures minimal and representative of a real contract edge or success path.
- Prefer explicit fixture names that describe the behavior under test.
- Update fixture families together when a versioned contract intentionally changes.
- Keep generated outputs deterministic so specs do not fail on ordering noise.

## Verification Expectations
- Use targeted spec commands for TDD fast feedback, then run the documented task gate `./tests/run-tests.sh fast` before marking work complete.
- If a spec verifies requirements-backed behavior, use the documented citation format `Requirement: <ID>`.
- Treat false-green behavior as a bug in the test surface, not as an acceptable shortcut.

## Adding New Specs
- Put new executable specs in `tests/specs/` and make them runnable with `bash tests/specs/<name>.sh`.
- Wire new fast-suite specs into `tests/run-tests.sh` and mention them in `tests/README.md` when they change the documented inventory.
- Reuse `tests/spec-fixtures/` or add a clearly named fixture subdirectory when the spec needs durable inputs.
- Keep the spec focused on one contract surface so failures are easy to diagnose.

## Anti-Patterns
- Do not rely on file-exists checks alone when the contract needs content assertions.
- Do not hide unrelated setup inside a spec when it belongs in shared helpers or fixtures.
- Do not add slow or environment-heavy checks to the fast suite without updating the documented gate expectations.
