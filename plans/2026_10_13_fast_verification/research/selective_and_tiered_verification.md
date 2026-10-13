# External research: selective and tiered verification for a pnpm/Vitest/Playwright TypeScript monorepo

## Summary
1. Vitest's `--changed` and `related` are the only off-the-shelf selection for unit tests here; both are import-graph based and have documented blind spots (dynamic imports, fs fixtures, uncommitted-only default).
2. Playwright `--only-changed` is file-level only: editing a source file does not select the specs that exercise it. Dependency-based E2E selection is not provided by Playwright.
3. Only one selection system publishes numbers: Meta's predictive selection cut test infra cost ~2x while reporting >95% of individual failures and >99.9% of faulty changes. Per-test recall is not 100%, so selection belongs on fast per-change gates, with full runs later.
4. Industry tiering is consistent: Google keeps presubmit to fast, reliable tests and runs slow or unstable ones post-submit; GitHub merge queue and Uber SubmitQueue validate on top of the queue and drop a failing change rather than halting.
5. Speculative parallel validation buys latency with compute: Uber's 2025 paper reports 40-65% of speculative builds aborted before tuning, and a -53% CI resource cut after tuning.
6. E2E speed comes from Playwright sharding (`--shard`, file-level unless `fullyParallel`), per-worker data isolation (`workerIndex`, worker-scoped fixtures), and cheap per-test contexts. Two traps: a worker restarts after any failure, and `reuseExistingServer` can serve stale code between change sets.
7. Flaky handling that does not burn time: Google moves low-consistency tests out of gating into a reliability suite and tags failing tests to bugs; Playwright and Vitest retries are opt-in (default 0) and need a flaky-count budget.
8. For AI agents, the only quantified evidence is TDAD (arXiv 2603.17973, SWE-bench, not a TS monorepo): giving the agent a dependency map as context cut regressions 6.08% to 1.82%, while adding TDD instructions raised them to 9.94%.
9. Sequence traps: `--changed` and `--only-changed` default to uncommitted changes (empty selection if the agent committed); Nx/Turborepo affected base; stale dev server; Vitest records stale after import edits.
10. Not found: published browser-startup numbers for current Playwright; any study comparing pause-and-fix vs fix-forward for agents; Launchable's "up to 80%" is a vendor claim, not verified.

## 0. Method and limits
- Read primary docs (vitest.dev, playwright.dev, docs.github.com, nx.dev, turborepo.com, git-scm.com), papers (arXiv, ACM DL), and Google/Uber engineering pages. No local repo files were read or changed; no git state changed; no tests, builds, or installs were run.
- Search providers were intermittently unavailable (Exa rate-limited; Brave, Tavily, Perplexity, Gemini, OpenAI unconfigured). Key sources were fetched directly.
- Not read in full: Meta's paper body (abstract only), Google "Taming" PDF (abstract only), the TAP keynote (search snippet only).
- Side effect: fetching uber/submitqueue cloned it to /tmp/pi-github-repos (outside the three working trees).
- Rejected as unreliable: johal.in pages (claim Playwright "browser pooling" features with no verifiable source).

## 1. Selective / affected test execution

