#!/usr/bin/env bash
# Verify proof-set runtime namespace resolution, deterministic output, and environment-failure propagation.
# Requirement: FR-006
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

write_theme_collision_fixture() {
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

prepare_fake_home() {
  local home_dir="$1"
  local agent_dir="$home_dir/.pi/agent"

  mkdir -p "$agent_dir/packages" "$agent_dir/sources"
  printf '{}\n' >"$agent_dir/settings.json"

  mkdir -p "$agent_dir/sources/src-alpha" "$agent_dir/sources/src-beta"

  mkdir -p "$agent_dir/packages/alpha/meta" "$agent_dir/packages/beta/meta"

  cat >"$agent_dir/packages/alpha/package.json" <<'EOF'
{ "name": "alpha" }
EOF
  cat >"$agent_dir/packages/beta/package.json" <<'EOF'
{ "name": "beta" }
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
}

write_fake_pi_module() {
  local prefix_dir="$1" namespace="$2"
  local module_root="$prefix_dir/lib/node_modules/$namespace/pi-coding-agent"

  mkdir -p "$prefix_dir/bin" "$module_root/dist"

  cat >"$prefix_dir/bin/pi" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$prefix_dir/bin/pi"

  cat >"$module_root/package.json" <<'EOF'
{ "type": "module" }
EOF

  cat >"$module_root/dist/index.js" <<'EOF'
import path from 'node:path';

function packageRoot(agentDir, packageId) {
  return path.join(agentDir, 'packages', packageId);
}

function sourceRoot(agentDir, materializedKey) {
  return path.join(agentDir, 'sources', materializedKey);
}

function configuredPackage(agentDir, packageId) {
  return {
    source: `./packages/${packageId}`,
    scope: 'user',
    filtered: false,
    installedPath: packageRoot(agentDir, packageId),
  };
}

function extension(packageId, relativePath, tools, commands, flags) {
  return {
    path: path.join(packageRoot(this.agentDir, packageId), '_source', relativePath),
    resolvedPath: path.join('/resolved', packageId, relativePath),
    sourceInfo: { source: `./packages/${packageId}` },
    tools: new Map(tools.map((name) => [name, {}])),
    commands: new Map(commands.map((name) => [name, {}])),
    flags: new Map(flags.map((name) => [name, {}])),
  };
}

function skill(packageId, name) {
  return {
    name,
    filePath: path.join(packageRoot(this.agentDir, packageId), '_source', 'skills', name, 'SKILL.md'),
    sourceInfo: { source: `./packages/${packageId}` },
  };
}

function theme(packageId, name) {
  return {
    name,
    sourcePath: path.join(packageRoot(this.agentDir, packageId), '_source', 'themes', `${name}.json`),
    sourceInfo: { source: `./packages/${packageId}` },
  };
}

export class SettingsManager {
  constructor(cwd, agentDir) {
    this.cwd = cwd;
    this.agentDir = agentDir;
  }

  static create(cwd, agentDir) {
    return new SettingsManager(cwd, agentDir);
  }

  async reload() {}

  getTheme() {
    return null;
  }
}

export class DefaultPackageManager {
  constructor({ agentDir }) {
    this.agentDir = agentDir;
  }

  listConfiguredPackages() {
    return [
      configuredPackage(this.agentDir, 'beta'),
      configuredPackage(this.agentDir, 'alpha'),
    ];
  }
}

export class DefaultResourceLoader {
  constructor({ agentDir }) {
    this.agentDir = agentDir;
  }

  async reload() {}

  getExtensions() {
    return {
      extensions: [
        extension.call(this, 'beta', path.join('extensions', 'beta.ts'), ['tool-b', 'tool-a'], ['cmd-b', 'cmd-a'], ['flag-b', 'flag-a']),
        extension.call(this, 'alpha', path.join('extensions', 'zeta.ts'), ['tool-z', 'tool-a'], ['cmd-z', 'cmd-a'], ['flag-z', 'flag-a']),
        extension.call(this, 'alpha', path.join('extensions', 'alpha.ts'), ['tool-c', 'tool-b'], ['cmd-c', 'cmd-b'], ['flag-c', 'flag-b']),
      ],
      errors: [],
    };
  }

  getSkills() {
    return {
      skills: [
        skill.call(this, 'alpha', 'alpha-skill-z'),
        skill.call(this, 'alpha', 'alpha-skill-a'),
      ],
      diagnostics: [],
    };
  }

  getThemes() {
    return {
      themes: [
        theme.call(this, 'beta', 'beta-theme'),
      ],
      diagnostics: [],
    };
  }
}
EOF
}

write_fake_theme_override_pi_module() {
  local prefix_dir="$1" namespace="$2"
  local module_root="$prefix_dir/lib/node_modules/$namespace/pi-coding-agent"

  mkdir -p "$prefix_dir/bin" "$module_root/dist"

  cat >"$prefix_dir/bin/pi" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$prefix_dir/bin/pi"

  cat >"$module_root/package.json" <<'EOF'
{ "type": "module" }
EOF

  cat >"$module_root/dist/index.js" <<'EOF'
import path from 'node:path';

function packageRoot(agentDir, packageId) {
  return path.join(agentDir, 'packages', packageId);
}

function configuredPackage(agentDir, packageId) {
  return {
    source: `./packages/${packageId}`,
    scope: 'user',
    filtered: false,
    installedPath: packageRoot(agentDir, packageId),
  };
}

export class SettingsManager {
  constructor(cwd, agentDir) {
    this.cwd = cwd;
    this.agentDir = agentDir;
  }

  static create(cwd, agentDir) {
    return new SettingsManager(cwd, agentDir);
  }

  async reload() {}

  getTheme() {
    return 'beta-theme';
  }
}

export class DefaultPackageManager {
  constructor({ agentDir }) {
    this.agentDir = agentDir;
  }

  listConfiguredPackages() {
    return [configuredPackage(this.agentDir, 'beta')];
  }
}

export class DefaultResourceLoader {
  constructor({ agentDir }) {
    this.agentDir = agentDir;
  }

  async reload() {}

  getExtensions() {
    return { extensions: [], errors: [] };
  }

  getSkills() {
    return { skills: [], diagnostics: [] };
  }

  getThemes() {
    const topLevelPath = path.join(this.agentDir, 'themes', 'beta-theme.json');
    const packageThemePath = path.join(packageRoot(this.agentDir, 'beta'), '_source', 'themes', 'beta-theme.json');

    return {
      themes: [
        {
          name: 'beta-theme',
          sourcePath: topLevelPath,
          sourceInfo: {
            path: topLevelPath,
            source: 'auto',
            scope: 'user',
            origin: 'top-level',
            baseDir: this.agentDir,
          },
        },
      ],
      diagnostics: [
        {
          type: 'collision',
          message: 'name "beta-theme" collision',
          path: packageThemePath,
          collision: {
            resourceType: 'theme',
            name: 'beta-theme',
            winnerPath: topLevelPath,
            loserPath: packageThemePath,
          },
        },
      ],
    };
  }
}
EOF
}

assert_snapshot_case() {
  local namespace="$1" label="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local prefix_dir="$tmp_dir/prefix"
  local fixture_path="$tmp_dir/proof-set.json"
  local snapshot_a="$tmp_dir/snapshot-a.json"
  local snapshot_b="$tmp_dir/snapshot-b.json"
  local stderr_path="$tmp_dir/stderr.txt"
  local expected_module_path="$prefix_dir/lib/node_modules/$namespace/pi-coding-agent/dist/index.js"

  prepare_fake_home "$home_dir"
  write_fixture "$fixture_path"
  write_fake_pi_module "$prefix_dir" "$namespace"

  if HOME="$home_dir" PATH="$prefix_dir/bin:$PATH" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_a" 2>"$stderr_path"; then
    pass "$label snapshot succeeds"
  else
    fail "$label snapshot succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  if HOME="$home_dir" PATH="$prefix_dir/bin:$PATH" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_b" 2>>"$stderr_path"; then
    pass "$label repeated snapshot succeeds"
  else
    fail "$label repeated snapshot succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  local actual_module_path
  actual_module_path="$(jq -r '.host.piModulePath' "$snapshot_a")"
  assert_equals "$actual_module_path" "$expected_module_path" "$label selects the expected Pi module path"

  local configured_ids
  configured_ids="$(jq -r '[.settings.configuredPackages[].packageId] | join(",")' "$snapshot_a")"
  assert_equals "$configured_ids" 'alpha,beta' "$label sorts configured packages deterministically"

  local alpha_extensions
  alpha_extensions="$(jq -r '.proofSet[] | select(.packageId == "alpha") | [.discovered.extensions[].sourceRelativePath] | join(",")' "$snapshot_a")"
  assert_equals "$alpha_extensions" './extensions/alpha.ts,./extensions/zeta.ts' "$label sorts discovered extensions deterministically"

  local alpha_tools
  alpha_tools="$(jq -r '.proofSet[] | select(.packageId == "alpha") | .discovered.extensions[0].tools | join(",")' "$snapshot_a")"
  assert_equals "$alpha_tools" 'tool-b,tool-c' "$label sorts extension tools deterministically"

  if diff -u <(jq -S 'del(.generatedAt)' "$snapshot_a") <(jq -S 'del(.generatedAt)' "$snapshot_b") >/dev/null; then
    pass "$label produces deterministic snapshots across repeated runs"
  else
    fail "$label produces deterministic snapshots across repeated runs"
  fi

  rm -rf "$tmp_dir"
}

assert_missing_module_fails() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local prefix_dir="$tmp_dir/prefix"
  local fixture_path="$tmp_dir/proof-set.json"
  local stdout_path="$tmp_dir/stdout.txt"
  local stderr_path="$tmp_dir/stderr.txt"
  local status=0

  prepare_fake_home "$home_dir"
  write_fixture "$fixture_path"
  mkdir -p "$prefix_dir/bin"
  cat >"$prefix_dir/bin/pi" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$prefix_dir/bin/pi"

  if HOME="$home_dir" PATH="$prefix_dir/bin:$PATH" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$stdout_path" 2>"$stderr_path"; then
    status=0
  else
    status=$?
  fi

  assert_equals "$status" '2' 'Missing Pi module entrypoint exits with environment failure'
  assert_file_contains "$stderr_path" 'Unable to locate Pi module entrypoint' 'Missing Pi module entrypoint reports an explicit error'

  rm -rf "$tmp_dir"
}

