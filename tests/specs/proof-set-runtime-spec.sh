#!/usr/bin/env bash
# Verify proof-set runtime snapshot behavior, deterministic output, and environment-failure propagation.
# Requirement: FR-006
#
# The snapshot generator enumerates facades from the filesystem and facade
# manifests (no Pi module import — Pi >=0.80.8 ships as a compiled bundle).
# These cases stub a fake agent directory with real facades, sources, and
# manifests, then assert the generator's snapshot shape, ordering,
# determinism, diagnostics, and environment-failure contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(repo_root)"
PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

assert_equals() {
  local actual="$1" expected="$2" desc="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc (expected: $expected, actual: $actual)"
  fi
}

assert_file_contains() {
  local path="$1" needle="$2" desc="$3"
  if [[ ! -f "$path" ]]; then
    fail "$desc (missing file: $path)"
    return
  fi

  if grep -Fq "$needle" "$path"; then
    pass "$desc"
  else
    fail "$desc (missing: $needle)"
  fi
}

write_fixture() {
  local fixture_path="$1"
  cat >"$fixture_path" <<'EOF'
{
  "schemaVersion": 2,
  "packages": [
    {
      "packageId": "alpha",
      "sourceManifestName": "alpha-manifest",
      "sourceSpec": "alpha@1.0.0",
      "resourceExpectations": {
        "extensions": [
          "./extensions/alpha.ts",
          "./extensions/zeta.ts"
        ],
        "skills": [
          "alpha-skill-a",
          "alpha-skill-z"
        ],
        "themes": []
      }
    },
    {
      "packageId": "beta",
      "sourceManifestName": "beta-manifest",
      "sourceSpec": "beta@2.0.0",
      "resourceExpectations": {
        "extensions": [
          "./extensions/beta.ts"
        ],
        "skills": [],
        "themes": [
          "beta-theme"
        ]
      }
    }
  ]
}
EOF
}

write_theme_override_fixture() {
  local fixture_path="$1"
  cat >"$fixture_path" <<'EOF'
{
  "schemaVersion": 2,
  "packages": [
    {
      "packageId": "beta",
      "sourceManifestName": "beta-manifest",
      "sourceSpec": "beta@2.0.0",
      "resourceExpectations": {
        "extensions": [],
        "skills": [],
        "themes": [
          "beta-theme"
        ]
      }
    }
  ]
}
EOF
}

