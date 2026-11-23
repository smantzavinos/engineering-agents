# Launching a role

Pi has two launchers for the same named roles. If `delegate_task` is available,
use T3. Otherwise use terminal Pi's `subagent`. Don't substitute a different
model or launcher for a missing role model; stop and report the model and set.

## T3

1. From the project root, run `node "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/delegate/role.mjs" <role>`.
   Use its `model`, `thinking`, `skills` and `skillPaths`: repo
   `.pi/settings.json` override, then the user's override, then the installed
   `agents/<role>.md` frontmatter, field by field. The resolver does not read
   `agentOverridesByProvider`, `subagents.defaultModel`, `subagents.defaultProvider`,
   or project `.pi/agents/<role>.md` files.
2. Discover the local catalog with `orchestrator_capabilities` before the first
   launch. Use the Pi instance offering the resolved model. Launch with
   `delegate_task`, for example:

   ```json
   {
     "title": "Implement approved plan",
     "role": "implementation",
     "mode": "async",
     "target": {
       "providerInstanceId": "pi",
       "model": "openai-codex/gpt-5.6-sol",
       "options": { "thinking": "medium" }
     },
     "task": "Read your installed agents/implementer.md from the Pi agent directory and follow the implement, architecture-model, delegate and test-quality skills. You may delegate bounded helper errands. Build the approved plan at <path> from <base>."
   }
   ```

   Substitute the resolved model and thinking. T3's `role` is a generic tool
   category (`design` for plan-author, `implementation` for implementer,
   `review` for reviewer, `research` for researcher, `general` for helper or
   oracle); name the exact Pi role and its skills in the task. T3 does not
   inject the agent file: tell the child to read it and any resolved skill
   paths. For a manual-only skill, give the file path or start the task with
   `/skill:<name>`. When `mayDelegate` is true (the resolved skills include
   `delegate`, as for the shipped plan-author, implementer and reviewer), the
   T3 task must explicitly say the child may delegate bounded helper errands.
   Otherwise don't grant nested delegation.
3. Record `taskId`, `childThreadId`, the child run ID if returned, and the
   launcher in `state.json` when the workflow uses it. Each child is a visible
   thread. Honor the launch receipt's completion instruction; don't poll a
   running task or block for its result. On completion, consume the result
   once (`task_status` if the completion notice didn't include it).
4. Continue the same stopped/finished author or implementer with
   `t3_thread_send` to its `childThreadId` (`mode: "auto"`); record any new
   task/run IDs. For a running child, steer with `mode: "steer"`. Stop a
   delegate's work with `task_cancel` on its `taskId`, not a thread interrupt.
   A fresh review (including a re-check) is always a new `delegate_task`.

Shared checkout is the default; allow only one writer at a time. For an
isolated epic lane pass `isolation: "worktree"`: T3 prepares it from your
committed state. There is no `cwd` argument. Never make the child's checkout
in the shell or tell the child to make it. Integrate its reported branch.

## Terminal Pi

Launch `subagent` with `agent: "<role>"`, `task: "<brief>"` and `async: true`.
For an existing lane checkout, pass its `cwd`. The launcher loads the agent
file and applies the settings overrides itself. Record the returned run ID
and launcher; use the completion notice to consume the result. Continue an
exited or paused author or implementer with `action: "resume"`, `id` and `message`;
record the new run ID. Use `action: "steer"` with `id` and `message` to guide a
running child, `action: "stop"` with `id` to cancel it permanently, and `action: "status"`
with `id` to reconcile a known run after recovery. Start a new run for every
fresh review. See the manual-only `/skill:pi-subagents` for launcher details.