assert_theme_override_collision_preserves_proof_theme() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local prefix_dir="$tmp_dir/prefix"
  local fixture_path="$tmp_dir/proof-set.json"
  local snapshot_path="$tmp_dir/snapshot.json"
  local stderr_path="$tmp_dir/stderr.txt"
  local contract_stdout="$tmp_dir/assert-stdout.txt"
  local contract_stderr="$tmp_dir/assert-stderr.txt"
  local contract_status=0

  prepare_fake_home "$home_dir"
  write_theme_collision_fixture "$fixture_path"
  write_fake_theme_override_pi_module "$prefix_dir" '@earendil-works'

  if HOME="$home_dir" PATH="$prefix_dir/bin:$PATH" node "$REPO_ROOT/tests/scripts/resource-snapshot.mjs" --fixture "$fixture_path" >"$snapshot_path" 2>"$stderr_path"; then
    pass 'Theme override collision snapshot succeeds'
  else
    fail "Theme override collision snapshot succeeds (exit $?, stderr: $(cat "$stderr_path"))"
    rm -rf "$tmp_dir"
    return
  fi

  local beta_themes
  beta_themes="$(jq -r '.proofSet[] | select(.packageId == "beta") | [.discovered.themes[].name] | join(",")' "$snapshot_path")"
  assert_equals "$beta_themes" 'beta-theme' 'Theme override collision preserves proof-set theme discovery'

  local override_warning_count
  override_warning_count="$(jq -r '[.warnings[] | select(.code == "PI_VERIFY_WARN_LOCAL_THEME_OVERRIDE")] | length' "$snapshot_path")"
  assert_equals "$override_warning_count" '0' 'Theme override collision does not emit a false local-theme warning'

  local beta_theme_diagnostic_count
  beta_theme_diagnostic_count="$(jq -r '[.proofSet[] | select(.packageId == "beta") | .diagnostics.themes[]?] | length' "$snapshot_path")"
  assert_equals "$beta_theme_diagnostic_count" '0' 'Theme override collision does not leave per-package theme diagnostics behind'

  if bash "$REPO_ROOT/tests/scripts/assert-contract.sh" \
    --fixture "$fixture_path" \
    --snapshot "$snapshot_path" \
    >"$contract_stdout" 2>"$contract_stderr"; then
    contract_status=0
  else
    contract_status=$?
  fi

  assert_equals "$contract_status" '0' 'Theme override collision snapshot passes assert-contract helper'
  assert_file_contains "$contract_stdout" 'Pi proof-set contract ok' 'Theme override collision contract run reports proof-set success'

  rm -rf "$tmp_dir"
}

