// Bridge pi-tasks' TaskExecute onto the managed pi-subagents package.
//
// pi-tasks drives subagents through the @tintinweb/pi-subagents event-bus
// protocol (v2): `subagents:rpc:{ping,spawn,stop,consume}` requests with
// `<channel>:reply:<requestId>` replies, plus `subagents:ready` and the
// `subagents:completed` / `subagents:failed` lifecycle events. The managed
// pi-subagents (nicobailon) exposes its own RPC instead: requests on
// `subagents:rpc:v1:request` answered on `subagents:rpc:v1:reply:<id>`, and
// async completions on `subagent:async-complete`. This extension translates
// between the two so tasks with an `agentType` can run as managed subagents,
// be tracked, cascade, and report through TaskOutput.
//
// Scope: only the four requests pi-tasks sends. Every TaskExecute spawn is a
// detached async run; completions are translated for every async run (not
// just ones spawned here) so tasks pi-tasks relinks after a reload still
// resolve — pi-tasks ignores ids it does not own. `consume` is acknowledged
// only: pi-subagents delivers its own completion notice regardless.
import { randomUUID } from "node:crypto";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const TASKS_PROTOCOL_VERSION = 2;
const V1 = {
  version: 1,
  request: "subagents:rpc:v1:request",
  reply: (id: string) => `subagents:rpc:v1:reply:${id}`,
  ready: "subagents:rpc:v1:ready",
  asyncComplete: "subagent:async-complete",
};

// pi-tasks' guidance suggests Claude Code agent types; map them onto the
// managed roster. Anything else passes through unchanged.
export const AGENT_TYPE_ALIASES: Record<string, string> = {
  "general-purpose": "worker",
  explore: "researcher",
  plan: "planner",
};

export function resolveAgentType(type: string): string {
  return AGENT_TYPE_ALIASES[type.toLowerCase()] ?? type;
}

type Reply = { success: true; data?: unknown } | { success: false; error: string };
type Events = ExtensionAPI["events"];

export interface SpawnRequest {
  type?: unknown;
  prompt?: unknown;
  options?: { model?: unknown; maxTurns?: unknown } | null;
}

/** Translate a pi-tasks spawn request into pi-subagents RPC v1 spawn params. */
export function toV1SpawnParams(request: SpawnRequest): Record<string, unknown> {
  if (typeof request.type !== "string" || !request.type.trim()) throw new Error("spawn requires an agent type");
  if (typeof request.prompt !== "string" || !request.prompt.trim()) throw new Error("spawn requires a prompt");
  const options = request.options ?? {};
  const params: Record<string, unknown> = {
    agent: resolveAgentType(request.type.trim()),
    task: request.prompt,
    async: true,
  };
  if (typeof options.model === "string" && options.model.trim()) params.model = options.model.trim();
  if (typeof options.maxTurns === "number" && Number.isInteger(options.maxTurns) && options.maxTurns > 0) {
    params.turnBudget = { maxTurns: options.maxTurns };
  }
  return params;
}

/** Translate a pi-subagents async completion into a pi-tasks lifecycle event. */
export function toLifecycleEvent(raw: unknown):
  | { channel: "subagents:completed" | "subagents:failed"; payload: Record<string, unknown> }
  | undefined {
  if (!raw || typeof raw !== "object") return undefined;
  const data = raw as Record<string, unknown>;
  const id = typeof data.id === "string" && data.id ? data.id : typeof data.runId === "string" ? data.runId : undefined;
  if (!id) return undefined;
  const results = Array.isArray(data.results) ? (data.results as Array<Record<string, unknown>>) : [];
  const text = (value: unknown) => (typeof value === "string" && value.trim() ? value : undefined);
  // Prefer the children's own output: for single spawns pi-subagents'
  // summary wraps it in workflow metadata (digests, artifact paths).
  const childOutput = results.map((r) => text(r.output) ?? text(r.summary)).filter(Boolean).join("\n\n");
  const result = childOutput || text(data.summary);
  const state = typeof data.state === "string" ? data.state : undefined;
  if (data.success === true && state !== "stopped" && state !== "paused") {
    return { channel: "subagents:completed", payload: { id, status: "completed", result: result || undefined } };
  }
  const error = text(data.error) ?? results.map((r) => text(r.error)).find(Boolean) ?? state ?? "failed";
  return {
    channel: "subagents:failed",
    payload: { id, status: state === "stopped" ? "stopped" : "error", error, result: result || undefined },
  };
}

