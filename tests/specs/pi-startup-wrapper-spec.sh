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

fake_git_bin="$TMP_DIR/fake-git"
cat >"$fake_git_bin" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$#" -eq 2 && "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
  printf '%s\\n' '$REPO_ROOT'
  exit 0
fi
exit 1
EOF
chmod +x "$fake_git_bin"

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
  PI_WRAPPER_GIT_BIN="$fake_git_bin" \
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
assert_contains 'interactive launch does not export the retired Team profile directory' "$SUCCESS_REAL_LOG" 'team_profile_dir=<unset>'
if grep -Fq 'PI_MESSENGER_TEAM_PROFILE_DIR' "$WRAPPER_PATH"; then
  fail 'wrapper retains retired Team profile environment wiring'
else
  printf 'PASS: wrapper contains no retired Team profile environment wiring\n'
fi
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

# ============================================================
# T3 profile (S12): under T3 (T3_PI_MCP_EXTENSION_PATH set and --mode rpc),
# the wrapper prepends the literal arguments in t3-profile.args (one argument
# per line, read from ${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}) before the
# caller's arguments. Everything else is unchanged.
T3_PROFILE_FIXTURE="$FIXTURE_DIR/t3-profile.args"
mapfile -t T3_PROFILE_ARGS <"$T3_PROFILE_FIXTURE"
if [[ "${#T3_PROFILE_ARGS[@]}" -ne 7 || "${T3_PROFILE_ARGS[0]}" != '-ne' ]]; then
  fail "t3-profile.args fixture must hold seven literal lines starting with -ne"
fi

assert_argv() {
  local description="$1"
  local log_path="$2"
  shift 2
  local expected_path="$TMP_DIR/expected-argv.$RANDOM"
  local actual_path="$TMP_DIR/actual-argv.$RANDOM"

  if [[ "$#" -eq 0 ]]; then
    : >"$expected_path"
  else
    printf '%s\n' "$@" >"$expected_path"
  fi
  sed -n 's/^arg=//p' "$log_path" >"$actual_path"

  if cmp -s "$expected_path" "$actual_path"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'expected argv:\n' >&2
    cat "$expected_path" >&2
    printf 'actual argv:\n' >&2
    cat "$actual_path" >&2
    fail "$description"
  fi
}

# Runs the wrapper with a clean T3/agent-dir environment. $1 HOME, $2 agent dir
# or "" (unset), $3 "t3" to set T3_PI_MCP_EXTENSION_PATH, $4 real-pi log, then
# the wrapper arguments.
run_profile_wrapper() {
  local home_dir="$1" agent_dir="$2" t3_mode="$3" real_log="$4"
  shift 4
  local -a extra_env=()

  if [[ -n "$agent_dir" ]]; then
    extra_env+=(PI_CODING_AGENT_DIR="$agent_dir")
  fi
  if [[ "$t3_mode" == 't3' ]]; then
    extra_env+=(T3_PI_MCP_EXTENSION_PATH="$FIXTURE_DIR/fake-real-pi.sh")
  fi

  env -u PI_CODING_AGENT_DIR -u T3_PI_MCP_EXTENSION_PATH \
    HOME="$home_dir" \
    PATH="$poison_dir:$PATH" \
    FAKE_REAL_PI_LOG="$real_log" \
    PI_WRAPPER_REAL_PI_BIN="$FIXTURE_DIR/fake-real-pi.sh" \
    PI_WRAPPER_NODE_BIN="$REAL_NODE_BIN" \
    "${extra_env[@]}" \
    "$WRAPPER_PATH" "$@" >"$real_log.out" 2>"$real_log.err"
}

PROFILE_AGENT_DIR="$TMP_DIR/profile-agent-dir"
mkdir -p "$PROFILE_AGENT_DIR"
cp "$T3_PROFILE_FIXTURE" "$PROFILE_AGENT_DIR/t3-profile.args"
T3_RPC_ARGS=(--mode rpc --session "$TMP_DIR/t3-session.jsonl" --extension /t3/pi-t3-mcp-extension.ts)

