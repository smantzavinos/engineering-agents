# Pi Team Setup and Preflight

**Status:** additive and non-canonical. This is an experimental Pi-only setup guide for the
reviewed rollout. It does not replace the current process, requirements, team policy, or OpenCode
configuration. Calibration and an explicitly approved migration are required before any of those
canonical sources change.

## Provenance and installation

`pi-messenger@0.15.0` is the only proven package version for this rollout. Its package declaration,
including the `./index.ts` extension and `pi-messenger-crew` skill, is in
`nix/modules/pi/default.nix`. The investigation's Phase 0 upstream proof passed at the pinned
v0.15.0 source commit; that proves the substrate, not an active local installation.

Nix also installs `pi-team` as a PATH command. It is the wrapper for the repository's
`tools/pi-team.mjs`; use `pi-team check`, `pi-team init-board`, and `pi-team review-wave`, not a
separate package or copied script.

Apply the managed installation before active-install verification:

```bash
home-manager switch --flake .#<hostname>
```

## Stable configuration and runtime boundary

`config/pi-team/` is the canonical project source for both Crew and profile configuration.

| Item | Canonical source | Installed or project runtime location |
|---|---|---|
| Crew defaults | `config/pi-team/crew-config.json` | tracked relative symlink `.pi/messenger/crew/config.json` |
| `pi-team` profile | `config/pi-team/team-profile.json` | `~/.pi/agent/messenger/team-profiles/pi-team.json` |
| Task reviewer | `agents/pi-team-reviewer.md` | `~/.pi/agent/agents/pi-team-reviewer.md` |
| Messenger package | `nix/modules/pi/default.nix` | managed Pi package |

The tracked symlink is the only admitted project `.pi` configuration. Do not copy or edit its
target under `.pi`; edit `config/pi-team/crew-config.json`. Runtime board state is generated and
ignored: `.pi/messenger/team/` and all board entries under `.pi/messenger/crew/` except
`config.json` and `agents/`. The generated entries are `plan.json`, `plan.md`, `tasks/`, `blocks/`,
`artifacts/`, `planning-progress.md`, and `planning-outline.md`.

Recovery moves only those generated board entries to
`.pi/messenger/crew-runs/<UTC-basic-timestamp>/`; it never moves `config.json` or `agents/`.
Archive a partial materialization automatically only before any worker starts. Obtain human
confirmation before recovering incomplete started work.

## Pi-session preflight

`pi_messenger` is a Pi tool, not a shell command. In the lead's Pi session, activate the profile
with the exact tool invocation `pi_messenger team.profile.use name pi-team`. Activation is
idempotent and is a preflight, not persisted project state.

After activation, inspect the returned active profile. It must be exactly `pi-team` and contain
these roles with the declared `pi-team-worker` skill:

- `worker-cheap`: `github-copilot/gpt-5.6-terra`, `low`
- `worker-std`: `github-copilot/gpt-5.6-terra`, `medium`
- `worker-complex`: `github-copilot/gpt-5.6-sol`, `high`
- `worker-visual`: `github-copilot/gpt-5.6-terra`, `high`
- `worker-visual-complex`: `github-copilot/gpt-5.6-sol`, `high`

Also verify the approval policy is `risk-labels` with exactly `migration, destructive, auth,
api-contract`. Never use a bare packaged role and never auto-approve a risk-labelled task.

## Board preflight and commands

The authored `plan.md` is the execution contract. The board is generated runtime state. Run the
following from a repository with a reviewed plan; `BASE` must be recorded from a clean index and
worktree. The review output directory must not exist when passed to `review-wave`.

```bash
REPO="$(git rev-parse --show-toplevel)"
PLAN="$REPO/plans/YYYY_MM_DD_<slug>/plan.md"
CREW="$REPO/.pi/messenger/crew"
BASE="$(git -C "$REPO" rev-parse HEAD)"
WAVE_IDS="T1,T2"
OUTPUT_DIR="$REPO/.pi/messenger/reviews/wave-1"

pi-team check "$PLAN" --json
pi-team init-board "$PLAN" --crew-dir "$CREW" --repo-root "$REPO"
pi-team review-wave "$PLAN" --scope "$WAVE_IDS" --bundle "$WAVE_IDS" --repo-root "$REPO" --base "$BASE" --output-dir "$OUTPUT_DIR"
```

Before initialization, refuse existing generated board state; stable `config.json` and `agents/`
are no-clobber inputs. Materialize tasks through the `pi_messenger` tool in stable topological
order, retain the plan-ID-to-Crew-ID map, then run `crew.validate`. The single missing-`plan.md`
warning is expected because the authored plan remains at `prd`; any other warning, graph error, or
count error stops execution and archives partial state. Do not create a second board plan or treat
runtime files as tracked sources.

## Verification gates and failure policy

Run the narrow checks during work and record baseline failures before each touched gate:

```bash
bash tests/specs/repo-readiness-docs-spec.sh
./tests/run-tests.sh fast
./scripts/pi-dev.sh --verify
home-manager switch --flake .#<hostname>
./tests/run-tests.sh all
```

The targeted readiness spec is fast feedback. `fast` is the task gate. `pi-dev` verifies the
current checkout in its isolated sandbox. The Home Manager command applies the active installation
for live package, skill, profile, project-config, reviewer, and callable `pi_messenger` proof.
`all` is the final plan gate. Baseline failures must be recorded separately and compared after the
gate; only new failures block this rollout task. `full` remains an optional release smoke under
`docs/testing-strategy.md`.

Do not treat a green deployment proof as calibration. Current canonical process and OpenCode
behavior remain unchanged pending calibration; see
`docs/investigations/2026-07-31-plan-execution-efficiency/pi-team-execution.md` for the reviewed
experimental lifecycle and its promotion boundary.
