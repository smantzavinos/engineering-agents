#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq python3 >/dev/null

REPO_ROOT="$(repo_root)"
HELPER_PATH="$REPO_ROOT/nix/modules/pi/check-managed-package-status.mjs"
CHECK_UPDATES_PATH="$REPO_ROOT/scripts/check-updates.sh"
FIXTURE_DIR="$(tests_dir)/spec-fixtures/managed-package-status"
UPDATE_FIXTURE_PATH="$(tests_dir)/spec-fixtures/update-checker/pi.nix.sample"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_helper() {
  local output_format="$1"
  local manifest_path="$2"
  local stdout_path="$3"
  local stderr_path="$4"
  shift 4

  set +e
  node "$HELPER_PATH" \
    --manifest "$manifest_path" \
    --mode manual \
    --format "$output_format" \
    --npm-bin "$FIXTURE_DIR/fake-npm" \
    --git-bin "$FIXTURE_DIR/fake-git" \
    "$@" \
    >"$stdout_path" 2>"$stderr_path"
  local status=$?
  set -e

  return "$status"
}

run_check_updates() {
  local stdout_path="$1"
  local stderr_path="$2"
  shift 2

  set +e
  PI_UPDATE_CHECKER_INSTALL_STATE_FILE="$FIXTURE_DIR/manifest.ok.json" \
  PI_UPDATE_CHECKER_NIX_FILE="$UPDATE_FIXTURE_PATH" \
  PI_UPDATE_CHECKER_HELPER="$HELPER_PATH" \
  PI_UPDATE_CHECKER_NODE_BIN="node" \
  PI_UPDATE_CHECKER_NPM_BIN="$FIXTURE_DIR/fake-npm" \
  PI_UPDATE_CHECKER_GIT_BIN="$FIXTURE_DIR/fake-git" \
  PI_UPDATE_CHECKER_PYTHON_BIN="python3" \
  PI_UPDATE_CHECKER_ASSUME_YES="1" \
    "$CHECK_UPDATES_PATH" "$@" >"$stdout_path" 2>"$stderr_path"
  local status=$?
  set -e

  return "$status"
}

assert_json() {
  local description="$1"
  local path="$2"
  local filter="$3"

  if jq -e "$filter" "$path" >/dev/null; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'File under test: %s\n' "$path" >&2
    cat "$path" >&2 || true
    fail "$description"
  fi
}

assert_contains() {
  local description="$1"
  local path="$2"
  local needle="$3"

  if grep -Fq "$needle" "$path"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'File under test: %s\n' "$path" >&2
    cat "$path" >&2 || true
    fail "$description"
  fi
}

assert_not_contains() {
  local description="$1"
  local path="$2"
  local needle="$3"

  if grep -Fq "$needle" "$path"; then
    printf 'File under test: %s\n' "$path" >&2
    cat "$path" >&2 || true
    fail "$description"
  else
    printf 'PASS: %s\n' "$description"
  fi
}

assert_exit_code() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" == "$actual" ]]; then
    printf 'PASS: %s\n' "$description"
  else
    fail "$description (expected exit $expected, got $actual)"
  fi
}

JSON_STDOUT="$TMP_DIR/status.json"
JSON_STDERR="$TMP_DIR/status.stderr"
TEXT_STDOUT="$TMP_DIR/status.txt"
TEXT_STDERR="$TMP_DIR/status-text.stderr"
CHECK_STDOUT="$TMP_DIR/check-updates.out"
CHECK_STDERR="$TMP_DIR/check-updates.err"
MISSING_STDOUT="$TMP_DIR/missing.out"
MISSING_STDERR="$TMP_DIR/missing.err"
MALFORMED_STDOUT="$TMP_DIR/malformed.out"
MALFORMED_STDERR="$TMP_DIR/malformed.err"
TIMEOUT_STDOUT="$TMP_DIR/timeout.json"
TIMEOUT_STDERR="$TMP_DIR/timeout.err"
UPDATE_TMP="$TMP_DIR/pi.nix.update"
cp "$UPDATE_FIXTURE_PATH" "$UPDATE_TMP"

if ! run_helper json "$FIXTURE_DIR/manifest.ok.json" "$JSON_STDOUT" "$JSON_STDERR"; then
  printf 'stdout:\n' >&2
  cat "$JSON_STDOUT" >&2 || true
  printf 'stderr:\n' >&2
  cat "$JSON_STDERR" >&2 || true
  fail 'helper should emit status JSON for the fixture manifest'
fi