T3_LONG_LOG="$TMP_DIR/t3-long-real.log"
run_profile_wrapper "$TMP_DIR/home-t3-long" "$PROFILE_AGENT_DIR" t3 "$T3_LONG_LOG" "${T3_RPC_ARGS[@]}"
assert_argv \
  'T3 rpc launch puts the T3 profile arguments before the caller arguments' \
  "$T3_LONG_LOG" "${T3_PROFILE_ARGS[@]}" "${T3_RPC_ARGS[@]}"

T3_EQ_LOG="$TMP_DIR/t3-eq-real.log"
run_profile_wrapper "$TMP_DIR/home-t3-eq" "$PROFILE_AGENT_DIR" t3 "$T3_EQ_LOG" \
  --mode=rpc --session "$TMP_DIR/t3-session.jsonl" --extension /t3/pi-t3-mcp-extension.ts
assert_argv \
  'T3 launch with --mode=rpc gets the profile and Pi-compatible mode arguments' \
  "$T3_EQ_LOG" "${T3_PROFILE_ARGS[@]}" "${T3_RPC_ARGS[@]}"

T3_HOME_LOG="$TMP_DIR/t3-home-real.log"
mkdir -p "$TMP_DIR/home-t3-default/.pi/agent"
cp "$T3_PROFILE_FIXTURE" "$TMP_DIR/home-t3-default/.pi/agent/t3-profile.args"
run_profile_wrapper "$TMP_DIR/home-t3-default" "" t3 "$T3_HOME_LOG" "${T3_RPC_ARGS[@]}"
assert_argv \
  'T3 launch reads the profile from $HOME/.pi/agent when PI_CODING_AGENT_DIR is unset' \
  "$T3_HOME_LOG" "${T3_PROFILE_ARGS[@]}" "${T3_RPC_ARGS[@]}"

TERMINAL_LOG="$TMP_DIR/terminal-session-real.log"
run_profile_wrapper "$TMP_DIR/home-terminal" "$PROFILE_AGENT_DIR" t3 "$TERMINAL_LOG" --session "$TMP_DIR/t3-session.jsonl"
assert_argv \
  'non-rpc launch under the T3 environment gets no profile arguments' \
  "$TERMINAL_LOG" --session "$TMP_DIR/t3-session.jsonl"

TERMINAL_NOARGS_LOG="$TMP_DIR/terminal-noargs-real.log"
run_profile_wrapper "$TMP_DIR/home-terminal-noargs" "$PROFILE_AGENT_DIR" t3 "$TERMINAL_NOARGS_LOG"
assert_argv \
  'interactive terminal launch under the T3 environment gets no profile arguments' \
  "$TERMINAL_NOARGS_LOG"

NO_ENV_LOG="$TMP_DIR/no-env-real.log"
run_profile_wrapper "$TMP_DIR/home-no-env" "$PROFILE_AGENT_DIR" "" "$NO_ENV_LOG" "${T3_RPC_ARGS[@]}"
assert_argv \
  'rpc launch without T3_PI_MCP_EXTENSION_PATH gets no profile arguments' \
  "$NO_ENV_LOG" "${T3_RPC_ARGS[@]}"

MISSING_ARGS_DIR="$TMP_DIR/agent-without-profile"
mkdir -p "$MISSING_ARGS_DIR"
MISSING_LOG="$TMP_DIR/missing-args-real.log"
run_profile_wrapper "$TMP_DIR/home-missing-args" "$MISSING_ARGS_DIR" t3 "$MISSING_LOG" "${T3_RPC_ARGS[@]}"
assert_argv \
  'T3 rpc launch with no t3-profile.args file is a no-op' \
  "$MISSING_LOG" "${T3_RPC_ARGS[@]}"

printf 'pi startup wrapper spec ok\n'
