#!/usr/bin/env bash
# Verify the repo-local readiness docs and root routing contract.
# Requirement: FR-001
# Requirement: FR-002
# Requirement: FR-003
# Requirement: FR-004
# Requirement: FR-005
# Requirement: OPR-001
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
assert_file_exists "$REPO_ROOT/docs/testing-strategy.md" "Testing strategy doc exists"
assert_file_exists "$REPO_ROOT/docs/backlog.md" "Backlog doc exists"
assert_file_exists "$REPO_ROOT/docs/requirements.md" "Requirements doc exists"

assert_file_contains "$REPO_ROOT/AGENTS.md" "# Project Agent Guide" "AGENTS has routing title"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Architecture" "AGENTS routes architecture section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/architecture.md" "AGENTS routes to architecture doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Coding Rules" "AGENTS routes coding rules section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/coding-rules.md" "AGENTS routes to coding rules doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Development Environment" "AGENTS routes development environment section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/development-environment.md" "AGENTS routes to development environment doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Test Infrastructure" "AGENTS routes test infrastructure section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/testing-strategy.md" "AGENTS points to the canonical testing strategy"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Task Tracking" "AGENTS routes task tracking section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/backlog.md" "AGENTS points to the canonical backlog doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "Non-critical follow-up work belongs in the backlog" "AGENTS states non-critical capture policy"
assert_file_contains "$REPO_ROOT/AGENTS.md" "Critical discoveries that affect correctness, safety, scope, or verification must be raised immediately" "AGENTS states critical discovery policy"
assert_file_contains "$REPO_ROOT/AGENTS.md" "## Requirements" "AGENTS routes requirements section"
assert_file_contains "$REPO_ROOT/AGENTS.md" "docs/requirements.md" "AGENTS points to the canonical requirements doc"
assert_file_contains "$REPO_ROOT/AGENTS.md" "ACT-001" "AGENTS documents actor ID prefix"
assert_file_contains "$REPO_ROOT/AGENTS.md" "UC-001" "AGENTS documents use-case ID prefix"
assert_file_contains "$REPO_ROOT/AGENTS.md" "WF-001" "AGENTS documents workflow ID prefix"
assert_file_contains "$REPO_ROOT/AGENTS.md" "FR-001" "AGENTS documents functional requirement ID prefix"
assert_file_contains "$REPO_ROOT/AGENTS.md" "NFR-001" "AGENTS documents non-functional requirement ID prefix"
assert_file_contains "$REPO_ROOT/AGENTS.md" "OPR-001" "AGENTS documents operational requirement ID prefix"
assert_file_contains "$REPO_ROOT/AGENTS.md" 'Requirement: FR-001' "AGENTS documents the test requirement citation format"
assert_file_contains "$REPO_ROOT/AGENTS.md" "Canonical requirement edits require human approval unless explicitly delegated" "AGENTS states the requirement approval boundary"

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

assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "# Testing Strategy" "Testing strategy doc has title"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "## Standard Level Mapping" "Testing strategy doc maps commands to standard levels"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "./tests/run-tests.sh fast" "Testing strategy doc covers the fast gate"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "./tests/run-tests.sh all" "Testing strategy doc covers the final gate"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "./tests/run-tests.sh full" "Testing strategy doc covers the full gate"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "## Scope, Timing, and Prerequisites" "Testing strategy doc explains scope and prerequisites"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "task completion gate" "Testing strategy doc identifies the task gate"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "final plan gate" "Testing strategy doc identifies the final gate"
assert_file_contains "$REPO_ROOT/docs/testing-strategy.md" "bash tests/specs/proof-set-runtime-spec.sh" "Testing strategy doc lists targeted proof-set feedback"

