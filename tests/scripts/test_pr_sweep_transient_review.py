"""Only explicit machine-classified pending reviews may resume.

Ported from gm-agent-pipeline (pipeline/test_transient_review.py).
Requirement: FR-001
"""
import importlib.util
import json
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = __import__('pathlib').Path(__file__).resolve().parents[2] / 'scripts'
ROOT = Path(__file__).resolve().parent
HEAD = 'a' * 40


def dispatcher():
    # Checks only a person can satisfy are configured per install (PR_HUMAN_CHECKS); these tests use a label gate.
    with patch.dict('os.environ', {'PR_HUMAN_CHECKS': 'require-label / Require Label, label / Require Label'}):
        spec = importlib.util.spec_from_file_location('sweep_transient', SCRIPTS / 'pr-sweep-dispatch.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    module.REQUIRE_LOGS = False  # log evidence is covered by test_pr_sweep_result_evidence.py
    module.OWNERS, module.LOGINS = frozenset({'owner'}), {'bot'}
    return module


def setup_dispatcher(temp):
    """A dispatcher on a TEST ONLY PR with two FIX verdicts; spawn() records instead of launching."""
    d = dispatcher()
    d.RESULTS = Path(temp) / 'results'
    d.RESULTS.mkdir()
    d.LOGS = Path(temp) / 'logs'
    d.LOGS.mkdir()
    d.DRY = True
    d.alive = lambda pid: False
    d.set_state_label = lambda *args: None
    d.remove_label = lambda *args: None
    pr = {'number': 1, 'title': 'TEST ONLY', 'headRefName': 'test', 'headRefOid': HEAD,
          'labels': [{'name': 'fix-bot:queued'}], 'isDraft': False,
          'statusCheckRollup': [{'name': 'Rust tests', 'status': 'COMPLETED', 'conclusion': 'FAILURE'}]}
    comments = [{'id': i, 'body': '<!-- pr-review verdict=FIX head=' + HEAD + ' -->',
                 'user': {'login': 'owner'}} for i in (1, 2)]
    d.gh = lambda *args: [pr] if args[0] == 'pr' else (comments if '/comments' in args[1] else [])
    events = []

    def spawn(kind, *args):
        events.append((kind, args))
        return 0, 'TEST_ONLY'
    d.spawn = spawn
    return d, events


class TransientReviewTests(unittest.TestCase):
    def test_explicit_pending_review_resumes_only_after_checks_pass(self):
        d = dispatcher()
        self.assertTrue(hasattr(d, 'transient_review_due'))
        with tempfile.TemporaryDirectory() as temp:
            d.RESULTS = Path(temp)
            result = {'verdict': 'BLOCKED', 'owner_decision': False,
                      'blocked_reason': 'PENDING_CI', 'url': 'exact-verdict'}
            rec = {'tag': 'review', 'ts': 1}
            verdict = ('BLOCKED', HEAD, {'html_url': 'exact-verdict'})
            complete = [{'name': 'Rust tests', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
            path = d.RESULTS / 'review.json'
            path.write_text(json.dumps(result))
            with patch.object(d, 'has_result', return_value=True):
                self.assertTrue(d.transient_review_due([rec], complete, verdict, HEAD))
                self.assertFalse(d.transient_review_due([rec], [], verdict, HEAD))
                self.assertFalse(d.transient_review_due([rec], complete, verdict, 'b' * 40))
                self.assertFalse(d.transient_review_due([rec], complete,
                    ('BLOCKED', HEAD, {'html_url': 'new-owner-ruling'}), HEAD))
                for fields in ({'owner_decision': True}, {'blocked_reason': 'OTHER'},
                               {'blocked_reason': None}):
                    path.write_text(json.dumps({**result, **fields}))
                    self.assertFalse(d.transient_review_due([rec], complete, verdict, HEAD))

    def test_human_workflow_alias_does_not_block_ready(self):
        d = dispatcher()
        checks = [{'name': 'require-label / Require Label', 'status': 'COMPLETED', 'conclusion': 'FAILURE'},
                  {'name': 'Rust tests', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
        fires, _, ready = d.ci_round_due(checks, set(), HEAD, HEAD)
        self.assertEqual(fires, [])
        self.assertTrue(ready)


class WaitingForChecksTests(unittest.TestCase):
    """A review whose only blocker is pending checks keeps a bot label; it never reaches the owner."""
    PENDING = [{'name': 'Rust tests', 'status': 'IN_PROGRESS', 'conclusion': ''}]
    DONE = [{'name': 'Rust tests', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
    VERDICT = ('BLOCKED', HEAD, {'html_url': 'exact-verdict'})

    def setUp(self):
        self.d = dispatcher()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.d.RESULTS = Path(self.temp.name)
        self.rec = {'tag': 'review', 'ts': 1, 'kind': 'review', 'head': HEAD}
        self.write({'verdict': 'BLOCKED', 'owner_decision': False, 'blocked_reason': 'PENDING_CI',
                    'url': 'exact-verdict'})
        patcher = patch.object(self.d, 'has_result', return_value=True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, result):
        (self.d.RESULTS / 'review.json').write_text(json.dumps(result))

    def wanted(self, rollup, mention=None, done=False):
        d = self.d
        return d.review_wanted(d.REVIEW_QUEUED, [d.REVIEW_QUEUED], done, mention,
                               [self.rec], rollup, self.VERDICT, HEAD)

    def test_no_review_starts_while_checks_are_pending(self):
        self.assertFalse(self.wanted(self.PENDING))
        self.assertFalse(self.wanted([]))

    def test_review_starts_once_checks_finish(self):
        self.assertTrue(self.wanted(self.DONE))

    def test_explicit_review_request_still_runs_while_pending(self):
        self.assertTrue(self.wanted(self.PENDING, mention={'id': 1}))

    def test_waiting_result_is_not_final_so_the_tick_cannot_relabel_it(self):
        self.assertFalse(self.d.handled_dispatch(self.rec))
        self.assertTrue(self.d.waiting_for_checks([self.rec], self.VERDICT, HEAD))

    def test_waiting_result_sends_no_owner_message(self):
        self.assertTrue(self.d.is_waiting_result(json.loads((self.d.RESULTS / 'review.json').read_text())))
        self.assertFalse(self.d.is_waiting_result({'verdict': 'BLOCKED', 'owner_decision': True,
                                                   'blocked_reason': 'PENDING_CI'}))
        self.assertFalse(self.d.is_waiting_result({'verdict': 'BLOCKED', 'owner_decision': False,
                                                   'blocked_reason': 'OTHER'}))

    def sweep_fixture(self, temp):
        d, events = setup_dispatcher(temp)
        d.DRY = False
        labels = []
        d.set_state_label = lambda repo, n, label: labels.append(label)
        url = 'https://github.com/owner/repo/pull/1#issuecomment-42'
        original = d.gh

        def gh(*args):
            data = original(*args)
            if args[0] == 'pr':
                data[0]['labels'] = [{'name': 'review-bot:queued'}]
                data[0]['statusCheckRollup'] = self.DONE
            elif '/comments' in args[1]:
                return [{'id': 42, 'html_url': url, 'user': {'login': 'owner'},
                         'body': '<!-- pr-review verdict=BLOCKED head=' + HEAD + ' -->'}]
            return data
        d.gh = gh
        return d, events, labels, url

    def sweep_recs(self, d, url, count, owner_decision, reason):
        recs = []
        for i in range(count):
            (d.RESULTS / f'w{i}.json').write_text(json.dumps(
                {'repo': 'owner/repo', 'kind': 'review', 'pr': 1, 'head': HEAD, 'verdict': 'BLOCKED',
                 'owner_decision': owner_decision, 'blocked_reason': reason, 'url': url}))
            recs.append({'repo': 'owner/repo', 'pr': 1, 'head': HEAD, 'kind': 'review',
                         'tag': f'w{i}', 'pid': 1, 'ts': 1 + i})
        return recs

    def test_open_owner_question_still_needs_the_owner(self):
        """Sweep level: an owner_decision:true BLOCKED result at the head, PR still review-bot:queued."""
        with tempfile.TemporaryDirectory() as temp:
            d, events, labels, url = self.sweep_fixture(temp)
            recs = self.sweep_recs(d, url, 1, True, 'OTHER')
            d.sweep_repo('owner/repo', recs, set())
            self.assertEqual(labels, [d.HUMAN_DECISION])
            self.assertEqual(events, [])

    def test_pr214_finished_waiting_review_runs_again_when_checks_complete(self):
        """Sweep level, real PR 214: waiting result at head, checks done, label still queued."""
        with tempfile.TemporaryDirectory() as temp:
            d, events, labels, url = self.sweep_fixture(temp)
            d.DISPATCH = Path(temp) / 'dispatches.jsonl'
            recs = self.sweep_recs(d, url, 1, False, 'PENDING_CI')
            d.sweep_repo('owner/repo', recs, set())
            self.assertEqual(labels, [d.REVIEW_RUNNING])
            self.assertEqual(len(events), 1)

    def test_classic_commit_status_does_not_block_completion(self):
        """A StatusContext entry (state, no status) must not hold a waiting review forever."""
        ctx = {'__typename': 'StatusContext', 'context': 'sonar', 'state': 'SUCCESS'}
        self.assertTrue(self.wanted(self.DONE + [ctx]))
        self.assertFalse(self.wanted(self.DONE + [{**ctx, 'state': 'PENDING'}]))

    def _recs(self, count, ts):
        recs = []
        for i in range(count):
            self.write({'verdict': 'BLOCKED', 'owner_decision': False, 'blocked_reason': 'PENDING_CI',
                        'url': 'exact-verdict'})
            (self.d.RESULTS / f'w{i}.json').write_text((self.d.RESULTS / 'review.json').read_text())
            recs.append({'tag': f'w{i}', 'ts': ts + i, 'kind': 'review', 'head': HEAD})
        return recs

    def wanted_recs(self, recs, rollup, now):
        d = self.d
        return d.review_wanted(d.REVIEW_QUEUED, [d.REVIEW_QUEUED], False, None, recs, rollup, self.VERDICT, HEAD, now=now)

    def test_failed_or_cancelled_rollup_wants_a_review(self):
        for conclusion in ('FAILURE', 'CANCELLED', 'TIMED_OUT'):
            rollup = [{'name': 'Rust tests', 'status': 'COMPLETED', 'conclusion': conclusion},
                      {'name': 'label / Require Label', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
            with self.subTest(conclusion=conclusion):
                self.assertTrue(self.wanted(rollup))
        self.assertFalse(self.wanted(self.PENDING + [{'name': 'x', 'status': 'COMPLETED', 'conclusion': 'FAILURE'}]))
        # the human Require Label gate being incomplete does not hold the review
        self.assertTrue(self.wanted(self.DONE + [{'name': 'label / Require Label', 'status': 'QUEUED', 'conclusion': ''}]))

    def test_no_new_waiting_review_inside_the_recheck_gap(self):
        d = self.d
        recs = self._recs(1, 10_000)
        self.assertEqual(d.WAIT_RECHECK_SECS, 20 * 60)
        self.assertFalse(self.wanted_recs(recs, self.DONE, 10_000 + d.WAIT_RECHECK_SECS - 1))
        self.assertTrue(self.wanted_recs(recs, self.DONE, 10_000 + d.WAIT_RECHECK_SECS))

    def test_waiting_reviews_are_capped_per_head(self):
        d = self.d
        self.assertEqual(d.WAIT_REVIEW_CAP, 3)
        recs = self._recs(d.WAIT_REVIEW_CAP - 1, 1)
        self.assertTrue(self.wanted_recs(recs, self.DONE, 10 ** 6))
        self.assertFalse(d.waiting_exhausted(recs, self.VERDICT, HEAD))
        recs = self._recs(d.WAIT_REVIEW_CAP, 1)
        self.assertTrue(d.waiting_exhausted(recs, self.VERDICT, HEAD))
        self.assertFalse(self.wanted_recs(recs, self.DONE, 10 ** 6))

    def test_sweep_escalates_once_when_checks_never_settle(self):
        with tempfile.TemporaryDirectory() as temp:
            d, events, labels, url = self.sweep_fixture(temp)
            recs = self.sweep_recs(d, url, d.WAIT_REVIEW_CAP, False, 'PENDING_CI')
            reported = set()
            before = len(d.out)
            d.sweep_repo('owner/repo', recs, reported)
            d.sweep_repo('owner/repo', recs, reported)
            self.assertEqual(events, [])
            self.assertEqual(labels[:1], [d.HUMAN_DECISION])
            self.assertEqual(len([l for l in d.out[before:] if 'never settled' in l]), 1)

    def test_review_prompt_has_the_waiting_ending_and_carry_forward_rule(self):
        review = (SCRIPTS / 'pr-sweep-prompts/review.md').read_text(encoding='utf-8')
        for phrase in ('🤖 **Waiting for checks: the review bot runs again when they finish**',
                       '**Result: Waiting for checks (no action needed)**', '`review-bot:queued`',
                       'asks the owner something', 'even if checks are also pending'):
            self.assertIn(phrase, review)
        template = (SCRIPTS.parent / 'docs/references/comment-style.md').read_text(encoding='utf-8')
        self.assertIn('Waiting for checks', template)
        sys.path.insert(0, str(SCRIPTS))
        import comment_style
        self.assertIn('Waiting for checks', comment_style.WHO)


if __name__ == '__main__':
    unittest.main()
