"""Unanswered review threads (e.g. Copilot) must be answered before a PR counts as ready to merge.

Ported from gm-agent-pipeline (pipeline/test_review_threads.py).
Requirement: FR-001
"""
import os
import runpy
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = __import__('pathlib').Path(__file__).resolve().parents[2] / 'scripts'
HERE = Path(__file__).resolve().parent


def load():
    with mock.patch.dict(os.environ, {"PR_SWEEP_REPOS": "o/r", "PR_AGENT_HANDLE": "agent owner", "PR_SWEEP_DRY": "1"}):
        return runpy.run_path(str(SCRIPTS / "pr-sweep-dispatch.py"))


def thread(resolved, *authors):
    return {"isResolved": resolved,
            "comments": {"nodes": [{"databaseId": i, "author": {"login": a}} for i, a in enumerate(authors, 1)]}}


class Threads(unittest.TestCase):
    def setUp(self):
        self.g = load()
        self.authors = set(self.g["LOGINS"])

    def test_copilot_thread_without_reply_is_open(self):
        self.assertEqual(self.g["unanswered_threads"]([thread(False, "copilot-pull-request-reviewer")], self.authors), [1])

    def test_answered_or_resolved_threads_are_not_open(self):
        f = self.g["unanswered_threads"]
        self.assertEqual(f([thread(False, "copilot-pull-request-reviewer", "owner")], self.authors), [])
        self.assertEqual(f([thread(True, "copilot-pull-request-reviewer")], self.authors), [])

    def test_follow_up_after_our_answer_reopens_it(self):
        f = self.g["unanswered_threads"]
        self.assertEqual(f([thread(False, "copilot-pull-request-reviewer", "owner", "someone")], self.authors), [3])

    def test_bot_rounds_no_longer_require_an_active_claim(self):
        src = (SCRIPTS / "pr-sweep-dispatch.py").read_text(encoding="utf-8")
        self.assertIn('bot_round = (owned or claim == "none") and bot_rev is not None', src)
        self.assertIn("thread_round", src)

    def test_green_ci_does_not_send_a_pr_with_open_threads_back_to_merge(self):
        src = (SCRIPTS / "pr-sweep-dispatch.py").read_text(encoding="utf-8")
        self.assertIn("label == FIX_QUEUED and ready_at_head and not open_threads", src)

    def test_prompts_forbid_ready_and_stopping_with_open_threads(self):
        review = (SCRIPTS / "pr-sweep-prompts" / "review.md").read_text(encoding="utf-8")
        babysit = (SCRIPTS / "pr-sweep-prompts" / "babysit.md").read_text(encoding="utf-8")
        self.assertIn("cannot be READY while such a thread exists", review)
        self.assertIn("a READY verdict does not excuse an unanswered thread", babysit)


if __name__ == "__main__":
    unittest.main()