assert_json \
  'helper emits schemaVersion 1 with manual mode' \
  "$JSON_STDOUT" \
  '.schemaVersion == 1 and .mode == "manual"'

assert_json \
  'helper returns deterministically sorted sources and grouped packageIds' \
  "$JSON_STDOUT" \
  '.sources == (.sources | sort_by(.sourceKey)) and any(.sources[]; .sourceKey == "src-008-git-pinned-shared-stale" and .packageIds == ["git-shared-alpha", "git-shared-beta"])'

assert_json \
  'npm sources classify current, stale, and lookup failure as expected' \
  "$JSON_STDOUT" \
  'any(.sources[]; .sourceKey == "src-001-npm-current" and .status == "current" and .latestVersion == "1.0.0")
   and any(.sources[]; .sourceKey == "src-002-npm-stale" and .status == "stale" and .latestVersion == "2.0.0")
   and any(.sources[]; .sourceKey == "src-003-npm-lookup-failure" and .status == "unknown" and .reasonCode == "LOOKUP_FAILED")'

assert_json \
  'git default, branch, pinned commit, and pinned tag semantics classify current or stale correctly' \
  "$JSON_STDOUT" \
  'any(.sources[]; .sourceKey == "src-004-git-default-current" and .status == "current" and .remote.commit == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
   and any(.sources[]; .sourceKey == "src-005-git-default-stale" and .status == "stale" and .remote.commit == "9999999999999999999999999999999999999999")
   and any(.sources[]; .sourceKey == "src-006-git-branch-current" and .status == "current" and .remote.ref == "refs/heads/feature")
   and any(.sources[]; .sourceKey == "src-007-git-branch-stale" and .status == "stale" and .remote.ref == "refs/heads/release")
   and any(.sources[]; .sourceKey == "src-008-git-pinned-shared-stale" and .status == "stale" and .remote.ref == "refs/heads/main" and .packageIds == ["git-shared-alpha", "git-shared-beta"])
   and any(.sources[]; .sourceKey == "src-009-git-tag-current" and .status == "current" and .remote.ref == "refs/tags/v1.2.3" and .remote.commit == "1234123412341234123412341234123412341234")
   and any(.sources[]; .sourceKey == "src-010-git-tag-stale" and .status == "stale" and .remote.ref == "refs/tags/v2.0.0" and .remote.commit == "9999999999999999999999999999999999999999")'

assert_json \
  'git unknown states expose stable reason codes for missing refs, auth failures, and offline failures' \
  "$JSON_STDOUT" \
  'any(.sources[]; .sourceKey == "src-011-git-missing-ref" and .status == "unknown" and .reasonCode == "REF_MISSING")
   and any(.sources[]; .sourceKey == "src-012-git-auth-required" and .status == "unknown" and .reasonCode == "AUTH_REQUIRED")
   and any(.sources[]; .sourceKey == "src-013-git-offline" and .status == "unknown" and .reasonCode == "OFFLINE")'

assert_json \
  'summary counts and warning object shape stay stable when warnings are emitted' \
  "$JSON_STDOUT" \
  '.summary.current == 4 and .summary.stale == 5 and .summary.unknown == 4
   and (.warnings | length) == 9
   and all(.warnings[]; (.code | type) == "string" and (.message | type) == "string" and (.sourceKey | type) == "string" and (.packageIds | type) == "array" and (.detail | type) == "object")'

if ! run_helper text "$FIXTURE_DIR/manifest.ok.json" "$TEXT_STDOUT" "$TEXT_STDERR"; then
  printf 'stdout:\n' >&2
  cat "$TEXT_STDOUT" >&2 || true
  printf 'stderr:\n' >&2
  cat "$TEXT_STDERR" >&2 || true
  fail 'helper should emit status text for the fixture manifest'
fi

assert_contains 'text output lists stale sources before unknown sources' "$TEXT_STDOUT" 'Stale managed package sources (5):'
assert_contains 'text output includes grouped packageIds deterministically for shared sources' "$TEXT_STDOUT" 'git-shared-alpha, git-shared-beta'
assert_contains 'text output includes unknown section with stable reason labels' "$TEXT_STDOUT" 'Unknown managed package sources (4):'

if ! python3 - "$TEXT_STDOUT" <<'PY'
import pathlib
import sys
text = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
stale_index = text.index('Stale managed package sources (5):')
unknown_index = text.index('Unknown managed package sources (4):')
if stale_index >= unknown_index:
    raise SystemExit(1)
PY
then
  printf 'File under test: %s\n' "$TEXT_STDOUT" >&2
  cat "$TEXT_STDOUT" >&2 || true
  fail 'text output ordering should keep stale sources before unknown sources'
