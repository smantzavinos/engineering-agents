#!/usr/bin/env bash
#
# check-updates.sh - Inspect managed Pi package freshness or rewrite npm declarations.
#
# Usage:
#   ./check-updates.sh            # Dry-run inspection (default)
#   ./check-updates.sh --dry-run  # Dry-run inspection explicitly
#   ./check-updates.sh --update   # Rewrite stale npm declarations only
#   ./check-updates.sh --help     # Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NIX_FILE="${PI_UPDATE_CHECKER_NIX_FILE:-$REPO_ROOT/nix/modules/pi/default.nix}"
INSTALL_STATE_FILE="${PI_UPDATE_CHECKER_INSTALL_STATE_FILE:-${HOME}/.pi/agent/managed-packages.install-state.json}"
HELPER_PATH="${PI_UPDATE_CHECKER_HELPER:-$REPO_ROOT/nix/modules/pi/check-managed-package-status.mjs}"
NODE_BIN="${PI_UPDATE_CHECKER_NODE_BIN:-node}"
NPM_BIN="${PI_UPDATE_CHECKER_NPM_BIN:-npm}"
GIT_BIN="${PI_UPDATE_CHECKER_GIT_BIN:-git}"
PYTHON_BIN="${PI_UPDATE_CHECKER_PYTHON_BIN:-python3}"
ASSUME_YES="${PI_UPDATE_CHECKER_ASSUME_YES:-0}"
UPDATE_MODE=false

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run    Inspect managed Pi package status without modifying declarations (default)
  --update     Rewrite stale npm declarations only; git/local declarations are never rewritten
  --help, -h   Show this help message

Inspection workflow:
  1. Run check-updates --dry-run to inspect managed Pi package status.
  2. Apply declaration/runtime changes with home-manager switch --flake .#<hostname>.
EOF
}

fail_usage() {
  printf '%s\n' "$1" >&2
  exit 1
}

fail_dependency() {
  printf '%s\n' "$1" >&2
  exit 2
}