# Build a fake activated agent directory: real facades with `pi` manifests,
# meta/source.json provenance, _source symlinks into materialized sources,
# and real resource files — the same layout compile-managed-packages.mjs
# produces (and the FS snapshot generator consumes).
prepare_fake_home() {
  local home_dir="$1"
  local agent_dir="$home_dir/.pi/agent"

  mkdir -p "$agent_dir/packages" "$agent_dir/sources"

  mkdir -p \
    "$agent_dir/sources/src-alpha/extensions" \
    "$agent_dir/sources/src-alpha/skills/alpha-skill-a" \
    "$agent_dir/sources/src-alpha/skills/alpha-skill-z" \
    "$agent_dir/sources/src-beta/extensions" \
    "$agent_dir/sources/src-beta/themes"

  printf '// alpha extension\n' >"$agent_dir/sources/src-alpha/extensions/alpha.ts"
  printf '// zeta extension\n' >"$agent_dir/sources/src-alpha/extensions/zeta.ts"
  printf '# alpha skill a\n' >"$agent_dir/sources/src-alpha/skills/alpha-skill-a/SKILL.md"
  printf '# alpha skill z\n' >"$agent_dir/sources/src-alpha/skills/alpha-skill-z/SKILL.md"
  printf '// beta extension\n' >"$agent_dir/sources/src-beta/extensions/beta.ts"
  printf '{ "name": "beta-theme" }\n' >"$agent_dir/sources/src-beta/themes/beta-theme.json"

  mkdir -p "$agent_dir/packages/alpha/meta" "$agent_dir/packages/beta/meta"

  ln -s ../../sources/src-alpha "$agent_dir/packages/alpha/_source"
  ln -s ../../sources/src-beta "$agent_dir/packages/beta/_source"

  cat >"$agent_dir/packages/alpha/package.json" <<'EOF'
{
  "name": "alpha",
  "private": true,
  "version": "0.0.0-generated",
  "pi": {
    "extensions": ["./_source/extensions/alpha.ts", "./_source/extensions/zeta.ts"],
    "skills": ["./_source/skills/alpha-skill-a/SKILL.md", "./_source/skills/alpha-skill-z/SKILL.md"],
    "prompts": [],
    "themes": []
  }
}
EOF

  cat >"$agent_dir/packages/beta/package.json" <<'EOF'
{
  "name": "beta",
  "private": true,
  "version": "0.0.0-generated",
  "pi": {
    "extensions": ["./_source/extensions/beta.ts"],
    "skills": [],
    "prompts": [],
    "themes": ["./_source/themes/beta-theme.json"]
  }
}
EOF

  cat >"$agent_dir/packages/alpha/meta/source.json" <<EOF
{
  "schemaVersion": 1,
  "packageId": "alpha",
  "source": {
    "type": "npm",
    "spec": "alpha@1.0.0",
    "materializedKey": "src-alpha"
  },
  "sourceManifestName": "alpha-manifest",
  "sourceRoot": "$agent_dir/sources/src-alpha",
  "selectedResources": {
    "extensions": ["./extensions/alpha.ts", "./extensions/zeta.ts"],
    "skills": ["alpha-skill-a", "alpha-skill-z"],
    "prompts": [],
    "themes": []
  }
}
EOF

  cat >"$agent_dir/packages/beta/meta/source.json" <<EOF
{
  "schemaVersion": 1,
  "packageId": "beta",
  "source": {
    "type": "npm",
    "spec": "beta@2.0.0",
    "materializedKey": "src-beta"
  },
  "sourceManifestName": "beta-manifest",
  "sourceRoot": "$agent_dir/sources/src-beta",
  "selectedResources": {
    "extensions": ["./extensions/beta.ts"],
    "skills": [],
    "prompts": [],
    "themes": ["beta-theme"]
  }
}
EOF

  write_fake_settings "$agent_dir" 'null'
}

write_fake_settings() {
  local agent_dir="$1" theme="$2"
  cat >"$agent_dir/settings.json" <<EOF
{
  "packages": ["./packages/alpha", "./packages/beta"],
  "theme": ${theme}
}
EOF
}

write_fake_pi_wrapper() {
  local wrapper_prefix="$1" real_pi_binary="$2"

  mkdir -p "$wrapper_prefix/bin"
  cat >"$wrapper_prefix/bin/pi" <<EOF
#!/usr/bin/env bash
export PI_WRAPPER_REAL_PI_BIN="$real_pi_binary"
exit 0
EOF
  chmod +x "$wrapper_prefix/bin/pi"
}

