VERDICT: YES — our own review criteria can be applied by replacing the project `crew-reviewer.md` system prompt (`crew/utils/discover.ts:123-127`, `crew/agents.ts:247-255`), and a NEEDS_WORK retry carries parsed review feedback into the worker prompt (`crew/handlers/review.ts:146-155`, `crew/prompt.ts:62-75`).

## 1. Auto-review trigger

Auto-review is a post-batch step, not a per-task completion callback. `work.execute` first waits for `spawnAgents(...)` to return, then processes the complete `workerResults` array and populates `succeeded` (`crew/handlers/work.ts:197-257`). Only after that loop does it enter the auto-review block (`crew/handlers/work.ts:259-269`). It reviews each qualifying task in `succeeded` sequentially (`crew/handlers/work.ts:263-269`).

Therefore, in autonomous execution it happens at the end of the worker batch/current wave, before the wave result is recorded (`crew/handlers/work.ts:301-314`), rather than immediately after each individual task reports completion. It runs only when review is enabled, at least one task succeeded, a `crew-reviewer` is discovered, the task has `base_commit`, and its `review_count` is below the configured limit (`crew/handlers/work.ts:259-269`).

## 2. Verdict effects on task state

The reviewer output is parsed into exactly `SHIP`, `NEEDS_WORK`, or `MAJOR_RETHINK`; the parser defaults to `NEEDS_WORK` if it cannot find a recognized verdict heading (`crew/utils/verdict.ts:14-25`). Before applying the verdict, the handler increments `review_count` (`crew/handlers/work.ts:277-279`). The parsed feedback is stored for every verdict in `task.last_review` (`crew/handlers/review.ts:143-158`).

- **SHIP:** No task-state transition is performed. The task remains `done` and remains in `succeeded`; the handler only logs the review event (`crew/handlers/work.ts:280-282`).
- **NEEDS_WORK:** `resetTask` changes the task to `todo`, removes completion/start/base-commit/assignment/summary/evidence/block metadata, and deliberately keeps `attempt_count` (`crew/handlers/work.ts:282-285`; `crew/store.ts:429-447`). The handler removes it from `succeeded` and adds it to `failed` (`crew/handlers/work.ts:283-286`). `resetTask` does not clear `review_count` or `last_review`; the tests explicitly assert both are preserved (`tests/crew/auto-review.test.ts:51-69`).
- **MAJOR_RETHINK:** The handler takes the first line of the stored review summary (up to 120 characters), blocks the task with `Reviewer: ...`, removes it from `succeeded`, and adds it to `blocked` (`crew/handlers/work.ts:287-295`). `blockTask` sets `status: "blocked"`, `blocked_reason`, and clears `assigned_to` (`crew/store.ts:402-414`).

## 3. NEEDS_WORK feedback persistence and retry prompt

The exact persistence path is `task.last_review`, populated with parsed (not raw) reviewer output:

```ts
store.updateTask(cwd, taskId, {
  last_review: {
    verdict: verdict.verdict,
    summary: verdict.summary,
    issues: verdict.issues,
    suggestions: verdict.suggestions,
    reviewed_at: new Date().toISOString()
  }
});
```

`crew/handlers/review.ts:146-155`. The parser extracts `summary`, `issues`, and `suggestions` from the reviewer output (`crew/utils/verdict.ts:28-51`); the complete raw output is not stored.

`resetTask` updates only the reset fields and leaves `last_review` intact (`crew/store.ts:437-447`). On the next work attempt, `buildWorkerPrompt` reads `task.last_review` and appends it to the retry prompt:

```ts
if (task.last_review) {
  prompt += `## ⚠️ Previous Review Feedback

**Verdict:** ${task.last_review.verdict}

${task.last_review.summary}

${task.last_review.issues.length > 0 ? `**Issues to fix:**\n${task.last_review.issues.map(i => `- ${i}`).join("\n")}\n` : ""}
${task.last_review.suggestions.length > 0 ? `**Suggestions:**\n${task.last_review.suggestions.map(s => `- ${s}`).join("\n")}\n` : ""}

**You MUST address the issues above in this attempt.**

`;
}
```

`crew/prompt.ts:62-75`. `work.execute` uses that prompt builder when constructing the next worker assignment (`crew/handlers/work.ts:172-194`). Thus, **yes**, NEEDS_WORK feedback is persisted and passed to the retry; it is the parsed summary/issues/suggestions, not the raw reviewer transcript.