assert_test_fast_propagates_environment_failures() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local home_dir="$tmp_dir/home"
  local snapshot_stub="$tmp_dir/snapshot-stub.mjs"
  local assert_stub="$tmp_dir/assert-stub.sh"
  local stdout_path="$tmp_dir/stdout.txt"
  local stderr_path="$tmp_dir/stderr.txt"
  local status=0

  mkdir -p "$home_dir/.pi/agent"
  printf '{}\n' >"$home_dir/.pi/agent/settings.json"

  cat >"$snapshot_stub" <<'EOF'
process.exit(2);
EOF

  cat >"$assert_stub" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$assert_stub"

  if HOME="$home_dir" PI_SNAPSHOT_SCRIPT_PATH="$snapshot_stub" PI_ASSERT_CONTRACT_SCRIPT_PATH="$assert_stub" bash "$REPO_ROOT/tests/test-fast.sh" >"$stdout_path" 2>"$stderr_path"; then
    status=0
  else
    status=$?
  fi

  assert_equals "$status" '2' 'test-fast propagates snapshot environment failures as non-zero exits'

  rm -rf "$tmp_dir"
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

assert_snapshot_case '@earendil-works' 'Current namespace'
assert_snapshot_case '@mariozechner' 'Legacy namespace'
assert_missing_module_fails
assert_theme_override_collision_preserves_proof_theme
assert_test_fast_propagates_environment_failures
assert_contract_script_accepts_valid_snapshot_fixture

printf '\n'
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