assert_snapshot_case() {
  local label="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local fixture_path="$tmp_dir/proof-set.json"
  local snapshot_a="$tmp_dir/snapshot-a.json"
  local snapshot_b="$tmp_dir/snapshot-b.json"
  local stderr_path="$tmp_dir/stderr.txt"

  prepare_fake_home "$home_dir"
  write_fixture "$fixture_path"

  if HOME="$home_dir" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_a" 2>"$stderr_path"; then
    pass "$label snapshot succeeds"
  else
    fail "$label snapshot succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  if HOME="$home_dir" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_b" 2>>"$stderr_path"; then
    pass "$label repeated snapshot succeeds"
  else
    fail "$label repeated snapshot succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  local snapshot_mode
  snapshot_mode="$(jq -r '.host.snapshotMode' "$snapshot_a")"
  assert_equals "$snapshot_mode" 'fs-manifest' "$label enumerates from the filesystem manifest"

  local configured_ids
  configured_ids="$(jq -r '[.settings.configuredPackages[].packageId] | join(",")' "$snapshot_a")"
  assert_equals "$configured_ids" 'alpha,beta' "$label sorts configured packages deterministically"

  local alpha_extensions
  alpha_extensions="$(jq -r '.proofSet[] | select(.packageId == "alpha") | [.discovered.extensions[].sourceRelativePath] | join(",")' "$snapshot_a")"
  assert_equals "$alpha_extensions" './extensions/alpha.ts,./extensions/zeta.ts' "$label sorts discovered extensions deterministically"

  local alpha_skills
  alpha_skills="$(jq -r '.proofSet[] | select(.packageId == "alpha") | [.discovered.skills[].name] | join(",")' "$snapshot_a")"
  assert_equals "$alpha_skills" 'alpha-skill-a,alpha-skill-z' "$label derives skill names from SKILL.md parents"

  local beta_theme
  beta_theme="$(jq -r '.proofSet[] | select(.packageId == "beta") | [.discovered.themes[].name] | join(",")' "$snapshot_a")"
  assert_equals "$beta_theme" 'beta-theme' "$label derives theme names from manifest paths"

  local alpha_resolved
  alpha_resolved="$(jq -r '.proofSet[] | select(.packageId == "alpha") | .discovered.extensions[0].resolvedPath' "$snapshot_a")"
  if [[ "$alpha_resolved" == *"/sources/src-alpha/extensions/"* ]]; then
    pass "$label resolves facade _source links to source roots"
  else
    fail "$label resolves facade _source links to source roots (got: $alpha_resolved)"
  fi

  local contract_status=0
  bash "$REPO_ROOT/tests/scripts/assert-contract.sh" \
    --fixture "$fixture_path" \
    --snapshot "$snapshot_a" >/dev/null 2>&1 || contract_status=$?
  assert_equals "$contract_status" '0' "$label snapshot satisfies assert-contract"

  if diff -u <(jq -S 'del(.generatedAt)' "$snapshot_a") <(jq -S 'del(.generatedAt)' "$snapshot_b") >/dev/null; then
    pass "$label produces deterministic snapshots across repeated runs"
  else
    fail "$label produces deterministic snapshots across repeated runs"
  fi

  rm -rf "$tmp_dir"
}

assert_wrapped_snapshot_case() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local wrapper_prefix="$tmp_dir/wrapper-prefix"
  local real_pi_prefix="$tmp_dir/real-pi-prefix"
  local fixture_path="$tmp_dir/proof-set.json"
  local snapshot_path="$tmp_dir/snapshot.json"
  local stderr_path="$tmp_dir/stderr.txt"
  local expected_pi_binary="$real_pi_prefix/bin/pi"

  prepare_fake_home "$home_dir"
  write_fixture "$fixture_path"
  mkdir -p "$real_pi_prefix/bin"
  cat >"$expected_pi_binary" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$expected_pi_binary"
  write_fake_pi_wrapper "$wrapper_prefix" "$expected_pi_binary"

  if HOME="$home_dir" PATH="$wrapper_prefix/bin:$PATH" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_path" 2>"$stderr_path"; then
    pass 'Wrapped Pi snapshot succeeds'
  else
    fail "Wrapped Pi snapshot succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  local actual_pi_binary
  actual_pi_binary="$(jq -r '.host.piBinary' "$snapshot_path")"
  assert_equals "$actual_pi_binary" "$expected_pi_binary" 'Wrapped Pi host block reports the unwrapped real Pi binary'

  rm -rf "$tmp_dir"
}

assert_invalid_settings_fails() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local fixture_path="$tmp_dir/proof-set.json"
  local stderr_path="$tmp_dir/stderr.txt"
  local status=0

  prepare_fake_home "$home_dir"
  write_fixture "$fixture_path"
  printf 'this is not json\n' >"$home_dir/.pi/agent/settings.json"

  if HOME="$home_dir" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >/dev/null 2>"$stderr_path"; then
    status=0
  else
    status=$?
  fi

  assert_equals "$status" '2' 'Invalid settings.json exits with environment failure'
  assert_file_contains "$stderr_path" 'Unable to read Pi settings' 'Invalid settings.json reports an explicit error'

  rm -rf "$tmp_dir"
}

