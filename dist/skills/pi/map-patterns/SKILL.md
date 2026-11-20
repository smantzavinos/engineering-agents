---
name: map-patterns
description: Reverse-engineer the patterns a codebase already uses and write them into the project's pattern catalog — the entries, one golden example each, the catalog profile and the path file — with what was found about existing code kept outside it. Use to start a catalog, to extend it to an area a plan is about to touch, or to change an entry. The human approves every entry.
compatibility: pi
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
1. **Read what the project already says:** its agent guide, architecture and coding rules, any existing pattern or schema docs, lint and structural rules. A rule the project already wrote down is a pattern candidate with an owner. Don't restate a doc that already works as an entry; give it ids and link it.
2. **Find the shared code.** A pattern is defined by the shared code a definition must go through: a guard, a visibility filter, a write helper, a loader, a frame. List those first, by area. Then find what goes through each.
3. **Survey with fast subagents** (`delegate`): per area, every definition of a kind (every query, every write, every page, every form action), which shared code it reaches, and how it differs from its neighbours. Ask for tables, not prose.
4. **Read the critical code yourself:** every shared helper, and three or four uses of each candidate, including the odd ones. The entry is your judgment, not the survey's.
5. **Decide what each candidate is:**

   | What you found | It is |
   |---|---|
   | Two or more uses going through the same shared code | A pattern |
   | The same job done with and without the shared code | One pattern. The uses without it are findings |
   | Two helpers doing one job | One pattern through one of them. The twin is a finding |
   | One use | Held back: listed at the end of its area, tagged bespoke when next touched |
   | A shape defined by where files sit, with nothing shared behind it | A convention of another pattern, or nothing |
   | Recurring code the project wants to stop writing | Not a pattern. A finding |

6. **Ask the human** the questions only they can answer, batched: which of two competing shapes is the rule, whether a divergence is deliberate, what is in scope. Record each answer with its date.

## Write
For each pattern, in the contract's order:
1. **The card.** Name the shared code by path. Say what the pattern protects against in one line; if you can't, it may not be a pattern.
2. **The requirements.** Each is something a definition must do, that a reader can check on one definition, with what checks it. Keep conventions apart. Fewer, sharper requirements are better: a requirement no test, reviewer or rule could fail is not one.
3. **The shape.** The intended form as a short code block with a marked line per requirement, taken from the golden example and cut down. A wrong example from a real mistake where there is one.
4. **The golden example.** One, and a full fit: it meets every requirement and has every test the entry asks for. Check both by reading the code and running its tests. When the best candidate falls short:
   - fix it, in its own small commit, with its tests run and a new test shown to fail on a seeded fault; or
   - choose another example; or
   - if no full fit exists anywhere, the entry is not ready. Say so to the human.

   Never list a partial fit as the golden example, and never weaken a requirement to make one fit.
5. **Tests a new one needs,** naming the test files a new definition adds a case to.
6. **In a plan model.** How a plan author draws it: element kind, relationships and who enforces each, the contract clause, what it usually comes with.
7. **The diagram:** a small `c4ish` model per entry, beside the docs. What a plan adds is drawn as new, the shared code as reused, and the connector labels carry the requirement numbers.

Then, per area: the shared rules stated once, the **chooser table** (what the code is → the pattern), what isn't covered, and the held-back shapes.

**The profile:** one entry per pattern (id, label, family, how it is drawn, the link to its section, `code` = the golden example), and a `category` for each element kind the project adds. The ids in the docs and the profile are the same set.

**The path file:** create or update it (`profile`, `catalog`, `rules`, `leftOut`, `noTag`, and `enforcement` when the profile names the levels differently). `leftOut` covers tests, docs, generated files and the plans directory. Name the path file in the project's agent guide.

## Findings stay outside the catalog
An entry states the rule, not the state of the code. Everything you learned about existing code goes in one dated findings file beside the catalog's plan or in the project's docs, never in an entry:
- code that does the same job without the shared code, and partial fits, by pattern;
- twins and copies of shared code;
- gaps in access or data integrity. Raise these with the human at once; they are defects, not notes;
- shapes a rule could check, with a sketch of the rule;
- what you didn't read. Say how much of each area the survey covered.

Real defects go to the backlog (`backlog`). Ask the human before creating items.

## Verify
- every diagram: `c4ish validate --strict`, then render it and look at it;
- `c4ish code <profile> --root <repo root>` exits 0: every golden example resolves;
- the ids in the docs and in the profile match, and every element kind has a category (`c4ish profile <profile>`);
- the project's formatter and doc checks pass on what you wrote;
- every test you added fails on a seeded fault, and the suites you touched pass.

## Approval
- Every entry starts as a draft, marked so on its card.
- Give the human the chooser tables and the diagrams first, then the entries, then the findings. Tell them which entries rest on a decision of yours.
- The human approves entry by entry. On approval, set the status and date on the card and commit. A later change to an approved entry needs their approval again.
- Commit the docs, diagrams, profile and path file together. A plan can't be approved until the path file and the profile are committed.

## Do
- Draw the rule from what the code does most often and what the shared code enforces, then check it with the human.
- Keep entries short enough to read in two minutes. A plan author reads one before drawing an element; an implementer reads one before building it.

## Don't
- Point an entry at code that uses the pattern, other than the one golden example. No usage counts, no lists of fits or misses.
- Tag code in bulk. Tags are added when a plan creates or changes a definition.
- Write a rule for a shape that can't be checked, or loosen one so that existing code passes.
- Invent patterns the code doesn't have, or name a pattern after its folder.
- Change production behaviour to make an example fit without the human's say. A dead branch or a missing test is yours to fix; a product change is theirs.
