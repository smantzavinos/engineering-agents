# Development Environment

## Required Tooling
- `bash`, `jq`, and `node` are required for the repo-local fast suite.
- `nix` is required for flake evaluation in broader verification.
- `pi` plus a completed Home Manager apply are required for proof-set verification and CLI smoke checks.

## Setup and Apply
1. Ensure Home Manager is available in your local environment.
2. Import this flake's Home Manager module in your personal configuration.
3. Apply the repo-managed tooling with:

```bash
home-manager switch --flake .#<hostname>
```

4. Authenticate the installed tools when needed (`/login` inside `pi`, `opencode auth login` for OpenCode).

## Verification Entry Points
- `./tests/run-tests.sh fast` — repo-local shell specs; use as the task completion gate.
- `./tests/run-tests.sh all` — repo-local specs plus flake evaluation and Pi proof-set verification; use before plan completion.
- `./tests/run-tests.sh full` — everything in `all` plus Pi CLI smoke checks.
- `bash tests/specs/repo-readiness-docs-spec.sh` — targeted fast feedback for the readiness-doc contract introduced by this plan.

For the canonical testing-level mapping and gate roles, see `docs/testing-strategy.md`. For suite inventory and individual spec entry points, see `tests/README.md`.
