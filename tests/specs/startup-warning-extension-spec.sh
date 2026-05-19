#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq python3 >/dev/null

REPO_ROOT="$(repo_root)"
EXTENSION_PATH="$REPO_ROOT/nix/modules/pi/extensions/startup-staleness-warning/index.ts"
HARNESS_PATH="$REPO_ROOT/tests/scripts/run-startup-warning-extension.mjs"
FIXTURE_DIR="$(tests_dir)/spec-fixtures/startup-warning-extension"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
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
  local initial_status="${5:-stale status from prior run}"

  set +e
  HOME="$home_dir" \
  PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH="$snapshot_path" \
  node "$HARNESS_PATH" \
    --extension "$EXTENSION_PATH" \
    --home "$home_dir" \
    --now "$now_iso" \
    --initial-status "$initial_status" \
    >"$output_path"
  local status=$?
  set -e

  return "$status"
}

VALID_HOME="$TMP_DIR/home-valid"
VALID_SNAPSHOT_DIR="$VALID_HOME/.pi/agent/startup-status"
VALID_SNAPSHOT="$VALID_SNAPSHOT_DIR/launch-valid.json"
VALID_OUTPUT="$TMP_DIR/valid.json"
mkdir -p "$VALID_SNAPSHOT_DIR"
cp "$FIXTURE_DIR/snapshot.valid.json" "$VALID_SNAPSHOT"

if ! run_harness "$VALID_HOME" "$VALID_SNAPSHOT" '2026-05-19T12:00:30.000Z' "$VALID_OUTPUT"; then
  fail 'valid startup snapshot should be accepted by the notifier harness'
fi

assert_json \
  'valid snapshot emits a warning notification and footer/status summary' \
  "$VALID_OUTPUT" \
  '(.notifications | length) == 1 and .notifications[0].level == "warning" and (.finalStatus | type) == "string"'

assert_json \
  'valid snapshot renders stale and unknown sections distinctly with deterministic grouped package ids' \
  "$VALID_OUTPUT" \
  '.notifications[0].message | contains("Stale managed package sources (2):")
   and contains("Unknown managed package sources (2):")
   and contains("pi-ext-leader-key, pi-ext-review")
   and contains("pi-gitnexus")'

assert_json \
  'valid snapshot copy stays within managed scope and points to the supported inspection/apply workflow' \
  "$VALID_OUTPUT" \
  '(.notifications[0].message | contains("packages/plugins")
   and contains("check-updates --dry-run")
   and contains("home-manager switch --flake .#<hostname>"))
   and ((.finalStatus | contains("2 stale")) and (.finalStatus | contains("2 unknown")))'

assert_json \
  'valid snapshot is consumed once after rendering' \
  "$VALID_OUTPUT" \
  '.snapshotExistsAfter == false'

REPLAY_OUTPUT="$TMP_DIR/replay.json"
if ! run_harness "$VALID_HOME" "$VALID_SNAPSHOT" '2026-05-19T12:00:35.000Z' "$REPLAY_OUTPUT"; then
  fail 'missing replay snapshot should be ignored after first consumption'
fi

assert_json \
  'consumed snapshot is not shown again and stale footer/status state is cleared' \
  "$REPLAY_OUTPUT" \
  '(.notifications | length) == 0 and .finalStatus == null'

EXPIRED_HOME="$TMP_DIR/home-expired"
EXPIRED_SNAPSHOT_DIR="$EXPIRED_HOME/.pi/agent/startup-status"
EXPIRED_SNAPSHOT="$EXPIRED_SNAPSHOT_DIR/launch-expired.json"
EXPIRED_OUTPUT="$TMP_DIR/expired.json"
mkdir -p "$EXPIRED_SNAPSHOT_DIR"
cp "$FIXTURE_DIR/snapshot.valid.json" "$EXPIRED_SNAPSHOT"

if ! run_harness "$EXPIRED_HOME" "$EXPIRED_SNAPSHOT" '2026-05-19T12:01:01.000Z' "$EXPIRED_OUTPUT"; then
  fail 'expired snapshot should be handled as an ignored no-op'
fi

assert_json \
  'snapshots older than 60s are rejected without notification or stale status replay' \
  "$EXPIRED_OUTPUT" \
  '(.notifications | length) == 0 and .finalStatus == null'

MALFORMED_HOME="$TMP_DIR/home-malformed"
MALFORMED_SNAPSHOT_DIR="$MALFORMED_HOME/.pi/agent/startup-status"
MALFORMED_SNAPSHOT="$MALFORMED_SNAPSHOT_DIR/launch-malformed.json"
MALFORMED_OUTPUT="$TMP_DIR/malformed.json"
mkdir -p "$MALFORMED_SNAPSHOT_DIR"
cp "$FIXTURE_DIR/snapshot.malformed.json" "$MALFORMED_SNAPSHOT"

if ! run_harness "$MALFORMED_HOME" "$MALFORMED_SNAPSHOT" '2026-05-19T12:00:30.000Z' "$MALFORMED_OUTPUT"; then
  fail 'malformed snapshot should be ignored without crashing the notifier harness'
fi

assert_json \
  'malformed snapshots are ignored and clear stale status state' \
  "$MALFORMED_OUTPUT" \
  '(.notifications | length) == 0 and .finalStatus == null'

MISSING_HOME="$TMP_DIR/home-missing"
MISSING_OUTPUT="$TMP_DIR/missing.json"
mkdir -p "$MISSING_HOME/.pi/agent/startup-status"

if ! run_harness "$MISSING_HOME" "$MISSING_HOME/.pi/agent/startup-status/does-not-exist.json" '2026-05-19T12:00:30.000Z' "$MISSING_OUTPUT"; then
  fail 'missing snapshot path should be ignored without crashing the notifier harness'
fi

assert_json \
  'missing snapshots from wrapper fail-open paths are ignored without stale status state' \
  "$MISSING_OUTPUT" \
  '(.notifications | length) == 0 and .finalStatus == null'

UNOWNED_HOME="$TMP_DIR/home-unowned"
UNOWNED_OUTPUT="$TMP_DIR/unowned.json"
UNOWNED_SNAPSHOT="$TMP_DIR/unowned-launch.json"
mkdir -p "$UNOWNED_HOME/.pi/agent/startup-status"
cp "$FIXTURE_DIR/snapshot.valid.json" "$UNOWNED_SNAPSHOT"

if ! run_harness "$UNOWNED_HOME" "$UNOWNED_SNAPSHOT" '2026-05-19T12:00:30.000Z' "$UNOWNED_OUTPUT"; then
  fail 'unowned snapshot path should be ignored without crashing the notifier harness'
fi

assert_json \
  'snapshot files outside the startup-status directory are ignored and clear stale status state' \
  "$UNOWNED_OUTPUT" \
  '(.notifications | length) == 0 and .finalStatus == null and .snapshotExistsAfter == true'

printf 'startup warning extension spec ok\n'