function v1Call(events: Events, method: string, params: unknown, timeoutMs: number): Promise<unknown> {
  const requestId = randomUUID();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      unsubscribe?.();
      reject(new Error(`pi-subagents ${method} timed out`));
    }, timeoutMs);
    const unsubscribe = events.on(V1.reply(requestId), (raw: unknown) => {
      clearTimeout(timer);
      unsubscribe?.();
      const reply = raw as { success?: boolean; data?: unknown; error?: { message?: string } };
      if (reply?.success) resolve(reply.data);
      else reject(new Error(reply?.error?.message ?? `pi-subagents ${method} failed`));
    });
    events.emit(V1.request, { version: V1.version, requestId, method, params, source: { extension: "pi-tasks-subagents-bridge" } });
  });
}

export default function piTasksSubagentsBridge(pi: ExtensionAPI): void {
  const events = pi.events;
  const reply = (channel: string, requestId: unknown, body: Reply) => {
    if (typeof requestId === "string" && requestId) events.emit(`${channel}:reply:${requestId}`, body);
  };
  const failure = (error: unknown): Reply => ({ success: false, error: error instanceof Error ? error.message : String(error) });

  // Answer only when the managed pi-subagents answers, so TaskExecute stays
  // "unavailable" (its own message) rather than failing at spawn time.
  events.on("subagents:rpc:ping", async (raw: unknown) => {
    const requestId = (raw as { requestId?: unknown })?.requestId;
    try {
      await v1Call(events, "ping", undefined, 4_000);
      reply("subagents:rpc:ping", requestId, { success: true, data: { version: TASKS_PROTOCOL_VERSION } });
    } catch {
      // No reply: pi-tasks times out and reports subagents as unavailable.
    }
  });

  events.on("subagents:rpc:spawn", async (raw: unknown) => {
    const request = (raw ?? {}) as SpawnRequest & { requestId?: unknown };
    try {
      const data = (await v1Call(events, "spawn", toV1SpawnParams(request), 25_000)) as {
        details?: { asyncId?: unknown; runId?: unknown };
      };
      const id = data?.details?.asyncId ?? data?.details?.runId;
      if (typeof id !== "string" || !id) throw new Error("pi-subagents spawn returned no async run id");
      reply("subagents:rpc:spawn", request.requestId, { success: true, data: { id } });
    } catch (error) {
      reply("subagents:rpc:spawn", request.requestId, failure(error));
    }
  });

  events.on("subagents:rpc:stop", async (raw: unknown) => {
    const request = (raw ?? {}) as { requestId?: unknown; agentId?: unknown };
    try {
      if (typeof request.agentId !== "string" || !request.agentId) throw new Error("stop requires agentId");
      await v1Call(events, "stop", { id: request.agentId }, 8_000);
      reply("subagents:rpc:stop", request.requestId, { success: true });
    } catch (error) {
      reply("subagents:rpc:stop", request.requestId, failure(error));
    }
  });

  events.on("subagents:rpc:consume", (raw: unknown) => {
    reply("subagents:rpc:consume", (raw as { requestId?: unknown })?.requestId, { success: true });
  });

  events.on(V1.asyncComplete, (raw: unknown) => {
    const event = toLifecycleEvent(raw);
    if (event) events.emit(event.channel, event.payload);
  });

  // pi-tasks re-pings on `subagents:ready`.
  events.on(V1.ready, () => events.emit("subagents:ready", {}));
}