assert_non_array_packages_fails() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local fixture_path="$tmp_dir/proof-set.json"
  local stderr_path="$tmp_dir/stderr.txt"
  local status=0

  prepare_fake_home "$home_dir"
  write_fixture "$fixture_path"
  printf '{ "packages": "nope" }\n' >"$home_dir/.pi/agent/settings.json"

  if HOME="$home_dir" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >/dev/null 2>"$stderr_path"; then
    status=0
  else
    status=$?
  fi

  assert_equals "$status" '2' 'Non-array settings packages exits with environment failure'
  assert_file_contains "$stderr_path" 'packages must be an array' 'Non-array settings packages reports an explicit error'

  rm -rf "$tmp_dir"
}

assert_missing_resource_surfaces_diagnostics() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local fixture_path="$tmp_dir/proof-set.json"
  local snapshot_path="$tmp_dir/snapshot.json"
  local stderr_path="$tmp_dir/stderr.txt"
  local contract_status=0

  prepare_fake_home "$home_dir"
  write_fixture "$fixture_path"
  rm "$home_dir/.pi/agent/sources/src-alpha/extensions/zeta.ts"

  if HOME="$home_dir" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_path" 2>"$stderr_path"; then
    pass 'Missing resource snapshot still succeeds'
  else
    fail "Missing resource snapshot still succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  local alpha_diag_count
  alpha_diag_count="$(jq -r '[.proofSet[] | select(.packageId == "alpha") | .diagnostics.extensions[]?] | length' "$snapshot_path")"
  assert_equals "$alpha_diag_count" '1' 'Missing extension surfaces a per-package diagnostic'

  local diag_message
  diag_message="$(jq -r '.proofSet[] | select(.packageId == "alpha") | .diagnostics.extensions[0].message' "$snapshot_path")"
  if [[ "$diag_message" == *"zeta.ts"* ]]; then
    pass 'Missing extension diagnostic names the missing resource'
  else
    fail "Missing extension diagnostic names the missing resource (got: $diag_message)"
  fi

  bash "$REPO_ROOT/tests/scripts/assert-contract.sh" \
    --fixture "$fixture_path" \
    --snapshot "$snapshot_path" >/dev/null 2>&1 || contract_status=$?
  assert_equals "$contract_status" '1' 'Missing resource fails the assert-contract gate'

  rm -rf "$tmp_dir"
}

assert_theme_override_collision_preserves_proof_theme() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local fixture_path="$tmp_dir/proof-set.json"
  local snapshot_path="$tmp_dir/snapshot.json"
  local stderr_path="$tmp_dir/stderr.txt"
  local contract_stdout="$tmp_dir/assert-stdout.txt"
  local contract_stderr="$tmp_dir/assert-stderr.txt"
  local contract_status=0

  prepare_fake_home "$home_dir"
  write_theme_override_fixture "$fixture_path"

  # A local (top-level) theme with the same name as the proof-set package
  # theme: the snapshot must still discover the package theme and must not
  # emit a local-theme-override warning for a proof-set theme.
  mkdir -p "$home_dir/.pi/agent/themes"
  printf '{ "name": "beta-theme" }\n' >"$home_dir/.pi/agent/themes/beta-theme.json"
  write_fake_settings "$home_dir/.pi/agent" '"beta-theme"'

  if HOME="$home_dir" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_path" 2>"$stderr_path"; then
    pass 'Theme override snapshot succeeds'
  else
    fail "Theme override snapshot succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  local beta_themes
  beta_themes="$(jq -r '.proofSet[] | select(.packageId == "beta") | [.discovered.themes[].name] | join(",")' "$snapshot_path")"
  assert_equals "$beta_themes" 'beta-theme' 'Theme override preserves proof-set theme discovery'

  local override_warning_count
  override_warning_count="$(jq -r '[.warnings[] | select(.code == "PI_VERIFY_WARN_LOCAL_THEME_OVERRIDE")] | length' "$snapshot_path")"
  assert_equals "$override_warning_count" '0' 'Theme override does not emit a false local-theme warning'

  local beta_theme_diagnostic_count
  beta_theme_diagnostic_count="$(jq -r '[.proofSet[] | select(.packageId == "beta") | .diagnostics.themes[]?] | length' "$snapshot_path")"
  assert_equals "$beta_theme_diagnostic_count" '0' 'Theme override does not leave per-package theme diagnostics behind'

  if bash "$REPO_ROOT/tests/scripts/assert-contract.sh" \
    --fixture "$fixture_path" \
    --snapshot "$snapshot_path" \
    >"$contract_stdout" 2>"$contract_stderr"; then
    contract_status=0
  else
    contract_status=$?
  fi

  assert_equals "$contract_status" '0' 'Theme override snapshot passes assert-contract helper'
  assert_file_contains "$contract_stdout" 'Pi proof-set contract ok' 'Theme override contract run reports proof-set success'

  rm -rf "$tmp_dir"
}

