#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node >/dev/null

REPO_ROOT="$(repo_root)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export PLAN_CHECK_REPO_ROOT="$REPO_ROOT"
export PLAN_CHECK_TMP_DIR="$TMP_DIR"

node --input-type=module <<'NODE'
import { mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

let pass = 0;
let fail = 0;

function check(description, condition, detail = "") {
  if (condition) {
    pass += 1;
    console.log(`PASS: ${description}`);
  } else {
    fail += 1;
    console.error(`FAIL: ${description}${detail ? ` (${detail})` : ""}`);
  }
}

function finish() {
  console.log(`Results: ${pass} passed, ${fail} failed`);
  process.exitCode = fail === 0 ? 0 : 1;
}

const repoRoot = process.env.PLAN_CHECK_REPO_ROOT;
const tempDir = process.env.PLAN_CHECK_TMP_DIR;
const checker = join(repoRoot, "tools", "check-plan.mjs");

function task(id, overrides = {}) {
  return {
    id,
    title: `${id} title`,
    brief: `${id} brief`,
    deps: [],
    writes: [`src/${id}.ts`],
    class: "check",
    verify: "node --version",
    ...overrides,
  };
}

function plan(ids) {
  const rows = ids.map((id) => `| ${id} | ${id} task | — | check | \`node --version\` |`);
  return [
    "# Test plan",
    "",
    "## Task Overview",
    "",
    "| ID | Task | Depends on | Class | Verification |",
    "|---:|------|------------|-------|--------------|",
    ...rows,
    "",
  ].join("\n");
}

function fixture(name, { planIds = [], data, planContents, tasksContents } = {}) {
  const directory = join(tempDir, name);
  mkdirSync(directory, { recursive: true });
  if (planContents === null) {
    // explicit: do not create plan.md
  } else if (planContents !== undefined) {
    writeFileSync(join(directory, "plan.md"), planContents);
  } else {
    writeFileSync(join(directory, "plan.md"), plan(planIds));
  }
  if (tasksContents !== undefined) {
    writeFileSync(join(directory, "tasks.json"), tasksContents);
  } else if (data !== undefined) {
    writeFileSync(join(directory, "tasks.json"), `${JSON.stringify(data, null, 2)}\n`);
  }
  return directory;
}

function data(tasks, overrides = {}) {
  return {
    schema: 1,
    maxWidth: 2,
    models: { cheap: "cheap-model", strong: "strong-model" },
    tasks,
    ...overrides,
  };
}

function run(directory, json = true) {
  const args = [checker];
  if (json) args.push("--json");
  args.push(directory);
  return spawnSync(process.execPath, args, { encoding: "utf8" });
}

function parsePayload(result) {
  try {
    return { value: JSON.parse(result.stdout), error: null };
  } catch (error) {
    return { value: null, error: error.message };
  }
}

function expectInvalid(description, directory, identifiers) {
  const result = run(directory);
  check(`${description}: exits one`, result.status === 1, `got ${result.status}`);
  const parsed = parsePayload(result);
  const validPayload = parsed.value
    && typeof parsed.value === "object"
    && Object.keys(parsed.value).sort().join(",") === "errors,ok"
    && parsed.value.ok === false
    && Array.isArray(parsed.value.errors)
    && parsed.value.errors.every((error) => typeof error === "string");
  check(`${description}: --json reports an error object`, validPayload, parsed.error ?? result.stdout);
  const errors = validPayload ? parsed.value.errors.join("\n") : "";
  for (const identifier of identifiers) {
    check(
      `${description}: error mentions ${identifier}`,
      errors.toLowerCase().includes(identifier.toLowerCase()),
      errors || "no reported errors",
    );
  }
}

const validDirectory = fixture("valid", {
  planIds: ["T1"],
  data: data([task("T1", {
    class: "contract",
    testPaths: ["tests/t1.spec.ts"],
  })]),
});
const validJson = run(validDirectory);
check("valid plan exits zero with --json", validJson.status === 0, `got ${validJson.status}`);
const validPayload = parsePayload(validJson);
check(
  "valid plan --json has the exact ok/errors shape",
  validPayload.value !== null
    && Object.keys(validPayload.value).sort().join(",") === "errors,ok"
    && validPayload.value.ok === true
    && Array.isArray(validPayload.value.errors)
    && validPayload.value.errors.length === 0,
  validPayload.error ?? validJson.stdout,
);
const validText = run(validDirectory, false);
check(
  "valid plan text mode exits zero and prints ok",
  validText.status === 0 && /ok/i.test(validText.stdout),
  `status ${validText.status}; stdout ${JSON.stringify(validText.stdout)}`,
);

for (const skill of ["dynamic-create-plan", "dynamic-execute-plan"]) {
  const packagedChecker = join(repoRoot, "dist", "skills", "pi", skill, "tools", "check-plan.mjs");
  const result = spawnSync(process.execPath, [packagedChecker, "--json", validDirectory], {
    cwd: tempDir,
    encoding: "utf8",
  });
  const parsed = parsePayload(result);
  check(
    `${skill} packaged checker runs outside the framework repository`,
    result.status === 0 && parsed.value?.ok === true,
    parsed.error ?? `status ${result.status}; stderr ${result.stderr}`,
  );

  const symlinkedChecker = join(tempDir, `${skill}-check-plan.mjs`);
  symlinkSync(packagedChecker, symlinkedChecker);
  const symlinkedResult = spawnSync(process.execPath, [symlinkedChecker, "--json", validDirectory], {
    cwd: tempDir,
    encoding: "utf8",
  });
  const symlinkedParsed = parsePayload(symlinkedResult);
  check(
    `${skill} checker validates when invoked through a symlink`,
    symlinkedResult.status === 0 && symlinkedParsed.value?.ok === true,
    symlinkedParsed.error ?? `status ${symlinkedResult.status}; stderr ${symlinkedResult.stderr}`,
  );
}

const templateTablesDirectory = fixture("template-tables", {
  planIds: ["T1"],
  planContents: `${plan(["T1"])}\n## Open Questions\n\n| Question | Owner | Due | Status |\n|----------|-------|-----|--------|\n| None | — | — | closed |\n\n## Risks\n\n| Risk | Likelihood | Impact | Mitigation |\n|------|------------|--------|------------|\n| None | low | low | none |\n\n## Decisions\n\n| Decision | Chosen | Rationale | Revisit If |\n|----------|--------|-----------|------------|\n| Mode | dynamic | safe | never |\n\n## Verification Plan\n\n| Command | Scope | When | What it proves |\n|---------|-------|------|----------------|\n| npm test | repo | final | integrity |\n`,
  data: data([task("T1")]),
});
const templateTables = run(templateTablesDirectory);
check(
  "official plan-template tables are not parsed as task IDs",
  templateTables.status === 0,
  `status ${templateTables.status}; stderr ${templateTables.stderr}`,
);

expectInvalid("duplicate task id", fixture("duplicate-id", {
  planIds: ["duplicate"],
  data: data([task("duplicate"), task("duplicate", { title: "second duplicate" })]),
}), ["duplicate"]);
expectInvalid("unknown dependency", fixture("unknown-dependency", {
  planIds: ["known"],
  data: data([task("known", { deps: ["missing-dependency"] })]),
}), ["missing-dependency"]);
expectInvalid("dependency cycle", fixture("cycle", {
  planIds: ["cycle-a", "cycle-b"],
  data: data([
    task("cycle-a", { deps: ["cycle-b"] }),
    task("cycle-b", { deps: ["cycle-a"] }),
  ]),
}), ["cycle-a"]);
expectInvalid("missing task id", fixture("missing-id", {
  data: data([task(undefined, { title: "missing-id-task", brief: "missing-id-task brief" })]),
}), ["id"]);
expectInvalid("missing task brief", fixture("missing-brief", {
  planIds: ["missing-brief"],
  data: data([task("missing-brief", { brief: "" })]),
}), ["missing-brief"]);

expectInvalid("contract task without testPaths", fixture("contract-no-test-paths", {
  planIds: ["contract-no-tests"],
  data: data([task("contract-no-tests", { class: "contract", testPaths: [] })]),
}), ["contract-no-tests"]);

expectInvalid("non-none task without verify", fixture("no-verify", {
  planIds: ["no-verify"],
  data: data([task("no-verify", { verify: "" })]),
}), ["no-verify"]);

expectInvalid("same-wave write collision", fixture("same-wave-collision", {
  planIds: ["writer-a", "writer-b"],
  data: data([
    task("writer-a", { writes: ["src/a.ts"] }),
    task("writer-b", { writes: ["src/a.ts"] }),
  ]),
}), ["src/a.ts"]);
expectInvalid("whole-segment glob overlaps a nested descendant", fixture("glob-descendant-collision", {
  planIds: ["glob-writer", "nested-writer"],
  data: data([
    task("glob-writer", { writes: ["src/components/*"] }),
    task("nested-writer", { writes: ["src/components/menu/item.ts"] }),
  ]),
}), ["src/components"]);
const sequentialWriteDirectory = fixture("different-wave-same-write", {
  planIds: ["writer-a", "writer-b"],
  data: data([
    task("writer-a", { writes: ["src/a.ts"] }),
    task("writer-b", { deps: ["writer-a"], writes: ["src/a.ts"] }),
  ]),
});
const sequentialWrite = run(sequentialWriteDirectory);
const sequentialWritePayload = parsePayload(sequentialWrite);
check(
  "different-wave shared write exits zero",
  sequentialWrite.status === 0,
  `got ${sequentialWrite.status}`,
);
check(
  "different-wave shared write reports ok JSON",
  sequentialWritePayload.value?.ok === true && Array.isArray(sequentialWritePayload.value.errors) && sequentialWritePayload.value.errors.length === 0,
  sequentialWritePayload.error ?? sequentialWrite.stdout,
);

expectInvalid("plan overview id missing from tasks.json", fixture("plan-only-id", {
  planIds: ["present", "plan-only"],
  data: data([task("present")]),
}), ["plan-only"]);
expectInvalid("tasks.json id absent from plan overview", fixture("json-only-id", {
  planIds: [],
  data: data([task("json-only")]),
}), ["json-only"]);

expectInvalid("empty cheap model", fixture("empty-cheap-model", {
  planIds: ["model-task"],
  data: data([task("model-task")], { models: { cheap: "", strong: "strong-model" } }),
}), ["cheap"]);
expectInvalid("empty strong model", fixture("empty-strong-model", {
  planIds: ["model-task"],
  data: data([task("model-task")], { models: { cheap: "cheap-model", strong: "" } }),
}), ["strong"]);

for (const [name, writes, identifier] of [
  ["recursive-glob", ["src/**"], "whole path segment"],
  ["partial-segment-glob", ["src/file*.ts"], "whole path segment"],
  ["parent-write-path", ["../outside"], "repository-relative"],
]) {
  expectInvalid(`unsupported write-set ${name}`, fixture(`writes-${name}`, {
    planIds: [name],
    data: data([task(name, { writes })]),
  }), [identifier]);
}

expectInvalid("invalid class", fixture("invalid-class", {
  planIds: ["invalid-class"],
  data: data([task("invalid-class", { class: "unsupported" })]),
}), ["invalid-class"]);
expectInvalid("unsupported schema", fixture("unsupported-schema", {
  planIds: ["schema-task"],
  data: data([task("schema-task")], { schema: 2 }),
}), ["schema"]);

function expectTextError(description, directory) {
  const result = run(directory, false);
  check(`${description}: exits one`, result.status === 1, `got ${result.status}`);
  check(`${description}: writes a human-readable stderr error without a stack trace`,
    result.stderr.trim().length > 0 && !/\n\s*at\s/.test(result.stderr),
    JSON.stringify(result.stderr),
  );
}

expectTextError("missing plan directory", join(tempDir, "does-not-exist"));
expectTextError("missing plan.md", fixture("missing-plan-md", {
  planContents: null,
  tasksContents: JSON.stringify(data([])),
}));
expectTextError("missing tasks.json", fixture("missing-tasks-json", {
  planContents: plan([]),
}));
expectTextError("malformed tasks.json", fixture("malformed-tasks-json", {
  planIds: [],
  tasksContents: "{ this is not json }\n",
}));

finish();
NODE
