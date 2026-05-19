# Extension Spec: State Validation & Continuation Enforcement

This document specifies the minimal coding agent extension that supports the autonomous development process. The extension is intentionally small — all workflow intelligence lives in skills and the orchestrator LLM.

---

## Purpose

The extension does exactly two things:

1. **State validation** — Ensures state.json phase transitions are legal
2. **Continuation enforcement** — Detects when an agent stopped mid-process and re-triggers it

Everything else (deciding what to do next, calling sub-agents, interpreting artifacts, making quality judgments) is handled by the orchestrator and skills.

---

## Why Minimal

Previous attempts at building a full orchestration extension proved unnecessary because:

- A high-powered orchestrator LLM can drive the process through sub-agent calls
- Complex state machines in extensions are rigid and hard to update
- Skills already encode the process knowledge
- The failure mode of a complex extension (wrong orchestration decisions) is worse than the failure mode of a minimal extension (didn't re-trigger when it should have)

The extension is a safety net, not a brain.

---

## State Validation

### Schema

```typescript
interface PlanState {
  level: "simple" | "standard" | "epic";
  phase: Phase;
  status: Status;
  // Epic-only fields
  currentChild?: string;
  completedChildren?: string[];
}

type Phase =
  | "draft"
  | "researching"
  | "researched"
  | "designing"
  | "designed"
  | "planning"
  | "planned"
  | "reviewing"
  | "reviewed"
  | "ready"
  | "executing"
  | "reviewing_code"
  | "complete"
  | "blocked";

type Status = "active" | "paused" | "complete" | "blocked";
```

### Valid Phase Transitions

```
draft → researching
researching → researched
researched → designing
designing → designed
designed → planning
planning → planned
planned → reviewing
reviewing → reviewed
reviewed → ready
ready → executing
executing → reviewing_code
reviewing_code → executing       (fix pass after review)
reviewing_code → complete
Any → blocked                    (can block from any phase)
Any → paused (via status)        (can pause from any phase)
```

### Simple Level Shortcuts

Simple plans can skip stages:
```
draft → executing → complete
```

### What the Extension Validates

On any state.json write:
- The new phase is a valid transition from the current phase
- The status value is valid
- Level-specific fields are present (e.g., epic plans have `currentChild`)
- The file is valid JSON matching the schema

On validation failure:
- Reject the write
- Log the invalid transition attempt
- Do NOT crash or corrupt state

---

## Continuation Enforcement

### The Problem

Agents sometimes stop mid-process:
- Context window exhaustion
- API timeout
- Model decides it's "done" when it's not
- Network interruption

When this happens, the plan directory has state.json showing `status: "active"` in a non-terminal phase, but no agent is running.

### Detection

The extension monitors for this condition:

```
IF state.json exists
AND status == "active"
AND phase is NOT "complete" AND phase is NOT "blocked"
AND no agent is currently executing against this plan
THEN trigger continuation
```

### Trigger Mechanism

When a stalled plan is detected:

1. Read `state.json` to determine current phase
2. Construct a continuation prompt:
   ```
   Resume the plan at [plan directory path].
   Current phase: [phase]. Status: active.
   Read the relevant artifacts and continue the process from where it left off.
   ```
3. Invoke the orchestrator with this prompt
4. The orchestrator reads the artifacts and determines the correct next action

### Detection Timing

The extension checks for stalled plans:
- On harness startup (catches plans stalled from a previous session)
- On a periodic interval (catches mid-session stalls)
- On explicit user request (`/eng-plan resume` or equivalent)

### Guard Rails

To prevent re-trigger loops:
- **Cooldown period** — Don't re-trigger within N minutes of the last trigger
- **Max retries** — After N consecutive re-triggers for the same plan without phase advancement, set status to `paused` and alert the human
- **Phase advancement check** — Only count a re-trigger as "progress" if the phase changes or the worklog shows a new completed task

### What the Extension Does NOT Do

- Does not decide which sub-agent to call
- Does not interpret artifact content
- Does not make quality judgments
- Does not manage the iteration loop (plan review, code review)
- Does not choose models
- Does not parse plan.md, worklog.md, or any markdown artifact
- Does not implement any workflow logic

---

## Extension Interface

### Commands (Minimal)

| Command | Purpose |
|---------|---------|
| `/eng-plan status [path]` | Show state.json contents for a plan |
| `/eng-plan resume [path]` | Manually trigger continuation for a stalled plan |
| `/eng-plan pause [path]` | Set status to paused (stops auto-continuation) |
| `/eng-plan reset [path] [phase]` | Manually set phase (escape hatch for stuck states) |

### Events Emitted

| Event | When |
|-------|------|
| `plan.state.changed` | state.json was updated |
| `plan.state.invalid` | An invalid transition was attempted |
| `plan.stalled` | A stalled plan was detected |
| `plan.continued` | A continuation was triggered |
| `plan.max_retries` | Max re-triggers hit, pausing |

### Configuration

```json
{
  "continuation": {
    "enabled": true,
    "checkInterval": "5m",
    "cooldownPeriod": "3m",
    "maxRetries": 3,
    "autoResumeOnStartup": true
  }
}
```

---

## Implementation Notes

### File Watching

The extension watches for `state.json` files in the configured plans directory (and subdirectories for epics). It does NOT watch markdown artifacts — those are the orchestrator's concern.

### Atomicity

State.json writes should be atomic (write to temp file, then rename). This prevents corrupted state from partial writes during interruptions.

### Concurrency

Only one agent should mutate a plan's state at a time. The extension should detect if two processes are trying to work on the same plan and prevent the conflict (second process gets an error, not silent corruption).

### No Network Dependencies

The extension operates entirely on local filesystem. No external services, no databases, no network calls. This keeps it simple and reliable.

---

## Future Considerations (Not in v1)

- **Plan discovery** — List all plans and their states
- **Dashboard view** — TUI showing all active/paused/blocked plans
- **Notification hooks** — Alert via external channel when a plan blocks or completes
- **Multi-plan coordination** — For epics, validate child plan ordering constraints

These are explicitly deferred. The v1 extension does state validation and continuation enforcement, nothing more.
