---
name: map-patterns
description: Reverse-engineer the patterns a codebase already uses and write them into the project's pattern catalog — the entries, one golden example each, the catalog profile and the path file — with what was found about existing code kept outside it. Use to start a catalog, to extend it to an area a plan is about to touch, or to change an entry. The human approves every entry.
harnesses: [pi]
---

# Map patterns

Plans are built from a catalog of the project's patterns. This skill writes that catalog from the code that exists. You work with the human: you find and draft, they approve. Nothing in a draft is binding.

The form is fixed by the catalog contract, [references/pattern-catalog.md](references/pattern-catalog.md): what an entry holds, the profile, the path file and the tags. Read it first. `c4ish guide` is the reference for the profile and the diagrams.

## Modes
- **Start a catalog.** Survey the repo and write a small key set: the shapes most new work will reuse, and the ones that guard access or data. Ten good entries beat forty thin ones.
- **Extend it** to an area a plan is about to touch. Only that area.
- **Change one entry,** when the human asks or a finding shows the rule is wrong.

A pattern a plan needs for code that doesn't exist yet is not this skill's job: the plan proposes it (`plan`).

## Find
1. **Read what the project already says:** its agent guide, architecture and coding rules, any existing pattern or schema docs, lint and structural rules. A rule the project already wrote down is a pattern candidate with an owner. Don't restate a doc that already holds the rules: link it. Each pattern in it still needs what the contract asks: an id, numbered requirements, a golden example and a profile entry. Add what is missing to that doc, or write a short entry that links it. The path file's `catalog` covers the linked doc.
2. **Find what every use goes through.** Usually that is shared code: a guard, a visibility filter, a write helper, a loader, a frame. List those first, by area, then find what goes through each. A data shape or a rule of single access has no helper: what every use must have is the thing itself (the field and its index, the one reader of a secret).
3. **Survey with fast subagents** (`delegate`): per area, every definition of a kind (every query, every write, every page, every form action), which shared code it reaches, and how it differs from its neighbours. Ask for tables, not prose, with rough counts.
4. **Read the critical code yourself:** every shared helper, and three or four uses of each candidate, including the odd ones. The entry is your judgment, not the survey's.
5. **Decide what each candidate is.** The first row that matches wins:

   | What you found | It is |
   |---|---|
   | The same job done with and without the shared code | One pattern. The uses without it are findings |
   | Two helpers doing one job | One pattern through one of them. Ask the human which is kept; the entry names only that one, and the twin is a finding |
   | The shared code reached directly by some uses and through a wrapper by others | One pattern. Both routes are full fits; a convention says which to prefer |
   | Two or more uses going through the same shared code | A pattern |
   | A recurring data shape, or a rule of single access, that guards access, data or secrets, with no helper | A pattern. Its card says what every definition must have |
   | A difference the human says is deliberate and lasting | Part of the rule: an exception the entry names by kind, or a convention |
   | One use | Held back: listed at the end of its area, tagged bespoke when next touched |
   | A shape defined only by where files sit | A convention of another pattern, or nothing |
   | Recurring code the project wants to stop writing | Not a pattern. A finding |

6. **Ask the human** the questions only they can answer, batched: which of two competing shapes is the rule, whether a difference is deliberate, what is in scope. A difference they keep for good changes the rule (the table). One they call temporary is a finding, and its code is tagged `partial: Rn` when a plan next touches it. Record each answer with its date under Decisions in the findings file.

## Write
Write each entry as the contract lays it out. In practice, work in this order:
1. **The card.** Name what the pattern goes through, by path where it is code. Say what it protects against in one line; if you can't, it may not be a pattern.
2. **The requirements.** Each is something a definition must do, that a reader can check on one definition, with what checks it. Keep conventions apart. Fewer, sharper requirements are better: a requirement no test, reviewer or rule could fail is not one.
3. **The golden example.** One use of the pattern, with all its pieces, that is a full fit. Check it by reading the code and running its tests. When the best candidate falls short:
   - fix it, in its own small commit, with its tests run and a new test shown to fail on a seeded fault; or
   - choose another; or
   - if no full fit exists anywhere, the entry is not ready: leave it out of the profile and the chooser, list it under what the area doesn't cover, record what the fix needs in the findings, and tell the human.

   Tag the golden example. Never weaken a requirement to make one fit.
4. **The shape:** the code block, cut down from the golden example, and a wrong example from a real mistake where there is one.
5. **Tests a new one needs,** and **In a plan model.**
6. **The diagram:** a small `c4ish` model per entry, beside the docs, using the catalog profile. What a plan adds is drawn as new, the shared code as reused with its code reference, and the connector labels carry the requirement numbers.

Then, per area: the shared rules stated once, the **chooser table**, what isn't covered, and the held-back shapes.

**The profile:** one entry per pattern, as the contract says, with `"status": "proposed"` while the entry is a draft.

**The path file:** create or update it, and name it in the project's agent guide.

**Rules:** write one only where the shape can be checked and the human wants it now. Show that it passes on the golden example and fails on a seeded fault. Otherwise sketch it in the findings.

## Findings
Everything you learned about existing code goes in one dated findings file, outside the paths the path file's `catalog` covers, never in an entry:
- **Decisions:** the human's answers, dated;
- per pattern: rough counts of uses, code that does the same job another way, and partial fits;
- twins and copies of shared code;
- golden examples you fixed, and how;
- rules that could be written, each with a sketch;
- what you didn't read. Say how much of each area the survey covered.

A gap in access or data integrity is a defect, not a note. Raise it with the human at once, and ask whether its details belong in a committed file before you write them there. Real defects go to the backlog (`backlog`); ask the human before creating items.

## Verify
- every diagram: `c4ish validate --strict`, `c4ish code <diagram> --root <repo root>` (the shared code it names still resolves), then render it and look at it;
- `c4ish code <profile> --root <repo root>` exits 0: every golden example resolves;
- in the output of `c4ish profile <profile>`, every pattern has `code` and `catalog`, and every element kind that is a container, code, data or a product concept has a `category`;
- the ids in the docs and in the profile are the same set (compare them; no command does);
- the project's formatter and doc checks pass on what you wrote;
- every test or rule you added fails on a seeded fault, and the suites you touched pass.

## Approval
- Every entry starts as a draft: marked so on its card, and `proposed` in the profile.
- Give the human the chooser tables and the diagrams first, then the entries, then the findings. Tell them which entries rest on a decision of yours.
- The human approves entry by entry. On approval, set the status and date on the card, remove `"status": "proposed"` from the profile, and commit. A later change to an approved entry needs their approval again.
- Commit the docs, diagrams, profile and path file together.
- **Timing.** A plan uses approved entries, so extend the catalog and get it approved before the plan that needs it is approved. After that approval, a catalog change stops the plan's build.

## Do
- Draw the rule from what the code does most often and what the shared code enforces, then check it with the human.
- Keep entries short enough to read in two minutes. A plan author reads one before drawing an element; an implementer reads one before building it.

## Don't
- Put what you found about existing code in an entry. An entry states the rule; the contract says what it may point at.
- Tag code in bulk. Tags are added when a plan creates or changes a definition.
- Loosen a rule or a requirement so that existing code passes.
- Invent patterns the code doesn't have, or name a pattern after its folder.
- Change production behaviour to make an example fit without the human's say. A dead branch or a missing test is yours to fix; a product change is theirs.