else
  printf 'PASS: text output ordering keeps stale sources before unknown sources\n'
fi

if ! run_helper json "$FIXTURE_DIR/manifest.timeout.json" "$TIMEOUT_STDOUT" "$TIMEOUT_STDERR" --per-source-timeout-ms 50 --overall-timeout-ms 500 --max-concurrent-probes 2; then
  printf 'stdout:\n' >&2
  cat "$TIMEOUT_STDOUT" >&2 || true
  printf 'stderr:\n' >&2
  cat "$TIMEOUT_STDERR" >&2 || true
  fail 'helper should allow test overrides for timeout and concurrency settings'
fi

assert_json \
  'manual-mode overrides and timeout reason codes are reflected when provided' \
  "$TIMEOUT_STDOUT" \
  '.settings.perSourceTimeoutMs == 50 and .settings.overallTimeoutMs == 500 and .settings.maxConcurrentProbes == 2 and .summary.unknown == 1 and .sources[0].status == "unknown" and .sources[0].reasonCode == "TIMEOUT"'

STARTUP_STDOUT="$TMP_DIR/startup.json"
STARTUP_STDERR="$TMP_DIR/startup.stderr"
set +e
node "$HELPER_PATH" \
  --manifest "$FIXTURE_DIR/manifest.ok.json" \
  --mode startup \
  --format json \
  --npm-bin "$FIXTURE_DIR/fake-npm" \
  --git-bin "$FIXTURE_DIR/fake-git" \
  >"$STARTUP_STDOUT" 2>"$STARTUP_STDERR"
startup_status=$?
set -e
if [[ "$startup_status" -ne 0 ]]; then
  printf 'stdout:\n' >&2
  cat "$STARTUP_STDOUT" >&2 || true
  printf 'stderr:\n' >&2
  cat "$STARTUP_STDERR" >&2 || true
  fail 'startup mode should succeed with fixture data'
fi

assert_json \
  'startup mode publishes the fixed v1 defaults' \
  "$STARTUP_STDOUT" \
  '.mode == "startup" and .settings.perSourceTimeoutMs == 2000 and .settings.overallTimeoutMs == 4000 and .settings.maxConcurrentProbes == 4'

set +e
node "$HELPER_PATH" \
  --manifest "$FIXTURE_DIR/does-not-exist.json" \
  --mode manual \
  --format json \
  --npm-bin "$FIXTURE_DIR/fake-npm" \
  --git-bin "$FIXTURE_DIR/fake-git" \
  >"$MISSING_STDOUT" 2>"$MISSING_STDERR"
missing_status=$?
set -e
assert_exit_code 'missing manifest exits 2' 2 "$missing_status"
assert_contains 'missing manifest reports the missing input path' "$MISSING_STDERR" 'manifest file does not exist'

set +e
node "$HELPER_PATH" \
  --manifest "$FIXTURE_DIR/manifest.malformed.json" \
  --mode manual \
  --format json \
  --npm-bin "$FIXTURE_DIR/fake-npm" \
  --git-bin "$FIXTURE_DIR/fake-git" \
  >"$MALFORMED_STDOUT" 2>"$MALFORMED_STDERR"
malformed_status=$?
set -e
assert_exit_code 'malformed manifest exits 3' 3 "$malformed_status"
assert_contains 'malformed manifest reports a contract failure' "$MALFORMED_STDERR" 'malformed install-state contract'

if ! PI_UPDATE_CHECKER_INSTALL_STATE_FILE="$FIXTURE_DIR/manifest.ok.json" \
  PI_UPDATE_CHECKER_NIX_FILE="$UPDATE_FIXTURE_PATH" \
  PI_UPDATE_CHECKER_HELPER="$HELPER_PATH" \
  PI_UPDATE_CHECKER_NODE_BIN="node" \
  PI_UPDATE_CHECKER_NPM_BIN="$FIXTURE_DIR/fake-npm" \
  PI_UPDATE_CHECKER_GIT_BIN="$FIXTURE_DIR/fake-git" \
  PI_UPDATE_CHECKER_PYTHON_BIN="python3" \
  "$CHECK_UPDATES_PATH" --dry-run >"$CHECK_STDOUT" 2>"$CHECK_STDERR"; then
  printf 'stdout:\n' >&2
  cat "$CHECK_STDOUT" >&2 || true
  printf 'stderr:\n' >&2
  cat "$CHECK_STDERR" >&2 || true
  fail 'check-updates --dry-run should succeed for stale and unknown results'
fi