assert_test_fast_propagates_environment_failures() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local stdout_path="$tmp_dir/stdout.txt"
  local stderr_path="$tmp_dir/stderr.txt"
  local snapshot_stub="$tmp_dir/snapshot-stub.mjs"
  local assert_stub="$tmp_dir/assert-stub.sh"
  local status=0

  mkdir -p "$home_dir"

  cat >"$snapshot_stub" <<'EOF'
console.error('stubbed snapshot failure');
process.exit(2);
EOF

  cat >"$assert_stub" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$assert_stub"

  if HOME="$home_dir" \
    PI_SNAPSHOT_SCRIPT_PATH="$snapshot_stub" \
    PI_ASSERT_CONTRACT_SCRIPT_PATH="$assert_stub" \
    PI_LOAD_SMOKE_COMMAND="true" \
    bash "$REPO_ROOT/tests/test-fast.sh" >"$stdout_path" 2>"$stderr_path"; then
    status=0
  else
    status=$?
  fi

  assert_equals "$status" '2' 'test-fast propagates snapshot environment failures as non-zero exits'

  rm -rf "$tmp_dir"
}

assert_proof_set_excludes_retired_packages() {
  if jq -e '
    [ .packages[].packageId ]
    | all(. != "pi-messenger" and . != "pi-prompt-template-model"
          and . != "pi-ext-review" and . != "pi-interactive-shell")
  ' "$REPO_ROOT/tests/fixtures/proof-set.json" >/dev/null; then
    pass 'Proof set excludes the packages retired with team mode'
  else
    fail 'Proof set excludes the packages retired with team mode'
  fi
}

assert_contract_script_accepts_valid_snapshot_fixture() {
  local stdout_path stderr_path status=0
  stdout_path="$(mktemp)"
  stderr_path="$(mktemp)"

  if bash "$REPO_ROOT/tests/scripts/assert-contract.sh" \
    --fixture "$REPO_ROOT/tests/fixtures/proof-set.json" \
    --snapshot "$REPO_ROOT/tests/spec-fixtures/resource-snapshot.v2.ok.json" \
    >"$stdout_path" 2>"$stderr_path"; then
    status=0
  else
    status=$?
  fi

  assert_equals "$status" '0' 'assert-contract accepts the valid snapshot fixture'
  assert_file_contains "$stdout_path" 'Pi proof-set contract ok' 'assert-contract reports proof-set contract success'

  rm -f "$stdout_path" "$stderr_path"
}

printf 'Proof-set runtime verification\n'
printf '==============================\n\n'

assert_file_contains "$REPO_ROOT/tests/specs/proof-set-runtime-spec.sh" 'Requirement: FR-006' 'Proof-set runtime spec uses the documented requirement citation format'
assert_proof_set_excludes_retired_packages

assert_snapshot_case 'Fake home'
assert_wrapped_snapshot_case
assert_invalid_settings_fails
assert_non_array_packages_fails
assert_missing_resource_surfaces_diagnostics
assert_theme_override_collision_preserves_proof_theme
assert_test_fast_propagates_environment_failures
assert_contract_script_accepts_valid_snapshot_fixture

printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