assert_file_contains "$REPO_ROOT/docs/backlog.md" "# Backlog" "Backlog doc has title"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## System" "Backlog doc explains the system"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "canonical backlog" "Backlog doc declares itself canonical"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Required Operations" "Backlog doc has operations table"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Create item" "Backlog doc covers item creation"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Assign stable ID" "Backlog doc covers stable ID assignment"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Reference format" "Backlog doc covers reference format"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Source backlink" "Backlog doc covers source backlinks"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "List Inbox" "Backlog doc covers inbox listing"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "List Up next" "Backlog doc covers up-next listing"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Mark Ready" "Backlog doc covers ready transitions"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Mark Done" "Backlog doc covers done transitions"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Mark Canceled" "Backlog doc covers canceled transitions"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Defer / Icebox" "Backlog doc covers defer-to-icebox transitions"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Mark Blocked" "Backlog doc covers blocked transitions"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "Critical item policy" "Backlog doc covers critical-item policy"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "TASK-XXXX" "Backlog doc documents the stable ID format"
assert_file_contains "$REPO_ROOT/docs/backlog.md" 'Every item must include a `Source:` line' "Backlog doc requires source backlinks"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Item Template" "Backlog doc has an item template"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Up next" "Backlog doc has Up next section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Ready" "Backlog doc has Ready section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Inbox" "Backlog doc has Inbox section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Clarification needed" "Backlog doc has Clarification needed section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## In progress" "Backlog doc has In progress section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## In review" "Backlog doc has In review section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Blocked" "Backlog doc has Blocked section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Icebox" "Backlog doc has Icebox section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Done" "Backlog doc has Done section"
assert_file_contains "$REPO_ROOT/docs/backlog.md" "## Canceled" "Backlog doc has Canceled section"

assert_file_contains "$REPO_ROOT/docs/requirements.md" "# Requirements" "Requirements doc has title"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## System" "Requirements doc explains the system"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "canonical source for the repo's current accepted requirements" "Requirements doc declares the canonical store"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## Required Operations" "Requirements doc has operations table"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "List actors/personas" "Requirements doc covers listing actors"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "List use cases" "Requirements doc covers listing use cases"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "List workflows" "Requirements doc covers listing workflows"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "List functional requirements" "Requirements doc covers listing functional requirements"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "List non-functional requirements" "Requirements doc covers listing non-functional requirements"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "List operational requirements" "Requirements doc covers listing operational requirements"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "Discover stable IDs" "Requirements doc covers stable ID discovery"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "Reference format" "Requirements doc covers requirement reference format"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "Test citation format" "Requirements doc covers test citation format"
assert_file_contains "$REPO_ROOT/docs/requirements.md" 'Requirement: <ID>' "Requirements doc documents the test citation syntax"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "Apply approved changes" "Requirements doc covers applying approved changes"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "Retire or replace requirements" "Requirements doc covers retirement and replacement"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "Validation/query guidance" "Requirements doc covers validation and query guidance"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "human approval unless explicitly delegated" "Requirements doc states the approval boundary"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## Actors and Personas" "Requirements doc has actor section"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "ACT-001" "Requirements doc defines an actor"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## Use Cases" "Requirements doc has use-case section"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "UC-001" "Requirements doc defines a use case"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## Workflows" "Requirements doc has workflow section"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "WF-001" "Requirements doc defines a workflow"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## Functional Requirements" "Requirements doc has functional requirements section"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "FR-001" "Requirements doc defines a functional requirement"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## Non-Functional Requirements" "Requirements doc has non-functional requirements section"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "NFR-001" "Requirements doc defines a non-functional requirement"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "## Operational Requirements" "Requirements doc has operational requirements section"
assert_file_contains "$REPO_ROOT/docs/requirements.md" "OPR-001" "Requirements doc defines an operational requirement"

assert_file_contains "$REPO_ROOT/tests/specs/repo-readiness-docs-spec.sh" 'Requirement: FR-001' "Readiness docs spec cites a functional requirement"
assert_file_contains "$REPO_ROOT/tests/specs/repo-readiness-docs-spec.sh" 'Requirement: FR-004' "Readiness docs spec cites the requirements-system contract"
assert_file_contains "$REPO_ROOT/tests/specs/proof-set-runtime-spec.sh" 'Requirement: FR-006' "Proof-set runtime spec cites its functional requirement"

printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
