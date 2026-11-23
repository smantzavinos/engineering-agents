# Pattern catalog contract

What a project's pattern catalog must hold so that plans, builds and reviews can use it. The project owns the content. This page fixes only the form.

A pattern is an approved shape for a recurring piece of code. It is defined by **what every definition must go through or have**, not by where the code sits: usually shared code (a guard, a filter, a helper); for a data shape or a rule of single access, the thing itself (the field and its index, the one reader of a secret).

## Where it lives

The project's agent guide names one **path file** (JSON). Paths and globs are from the repository root; a path with no wildcard also covers everything under it.

| Key | Holds |
|---|---|
| `profile` | The catalog profile: one diagram-tool (`c4ish`) profile file |
| `catalog` | The catalog docs, including any older doc an entry links for its rules |
| `rules` | Where the conformance rules live. It may match nothing yet |
| `leftOut` | Paths the model-to-code check leaves out: tests, docs, generated files, the plans directory |
| `noTag` | File types that cannot carry a comment. Setting it replaces the default (JSON files), so include them |
| `enforcement` | Optional. Maps the levels `platform`, `platform-correlated`, `derived`, `our-code`, `nothing` to the profile's own ids |

Where the code sits in git submodules of the repository that holds the path file, every path and glob starts with the submodule's path, and the path file and the profile stay in that repository.

The path file and the profile are committed. A plan cannot be approved before they are: the check reads both at the approval commit.

## The docs

One file per area (for example backend, web, data). Each opens with:
- the rules every pattern in the area shares, stated once;
- a **chooser table**: what the code is → the pattern that fits. Entries don't repeat it;
- what the area doesn't cover yet.

## An entry

In this order:

1. **Card.** The id (`<family>/<name>`), then four lines: what it is, what it goes through, what it protects against, its status (draft, or approved with the date). An id starts with a letter or digit and uses only letters, digits, `.`, `_`, `/` and `-`, so that a tag can carry it.
2. **Shape.**
   - A small diagram: what a plan adds drawn as new, the shared code as reused.
   - A short code block of the intended form, with a marked line (`// R1`) for each requirement the code shows.
   - A wrong example of a few lines, and why it is wrong.
   - **One golden example:** a single use of the pattern, given as the code references of all its pieces from the repository root (the definition, and any handler or registration the pattern needs).
3. **Requirements**, numbered `R1`, `R2`, …. Each names what checks it: a test, the reviewer, or a rule with the rule's path. A rule's row says what the rule proves; code review skips only that.
4. **Conventions**, numbered `C1`, `C2`, …, kept apart from the requirements.
5. **Tests a new one needs**, with the test files a new definition adds a case to.
6. **In a plan model:** the element kind, its relationships and who enforces each, its contract clause, and the patterns it usually comes with.

## An entry states the rule, not the state of the code

- The golden example is the entry's only pointer to code that uses the pattern.
- An entry may name the shared code the pattern goes through, the test files a new definition adds to, the kinds of thing it applies to, and a doc that holds fuller rules. It points at no other code that uses the pattern.
- No lists of partial fits or divergences, and no usage counts. What is found about existing code goes to a findings file outside the catalog, to the backlog, or to a plan.

## The golden example is a full fit

It meets every requirement and has every test the entry asks for. Code that falls short is fixed, or another example is chosen. A partial fit is never listed as the golden example. A pattern with no full fit anywhere is not an entry yet: it is listed under what its area doesn't cover.

The golden example carries its tag, so that a reader copies the tag with the shape.

## What makes a fit

| The definition | Is | Tag |
|---|---|---|
| Meets every requirement | A full fit | `@pattern <id>` |
| Misses a requirement | A partial fit | `@pattern <id> partial: R4, R5`, naming each number |
| Misses a convention | A full fit with a review comment | `@pattern <id>` |
| Replaces the shared code with its own copy | A defect to fix. Not a partial fit, and not bespoke | none |
| Fits no pattern, and is a one-off | Bespoke | `@pattern bespoke: <what it is>` |

Where the call to the shared code sits is not part of the fit: in the definition itself, or in a helper it delegates to.

## The profile

One `c4ish` profile beside the catalog, durable and separate from any plan. It is the machine-readable index of the catalog, and plan models reference it.
- One entry per pattern: id, label, family, how it is drawn, `catalog` (the link to its section in the docs), and `code` (the golden example's references). The docs and the profile name the same example; change both together.
- A draft entry has `"status": "proposed"`, so a plan model that uses it draws it as proposed. Approval removes the line.
- A `category` for every element kind the project adds that is a container, code, data or a product concept. A kind that is none of these (a person, an external system) has none.
- The ids in the docs and in the profile are the same set.
- It lists patterns, not where they are used. There is no usage index: search the tags.

Check it two ways. `c4ish code <profile> --root <repo root>` fails when a golden example no longer resolves; it passes a pattern that names none. So also read the resolved profile (`c4ish profile <profile>`): every pattern has `code` and `catalog`.

## Tags

One comment directly above the definition. `@pattern` is the first word of the comment line, and the tag is one line. When the definition is a whole file, the tag is the file's first comment.

The check reads a tag after one of these comment markers: `//`, `/*`, `{/*`, a leading `*` inside a block comment, `#`, `<!--`, `--`, `;`, `%`. In a language with another comment syntax (a docstring, for example) the tag is not seen: list that file type under `noTag`.

| Form | For |
|---|---|
| `@pattern <id>` | Follows the pattern |
| `@pattern <id> partial: R4, R5` | A partial fit, naming the requirements it misses. That pattern's rule skips it |
| `@pattern bespoke: <what it is>` | A one-off |
| `; also <id>, <id>` added to any form | Further patterns the definition carries. Their rules still run |

- Untagged code is **unknown**, not "follows no pattern".
- A tag is added or changed only when a plan creates or changes that definition, or when the definition becomes a golden example. Never retag in bulk.
- A file type with no comment syntax carries no tag; list it under `noTag`.

## Rules

A rule is optional: a pattern has one where its shape can be checked. It fails tagged code that doesn't match its pattern and warns on untagged code of a known shape. It proves a shape, not the logic inside. A rule passes on the golden example and fails on a seeded fault, and is never loosened to earn a skip in review. Rules that exist run on changed files in the fast gates. A requirement no rule checks is the reviewer's.

## Shapes used once

A shape with one use is not a pattern. It is held back: listed by name at the end of its area file, and tagged `@pattern bespoke:` when a plan next touches it. The second use makes it a pattern.

## Who approves

The human approves every entry and every change to one. An entry is a draft until then, and nothing in a draft is binding.

- A plan uses approved entries. A draft a plan needs is approved first, in a commit before the plan's approval.
- A plan that needs a new shape proposes the pattern, and the human approves it with the plan.
- After a plan is approved, a change to the catalog, the profile or the path file stops that plan's build for re-approval. Change the catalog before the approval, or in a plan that proposes the change.