require_command() {
  local command_name="$1"

  if [[ "$command_name" == */* ]]; then
    [[ -x "$command_name" ]] || fail_dependency "Missing required command: $command_name"
    return 0
  fi

  command -v "$command_name" >/dev/null 2>&1 || fail_dependency "Missing required command: $command_name"
}

require_readable_file() {
  local file_path="$1"
  [[ -r "$file_path" ]] || fail_dependency "Missing required file: $file_path"
}

run_shared_checker() {
  local output_format="$1"

  "$NODE_BIN" "$HELPER_PATH" \
    --manifest "$INSTALL_STATE_FILE" \
    --mode manual \
    --format "$output_format" \
    --npm-bin "$NPM_BIN" \
    --git-bin "$GIT_BIN"
}

extract_npm_updates_json() {
  local helper_json="$1"

  "$PYTHON_BIN" - "$helper_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
updates = []
for source in payload.get('sources', []):
    if source.get('source', {}).get('type') != 'npm':
        continue
    if source.get('status') != 'stale':
        continue
    latest_version = source.get('latestVersion')
    package_name = source.get('source', {}).get('packageName')
    current_version = source.get('installedVersion')
    for package_id in source.get('packageIds', []):
        updates.append({
            'packageId': package_id,
            'packageName': package_name,
            'currentVersion': current_version,
            'latestVersion': latest_version,
        })

print(json.dumps({'updates': updates}))
PY
}

apply_updates() {
  local updates_json="$1"

  "$PYTHON_BIN" - "$NIX_FILE" "$updates_json" <<'PY'
import json
import pathlib
import re
import sys
import tempfile

PACKAGE_START_RE = re.compile(r'^\s*(?:"([^"]+)"|([A-Za-z0-9@._+-]+))\s*=\s*\{\s*(?:#.*)?$')
SOURCE_START_RE = re.compile(r'^\s*source\s*=\s*\{\s*(?:#.*)?$')
FIELD_RE = re.compile(r'^(\s*)(type|packageName|spec|installSpec|version)(\s*=\s*)"([^"]*)"(\s*;.*)$')


def brace_delta(line: str) -> int:
    return line.count('{') - line.count('}')


def fail(message: str, code: int) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


path = pathlib.Path(sys.argv[1])
updates = json.loads(sys.argv[2])
update_map = {entry['packageId']: entry for entry in updates['updates']}
if not update_map:
    raise SystemExit(0)

try:
    lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
except FileNotFoundError:
    fail(f'declaration file does not exist: {path}', 2)

start_index = None
for index, line in enumerate(lines):
    if re.match(r'^\s*piPackages\s*=\s*\{\s*(?:#.*)?$', line):
        start_index = index
        break

if start_index is None:
    fail('unsupported declaration contract: expected piPackages attrset', 2)

pi_depth = brace_delta(lines[start_index])
current_package_id = None
package_depth = 0
in_source = False
source_depth = 0
source_values = {}
line_numbers = {}
updated_packages = set()

for index in range(start_index + 1, len(lines)):
    line = lines[index]
    delta = brace_delta(line)

    if current_package_id is None and pi_depth == 1:
        match = PACKAGE_START_RE.match(line)
        if match:
            current_package_id = match.group(1) or match.group(2)
            package_depth = delta
            in_source = False
            source_depth = 0
            source_values = {}
            line_numbers = {}
            pi_depth += delta
            if pi_depth == 0:
                break
            continue

    if current_package_id is not None:
        if in_source:
            field_match = FIELD_RE.match(line)
            if field_match:
                _, field_name, _, field_value, _ = field_match.groups()
                source_values[field_name] = field_value
                line_numbers[field_name] = index
            source_depth += delta
            package_depth += delta
            if source_depth == 0:
                in_source = False
        else:
            if SOURCE_START_RE.match(line):
                in_source = True
                source_depth = delta
            package_depth += delta

        if package_depth == 0:
            update = update_map.get(current_package_id)
            if update is not None:
                package_name = source_values.get('packageName')
                current_version = source_values.get('version')
                latest_version = update['latestVersion']
                if not package_name or not current_version:
                    fail(
                        f'unsupported declaration contract: {current_package_id} is missing source.packageName/source.version',
                        2,
                    )
                replacements = {
                    'spec': f'{package_name}@{latest_version}',
                    'installSpec': f'{package_name}@{latest_version}',
                    'version': latest_version,
                }
                for field_name, replacement_value in replacements.items():
                    line_index = line_numbers.get(field_name)
                    if line_index is None:
                        fail(
                            f'unsupported declaration contract: {current_package_id} is missing source.{field_name}',
                            2,
                        )
                    field_match = FIELD_RE.match(lines[line_index])
                    if field_match is None:
                        fail(
                            f'unsupported declaration contract: could not rewrite {current_package_id} source.{field_name}',
                            2,
                        )
                    prefix, _, separator, _, suffix = field_match.groups()
                    lines[line_index] = f'{prefix}{field_name}{separator}"{replacement_value}"{suffix}\n'
                updated_packages.add(current_package_id)
            current_package_id = None
            source_values = {}
            line_numbers = {}

        pi_depth += delta
        if pi_depth == 0:
            break
        continue

    pi_depth += delta
    if pi_depth == 0:
        break

missing = sorted(set(update_map) - updated_packages)
if missing:
    fail(f'failed to update package blocks: {", ".join(missing)}', 1)

try:
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as handle:
        handle.writelines(lines)
        temp_path = pathlib.Path(handle.name)
    temp_path.replace(path)
except OSError as error:
    fail(f'failed to write updated file: {error}', 1)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      UPDATE_MODE=true
      shift
      ;;
    --dry-run)
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail_usage "Unknown option: $1"
      ;;
  esac
done

require_command "$NODE_BIN"
require_readable_file "$HELPER_PATH"
require_command "$NPM_BIN"
require_command "$GIT_BIN"

if [[ "$UPDATE_MODE" == false ]]; then
  helper_text="$(run_shared_checker text)" || exit "$?"
  printf 'Declaration file: %s\n' "$NIX_FILE"
  printf '%s' "$helper_text"
  exit 0
fi

require_command "$PYTHON_BIN"
helper_text="$(run_shared_checker text)" || exit "$?"
helper_json="$(run_shared_checker json)" || exit "$?"
updates_json="$(extract_npm_updates_json "$helper_json")"

printf 'Declaration file: %s\n' "$NIX_FILE"
printf '%s' "$helper_text"
printf 'Update mode rewrites npm declarations only.\n'

if [[ "$ASSUME_YES" != "1" ]]; then
  read -r -p "Rewrite stale npm declarations in $NIX_FILE? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    printf 'Update cancelled.\n'
    exit 0
  fi
fi

if [[ "$updates_json" == '{"updates": []}' ]]; then
  printf 'No stale npm declarations to rewrite.\n'
  exit 0
fi

apply_updates "$updates_json"
printf 'Updated %s\n' "$NIX_FILE"
