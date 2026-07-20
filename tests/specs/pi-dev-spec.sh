#!/usr/bin/env bash
# Verify repo-local Pi development sandbox isolation and auth-copy behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(repo_root)"
PI_DEV_SCRIPT="$REPO_ROOT/scripts/pi-dev.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$1"
}

assert_file_contains() {
  local description="$1"
  local path="$2"
  local needle="$3"

  if grep -Fq "$needle" "$path"; then
    pass "$description"
  else
    printf 'File under test: %s\n' "$path" >&2
    cat "$path" >&2 || true
    fail "$description"
  fi
}

assert_file_equals() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if cmp -s "$expected" "$actual"; then
    pass "$description"
  else
    fail "$description"
  fi
}

assert_not_exists() {
  local description="$1"
  local path="$2"

  if [[ ! -e "$path" ]]; then
    pass "$description"
  else
    fail "$description"
  fi
}

[[ -x "$PI_DEV_SCRIPT" ]] || fail 'pi-dev script must be executable'

FAKE_ACTIVATION="$TMP_DIR/fake-activation"
FAKE_WRAPPER_ROOT="$TMP_DIR/fake-wrapper"
LOG_PATH="$TMP_DIR/invocations.log"
SOURCE_HOME="$TMP_DIR/source-home"
DEV_ROOT="$TMP_DIR/dev-root"
NO_AUTH_DEV_ROOT="$TMP_DIR/no-auth-dev-root"
mkdir -p "$FAKE_WRAPPER_ROOT/bin" "$SOURCE_HOME/.pi/agent"
printf '{"provider":"test"}\n' >"$SOURCE_HOME/.pi/agent/auth.json"

cat >"$FAKE_ACTIVATION" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'activation HOME=%s XDG_STATE_HOME=%s XDG_CACHE_HOME=%s\n' "$HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" >>"$PI_DEV_TEST_LOG"
mkdir -p "$HOME/.pi/agent"
printf '{}\n' >"$HOME/.pi/agent/settings.json"
EOF
chmod +x "$FAKE_ACTIVATION"

cat >"$FAKE_WRAPPER_ROOT/bin/pi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'pi HOME=%s PI_CODING_AGENT_DIR=%s args=%s\n' "$HOME" "${PI_CODING_AGENT_DIR:-}" "$*" >>"$PI_DEV_TEST_LOG"
EOF
chmod +x "$FAKE_WRAPPER_ROOT/bin/pi"

HOME="$SOURCE_HOME" \
PI_DEV_ROOT="$DEV_ROOT" \
PI_DEV_ALLOW_CUSTOM_ROOT=1 \
PI_DEV_ACTIVATION_PATH="$FAKE_ACTIVATION" \
PI_DEV_WRAPPER_PATH="$FAKE_WRAPPER_ROOT" \
PI_DEV_TEST_LOG="$LOG_PATH" \
"$PI_DEV_SCRIPT" --copy-auth -- --version

assert_file_equals \
  'copy-auth copies the host Pi credentials into the isolated sandbox' \
  "$SOURCE_HOME/.pi/agent/auth.json" \
  "$DEV_ROOT/home/.pi/agent/auth.json"
assert_file_contains \
  'activation runs with the sandbox home directory' \
  "$LOG_PATH" \
  "activation HOME=$DEV_ROOT/home XDG_STATE_HOME=$DEV_ROOT/state XDG_CACHE_HOME=$DEV_ROOT/cache"
assert_file_contains \
  'Pi runs with the sandbox home and agent directory' \
  "$LOG_PATH" \
  "pi HOME=$DEV_ROOT/home PI_CODING_AGENT_DIR=$DEV_ROOT/home/.pi/agent args=--version"

HOME="$SOURCE_HOME" \
PI_DEV_ROOT="$NO_AUTH_DEV_ROOT" \
PI_DEV_ALLOW_CUSTOM_ROOT=1 \
PI_DEV_ACTIVATION_PATH="$FAKE_ACTIVATION" \
PI_DEV_WRAPPER_PATH="$FAKE_WRAPPER_ROOT" \
PI_DEV_TEST_LOG="$LOG_PATH" \
"$PI_DEV_SCRIPT" -- --help

assert_not_exists \
  'the sandbox does not copy credentials unless --copy-auth is requested' \
  "$NO_AUTH_DEV_ROOT/home/.pi/agent/auth.json"

HOME="$SOURCE_HOME" \
PI_DEV_ROOT="$DEV_ROOT" \
PI_DEV_ALLOW_CUSTOM_ROOT=1 \
"$PI_DEV_SCRIPT" --reset

assert_not_exists 'reset removes only the selected Pi development sandbox' "$DEV_ROOT"

printf 'pi-dev spec ok\n'
