#!/usr/bin/env bash

set -u -o pipefail

readonly STATUS_ENV_VAR='PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH'
readonly SNAPSHOT_TTL_MS=60000

REAL_PI_BIN="${PI_WRAPPER_REAL_PI_BIN:-}"
NODE_BIN="${PI_WRAPPER_NODE_BIN:-node}"
STATUS_HELPER="${PI_WRAPPER_STATUS_HELPER:-}"
MANIFEST_PATH="${PI_WRAPPER_MANIFEST_PATH:-${HOME}/.pi/agent/managed-packages.install-state.json}"
SNAPSHOT_DIR="${PI_WRAPPER_STARTUP_STATUS_DIR:-${HOME}/.pi/agent/startup-status}"
NPM_BIN="${PI_WRAPPER_NPM_BIN:-npm}"
GIT_BIN="${PI_WRAPPER_GIT_BIN:-git}"

clear_startup_status_env() {
  unset PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH || true
}

exec_real_pi() {
  if [[ -z "$REAL_PI_BIN" || ! -x "$REAL_PI_BIN" ]]; then
    printf 'pi wrapper could not execute the real pi binary: %s\n' "${REAL_PI_BIN:-<unset>}" >&2
    exit 127
  fi

  exec "$REAL_PI_BIN" "$@"
}

is_interactive_launch() {
  [[ "$#" -eq 0 ]]
}

compute_expires_at() {
  local created_at="$1"

  "$NODE_BIN" -e '
    const createdAt = process.argv[1];
    const created = new Date(createdAt);
    if (Number.isNaN(created.getTime())) {
      process.exit(1);
    }
    process.stdout.write(new Date(created.getTime() + 60000).toISOString());
  ' "$created_at"
}

generate_launch_id() {
  if [[ -n "${PI_WRAPPER_LAUNCH_ID:-}" ]]; then
    printf '%s\n' "$PI_WRAPPER_LAUNCH_ID"
    return 0
  fi

  if [[ -x "$NODE_BIN" ]]; then
    "$NODE_BIN" -e '
      const { randomUUID } = require("node:crypto");
      process.stdout.write(`launch-${Date.now()}-${randomUUID()}`);
    '
    return 0
  fi

  printf 'launch-%s-%s-%s\n' "$$" "$RANDOM" "$RANDOM"
}

generate_created_at() {
  if [[ -n "${PI_WRAPPER_CREATED_AT:-}" ]]; then
    printf '%s\n' "$PI_WRAPPER_CREATED_AT"
    return 0
  fi

  "$NODE_BIN" -e 'process.stdout.write(new Date().toISOString())'
}

prepare_startup_snapshot() {
  local launch_id created_at expires_at helper_output_path snapshot_tmp_path snapshot_path

  [[ -n "$STATUS_HELPER" && -r "$STATUS_HELPER" ]] || return 1
  [[ -x "$NODE_BIN" ]] || return 1

  mkdir -p "$SNAPSHOT_DIR" || return 1

  launch_id="$(generate_launch_id)" || return 1
  created_at="$(generate_created_at)" || return 1
  expires_at="$(compute_expires_at "$created_at")" || return 1
  helper_output_path="$(mktemp "$SNAPSHOT_DIR/.startup-status-helper.XXXXXX")" || return 1
  snapshot_tmp_path="$(mktemp "$SNAPSHOT_DIR/.startup-status-snapshot.XXXXXX")" || {
    rm -f "$helper_output_path"
    return 1
  }
  snapshot_path="$SNAPSHOT_DIR/${launch_id}.json"

  if ! "$NODE_BIN" "$STATUS_HELPER" \
    --manifest "$MANIFEST_PATH" \
    --mode startup \
    --format json \
    --npm-bin "$NPM_BIN" \
    --git-bin "$GIT_BIN" \
    >"$helper_output_path" 2>/dev/null; then
    rm -f "$helper_output_path" "$snapshot_tmp_path"
    return 1
  fi

  if ! "$NODE_BIN" - "$helper_output_path" "$snapshot_tmp_path" "$launch_id" "$created_at" "$expires_at" <<'NODE'
const fs = require('node:fs');

const [, , inputPath, outputPath, launchId, createdAt, expiresAt] = process.argv;
const raw = fs.readFileSync(inputPath, 'utf8');
const payload = JSON.parse(raw);

if (!payload || typeof payload !== 'object') {
  throw new Error('status payload must be an object');
}

if (payload.schemaVersion !== 1 || payload.mode !== 'startup') {
  throw new Error('status payload must be schemaVersion 1 startup output');
}

payload.launchId = launchId;
payload.createdAt = createdAt;
payload.expiresAt = expiresAt;

fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`);
NODE
  then
    rm -f "$helper_output_path" "$snapshot_tmp_path"
    return 1
  fi

  if ! mv "$snapshot_tmp_path" "$snapshot_path"; then
    rm -f "$helper_output_path" "$snapshot_tmp_path"
    return 1
  fi

  rm -f "$helper_output_path"
  export PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH="$snapshot_path"
  return 0
}

main() {
  if ! is_interactive_launch "$@"; then
    clear_startup_status_env
    exec_real_pi "$@"
  fi

  clear_startup_status_env
  prepare_startup_snapshot || clear_startup_status_env
  exec_real_pi "$@"
}

main "$@"