assert_contains 'check-updates dry-run uses the shared status text output' "$CHECK_STDOUT" 'Managed Pi package status'
assert_contains 'check-updates dry-run prints the configured declaration file path' "$CHECK_STDOUT" "$UPDATE_FIXTURE_PATH"
assert_contains 'check-updates dry-run includes grouped git stale results' "$CHECK_STDOUT" 'git-shared-alpha, git-shared-beta'
assert_contains 'check-updates dry-run keeps startup-aligned unknown reasons' "$CHECK_STDOUT" 'AUTH_REQUIRED'
assert_not_contains 'check-updates dry-run no longer emits legacy git manual-update warnings' "$CHECK_STDERR" 'PI_PACKAGE_WARN_GIT_SOURCE_MANUAL_UPDATE'

set +e
PI_UPDATE_CHECKER_INSTALL_STATE_FILE="$FIXTURE_DIR/does-not-exist.json" \
PI_UPDATE_CHECKER_NIX_FILE="$UPDATE_FIXTURE_PATH" \
PI_UPDATE_CHECKER_HELPER="$HELPER_PATH" \
PI_UPDATE_CHECKER_NODE_BIN="node" \
PI_UPDATE_CHECKER_NPM_BIN="$FIXTURE_DIR/fake-npm" \
PI_UPDATE_CHECKER_GIT_BIN="$FIXTURE_DIR/fake-git" \
PI_UPDATE_CHECKER_PYTHON_BIN="python3" \
  "$CHECK_UPDATES_PATH" --dry-run >"$MISSING_STDOUT" 2>"$MISSING_STDERR"
check_missing_status=$?
set -e
assert_exit_code 'check-updates propagates dependency/input failures with exit 2' 2 "$check_missing_status"

set +e
PI_UPDATE_CHECKER_INSTALL_STATE_FILE="$FIXTURE_DIR/manifest.malformed.json" \
PI_UPDATE_CHECKER_NIX_FILE="$UPDATE_FIXTURE_PATH" \
PI_UPDATE_CHECKER_HELPER="$HELPER_PATH" \
PI_UPDATE_CHECKER_NODE_BIN="node" \
PI_UPDATE_CHECKER_NPM_BIN="$FIXTURE_DIR/fake-npm" \
PI_UPDATE_CHECKER_GIT_BIN="$FIXTURE_DIR/fake-git" \
PI_UPDATE_CHECKER_PYTHON_BIN="python3" \
  "$CHECK_UPDATES_PATH" --dry-run >"$MALFORMED_STDOUT" 2>"$MALFORMED_STDERR"
check_malformed_status=$?
set -e
assert_exit_code 'check-updates propagates internal/contract failures with exit 3' 3 "$check_malformed_status"

set +e
PI_UPDATE_CHECKER_INSTALL_STATE_FILE="$FIXTURE_DIR/manifest.update.json" \
PI_UPDATE_CHECKER_NIX_FILE="$UPDATE_TMP" \
PI_UPDATE_CHECKER_HELPER="$HELPER_PATH" \
PI_UPDATE_CHECKER_NODE_BIN="node" \
PI_UPDATE_CHECKER_NPM_BIN="$FIXTURE_DIR/fake-npm" \
PI_UPDATE_CHECKER_GIT_BIN="$FIXTURE_DIR/fake-git" \
PI_UPDATE_CHECKER_PYTHON_BIN="python3" \
PI_UPDATE_CHECKER_ASSUME_YES="1" \
  "$CHECK_UPDATES_PATH" --update >"$CHECK_STDOUT" 2>"$CHECK_STDERR"
update_status=$?
set -e
assert_exit_code 'check-updates --update succeeds for npm declaration rewrites' 0 "$update_status"
assert_contains 'check-updates --update reports npm-only rewrite mode explicitly' "$CHECK_STDOUT" 'Update mode rewrites npm declarations only.'
assert_contains 'check-updates --update rewrites the npm version field' "$UPDATE_TMP" 'version = "2.0.0";'
assert_contains 'check-updates --update rewrites the npm spec field' "$UPDATE_TMP" 'spec = "sample-npm@2.0.0";'
assert_contains 'check-updates --update rewrites the npm installSpec field' "$UPDATE_TMP" 'installSpec = "sample-npm@2.0.0";'
assert_contains 'check-updates --update leaves git declarations untouched' "$UPDATE_TMP" 'spec = "github:example/sample-git#abc123";'
assert_contains 'check-updates --update leaves local declarations untouched' "$UPDATE_TMP" 'spec = "./local-packages/sample-local";'

printf 'managed package status spec ok\n'
