#!/usr/bin/env bash
# pi-tasks-bridge-spec.sh — contract for the pi-tasks -> pi-subagents bridge.
#
# Loads nix/modules/pi/extensions/pi-tasks-subagents-bridge/index.ts against
# a fake event bus that plays both sides: pi-tasks (the @tintinweb v2 RPC
# client) and the managed pi-subagents (RPC v1 responder + async-complete
# events). No model, network, or Pi process.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BRIDGE="$REPO_ROOT/nix/modules/pi/extensions/pi-tasks-subagents-bridge/index.ts"

echo "=== pi-tasks bridge spec ==="
command -v node >/dev/null || { echo "  FAIL: node is required"; exit 1; }
[[ -f "$BRIDGE" ]] || { echo "  FAIL: bridge extension missing: $BRIDGE"; exit 1; }

BRIDGE="$BRIDGE" node --experimental-strip-types --no-warnings --input-type=module <<'NODE'
const bridge = await import(process.env.BRIDGE);
const results = [];
const check = (name, ok, detail = "") => results.push({ name, ok: Boolean(ok), detail });

function createBus() {
  const handlers = new Map();
  return {
    on(channel, handler) {
      const list = handlers.get(channel) ?? [];
      list.push(handler);
      handlers.set(channel, list);
      return () => handlers.set(channel, (handlers.get(channel) ?? []).filter((h) => h !== handler));
    },
    emit(channel, data) {
      for (const handler of [...(handlers.get(channel) ?? [])]) handler(data);
    },
  };
}

// Fake managed pi-subagents v1 responder.
function installV1(bus, { spawnReply, stopReply } = {}) {
  const calls = [];
  bus.on("subagents:rpc:v1:request", (req) => {
    calls.push(req);
    const send = (body) => bus.emit(`subagents:rpc:v1:reply:${req.requestId}`, { version: 1, requestId: req.requestId, method: req.method, ...body });
    if (req.version !== 1) return send({ success: false, error: { code: "unsupported_version", message: "bad version" } });
    if (req.method === "ping") return send({ success: true, data: { version: 1 } });
    if (req.method === "spawn") return send(spawnReply ?? { success: true, data: { text: "started", details: { asyncId: "run-123", runId: "run-123" } } });
    if (req.method === "stop") return send(stopReply ?? { success: true, data: { state: "stopping" } });
  });
  return calls;
}

// pi-tasks side: v2 request/reply helper with timeout.
function call(bus, channel, params, timeoutMs = 300) {
  const requestId = crypto.randomUUID();
  return new Promise((resolve) => {
    const timer = setTimeout(() => { unsub(); resolve({ timeout: true }); }, timeoutMs);
    const unsub = bus.on(`${channel}:reply:${requestId}`, (reply) => { clearTimeout(timer); unsub(); resolve(reply); });
    bus.emit(channel, { requestId, ...params });
  });
}

function load(bus) {
  bridge.default({ events: bus });
}

// 1. No managed pi-subagents: ping gets no reply (pi-tasks reports unavailable).
{
  const bus = createBus();
  load(bus);
  const reply = await call(bus, "subagents:rpc:ping", {}, 4_500);
  check("ping without pi-subagents stays unanswered", reply.timeout === true, JSON.stringify(reply));
}

// 2. With pi-subagents: ping answers protocol v2.
{
  const bus = createBus();
  installV1(bus);
  load(bus);
  const reply = await call(bus, "subagents:rpc:ping", {});
  check("ping replies protocol v2", reply.success === true && reply.data?.version === 2, JSON.stringify(reply));
}

// 3. Spawn maps type/prompt/options and returns the async run id.
{
  const bus = createBus();
  const calls = installV1(bus);
  load(bus);
  const reply = await call(bus, "subagents:rpc:spawn", {
    type: "general-purpose",
    prompt: "You are executing task #1",
    options: { description: "Task one", isBackground: true, maxTurns: 7, model: "github-copilot/gpt-6-luna" },
  });
  const spawn = calls.find((c) => c.method === "spawn");
  check("spawn replies with the async run id", reply.success === true && reply.data?.id === "run-123", JSON.stringify(reply));
  check(
    "spawn forwards agent alias, task, async, model, and turn budget",
    spawn?.params?.agent === "worker" && spawn.params.task === "You are executing task #1" && spawn.params.async === true
      && spawn.params.model === "github-copilot/gpt-6-luna" && spawn.params.turnBudget?.maxTurns === 7
      && !("description" in spawn.params) && !("isBackground" in spawn.params),
    JSON.stringify(spawn?.params),
  );
  const passthrough = await call(bus, "subagents:rpc:spawn", { type: "oracle", prompt: "p", options: {} });
  const second = calls.filter((c) => c.method === "spawn")[1];
  check("unknown agent types pass through; no model/turnBudget when unset",
    passthrough.success === true && second?.params?.agent === "oracle" && !("model" in second.params) && !("turnBudget" in second.params),
    JSON.stringify(second?.params));
}