### 1a. Vitest `--changed` and `vitest related`
- Mechanism: `--changed [since]` selects tests whose module graph touches changed files. With no value it uses uncommitted changes (staged and unstaged); `--changed HEAD~1`, `--changed origin/develop` also work. Changes to setupFiles, globalSetup, runner, environment, snapshotSerializers, `.env`, or the project config rerun the whole project. Config and `package.json` changes rerun the whole suite by default. (https://vitest.dev/config/changed ; https://vitest.dev/guide/cli)
- `vitest related <files>`: static imports only, not dynamic `import(path)`. Designed for lint-staged/CI. (https://vitest.dev/guide/cli)
- `experimental.recordDependencies` (docs label 5.0.4+): records the modules each test actually loaded and uses them for `--changed`/`related` instead of transforming the graph. Tests without a record always run. (https://vitest.dev/config/experimental)
- Saves: skips unaffected files; with records, selection costs no transforms.
- Risks and failure modes:
  - Default `--changed` is uncommitted-only: an agent that commits each change set before testing gets an empty or wrong selection. Use `--changed <base>` explicitly.
  - Records describe the last run. If an import is added and committed before the test runs, a later change to the new import does not select the test. Docs say to run once after import changes. (https://vitest.dev/config/experimental)
  - `vi.mock` with a factory does not load its imports, so they are not recorded; fs-read fixtures and externalized deps are not recorded.
  - `isolate: false` can over-select (safe direction). Vitest's own diagnostics say `vitest doctor` must be used to validate `isolate: false`.
- Fails when: changes flow through files read at runtime (fixtures, JSON, env), through the backend over HTTP (invisible to the import graph), or through dynamic imports.

### 1b. Playwright `--only-changed`
- Mechanism: "Only run test files that have been changed between 'HEAD' and 'ref'. Defaults to running all uncommitted changes. Only supports Git." (https://playwright.dev/docs/test-cli)
- Saves: runs only edited spec files.
- Risks: it is file-level. A change to a component, API handler, or backend route selects zero specs. Using it as the E2E gate is unsafe. Same uncommitted default trap as Vitest.
- Fails when: nearly always for source-only changes. Any mapping from source paths to specs must be built by the team (no official Playwright equivalent found).

### 1c. Nx affected
- Mechanism: `nx affected -t <task>` uses git diff plus the project graph; project-level by default; `NX_LEGACY_AFFECTED=false` selects tasks by whether a change reaches what each task reads; `--explain` prints why. (https://nx.dev/docs/features/ci-features/affected)
- Base: default `main`; docs recommend base = last successful main commit (`nrwl/nx-set-shas`). Affected set is computed against that base, so it does not shrink as you iterate on a branch.
- Lock-file change marks all projects affected by default (`projectsAffectedByDependencyUpdates: "all"`).
- Risks: stacked agent changes grow the affected set; a wrong base silently drops changes. Whether this repo uses Nx is not checked here.

### 1d. Turborepo --affected
- Mechanism: `--affected` = `--filter=...[main...HEAD]`; package-level by default; `futureFlags.affectedUsingTaskInputs` filters at task level; `--filter=[HEAD^1]` for last commit. Base overridable with `TURBO_SCM_BASE`/`TURBO_SCM_HEAD`. (https://turborepo.com/docs/reference/run)
- Risk: shallow checkout makes all packages "changed" (docs say full history is needed; use `fetch-depth: 0` or `--filter=blob:none --depth=0`).

### 1e. Test impact analysis, published evidence
- Google TAP: presubmit tests run "fine-grained dependencies" against HEAD; postsubmit runs ~4.2M tests as changes are submitted, and a test is affected iff a changed file is in its transitive dependencies (TAP keynote, ICST 2017, slide text). (https://www.aster.or.jp/conference/icst2017/program/jmicco-keynote.pdf)
- Google, "What Breaks Google?" (2023): comprehensive testing is batched post-submit; a TAP Postsubmit scheduler ranks targets by predicted failure likelihood (bug-prediction metrics, change features, test history); automated culprit finders identify the breaking change. (https://research.google/pubs/what-breaks-google/)
- Google SWE book: presubmit tests "selected based on a model that predicts their likelihood of detecting a failure" is named as a valid strategy. (https://abseil.io/resources/swe-book/html/ch23.html)
- Google, "Taming Google-Scale Continuous Testing" (ICSE'17, abstract only): very few tests fail, failing tests tend to be "closer" to changed code, and code modified by more than 3 developers breaks more often. (https://research.google/pubs/taming-google-scale-continuous-testing/)
- Meta, "Predictive Test Selection" (arXiv:1810.05286): ML model trained on historical outcomes; cut testing infra cost ~2x; >95% of individual test failures and >99.9% of faulty changes still reported; accounts for flakiness. Body not read. (https://arxiv.org/abs/1810.05286)
- Launchable: commercial predictive selection from CI history; "up to 80%" appears only in marketing copy (https://medium.com/launchable/what-is-predictive-test-selection-4d718eba6ea1). Not verified.
- Reliability summary: the only quantified selection recall is Meta's (95% per failing test, 99.9% per faulty change). No published recall for a Vitest/Playwright TS monorepo: not found.
- What selection misses (generic): individual test-level failures (Meta's 5%); non-code inputs (fixtures, seeds, env, config); shared backend state; dynamic dispatch; cross-package effects through HTTP or generated code.

## 2. Tiered gates

- Google presubmit vs postsubmit: "only fast, reliable" tests on presubmit; "accept some loss of coverage on presubmit ... catch issues on post-submit, and accept some number of rollbacks." Presubmit is limited to the project's tests; unreliable tests are kept off presubmit. (SWE book ch23, https://abseil.io/resources/swe-book/html/ch23.html)
- Mid-air collision: two changes that each pass can break together. Google says it happens "most days at our scale"; serializing submits removes it for small repos. (same source)
- Green head vs true head: Google's continuous build marks the latest verified commit as "green head"; engineers can sync to green head while coding. (same source)
- GitHub merge queue: each entry is tested on the base plus earlier entries. On a failing check, the failing PR is removed and the temporary branch is rebuilt without it, so successors are re-tested (a re-run, not a binary search). Build concurrency is 1-100. "Only merge non-failing pull requests = No" lets failing PRs join a group if the last group passes (for intermittent failures). Jumping the queue forces a full rebuild. Merge queue requires `merge_group` triggers in CI. (https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue ; .../merging-a-pull-request-with-a-merge-queue)
- Uber SubmitQueue (EuroSys'19): speculatively builds pending changes on predicted HEADs, uses build-target conflict analysis, and isolates the offending change; before SubmitQueue, iOS mainline was green 52% of the time; with 16 concurrent conflicting changes, ~40% chance of breakage. Success model: logistic regression, 97% accuracy, strongest features are prior successful speculations and initial test results. (https://dl.acm.org/doi/10.1145/3302424.3303970 ; morning-paper summary https://blog.acolyer.org/2019/04/18/keeping-master-green-at-scale/)
- Uber 2025 follow-up (arXiv:2501.03440): 40-65% of builds aborted prematurely; after tuning, CI resource -53%, CPU -44%, p95 wait -37%. Build-to-change ratio fell 45-64%. (https://arxiv.org/html/2501.03440)
- Bisection: `git bisect` is binary search (about log2 n steps); `git bisect run <cmd>` automates it, with exit 125 meaning "skip this commit". (https://git-scm.com/docs/git-bisect) Uber's model is to isolate the failing change and re-test the rest (https://github.com/uber/submitqueue README); Google uses automated culprit finders (What Breaks Google).
- Candidate tiering from this evidence (for Design to decide):
  - Per change: typecheck, `vitest related` or `--changed <base>`, mapped specs.
  - Checkpoint: affected Vitest projects plus E2E specs mapped by path, including backend routes.
  - Batch or post-commit: full Vitest and full sharded E2E, with culprit search on failure.
  - Queue: GitHub merge queue or equivalent for the final gate.
- Risks: merge queues waste compute when failure rates are high (Uber 2025); a batch-based post-commit gate lets bad changes land and requires rollback or fix-forward; "only merge non-failing" trades false negatives for throughput. No public Vitest/Playwright merge-queue recipe found.

## 3. Full suite in parallel with next work; late failures

- Speculation evidence: Uber's model speculates on pending changes; this pays only when predicted success is high (97% accuracy in 2019). Expect abort waste (40-65%) without tuning.
- Late failure, documented policies:
  - Google: accept rollbacks; prefer fast presubmit to avoid late failures; "any change can be rolled back with two clicks" (SWE book ch23 footnote).
  - GitHub queue: drop the failing entry and re-test successors (automated).
  - Uber: isolate offending change, retry the rest.
  - Turborepo `--continue` default `never` cancels all tasks on error; use `dependencies-successful` or `always` to keep unrelated work running. (https://turborepo.com/docs/reference/run)
  - Playwright `-x`/`--max-failures` stops early; Vitest `bail`; Playwright `--last-failed` reruns failures.
- Fix-forward vs pause: no published comparison for agent workflows (not found). The documented pattern in queues is cut the culprit and re-test the rest, which suggests stacking agent changes on green head rather than the unverified branch tip.
- Risk: a next change built on an unverified tip inherits the late failure; mid-air collisions appear when independently green changes meet.

## 4. E2E speed (Playwright)

- Parallelism: test files run in parallel by default; tests in one file run in order in one worker. `fullyParallel` (project or config) or `test.describe.configure({mode:'parallel'})` parallelizes tests. Default workers are 50% of logical CPUs (`--workers`). Each worker starts its own browser. (https://playwright.dev/docs/test-parallel ; https://playwright.dev/docs/test-cli)
- Worker restart: "Workers are always shutdown after a test failure" (browser discarded, new worker). Retries follow the same path. (https://playwright.dev/docs/test-parallel ; https://playwright.dev/docs/test-retries)
- Sharding: `--shard=x/y` splits by file unless `fullyParallel`, which splits per test and balances better. Shards merge via blob reporter and `playwright merge-reports`. Shards need separate backends. (https://playwright.dev/docs/test-sharding)
- Isolation: each test gets its own BrowserContext ("fast and cheap to create"); a browser is shared per worker. (https://playwright.dev/docs/browser-contexts)
- Per-worker data and backend:
  - `testInfo.workerIndex` / `TEST_WORKER_INDEX` to create per-worker DB users; `testInfo.testId` for per-test records; `testInfo.outputPath` for unique files. (https://playwright.dev/docs/test-parallel)
  - Worker-scoped fixtures run once per worker and are "where you can set up services, run servers." (https://playwright.dev/docs/test-fixtures)
  - Not found: an official recipe for one backend per worker. The worker-scoped fixture pattern is the documented hook; port and DB name must be parameterized by `workerIndex` (team design).
- Server reuse: `webServer.reuseExistingServer: !process.env.CI` re-uses any server already listening on the URL. Across change sets this can run stale code. Set it to false, or restart/kill the server per change set. (https://playwright.dev/docs/test-webserver)
- Shared-resource tests: named `lock` on tests serializes only those tests across workers and projects (version not stated in the fetched doc). (https://playwright.dev/docs/test-parallel)
- Browser startup cost: not found in current official docs. Dated anecdote: Playwright issue #4345 (Linux, v1.3-1.5 era) reports cold launches of ~0.3-0.7s, with intermittent 5-8s launches. (https://github.com/microsoft/playwright/issues/4345) Treat as stale; measure locally.
- Risks: `fullyParallel` exposes hidden ordering between tests in a file; per-worker backends multiply resource use; many workers can stress one backend.
- Vitest-side speed: `isolate:false` and `pool` changes can be large wins but share state; `vitest doctor` measures alternatives and checks `isolate:false` with shuffled files (https://vitest.dev/guide/cli); Vitest shards by file, not test case (https://vitest.dev/guide/improving-performance); `vitest --reporter=blob --shard` plus `--merge-reports` for CI.

## 5. Flaky-test handling without wasting time

- Google reliability runs: repeated runs give consistency rates; tests below a threshold are moved out of gating into a reliability suite, kept for discovery and not used to block submission. (https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)
- Google SWE book: failing tests are tagged with a bug and suppressed; tag cleanup is automated; flaky tests can be tagged and are not prompted for cleanup. (https://abseil.io/resources/swe-book/html/ch23.html)
- Playwright: `retries` default 0; `--retries`; trace on first retry; `--fail-on-flaky-tests` makes a flaky result fail the run (default false). (https://playwright.dev/docs/test-retries ; https://playwright.dev/docs/test-cli)
- Vitest: `retry.count` (default 0), `retry.delay`, `retry.condition` (regex on error text), `repeats`; GitHub Actions reporter's job summary lists flaky tests. (https://vitest.dev/guide/cli ; https://vitest.dev/guide/reporters)
- Meta's model accounts for flakiness in selection outcomes (abstract).
- Risks: retries multiply wall time when failures are real (each failing test reruns N times); retries hide intermittent product bugs (Google blog: conditions that make E2E tests flaky are often the ones that cause bugs); quarantine without an expiry or owner accumulates; `retry.condition` can mask a regex-matching failure.
- Fails when: flakiness is in the backend or shared data, not the test; retries then only add time.

## 6. AI-agent specific evidence

- Vitest auto-selects the `minimal` reporter when it detects an AI coding agent: failures and errors only, with passing logs and summary suppressed. (https://vitest.dev/guide/reporters) Playwright equivalent: not found.
- TDAD (arXiv:2603.17973, 2026 tool paper): dependency map of source and tests, delivered as an agent skill; regressions 6.08% to 1.82% (Qwen3-Coder 30B, 100 SWE-bench Verified instances, n is small); TDD procedural instructions without test context raised regressions to 9.94%; surfacing context outperformed prescribed procedure. (https://arxiv.org/abs/2603.17973) Not a TS monorepo; open-weight models.
- Diff-scoped selection blog (Negi; opinion, no data): expand from the patch through ownership and dependency edges; print selected tests and reasons; escalate on migrations, auth, infra, and schema; quarantine flaky tests with owners. (https://negiadventures.github.io/blog/diff-scoped-test-selection-ai-coding-agents.html)
- Not found: benchmarks of wall time vs quality for agents running many sequential change sets against a TS monorepo.

## 7. Gaps and not-found items
- Meta paper body, Google TAP internals (batching, bisection algorithm), and Launchable's own accuracy data were not verified beyond the abstracts or marketing.
- No published recall for Vitest `--changed` or `related`; no published Playwright source-to-spec mapping.
- No official per-worker backend recipe for Playwright.
- No current browser-startup benchmark for Playwright.
- No agent-specific pause-vs-fix-forward study.

## 8. Facts to check locally (not explored here; for Design or the researcher's local worker)
- Vitest version: `recordDependencies` needs 5.0.4+ per docs; `vcsProvider` 4.1.1+.
- Playwright version: `--only-changed` exists in the fetched CLI doc; the `lock` option version is not stated.
- Whether CI clones full history (affects `--changed <base>`, Nx/Turbo affected).
- Whether agents commit before testing (affects uncommitted-default selection).
- Whether `reuseExistingServer` is enabled and whether the dev server restarts between change sets.
- Whether the repo uses Nx or Turborepo at all.

## Acceptance report
```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Report at /tmp/testspeed/ext_selective.md gives a 10-line summary, covers the four requested areas (selection, tiered gates and late failures, E2E speed, flakiness) plus agent evidence, cites URLs for each claim, marks gaps as not found, and lists residual risks in section 7-8."
    }
  ],
  "changedFiles": [
    "/tmp/testspeed/ext_selective.md"
  ],
  "testsAddedOrUpdated": [],
  "commandsRun": [],
  "validationOutput": [
    "Sources fetched directly: vitest.dev guide/cli, config/changed, config/experimental, guide/improving-performance, guide/reporters; playwright.dev test-cli, test-parallel, test-retries, test-sharding, test-fixtures, test-webserver, best-practices, browser-contexts; docs.github.com merge queue; nx.dev affected; turborepo.com reference/run; git-scm.com git-bisect; abseil.io SWE book ch23; research.google taming and what-breaks-google; arXiv 1810.05286, 2501.03440, 2603.17973; ACM DL 10.1145/3302424.3303970; Google testing blog 2016."
  ],
  "residualRisks": [
    "Meta and Google TAP claims rest on abstracts or search snippets, not full papers.",
    "TDAD evidence is SWE-bench Python with small n and open-weight models; not transferable to this stack without a local trial.",
    "Launchable's savings figure is vendor marketing and unverified.",
    "No current Playwright browser-startup or per-worker backend benchmark was found; numbers must be measured locally.",
    "Vitest record-based selection can miss changes if imports are committed before a run (documented)."
  ],
  "noStagedFiles": true,
  "diffSummary": "New report file only; no repository files, git state, or staging touched.",
  "reviewFindings": [
    "no blockers (research-only task; no code changes reviewed)"
  ],
  "manualNotes": "Search providers were intermittently unavailable (Exa rate-limited; others unconfigured), so primary sources were fetched by URL. Fetching uber/submitqueue cloned it to /tmp/pi-github-repos, outside the three working trees. johal.in pages were rejected as unreliable."
}
```