## 4. `review.maxIterations`

Before spawning a reviewer, the auto-review loop skips a task when `(task.review_count ?? 0) >= config.review.maxIterations` (`crew/handlers/work.ts:265-269`). There is no block, reset, or failure transition in this exhausted branch; the task remains in its current state (normally `done`) and remains in `succeeded` for that work invocation (`crew/handlers/work.ts:267-269`). Consequently, if a NEEDS_WORK reset has already consumed the maximum review count, a later successful retry can complete without another automatic review because this gate skips it (`crew/handlers/work.ts:265-269`).

## 5. Reviewer override and honored frontmatter

Yes. Discovery checks the extension’s bundled agents directory and the project directory at exactly `.pi/messenger/crew/agents` under the current working directory (`crew/utils/discover.ts:14-18`, `crew/utils/discover.ts:116-121`). It inserts extension agents into a map first and project agents second, keyed by `name`; therefore a project file named `.pi/messenger/crew/agents/crew-reviewer.md` with `name: crew-reviewer` replaces the extension definition (`crew/utils/discover.ts:123-127`). The repository test asserts that the project definition wins, including its model and system prompt (`tests/crew/utils/discover.test.ts:43-69`).

The replacement must provide frontmatter `name` and `description` to be loaded (`crew/utils/discover.ts:89-90`); use `name: crew-reviewer` because both review entry points explicitly look for that name (`crew/handlers/review.ts:35-43`; `crew/handlers/work.ts:259-269`). The Markdown body becomes `systemPrompt` (`crew/utils/discover.ts:97-105`) and is passed to Pi with `--append-system-prompt` (`crew/agents.ts:247-255`), so changing that body is how to apply custom review criteria. A differently named agent is not substituted because the auto-review call hardcodes `agent: "crew-reviewer"` (`crew/handlers/review.ts:129-134`).

The requested frontmatter fields are parsed and used as follows:

- `model` and `thinking` are parsed into the agent config (`crew/utils/discover.ts:97-103`). The model is used by the spawn path, but explicit task/config overrides take precedence: `task.modelOverride ?? config.models?.[role] ?? agentConfig?.model` (`crew/agents.ts:211-215`). Auto-review supplies `config.models?.reviewer ?? sessionModel` as `modelOverride` (`crew/handlers/work.ts:267-269`), so the project file’s `model` is used only when those explicit overrides are absent. Thinking resolves config-by-role before agent frontmatter (`crew/agents.ts:217-223`; `crew/agents.ts:80-87`).
- `tools` is parsed as a comma-separated list (`crew/utils/discover.ts:92-100`). Spawn translates recognized built-in names (`read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`) into `--tools`, and path-like values into `--extension` (`crew/agents.ts:41`, `crew/agents.ts:225-242`). The bundled frontmatter lists `read, bash, pi_messenger` (`crew/agents/crew-reviewer.md:1-9`); `pi_messenger` is not one of the recognized built-in names in `BUILTIN_TOOLS`, while the Messenger extension itself is always attached separately (`crew/agents.ts:41`, `crew/agents.ts:225-245`).

## 6. Reviewer context

For an implementation review, the prompt contains:

- task ID and title, plus the PRD label/path (`crew/handlers/review.ts:102-109`);
- the task specification returned by `store.getTaskSpec` (`crew/handlers/review.ts:97-112`);
- the commit log from `base_commit..HEAD` (`crew/handlers/review.ts:94-95`, `crew/handlers/review.ts:114-118`); and
- a Git diff from `base_commit..HEAD` (`crew/handlers/review.ts:85-95`, `crew/handlers/review.ts:119-122`).

It is not an independently generated changed-file list; changed paths appear only insofar as standard Git diff output includes them (`crew/handlers/review.ts:119-122`). It is also not always the full diff: `getGitDiff` truncates output above 50,000 characters and appends `[Diff truncated - too large]` (`crew/handlers/review.ts:281-291`). The implementation review prompt includes task title/spec, but not the full plan specification (`crew/handlers/review.ts:97-127`). The default reviewer instructions likewise state that its prompt contains task context and the git diff (`crew/agents/crew-reviewer.md:12-15`).
