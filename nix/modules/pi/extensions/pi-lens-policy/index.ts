// Host policy for the managed pi-lens package, applied in-process so it
// holds for every launch path (terminal, Hermes service, subagent children)
// rather than only login shells.
//
// 1. Environment (read lazily by pi-lens, so setting it in this factory is
//    early enough; `??=` keeps an explicit env value as a deliberate
//    per-invocation override):
//    - Language servers and linters come from Nix/PATH; pi-lens must not
//      npm/pip/go-install or download release binaries at runtime.
//    - The global config is the managed, read-only <agentDir>/pi-lens.json.
//      pi-lens never writes its global config.
//    - PI_LENS_HOME pins logs/state to the default ~/.pi-lens. Unset, pi-lens
//      redirects them into <cwd>/.pi-lens-probe-home whenever cwd is under
//      os.tmpdir() or .claude/worktrees/, i.e. into temp worktrees/checkouts.
//    - <agentDir>/pi-lens-tools/bin (Nix-built language servers, linters,
//      scanners; see pi-lens-tools.nix) is APPENDED to PATH, so project and
//      devshell tools still win. Child processes (including the bash tool)
//      inherit it.
//
// 2. Tool registration (guardrails tool registration protocol,
//    aliou/pi-guardrails#99, implemented in the smantzavinos forks of
//    pi-guardrails and pi-hooks): pi-lens tools that read or write files are
//    registered so guardrails policies/path access and the pi-hooks
//    permission levels gate them like the built-in read/edit tools.
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { getAgentDir, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const REGISTER_TOOL_EVENT = "guardrails:register-tool";
const REQUEST_TOOLS_EVENT = "guardrails:request-tools";

type Input = Record<string, unknown>;
type Targets =
  | { kind: "files"; access: "read" | "write"; paths: Array<{ path: string }> }
  | undefined;

function stringPaths(...values: unknown[]): Array<{ path: string }> {
  const paths: string[] = [];
  for (const value of values) {
    if (typeof value === "string" && value.trim()) paths.push(value);
    if (Array.isArray(value)) {
      for (const entry of value) {
        if (typeof entry === "string" && entry.trim()) paths.push(entry);
      }
    }
  }
  return [...new Set(paths)].map((path) => ({ path }));
}

// Tools without file paths (project_report, analyze, health, latency, ...)
// are intentionally unregistered: like `grep` with no path, there is no
// named target to check.
function files(access: "read" | "write", ...values: unknown[]): Targets {
  const paths = stringPaths(...values);
  return paths.length > 0 ? { kind: "files", access, paths } : undefined;
}

// A mutation with no named path applies to the workspace, so it is still
// checked (as cwd) rather than skipped.
function writes(...values: unknown[]): Targets {
  const paths = stringPaths(...values);
  return { kind: "files", access: "write", paths: paths.length > 0 ? paths : [{ path: "." }] };
}

const LSP_MUTATING_OPERATIONS = new Set(["rename", "rename_file", "codeAction"]);

export const PI_LENS_TOOL_RESOLVERS: Record<string, (input: Input) => Targets> = {
  read_symbol: (input) => files("read", input.path),
  read_enclosing: (input) => files("read", input.path),
  module_report: (input) => files("read", input.path),
  symbol_search: (input) => files("read", input.paths),
  lens_diagnostics: (input) => files("read", input.path, input.paths),
  lens_diagnostic_mark: (input) => files("read", input.filePath),
  ast_grep_search: (input) => files("read", input.paths),
  ast_grep_outline: (input) => files("read", input.paths),
  // apply defaults to false (preview only).
  ast_grep_replace: (input) =>
    input.apply === true ? writes(input.paths) : files("read", input.paths),
  // rename/rename_file/codeAction mutate only with apply=true; server
  // commands (executeCommand) may edit files regardless, so they count as
  // writes. Workspace-wide edits can touch files beyond `path`; the named
  // files are what can be checked.
  lsp_navigation: (input) => {
    const operation = String(input.operation ?? "");
    const mutates =
      operation === "executeCommand" ||
      (input.apply === true && LSP_MUTATING_OPERATIONS.has(operation));
    return mutates ? writes(input.path, input.newFilePath) : files("read", input.path);
  },
};

export default function piLensPolicy(pi: ExtensionAPI): void {
  process.env.PI_LENS_DISABLE_LSP_INSTALL ??= "1";
  process.env.PI_LENS_DISABLE_TOOL_INSTALL ??= "1";
  process.env.PI_LENS_CONFIG_PATH ??= join(getAgentDir(), "pi-lens.json");
  process.env.PI_LENS_HOME ??= join(homedir(), ".pi-lens");

  const toolsBin = join(getAgentDir(), "pi-lens-tools", "bin");
  const pathEntries = (process.env.PATH ?? "").split(delimiter).filter(Boolean);
  if (existsSync(toolsBin) && !pathEntries.includes(toolsBin)) {
    process.env.PATH = [...pathEntries, toolsBin].join(delimiter);
  }

  const register = () => {
    for (const [toolName, resolve] of Object.entries(PI_LENS_TOOL_RESOLVERS)) {
      pi.events.emit(REGISTER_TOOL_EVENT, {
        toolName,
        resolveTargets: ({ input }: { input: Input }) => resolve(input),
      });
    }
  };
  register();
  pi.events.on(REQUEST_TOOLS_EVENT, register);
}
