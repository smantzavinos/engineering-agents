#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node jq python3 >/dev/null

REPO_ROOT="$(repo_root)"
WRAPPER_PATH="$REPO_ROOT/scripts/pi-launch-wrapper.sh"
FIXTURE_DIR="$(tests_dir)/spec-fixtures/pi-startup-wrapper"
REAL_NODE_BIN="$(command -v node)"
RESOLVED_NODE_BIN="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$REAL_NODE_BIN")"
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

assert_not_exists() {
  local description="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    if [[ -f "$path" ]]; then
      printf 'File under test: %s\n' "$path" >&2
      cat "$path" >&2 || true
    fi
    fail "$description"
  else
    printf 'PASS: %s\n' "$description"
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

poison_dir="$TMP_DIR/poison-bin"
mkdir -p "$poison_dir"
cat >"$poison_dir/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${POISON_NODE_MARKER:?POISON_NODE_MARKER is required}"
printf 'poison-node\n' >>"$POISON_NODE_MARKER"
exit 99
EOF
cat >"$poison_dir/pi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${POISON_PI_MARKER:?POISON_PI_MARKER is required}"
printf 'poison-pi\n' >>"$POISON_PI_MARKER"
exit 98
EOF
chmod +x "$poison_dir/node" "$poison_dir/pi"

run_wrapper() {
  local home_dir="$1"
  local helper_mode="$2"
  local real_log="$3"
  local helper_log="$4"
  local stdout_path="$5"
  local stderr_path="$6"
  local poison_node_marker="$7"
  local poison_pi_marker="$8"
  shift 8

  set +e
  HOME="$home_dir" \
  PATH="$poison_dir:$PATH" \
  FAKE_REAL_PI_LOG="$real_log" \
  FAKE_STATUS_HELPER_LOG="$helper_log" \
  FAKE_STATUS_HELPER_MODE="$helper_mode" \
  POISON_NODE_MARKER="$poison_node_marker" \
  POISON_PI_MARKER="$poison_pi_marker" \
  PI_WRAPPER_REAL_PI_BIN="$FIXTURE_DIR/fake-real-pi.sh" \
  PI_WRAPPER_NODE_BIN="$REAL_NODE_BIN" \
  PI_WRAPPER_STATUS_HELPER="$FIXTURE_DIR/fake-status-helper.mjs" \
  PI_WRAPPER_MANIFEST_PATH="$FIXTURE_DIR/manifest.ok.json" \
  "$WRAPPER_PATH" "$@" >"$stdout_path" 2>"$stderr_path"
  local status=$?
  set -e

  return "$status"
}

SUCCESS_HOME="$TMP_DIR/home-success"
mkdir -p "$SUCCESS_HOME"
SUCCESS_STDOUT="$TMP_DIR/success.out"
SUCCESS_STDERR="$TMP_DIR/success.err"
SUCCESS_REAL_LOG="$TMP_DIR/success-real-pi.log"
SUCCESS_HELPER_LOG="$TMP_DIR/success-helper.log"
SUCCESS_NODE_MARKER="$TMP_DIR/success-poison-node.log"
SUCCESS_PI_MARKER="$TMP_DIR/success-poison-pi.log"

if ! PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH="$TMP_DIR/stale.json" \
  PI_WRAPPER_LAUNCH_ID='launch-fixture-001' \
  PI_WRAPPER_CREATED_AT='2026-05-19T12:00:00.000Z' \
  run_wrapper "$SUCCESS_HOME" success "$SUCCESS_REAL_LOG" "$SUCCESS_HELPER_LOG" "$SUCCESS_STDOUT" "$SUCCESS_STDERR" "$SUCCESS_NODE_MARKER" "$SUCCESS_PI_MARKER"; then
  printf 'stdout:\n' >&2
  cat "$SUCCESS_STDOUT" >&2 || true
  printf 'stderr:\n' >&2
  cat "$SUCCESS_STDERR" >&2 || true
  fail 'wrapper should exec the injected real pi binary for interactive startup'
fi

assert_not_exists 'wrapper does not resolve node from poisoned PATH' "$SUCCESS_NODE_MARKER"
assert_not_exists 'wrapper does not rediscover pi from poisoned PATH' "$SUCCESS_PI_MARKER"
assert_contains 'interactive launch invokes the injected real pi binary' "$SUCCESS_REAL_LOG" 'argc=0'
assert_contains 'interactive launch exports a startup snapshot path to the child pi process' "$SUCCESS_REAL_LOG" 'startup_status_path='
assert_json \
  'interactive launch invokes the helper through the injected absolute node/helper paths with startup-mode arguments' \
  "$SUCCESS_HELPER_LOG" \
  '.execPath == "'"$RESOLVED_NODE_BIN"'" and .argv[0] == "'"$FIXTURE_DIR/fake-status-helper.mjs"'" and (.argv | index("--mode")) != null and (.argv | index("startup")) != null and (.argv | index("--format")) != null and (.argv | index("json")) != null and (.argv | index("--manifest")) != null and (.argv | index("'"$FIXTURE_DIR/manifest.ok.json"'")) != null'

SUCCESS_SNAPSHOT_PATH="$(grep '^startup_status_path=' "$SUCCESS_REAL_LOG" | sed 's/^startup_status_path=//')"
assert_json \
  'interactive launch snapshot includes launch metadata with a 60s expiry window' \
  "$SUCCESS_SNAPSHOT_PATH" \
  '.schemaVersion == 1 and .mode == "startup" and .launchId == "launch-fixture-001" and .createdAt == "2026-05-19T12:00:00.000Z" and .expiresAt == "2026-05-19T12:01:00.000Z"'
assert_json \
  'interactive launch writes snapshots under the startup-status directory and preserves helper payload fields' \
  "$SUCCESS_SNAPSHOT_PATH" \
  '.generatedAt == "2026-05-19T12:00:00.000Z" and (.warnings | length) == 1 and (.summary.stale == 1)'

NONINTERACTIVE_FORMS=(
  '-h'
  '--help'
  'help'
  '-v'
  '--version'
  'version'
  'list'
  '.'
  'chat'
)

for form in "${NONINTERACTIVE_FORMS[@]}"; do
  run_id="$(printf '%s' "$form" | tr '/ .' '___')"
  home_dir="$TMP_DIR/home-skip-$run_id"
  mkdir -p "$home_dir"
  real_log="$TMP_DIR/skip-$run_id-real-pi.log"
  helper_log="$TMP_DIR/skip-$run_id-helper.log"
  stdout_path="$TMP_DIR/skip-$run_id.out"
  stderr_path="$TMP_DIR/skip-$run_id.err"
  poison_node_marker="$TMP_DIR/skip-$run_id-poison-node.log"
  poison_pi_marker="$TMP_DIR/skip-$run_id-poison-pi.log"

  set +e
  HOME="$home_dir" \
  PATH="$poison_dir:$PATH" \
  FAKE_REAL_PI_LOG="$real_log" \
  FAKE_STATUS_HELPER_LOG="$helper_log" \
  FAKE_STATUS_HELPER_MODE='success' \
  POISON_NODE_MARKER="$poison_node_marker" \
  POISON_PI_MARKER="$poison_pi_marker" \
  PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH="$TMP_DIR/stale-$run_id.json" \
  PI_WRAPPER_REAL_PI_BIN="$FIXTURE_DIR/fake-real-pi.sh" \
  PI_WRAPPER_NODE_BIN="$REAL_NODE_BIN" \
  PI_WRAPPER_STATUS_HELPER="$FIXTURE_DIR/fake-status-helper.mjs" \
  PI_WRAPPER_MANIFEST_PATH="$FIXTURE_DIR/manifest.ok.json" \
  "$WRAPPER_PATH" "$form" >"$stdout_path" 2>"$stderr_path"
  skip_status=$?
  set -e

  assert_exit_code "argv-bearing invocation '$form' still execs the real pi binary" 0 "$skip_status"
  assert_contains "argv-bearing invocation '$form' clears the startup-status env var" "$real_log" 'startup_status_path=<unset>'
  assert_not_exists "argv-bearing invocation '$form' skips the status helper" "$helper_log"
  assert_not_exists "argv-bearing invocation '$form' does not resolve node from poisoned PATH" "$poison_node_marker"
  assert_not_exists "argv-bearing invocation '$form' does not recurse into pi from poisoned PATH" "$poison_pi_marker"

  if find "$home_dir/.pi/agent/startup-status" -name '*.json' -print -quit 2>/dev/null | grep -q .; then
    fail "argv-bearing invocation '$form' should not leave startup snapshots behind"
  else
    printf "PASS: argv-bearing invocation '%s' leaves no startup snapshots behind\n" "$form"
  fi
done

for helper_mode in nonzero malformed; do
  run_id="$helper_mode"
  home_dir="$TMP_DIR/home-$run_id"
  mkdir -p "$home_dir"
  real_log="$TMP_DIR/$run_id-real-pi.log"
  helper_log="$TMP_DIR/$run_id-helper.log"
  stdout_path="$TMP_DIR/$run_id.out"
  stderr_path="$TMP_DIR/$run_id.err"
  poison_node_marker="$TMP_DIR/$run_id-poison-node.log"
  poison_pi_marker="$TMP_DIR/$run_id-poison-pi.log"

  if ! PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH="$TMP_DIR/stale-$run_id.json" \
    run_wrapper "$home_dir" "$helper_mode" "$real_log" "$helper_log" "$stdout_path" "$stderr_path" "$poison_node_marker" "$poison_pi_marker"; then
    printf 'stdout:\n' >&2
    cat "$stdout_path" >&2 || true
    printf 'stderr:\n' >&2
    cat "$stderr_path" >&2 || true
    fail "wrapper should fail open and still exec the real pi binary when helper mode is $helper_mode"
  fi

  assert_contains "helper mode '$helper_mode' still execs the real pi binary" "$real_log" 'argc=0'
  assert_contains "helper mode '$helper_mode' clears the startup-status env var before exec" "$real_log" 'startup_status_path=<unset>'
  assert_json "helper mode '$helper_mode' still invokes the helper" "$helper_log" '.argv[0] == "'"$FIXTURE_DIR/fake-status-helper.mjs"'"'

  if find "$home_dir/.pi/agent/startup-status" -name '*.json' -print -quit 2>/dev/null | grep -q .; then
    fail "helper mode '$helper_mode' should leave no snapshot behind"
  else
    printf "PASS: helper mode '%s' leaves no snapshot behind\n" "$helper_mode"
  fi
done

REPEAT_HOME="$TMP_DIR/home-repeat"
mkdir -p "$REPEAT_HOME"
REPEAT_ONE_REAL_LOG="$TMP_DIR/repeat-one-real.log"
REPEAT_ONE_HELPER_LOG="$TMP_DIR/repeat-one-helper.log"
REPEAT_TWO_REAL_LOG="$TMP_DIR/repeat-two-real.log"
REPEAT_TWO_HELPER_LOG="$TMP_DIR/repeat-two-helper.log"

if ! run_wrapper "$REPEAT_HOME" success "$REPEAT_ONE_REAL_LOG" "$REPEAT_ONE_HELPER_LOG" "$TMP_DIR/repeat-one.out" "$TMP_DIR/repeat-one.err" "$TMP_DIR/repeat-one-poison-node.log" "$TMP_DIR/repeat-one-poison-pi.log"; then
  fail 'first repeated interactive launch should succeed'
fi
if ! run_wrapper "$REPEAT_HOME" success "$REPEAT_TWO_REAL_LOG" "$REPEAT_TWO_HELPER_LOG" "$TMP_DIR/repeat-two.out" "$TMP_DIR/repeat-two.err" "$TMP_DIR/repeat-two-poison-node.log" "$TMP_DIR/repeat-two-poison-pi.log"; then
  fail 'second repeated interactive launch should succeed'
fi

REPEAT_ONE_SNAPSHOT="$(grep '^startup_status_path=' "$REPEAT_ONE_REAL_LOG" | sed 's/^startup_status_path=//')"
REPEAT_TWO_SNAPSHOT="$(grep '^startup_status_path=' "$REPEAT_TWO_REAL_LOG" | sed 's/^startup_status_path=//')"

if [[ "$REPEAT_ONE_SNAPSHOT" == "$REPEAT_TWO_SNAPSHOT" ]]; then
  fail 'repeated interactive launches should not reuse a fixed snapshot path'
else
  printf 'PASS: repeated interactive launches get unique snapshot paths\n'
fi

printf 'pi startup wrapper spec ok\n'
