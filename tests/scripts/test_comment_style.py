"""House-style checker for bot comments (scripts/comment_style.py, scripts/post-comment.py). Pure tests; no network.

Ported from gm-agent-pipeline (pipeline/test_comment_style.py). Rules: docs/references/comment-style.md.
Requirement: FR-001
"""
import datetime
import importlib.util
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import comment_style as cs  # noqa: E402

spec = importlib.util.spec_from_file_location('post_comment', SCRIPTS / 'post-comment.py')
pc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pc)

MENU = ('<details>\n<summary><b>Reply with</b> <code>@dan-agent approve|revise|discuss|reject</code></summary>\n\n'
        '| Reply | Effect |\n|---|---|\n| `@dan-agent approve` | Accept |\n</details>')

GATE_AFTER = f"""🤖 **Needs your decision: main now has its own tool-tip speed ceiling**

## Done
- schema v8 with per-joint planning limits; P1/P2 config files updated
- added new stop cause (tool-tip speed cap hit)
- plan-time tool-tip cap and real-time speed guard

Files: [design](https://github.com/o/r/blob/x/design.md) · [plan](https://github.com/o/r/blob/x/plan.md)

## Blockers
- Conflicts with main: main caps tool-tip speed per segment at plan time ([PR #656](https://github.com/o/r/pull/656)); this branch caps it another way.

## Decisions made
- D1. Deployed P1/P2 config files keep each robot's own calibration: dropping it silently is unsafe.
- D2. Added a tool-tip error type to planner errors: the existing profile error type cannot carry the numbers.

## Questions
1. How should this item continue?
   - _Option A_: keep main's ceiling; redo the tip-cap part on top of main after a short re-plan. _[⭐ smaller change]_
   - _Option B_: keep this branch's design and remove main's ceiling.
2. Open the `schemas` PR only after the re-plan? _[⭐ yes]_

{MENU}
<!-- gate stage=Execute head=c377925b03e35117fd99a9120a7ff50bc0d3c0e9 branch=feature/item-611 plan=docs/p -->"""

GATE_BEFORE = """🤖 **Gate: Escalation** — Motion: per-joint planner limits and speed-context ceiling (config schema v8)

Needs your decision: while the bot was coding, main gained its own tool-tip speed ceiling (#656 and #652).

Files (pushed at latest commit (`c377925`) on `feature/item-611`):
- https://github.com/o/r/blob/feature/item-611/docs/records/plans/x/worklog.md

What is done on the branch (all tests green before the merge attempt: 846 passed): schema v8 with per-joint planning limits and the shipped and deployed config files (T1–T4, deployed P1/P2 keep each robot's own values), the new stop cause (value 10, package 4.2.0, descriptor regenerated), the plan-time tool-tip cap, the real-time guard and docs. Formatting, schema checks, descriptor check and buf lint passed; workspace-wide clippy could not run on this machine (an unrelated camera crate fails to build).

What went wrong: merging main stops with 11 conflicted files. Main now already carries a different tool-tip ceiling: it limits speed per segment at plan time, certifies blends and stops against a frozen tool-tip, and the real-time loop now advances by elapsed cycles (#652). Our approved design (decisions F6, F7, F8 and the stop-cause amendment) does the same job another way. Resolving the conflicts would leave two competing speed caps or silently discard approved design decisions, so the merge was aborted and nothing was changed on the branch beyond a worklog note.

Questions (my recommendation in brackets):
1. How should #611 proceed? Options: (a) keep main's ceiling; (b) keep this branch's design. [a]

> [!TIP]
> **Reply** with a comment whose first line is one of:

<!-- gate stage=Execute head=c377925 branch=feature/item-611 plan=docs/p -->"""


