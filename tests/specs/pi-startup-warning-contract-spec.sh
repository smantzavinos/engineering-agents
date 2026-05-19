#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq python3 >/dev/null

REPO_ROOT="$(repo_root)"
README_PATH="$REPO_ROOT/README.md"
TESTS_README_PATH="$REPO_ROOT/tests/README.md"
RUNNER_PATH="$REPO_ROOT/tests/run-tests.sh"
PI_MODULE_PATH="$REPO_ROOT/nix/modules/pi/default.nix"
FLAKE_PATH="$REPO_ROOT/flake.nix"
EXTENSION_PATH="$REPO_ROOT/nix/modules/pi/extensions/startup-staleness-warning/index.ts"
HARNESS_PATH="$REPO_ROOT/tests/scripts/run-startup-warning-extension.mjs"
FIXTURE_DIR="$(tests_dir)/spec-fixtures/startup-warning-extension"
CHECK_UPDATES_PATH="$REPO_ROOT/scripts/check-updates.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
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

run_harness() {
  local home_dir="$1"
  local snapshot_path="$2"
  local now_iso="$3"
  local output_path="$4"

  set +e
  HOME="$home_dir" \
  PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH="$snapshot_path" \
  node "$HARNESS_PATH" \
    --extension "$EXTENSION_PATH" \
    --home "$home_dir" \
    --now "$now_iso" \
    >"$output_path"
  local status=$?
  set -e

  return "$status"
}

HARNESS_HOME="$TMP_DIR/home"
HARNESS_SNAPSHOT_DIR="$HARNESS_HOME/.pi/agent/startup-status"
HARNESS_SNAPSHOT="$HARNESS_SNAPSHOT_DIR/launch.json"
HARNESS_OUTPUT="$TMP_DIR/harness.json"
HELP_OUTPUT="$TMP_DIR/check-updates-help.txt"
mkdir -p "$HARNESS_SNAPSHOT_DIR"
cp "$FIXTURE_DIR/snapshot.valid.json" "$HARNESS_SNAPSHOT"

if ! run_harness "$HARNESS_HOME" "$HARNESS_SNAPSHOT" '2026-05-19T12:00:30.000Z' "$HARNESS_OUTPUT"; then
  fail 'startup warning harness should succeed for the valid snapshot fixture'
fi

assert_json \
  'startup warning output uses managed-scope wording and the documented inspection/apply workflow' \
  "$HARNESS_OUTPUT" \
  '(.notifications | length) == 1
   and (.notifications[0].title == "Managed Pi packages/plugins need attention")
   and (.notifications[0].message | contains("Managed Pi packages/plugins need attention."))
   and (.notifications[0].message | contains("check-updates --dry-run"))
   and (.notifications[0].message | contains("home-manager switch --flake .#<hostname>"))'

if ! "$CHECK_UPDATES_PATH" --help >"$HELP_OUTPUT"; then
  fail 'check-updates --help should succeed'
fi

assert_contains \
  'check-updates help documents dry-run inspection as the supported workflow' \
  "$HELP_OUTPUT" \
  'Run check-updates --dry-run to inspect managed Pi package status.'
assert_contains \
  'check-updates help documents the separate home-manager apply step' \
  "$HELP_OUTPUT" \
  'home-manager switch --flake .#<hostname>'
assert_contains \
  'check-updates help keeps update mode npm-only' \
  "$HELP_OUTPUT" \
  'Rewrite stale npm declarations only; git/local declarations are never rewritten'

assert_contains \
  'flake packaging exposes a dedicated check-updates helper wrapper' \
  "$FLAKE_PATH" \
  'writeShellScriptBin "check-updates"'
assert_contains \
  'packaged check-updates helper delegates to the repo-owned script' \
  "$FLAKE_PATH" \
  'exec ${self}/scripts/check-updates.sh "$@"'
assert_contains \
  'Pi module installs the packaged check-updates helper for repo users' \
  "$PI_MODULE_PATH" \
  'checkUpdatesPkg'

assert_contains \
  'README documents the startup warning inspection/apply workflow' \
  "$README_PATH" \
  'If Pi warns that managed packages/plugins need attention, run `check-updates --dry-run` to inspect what is stale, then apply your configuration with `home-manager switch --flake .#<hostname>`.'
assert_contains \
  'README keeps direct-cloned installs out of scope for the startup warning' \
  "$README_PATH" \
  'Direct cloned installs such as `agent-kit` and `visual-explainer` are outside this startup-warning scope.'

for spec_name in \
  'managed-package-install-state-spec.sh' \
  'managed-package-status-spec.sh' \
  'pi-startup-wrapper-spec.sh' \
  'startup-warning-extension-spec.sh' \
  'pi-startup-warning-contract-spec.sh'; do
  assert_contains "tests/run-tests.sh includes $spec_name" "$RUNNER_PATH" "$spec_name"
  assert_contains "tests/README.md lists $spec_name" "$TESTS_README_PATH" "$spec_name"
done

printf 'startup warning contract spec ok\n'
