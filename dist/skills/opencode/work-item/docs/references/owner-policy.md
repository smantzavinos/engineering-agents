# Owner policy: Decide, don't ask and Finish in task

NORMATIVE for every agent that works a board item or a pull request, on
every harness. Canonical source: `docs/references/owner-policy.md`; it is
packaged with the skills that cite it.

## Decide, don't ask

The owner's attention is the scarcest resource in the pipeline. Ask only
about items on the **owner list** below; decide everything else yourself,
record it, and move on. This section overrides any wording in a skill
("ask", "stop and ask", "ambiguous", "confirm", "open question")
that would send a non-owner-list question to the human.

**Sources, in this order:** the item text and owner comments; the
repository (code, tests, `AGENTS.md`, docs, git history, open and merged
PRs, earlier plan directories); the specs/requirements the repo cites; documentation the repo links;
conventions in sibling repositories. When two
answers are defensible, pick the one the sources support best; if they are
silent, pick the smaller, reversible option.

**Record every non-trivial decision** in a numbered **Decisions made** list
with its source in brackets, e.g.
`D3. Nightly run at 02:17 UTC [convention: other nightly workflows in .github/workflows]`.
The list lives in the brief/approach, the plan (new decisions only), and
the PR body (one merged list). The owner vetoes with `revise: D3 …` at a
gate or in a PR comment; a veto is cheap, a question is not. A decision
with a source is never phrased as a question.

**Owner list (ask; never decide):**

1. A contradiction between the item and the specs/requirements, or between
   two requirements, that the sources do not resolve.
2. An irreversible or externally visible action: data migration, public API
   or wire-format change, release, anything that touches production or a
   customer.
3. Spend: anything that adds cost — a new paid service or licence, or a
   bigger or paid CI machine (e.g. GitHub "larger runners").
4. Security posture: permissions, secrets, trust boundaries.
5. Changing a FROZEN decision or a frozen contract test.
6. Safety behaviour (stop conditions, interlocks, limits) that the spec
   does not already fix.
7. Creating a new backlog item (see "Finish in task").

Plus the human gates of the process in use (the board gates; in
`software-development`, "Autonomy defaults"). **Not** on the list:
"scope" (follow "Finish in task"), "ambiguous" (resolve it from the
sources), file placement, naming, test selection, schedules, defaults,
version bumps that follow repo convention, and anything already answered
by an approved gate. A diagnostic only a person can run (bench logs,
hardware access) is a request for information, phrased as one, not a
decision.

**Questions sections** (gates, triage, result files) hold owner-list items
only, at most three. When there are none, write
`Questions: none — see Decisions made.`

## Finish in task

The goal is a backlog that **shrinks**. An item is done when the problem
it states is solved for every case the repository can reach, including the
gaps found by the design scan and the review findings of every severity.

- **Default: do it here**, in this item's branch and PR. A file the work
  needs outside the plan's Scope/Touched-files list is added and recorded
  under Decisions made; it is never a question.
- **New backlog items: zero without the owner's explicit approval.** Propose
  one only for (a) a genuine defect outside this item's problem that cannot
  be fixed in this PR without changing an unrelated module's behaviour, or
  (b) an epic-sized item, where the Design gate proposes a split into 2–3
  items with one-line goals (more than three means an umbrella; recommend
  closing it after the split). Before proposing, search open issues
  (`gh issue list --search <key words>`) and propose extending a matching
  one instead. Proposals go in the next gate, or in the PR body under
  `## Proposed new issues (need your OK)`; nothing is filed until the
  owner approves.
- **Review Minors** are fixed in the same round when small (rename, doc,
  test, roughly under 30 lines); otherwise dropped with one line under
  `## Considered and not done` in the PR body. Minors are never filed and
  never listed as follow-ups.
- **Related repositories.** A change the item needs in another repository
  (dependency, consumer, shared library, schema or API) is made as a
  companion PR there, cross-linked with this item's PR and never merged by
  an agent, when the approved plan or design names it. Otherwise it is an
  owner-list question (an externally visible action), asked at the next
  gate; it is never filed as a follow-up.
- **Nice-to-haves** outside the item's problem are dropped and listed under
  "Considered and not done", not filed.
- The PR body's follow-ups section lists only issues that already exist
  with numbers, or says `None — finished in task.`