class Lint(unittest.TestCase):
    def test_house_style_gate_passes(self):
        self.assertEqual(cs.lint(GATE_AFTER), [])
        self.assertEqual(cs.infer_kind(GATE_AFTER), 'gate')

    def test_the_611_comment_is_rejected_with_named_reasons(self):
        problems = '\n'.join(cs.lint(GATE_BEFORE))
        for expected in ('first line must be', 'budget for gate', 'bare URL', '[!TIP]', 'must be collapsed',
                         '"gate:"', '"what is done on the branch"', '"all tests green"', 'bare IDs F6, F7, F8'):
            self.assertIn(expected, problems)

    def test_triage_ready_and_clarify_templates_pass(self):
        ready = ('🤖 **Ready to schedule: move the card to Up next when a bot should start.**\n\n'
                 '- each caller that starts a Long Move names its speed context\n'
                 '- safety-related (speed limits); overlaps [PR #656](https://x/656)\n'
                 '<!-- triage outcome=ready fields="Size=needs design Priority=P1" -->')
        self.assertEqual(cs.lint(ready), [])
        clarify = ('🤖 **Needs your decision: which part of this item should the bots take?**\n\n## Questions\n'
                   '1. Scope?\n   - _Option A_: Phase 0 + 1 only. _[⭐ J0 needs its own design]_\n   - _Option B_: all.\n'
                   '2. Verify without hardware? _[⭐ yes]_\n\n<details><summary>Reply</summary>x</details>\n'
                   '<!-- triage outcome=clarify -->')
        self.assertEqual(cs.lint(clarify), [])

    def test_visible_fields_list_and_long_ready_comment_are_flagged(self):
        ready = ('🤖 **Ready to schedule: move the card to Up next when a bot should start.**\n\n'
                 'Fields set where they were empty: Kind=feature, Origin=human-request, Priority=P1, '
                 'Track=standard-implementation. Note that "(P1)" in the title means the P1 prototype, not a '
                 'priority. I picked P1 because you are already working on this.\n<!-- triage outcome=ready -->')
        problems = '\n'.join(cs.lint(ready))
        self.assertIn('budget for triage-ready is 40', problems)
        self.assertIn('"fields set"', problems)

    def test_question_without_star_and_unknown_heading(self):
        body = ('🤖 **Needs your decision: scope**\n\n## What I found\n- x\n\n## Questions\n1. Which?\n'
                '   - _Option A_: a\n<details>m</details>\n<!-- triage outcome=clarify -->')
        problems = '\n'.join(cs.lint(body))
        self.assertIn('question 1 has no ⭐', problems)
        self.assertIn('unknown headings "## What I found"', problems)

    def test_sections_order_and_limits(self):
        body = ('🤖 **Needs your approval: plan ready**\n\n## Questions\n1. Ok? _[⭐ yes]_\n\n## Done\n'
                + ''.join(f'- thing {i}\n' for i in range(7)) + '<details>m</details>\n<!-- gate stage=Plan -->')
        problems = '\n'.join(cs.lint(body))
        self.assertIn('sections out of order', problems)
        self.assertIn('## Done has 7 bullets', problems)

    def test_empty_sections_are_flagged_and_waiting_on_is_allowed(self):
        body = ('🤖 **Waiting for checks: the review bot runs again when they finish**\n\n'
                '## Must fix\nNone.\n\n## Should fix\nNone.\n\n## Waiting on\nCI: 9 jobs still running.\n\n'
                '<details><summary>Review checklist (1 check: 1 pass)</summary>x</details>\n'
                '**Result: Waiting for checks (no action needed)**\n<!-- pr-review verdict=BLOCKED head=abc -->')
        problems = cs.lint(body)
        self.assertTrue(any('"## Must fix" is empty' in p for p in problems), problems)
        self.assertTrue(any('"## Should fix" is empty' in p for p in problems), problems)
        self.assertFalse(any('Waiting on' in p for p in problems), problems)
        trimmed = body.replace('## Must fix\nNone.\n\n## Should fix\nNone.\n\n', '')
        self.assertFalse(any('empty' in p or 'unknown heading' in p for p in cs.lint(trimmed)), cs.lint(trimmed))

    def test_machine_comments_only_need_to_stay_short(self):
        self.assertEqual(cs.lint('🤖 work: released <!-- work-claim -->'), [])
        self.assertEqual(cs.lint('🤖 fix-bot: owns this branch; session=x last-active=y'), [])
        self.assertEqual(cs.lint('🤖 Related [PR #643](u).\n<!-- pr-link pr=643 -->'), [])

    def test_close_proposal_is_not_mistaken_for_clarify(self):
        body = ('🤖 **Possibly done: duplicate of [issue #612](u). Close this issue?**\n\n'
                '- closes automatically after 48 h unless you reply\n\n<details>m</details>\n'
                '<!-- close-proposal reason=duplicate dup=612 auto_close_after=2026-10-10T14:00:00Z -->\n'
                '<!-- triage outcome=clarify -->')
        self.assertEqual(cs.infer_kind(body), 'close-proposal')
        self.assertEqual(cs.lint(body), [])

    def test_ids_inside_decisions_and_code_are_fine(self):
        body = ('🤖 **Needs your approval: design ready**\n\n## Decisions made\n- D1. Kept T3 naming: it matches.\n'
                '\nRun `T5` job.\n<details>m</details>\n<!-- gate stage=Design -->')
        self.assertEqual(cs.lint(body), [])


class Helper(unittest.TestCase):
    def test_warn_mode_until_the_enforce_date(self):
        self.assertFalse(pc.enforcing('2026-10-16', datetime.date(2026, 10, 15)))
        self.assertTrue(pc.enforcing('2026-10-16', datetime.date(2026, 10, 16)))
        self.assertFalse(pc.enforcing('', datetime.date(2030, 1, 1)))


if __name__ == '__main__':
    unittest.main()
