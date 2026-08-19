#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_commands node >/dev/null

REPO_ROOT="$(repo_root)"
export WAVE_MODULE_PATH="$REPO_ROOT/workflows/wave.mjs"

node --input-type=module <<'NODE'
import { pathToFileURL } from "node:url";

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

function equal(description, actual, expected) {
  check(
    description,
    JSON.stringify(actual) === JSON.stringify(expected),
    `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
  );
}

function finish() {
  console.log(`Results: ${pass} passed, ${fail} failed`);
  process.exitCode = fail === 0 ? 0 : 1;
}

let wave;
try {
  wave = await import(pathToFileURL(process.env.WAVE_MODULE_PATH).href);
} catch (error) {
  check(
    "workflows/wave.mjs loads",
    false,
    error?.message ?? String(error),
  );
  finish();
  process.exit();
}

const {
  validateGraph,
  readySet,
  classifyFailure,
  buildWaveScript,
  resolveFenceGroups,
  validateFenceGroups,
  buildGroupScript,
} = wave;
const hasAllExports = [
  validateGraph,
  readySet,
  classifyFailure,
  buildWaveScript,
  resolveFenceGroups,
  validateFenceGroups,
  buildGroupScript,
].every((exported) => typeof exported === "function");
check("wave engine exports validateGraph", typeof validateGraph === "function");
check("wave engine exports readySet", typeof readySet === "function");
check("wave engine exports classifyFailure", typeof classifyFailure === "function");
check("wave engine exports buildWaveScript", typeof buildWaveScript === "function");
check("wave engine exports resolveFenceGroups", typeof resolveFenceGroups === "function");
check("wave engine exports validateFenceGroups", typeof validateFenceGroups === "function");
check("wave engine exports buildGroupScript", typeof buildGroupScript === "function");
if (!hasAllExports) {
  finish();
  process.exit();
}

const validTasks = [
  { id: "foundation", brief: "Create the foundation." },
  { id: "api", brief: "Add the API.", deps: ["foundation"] },
  { id: "ui", brief: "Add the UI.", deps: ["foundation"] },
];

function reportsGraphError(tasks) {
  const errors = validateGraph(tasks);
  return Array.isArray(errors) && errors.length > 0 && errors.every((error) => typeof error === "string");
}

equal("validateGraph accepts a valid graph", validateGraph(validTasks), []);
check(
  "validateGraph rejects duplicate task ids with error strings",
  reportsGraphError([
    { id: "duplicate", brief: "First." },
    { id: "duplicate", brief: "Second." },
  ]),
);
check(
  "validateGraph rejects dependencies on unknown ids with error strings",
  reportsGraphError([{ id: "known", brief: "Known.", deps: ["missing"] }]),
);
check(
  "validateGraph rejects dependency cycles with error strings",
  reportsGraphError([
    { id: "one", brief: "One.", deps: ["two"] },
    { id: "two", brief: "Two.", deps: ["one"] },
  ]),
);
check(
  "validateGraph rejects a task missing id with error strings",
  reportsGraphError([{ brief: "No id." }]),
);
check(
  "validateGraph rejects a task missing brief with error strings",
  reportsGraphError([{ id: "no-brief" }]),
);

const readinessTasks = [
  { id: "first", brief: "First." },
  { id: "blocked", brief: "Blocked.", deps: ["missing-prerequisite"] },
  { id: "third", brief: "Third." },
  { id: "after-first", brief: "After first.", deps: ["first"] },
];

equal(
  "readySet excludes tasks with unmet dependencies and preserves input order",
  readySet(readinessTasks, new Set(), 10).map((task) => task.id),
  ["first", "third"],
);
equal(
  "readySet excludes tasks already done",
  readySet(readinessTasks, new Set(["first"]), 10).map((task) => task.id),
  ["third", "after-first"],
);
equal(
  "readySet truncates the ordered ready tasks to maxWidth",
  readySet(readinessTasks, new Set(), 1).map((task) => task.id),
  ["first"],
);
equal(
  "readySet returns an empty array when everything is done",
  readySet(readinessTasks, new Set(["first", "blocked", "third", "after-first"]), 10),
  [],
);

equal(
  "classifyFailure recognizes acceptance rejection",
  classifyFailure("Acceptance rejected: evidence is incomplete"),
  "acceptance",
);
equal(
  "classifyFailure recognizes an unknown subagent model",
  classifyFailure("Unknown subagent model: unavailable"),
  "model",
);
equal(
  "classifyFailure recognizes a fan-out cap failure",
  classifyFailure("Run fan-out: 64/64 used"),
  "spawn-budget",
);
equal(
  "classifyFailure recognizes a fan-out count over the cap",
  classifyFailure("Run fan-out: 65/64 used"),
  "spawn-budget",
);
equal(
  "classifyFailure does not classify fan-out below the cap as spawn-budget",
  classifyFailure("Run fan-out: 63/64 used"),
  "failure",
);
for (const input of ["ordinary failure", "", null, undefined]) {
  equal(`classifyFailure defaults ${String(input)} to failure`, classifyFailure(input), "failure");
}

const adversarialBrief = 'Payload: "double quote", `backtick`, backslash \\, newline:\n${mustNotInterpolate}';
const waveTasks = [
  { id: "simple", brief: adversarialBrief },
  { id: "complex-ui", brief: "Use the complex UI route.", class: "complex", ui: true },
];
const options = { cheapModel: "cheap-model", strongModel: "strong-model" };
const script = buildWaveScript(waveTasks, options);

check("buildWaveScript returns a string", typeof script === "string");
check("buildWaveScript fans out with runs.all", script.includes("runs.all("));
check("buildWaveScript never uses runs.run", !script.includes("runs.run("));
check("buildWaveScript omits gate configuration", !script.includes("gate:"));
check("buildWaveScript omits turnBudget", !script.includes("turnBudget"));
check("buildWaveScript omits toolBudget", !script.includes("toolBudget"));
check("buildWaveScript omits non-portable async function helpers", !script.includes("async function"));

let parsedScript = true;
try {
  new Function(script);
} catch (error) {
  parsedScript = false;
  console.error(`Script syntax error: ${error.message}`);
}
check("buildWaveScript escapes adversarial task briefs into valid JavaScript", parsedScript);

let children;
try {
  children = new Function("runs", script)({
    all: (emitted) => emitted,
    run: () => {
      throw new Error("runs.run must not be called");
    },
  });
} catch (error) {
  children = undefined;
  console.error(`Script execution error: ${error.message}`);
}
check("buildWaveScript returns its emitted children through runs.all", Array.isArray(children));
if (Array.isArray(children)) {
  equal("buildWaveScript preserves the adversarial brief exactly", children[0]?.task, adversarialBrief);
  check(
    "buildWaveScript gives every child an explicit model",
    children.every((child) => Object.hasOwn(child, "model") && typeof child.model === "string"),
  );
  equal("buildWaveScript routes ordinary tasks to worker with cheapModel", children[0] && {
    agent: children[0].agent,
    model: children[0].model,
  }, { agent: "worker", model: options.cheapModel });
  equal("buildWaveScript routes complex UI tasks to ui-worker with strongModel", children[1] && {
    agent: children[1].agent,
    model: children[1].model,
  }, { agent: "ui-worker", model: options.strongModel });
}

equal(
  "resolveFenceGroups defaults to one group of every task",
  resolveFenceGroups({ tasks: validTasks }),
  [{ id: "all", tasks: ["foundation", "api", "ui"] }],
);
equal(
  "validateFenceGroups accepts omitted groups",
  validateFenceGroups({ tasks: validTasks }),
  [],
);
check(
  "validateFenceGroups rejects a task listed twice",
  validateFenceGroups({
    tasks: validTasks,
    fenceGroups: [
      { id: "a", tasks: ["foundation", "api"] },
      { id: "b", tasks: ["api", "ui"] },
    ],
  }).some((error) => error.includes("api")),
);

const dagTasks = [
  { id: "T1", brief: adversarialBrief, class: "check", writes: ["src/t1.ts"], verify: "true" },
  { id: "T2", brief: "second", deps: ["T1"], class: "contract", testPaths: ["t2.spec.ts"], writes: ["src/t2.ts"], verify: "true" },
  { id: "T3", brief: "third", class: "check", ui: true, writes: ["src/t3.ts"], verify: "true" },
];
const groupScript = buildGroupScript(dagTasks, options);
check("buildGroupScript returns a string", typeof groupScript === "string");
check("buildGroupScript fans out with runs.all", groupScript.includes("runs.all("));
check("buildGroupScript never uses runs.run", !groupScript.includes("runs.run("));
check("buildGroupScript omits gate configuration", !groupScript.includes("gate:"));
check("buildGroupScript omits non-portable async function helpers", !groupScript.includes("async function"));
check("buildGroupScript joins T2 on T1", /p\["T2"\] = p\["T1"\]\.then/.test(groupScript));
check("buildGroupScript launches independent T3 without waiting for T1", /p\["T3"\] = launch/.test(groupScript));
let parsedGroup = true;
try {
  new Function(groupScript);
} catch (error) {
  parsedGroup = false;
  console.error(`Group script syntax error: ${error.message}`);
}
check("buildGroupScript escapes adversarial task briefs into valid JavaScript", parsedGroup);

finish();
NODE
