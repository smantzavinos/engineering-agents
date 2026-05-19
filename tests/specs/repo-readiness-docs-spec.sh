#!/usr/bin/env bash
# Verify the repo-local readiness docs and root routing contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

assert_file_exists() {
  local path="$1" desc="$2"
  if [[ -f "$path" ]]; then pass "$desc"; else fail "$desc (missing: $path)"; fi
}

assert_file_contains() {
  local path="$1" needle="$2" desc="$3"
  if [[ ! -f "$path" ]]; then fail "$desc (file missing: $path)"; return; fi
  if grep -Fq "$needle" "$path"; then pass "$desc"; else fail "$desc (missing: $needle in $path)"; fi
}

printf 'Repo readiness docs verification\n'
printf '================================\n\n'

assert_file_exists "$REPO_ROOT/AGENTS.md" "Root AGENTS routing doc exists"
assert_file_exists "$REPO_ROOT/docs/architecture.md" "Architecture doc exists"
assert_file_exists "$REPO_ROOT/docs/coding-rules.md" "Coding rules doc exists"
assert_file_exists "$REPO_ROOT/docs/development-environment.md" "Development environment doc exists"

assert_file_contains "$REPO_ROOT/AGENTS.md" "# Project Agent Guide" "AGENTS has routing title"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Architecture" "AGENTS routes architecture section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/architecture.md" "AGENTS routes to architecture doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Coding Rules" "AGENTS routes coding rules section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/coding-rules.md" "AGENTS routes to coding rules doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Development Environment" "AGENTS routes development environment section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/development-environment.md" "AGENTS routes to development environment doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Test Infrastructure" "AGENTS routes test infrastructure section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "tests/README.md" "AGENTS points to canonical current test docs"

assert_file_contains "$REPO_ROOT/docs/architecture.md" "# Repository Architecture" "Architecture doc has title"
assert_file_contains "$REPO_ROOT/docs/architecture.md" "## Repository Purpose" "Architecture doc describes repository purpose"
assert_file_contains "$REPO_ROOT/docs/architecture.md" "## Primary Surfaces" "Architecture doc lists primary surfaces"
assert_file_contains "$REPO_ROOT/docs/architecture.md" "## Core Flows" "Architecture doc describes core flows"
assert_file_contains "$REPO_ROOT/docs/architecture.md" "## Boundaries and Constraints" "Architecture doc states boundaries"

assert_file_contains "$REPO_ROOT/docs/coding-rules.md" "# Coding Rules" "Coding rules doc has title"
assert_file_contains "$REPO_ROOT/docs/coding-rules.md" "## Documentation and Planning Artifacts" "Coding rules cover planning artifacts"
assert_file_contains "$REPO_ROOT/docs/coding-rules.md" "## Shell and CLI Conventions" "Coding rules cover shell conventions"
assert_file_contains "$REPO_ROOT/docs/coding-rules.md" "## Verification Rules" "Coding rules cover verification expectations"
assert_file_contains "$REPO_ROOT/docs/coding-rules.md" "TDD" "Coding rules require TDD"

assert_file_contains "$REPO_ROOT/docs/development-environment.md" "# Development Environment" "Development environment doc has title"
assert_file_contains "$REPO_ROOT/docs/development-environment.md" "## Required Tooling" "Development environment doc lists tooling"
assert_file_contains "$REPO_ROOT/docs/development-environment.md" "## Setup and Apply" "Development environment doc explains setup"
assert_file_contains "$REPO_ROOT/docs/development-environment.md" "home-manager switch --flake .#<hostname>" "Development environment doc includes apply command"
assert_file_contains "$REPO_ROOT/docs/development-environment.md" "## Verification Entry Points" "Development environment doc lists verification entry points"

printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