// 4. Spawn failures surface as error envelopes.
{
  const bus = createBus();
  installV1(bus, { spawnReply: { success: false, error: { code: "invalid_params", message: "Unknown agent: nope" } } });
  load(bus);
  const failed = await call(bus, "subagents:rpc:spawn", { type: "nope", prompt: "p" });
  check("spawn error propagates", failed.success === false && failed.error.includes("Unknown agent"), JSON.stringify(failed));
  const invalid = await call(bus, "subagents:rpc:spawn", { type: "worker", prompt: "  " });
  check("spawn without a prompt is rejected", invalid.success === false && /prompt/.test(invalid.error), JSON.stringify(invalid));
}

// 5. Stop forwards the run id.
{
  const bus = createBus();
  const calls = installV1(bus);
  load(bus);
  const reply = await call(bus, "subagents:rpc:stop", { agentId: "run-123" });
  const stop = calls.find((c) => c.method === "stop");
  check("stop forwards the run id", reply.success === true && stop?.params?.id === "run-123", JSON.stringify({ reply, stop }));
}

// 6. Completion translation.
{
  const bus = createBus();
  installV1(bus);
  load(bus);
  const seen = [];
  bus.on("subagents:completed", (d) => seen.push(["completed", d]));
  bus.on("subagents:failed", (d) => seen.push(["failed", d]));
  bus.emit("subagent:async-complete", { id: "run-1", success: true, state: "complete", summary: "all done" });
  bus.emit("subagent:async-complete", { id: "run-2", success: false, state: "failed", results: [{ error: "boom" }] });
  bus.emit("subagent:async-complete", { id: "run-3", success: false, state: "stopped", summary: "partial" });
  bus.emit("subagent:async-complete", { runId: "run-4", success: true, results: [{ output: "child output" }] });
  bus.emit("subagent:async-complete", { id: "run-5", success: true, summary: "Workflow completed with 1 child run(s). Return: {...}", results: [{ output: "the answer" }] });
  bus.emit("subagent:async-complete", { success: true });
  const byId = Object.fromEntries(seen.map(([channel, d]) => [d.id, { channel, ...d }]));
  check("success -> subagents:completed with result", byId["run-1"]?.channel === "completed" && byId["run-1"].result === "all done", JSON.stringify(byId["run-1"]));
  check("failure -> subagents:failed with error", byId["run-2"]?.channel === "failed" && byId["run-2"].status === "error" && byId["run-2"].error === "boom", JSON.stringify(byId["run-2"]));
  check("stop -> subagents:failed status stopped keeps partial result", byId["run-3"]?.channel === "failed" && byId["run-3"].status === "stopped" && byId["run-3"].result === "partial", JSON.stringify(byId["run-3"]));
  check("runId fallback and child output", byId["run-4"]?.channel === "completed" && byId["run-4"].result === "child output", JSON.stringify(byId["run-4"]));
  check("child output preferred over the workflow summary", byId["run-5"]?.result === "the answer", JSON.stringify(byId["run-5"]));
  check("completions without an id are ignored", seen.length === 5, String(seen.length));
}

// 7. Ready forwarding.
{
  const bus = createBus();
  load(bus);
  let ready = 0;
  bus.on("subagents:ready", () => ready++);
  bus.emit("subagents:rpc:v1:ready", {});
  check("v1 ready is forwarded as subagents:ready", ready === 1, String(ready));
}

let failed = 0;
for (const r of results) {
  console.log(`  ${r.ok ? "PASS" : "FAIL"}: ${r.name}${r.ok ? "" : ` (${r.detail})`}`);
  if (!r.ok) failed++;
}
console.log(`Results: ${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
NODE
