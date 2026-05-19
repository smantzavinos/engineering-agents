#!/usr/bin/env bash
#
# check-updates.sh - Check or apply registry-backed updates for unified Pi package declarations.
#
# Usage:
#   ./check-updates.sh            # Dry-run (default)
#   ./check-updates.sh --dry-run  # Dry-run explicitly
#   ./check-updates.sh --update   # Apply available npm version updates to pi.nix
#   ./check-updates.sh --help     # Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_FILE="${PI_UPDATE_CHECKER_NIX_FILE:-$SCRIPT_DIR/pi.nix}"
NPM_BIN="${PI_UPDATE_CHECKER_NPM_BIN:-npm}"
PYTHON_BIN="${PI_UPDATE_CHECKER_PYTHON_BIN:-python3}"
ASSUME_YES="${PI_UPDATE_CHECKER_ASSUME_YES:-0}"
UPDATE_MODE=false

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run    Check for managed Pi package updates without modifying pi.nix (default)
  --update     Apply available registry-backed npm version updates to pi.nix
  --help, -h   Show this help message
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

fail_update() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_command() {
  local command_name="$1"

  if [[ "$command_name" == */* ]]; then
    [[ -x "$command_name" ]] || fail_dependency "Missing required command: $command_name"
    return 0
  fi

  command -v "$command_name" >/dev/null 2>&1 || fail_dependency "Missing required command: $command_name"
}

parse_declarations_json() {
  "$PYTHON_BIN" - "$NIX_FILE" <<'PY'
import json
import pathlib
import re
import sys

PACKAGE_START_RE = re.compile(r'^\s*(?:"([^"]+)"|([A-Za-z0-9@._+-]+))\s*=\s*\{\s*(?:#.*)?$')
SOURCE_START_RE = re.compile(r'^\s*source\s*=\s*\{\s*(?:#.*)?$')
FIELD_RE = re.compile(r'^\s*(type|packageName|spec|installSpec|version)\s*=\s*"([^"]*)"\s*;.*$')


def brace_delta(line: str) -> int:
    return line.count('{') - line.count('}')


def unsupported(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(2)


def finalize_package(package: dict) -> dict:
    source = package.get('source', {})
    for field in ('type', 'packageName', 'spec', 'installSpec'):
        value = source.get(field)
        if not isinstance(value, str) or not value:
            unsupported(
                f"unsupported declaration contract: {package['packageId']} is missing source.{field} in piPackages"
            )

    if source['type'] == 'npm':
        version = source.get('version')
        if not isinstance(version, str) or not version:
            unsupported(
                f"unsupported declaration contract: {package['packageId']} is missing source.version for npm source"
            )
        expected_spec = f"{source['packageName']}@{version}"
        if source['spec'] != expected_spec or source['installSpec'] != expected_spec:
            unsupported(
                f"unsupported declaration contract: {package['packageId']} npm source must keep spec/installSpec aligned with source.version"
            )
    elif source['type'] not in ('git', 'local'):
        unsupported(
            f"unsupported declaration contract: {package['packageId']} uses unsupported source.type {source['type']}"
        )

    return package


def parse(path_str: str) -> list[dict]:
    path = pathlib.Path(path_str)
    try:
        lines = path.read_text(encoding='utf-8').splitlines(keepends=True)
    except FileNotFoundError:
        unsupported(f"declaration file does not exist: {path}")

    start_index = None
    for index, line in enumerate(lines):
        if re.match(r'^\s*piPackages\s*=\s*\{\s*(?:#.*)?$', line):
            start_index = index
            break

    if start_index is None:
        unsupported('unsupported declaration contract: expected piPackages attrset')

    packages = []
    pi_depth = brace_delta(lines[start_index])
    current = None
    package_depth = 0
    in_source = False
    source_depth = 0

    for index in range(start_index + 1, len(lines)):
        line = lines[index]
        delta = brace_delta(line)

        if current is None and pi_depth == 1:
            match = PACKAGE_START_RE.match(line)
            if match:
                package_id = match.group(1) or match.group(2)
                current = {
                    'packageId': package_id,
                    'source': {},
                    'lineNumbers': {},
                }
                package_depth = delta
                pi_depth += delta
                if package_depth == 0:
                    packages.append(finalize_package(current))
                    current = None
                if pi_depth == 0:
                    break
                continue

        if current is not None:
            if in_source:
                field_match = FIELD_RE.match(line)
                if field_match:
                    field_name, field_value = field_match.groups()
                    current['source'][field_name] = field_value
                    current['lineNumbers'][field_name] = index
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
                packages.append(finalize_package(current))
                current = None

            pi_depth += delta
            if pi_depth == 0:
                break
            continue

        pi_depth += delta
        if pi_depth == 0:
            break

    if pi_depth != 0 or current is not None:
        unsupported('unsupported declaration contract: unterminated piPackages attrset')

    if not packages:
        unsupported('unsupported declaration contract: piPackages attrset is empty')

    packages.sort(key=lambda package: package['packageId'])
    return packages


print(json.dumps({'packages': parse(sys.argv[1])}))
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

require_command "$NPM_BIN"
require_command "$PYTHON_BIN"

printf 'Managed Pi package update checker\n'
printf 'Declaration file: %s\n\n' "$NIX_FILE"

parsed_json="$(parse_declarations_json)"
mapfile -t package_lines < <(
  "$PYTHON_BIN" - "$parsed_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
for package in payload['packages']:
    source = package['source']
    print('\t'.join([
        package['packageId'],
        source['type'],
        source['packageName'],
        source['spec'],
        source.get('version', ''),
    ]))
PY
)

declare -a updates=()

for line in "${package_lines[@]}"; do
  IFS=$'\t' read -r package_id source_type package_name source_spec current_version <<<"$line"

  case "$source_type" in
    npm)
      latest_version="$("$NPM_BIN" view "$package_name" version 2>/dev/null || true)"
      if [[ -z "$latest_version" ]]; then
        fail_update "failed to query npm version for $package_name"
      fi
      printf '%s (%s): %s -> %s\n' "$package_id" "$package_name" "$current_version" "$latest_version"
      if [[ "$current_version" != "$latest_version" ]]; then
        updates+=("$package_id|$package_name|$current_version|$latest_version")
      fi
      ;;
    git)
      printf '[PI_PACKAGE_WARN_GIT_SOURCE_MANUAL_UPDATE] %s uses git source %s\n' "$package_id" "$source_spec" >&2
      ;;
    local)
      printf '[PI_PACKAGE_WARN_LOCAL_SOURCE_NO_AUTO_UPDATE] %s uses local source %s\n' "$package_id" "$source_spec" >&2
      ;;
    *)
      fail_dependency "unsupported declaration contract: $package_id uses unsupported source.type $source_type"
      ;;
  esac
done

printf '\n'
if [[ ${#updates[@]} -eq 0 ]]; then
  printf 'No registry-backed npm package updates available.\n'
  exit 0
fi

printf 'Registry-backed npm updates available: %d\n' "${#updates[@]}"

if [[ "$UPDATE_MODE" == false ]]; then
  printf 'Run with --update to apply these version changes.\n'
  exit 0
fi

if [[ "$ASSUME_YES" != "1" ]]; then
  read -r -p "Update $NIX_FILE with these versions? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    printf 'Update cancelled.\n'
    exit 0
  fi
fi

updates_json="$(
  "$PYTHON_BIN" - "${updates[@]}" <<'PY'
import json
import sys

updates = []
for raw_line in sys.argv[1:]:
    package_id, package_name, current_version, latest_version = raw_line.split('|')
    updates.append({
        'packageId': package_id,
        'packageName': package_name,
        'currentVersion': current_version,
        'latestVersion': latest_version,
    })
print(json.dumps({'updates': updates}))
PY
)"

apply_updates "$updates_json"
printf 'Updated %s\n' "$NIX_FILE"
