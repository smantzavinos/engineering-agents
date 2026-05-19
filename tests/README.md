# Engineering Agents Test Suite

## Test Tiers

| Tier | What | Requires | Runner |
|------|------|----------|--------|
| **Repo-local specs** | File structure, readiness docs, frontmatter, skill/agent refs, compiler, presets | `bash`, `jq`, `node` | `tests/run-tests.sh fast` |
| **Flake eval** | Nix module evaluation, package builds | `nix` | `tests/run-tests.sh all` |
| **Pi proof-set** | Live facade/provenance verification | Pi installed, `home-manager switch` run | `tests/run-tests.sh all` |
| **CLI smoke** | `pi --help`, `pi list` output | Pi installed | `tests/run-tests.sh full` |

## Quick Commands

```bash
# Repo-local only (no Nix or Pi required)
./tests/run-tests.sh fast

# Repo-local + flake eval + proof-set
./tests/run-tests.sh all

# Everything including CLI smoke
./tests/run-tests.sh full

# Individual specs
bash tests/specs/repo-structure-spec.sh
bash tests/specs/repo-readiness-docs-spec.sh
bash tests/specs/skill-content-spec.sh
bash tests/specs/flake-eval-spec.sh
bash tests/specs/preset-spec.sh
bash tests/specs/pi-module-content-spec.sh
bash tests/specs/compiler-contract-spec.sh
```

## Test Adaptation

This suite is adapted from `dotfiles/nix/tests/pi/`. The following were ported:

- **`resource-snapshot.mjs`** — Live Pi state snapshot using Pi's `DefaultResourceLoader`
- **`assert-contract.sh`** — Proof-set contract assertions (facade, provenance, resources)
- **`compiler-contract-spec.sh`** — Compile-managed-packages.mjs fixture tests
- **`proof-set.json`** — Representative proof-set expectations (pi-ding, pi-subagents, catppuccin-mocha, pi-ext-leader-key, pi-ext-review)
- **Spec fixture directories** — Compiler declarations, resource-snapshot snapshots

New tests specific to this repo:

- **`repo-structure-spec.sh`** — All required files/dirs exist, README has key content
- **`repo-readiness-docs-spec.sh`** — Root AGENTS routing and canonical contributor docs exist with required anchors
- **`skill-content-spec.sh`** — Skill frontmatter, references, templates, key sections
- **`pi-module-content-spec.sh`** — Module skill/agent refs resolve, guardrails valid JSON, compile helper valid JS
- **`preset-spec.sh`** — All three modes (discovery/design/execute) defined, all 8 agents present
- **`flake-eval-spec.sh`** — All modules evaluate, docs package builds, dev shell works

## File Layout

```
tests/
├── lib/common.sh                    # Shared utilities (paths, assertions)
├── fixtures/proof-set.json          # Proof-set expectations for live verification
├── scripts/
│   ├── assert-contract.sh           # Proof-set contract assertions
│   └── resource-snapshot.mjs        # Live Pi state snapshot generator
├── spec-fixtures/
│   ├── compiler/                    # compile-managed-packages.mjs test inputs
│   ├── resource-snapshot.*          # Snapshot contract test fixtures
│   └── update-checker/              # Update checker test fixtures
├── specs/
│   ├── repo-structure-spec.sh       # File/dir existence checks
│   ├── repo-readiness-docs-spec.sh  # Root routing and core contributor docs
│   ├── skill-content-spec.sh        # Skill quality checks
│   ├── pi-module-content-spec.sh    # Module content integrity
│   ├── preset-spec.sh               # Preset configuration validation
│   ├── flake-eval-spec.sh           # Nix flake evaluation
│   └── compiler-contract-spec.sh    # Compile helper contract tests
├── test-fast.sh                     # Read-only Pi proof-set verification
└── run-tests.sh                     # Main test runner (fast/all/full)
```
