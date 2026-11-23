"""PR-sweep progress guarantees, exercised against the INSTALLED dispatcher (offline, TEST ONLY data).

Label pattern: `review-bot:*` / `fix-bot:*` = a bot acts next; `needs-human:*` = a person acts next.
Invariant: a PR never keeps a bot state label that no bot will act on.

Ported from gm-agent-pipeline (pipeline/test_sweep_progress.py).
Requirement: FR-001
"""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest

SCRIPTS = __import__('pathlib').Path(__file__).resolve().parents[2] / 'scripts'
HERE = Path(__file__).resolve().parent
REPO = 'owner/repo'
OLD = 'a' * 40
NEW = 'b' * 40


def load(state):
    env = {'PR_SWEEP_STATE': str(state), 'PR_AGENT_HANDLE': 'agent', 'PR_SWEEP_REPOS': REPO}
    previous = {k: os.environ.get(k) for k in env}
    os.environ.update(env)
    try:
        spec = importlib.util.spec_from_file_location('installed_sweep', SCRIPTS / 'pr-sweep-dispatch.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        for k, v in previous.items():
            os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)
    for d in (module.STATE, module.RESULTS, module.LOGS):
        d.mkdir(parents=True, exist_ok=True)
    module.REQUIRE_LOGS = False  # these tests exercise label flow; log evidence: test_pr_sweep_result_evidence.py
    return module


class Harness:
    def __init__(self, module, labels, comments, head=NEW):
        self.m, self.labels, self.comments, self.head = module, list(labels), comments, head
        self.spawned, self.label_writes, self.posted = [], [], []
        module.alive = lambda pid: False
        module.gh = self.gh
        module.spawn = self.spawn
        module.out.clear()

    def gh(self, *args, parse=True):
        if args[:2] == ('pr', 'list'):
            return [{'number': 7, 'title': 'TEST ONLY', 'headRefName': 'feature/x', 'headRefOid': self.head,
                     'labels': [{'name': l} for l in self.labels], 'isDraft': False, 'statusCheckRollup': []}]
        path = next(a for a in args if a.startswith('repos/'))
        if '-X' in args and path.endswith('/comments'):
            self.posted.append(args[-1].split('=', 1)[1])
            self.comments.append({'id': 900 + len(self.posted), 'user': {'login': 'bot'}, 'body': self.posted[-1],
                                  'html_url': 'https://example.invalid/posted'})
            return ''
        if '-X' in args:
            method = args[args.index('-X') + 1]
            name = path.rsplit('/', 1)[1] if method == 'DELETE' else args[-1].split('=', 1)[1]
            self.label_writes.append((method, name))
            if method == 'DELETE':
                self.labels.remove(name)
            elif name not in self.labels:
                self.labels.append(name)
            return ''
        if path.endswith('/labels'):
            return [{'name': l} for l in self.labels]
        if '/comments' in path:
            return self.comments
        if '/reviews' in path:
            return []
        raise AssertionError('unexpected TEST ONLY GitHub call: %r' % (args,))

    def spawn(self, kind, repo, pr, head, *rest, **kwargs):
        self.spawned.append((kind, head, (rest[-1] if rest and isinstance(rest[-1], dict) else {})))
        return 4242, f'{kind}-test-{len(self.spawned)}'

    def kinds(self):
        return [(k, h) for k, h, _ in self.spawned]


def claim(session='babysit-pr7-aaaaaaaa-1', when='2026-01-01T00:00:00Z', legacy=False):
    body = (f'babysit: session={session} heartbeat={when}' if legacy
            else f'fix-bot: owns this branch; session={session} last-active={when}')
    return {'id': 1, 'user': {'login': 'owner'}, 'body': body, 'html_url': 'https://example.invalid/c1'}


def verdict(kind, head=NEW, cid=2):
    return {'id': cid, 'user': {'login': 'owner'}, 'html_url': f'https://example.invalid/c{cid}',
            'body': f'**Verdict: {kind}**\n<!-- pr-review verdict={kind} head={head} -->'}


def now_iso():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


class SweepProgressTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.m = load(Path(self.temp.name))

    def tearDown(self):
        self.temp.cleanup()

    def result(self, tag, **fields):
        (self.m.RESULTS / f'{tag}.json').write_text(json.dumps({'repo': REPO, 'pr': 7, **fields}))

    def fixed_round(self, ts):
        tag = 'babysit-pr7-aaaaaaaa-1'
        self.result(tag, kind='babysit', input_head=OLD, head=NEW, status='FIXED')
        return {'ts': ts, 'kind': 'babysit', 'repo': REPO, 'pr': 7, 'head': OLD, 'pid': 1, 'tag': tag}

    def review_rec(self, verdict_kind, ts, head=NEW, tag='review-pr7-bbbbbbbb-1', **extra):
        self.result(tag, kind='review', head=head, verdict=verdict_kind, **extra)
        return {'ts': ts, 'kind': 'review', 'repo': REPO, 'pr': 7, 'head': head, 'pid': 1, 'tag': tag}

    def stalls(self):
        return [line for line in self.m.out if 'no bot is due to act' in line]

    # --- naming

    def test_label_vocabulary_separates_bot_states_from_human_states(self):
        self.assertTrue(all(l.startswith(('review-bot:', 'fix-bot:')) for l in self.m.BOT_STATES))
        self.assertTrue(all(l.startswith('needs-human:') for l in self.m.HUMAN_STATES))
        self.assertEqual(set(self.m.STATE_LABELS), set(self.m.BOT_STATES) | set(self.m.HUMAN_STATES))
        self.assertFalse([l for l in self.m.STATE_LABELS if l.startswith('pr:')])

    def test_legacy_labels_are_renamed_on_sight(self):
        h = Harness(self.m, ['pr:escalated', 'pr:babysat'], [claim(legacy=True)])
        self.m.sweep_repo(REPO, [], set())
        self.assertEqual(sorted(h.labels), ['fix-bot:owns-branch', 'needs-human:decision'])

    def test_legacy_claim_comment_is_still_recognised(self):
        self.assertEqual(self.m.claim_state(['fix-bot:owns-branch'], [claim(legacy=True)], time.time()), 'active')
        self.assertTrue(self.m.sweep_owned([claim(legacy=True)]))
        self.assertTrue(self.m.sweep_owned([claim()]))

    # --- liveness

    def test_fix_bot_push_without_state_label_is_reviewed(self):
        h = Harness(self.m, ['fix-bot:owns-branch'], [claim()])
        self.m.sweep_repo(REPO, [self.fixed_round(time.time() - 60)], set())
        self.assertIn(('POST', 'review-bot:queued'), h.label_writes)
        self.assertEqual(h.kinds(), [('review', NEW)])

    def test_fix_verdict_starts_the_fix_bot_without_a_prior_claim(self):
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX')])
        self.m.sweep_repo(REPO, [self.review_rec('FIX', time.time() - 60)], set())
        self.assertEqual(h.kinds(), [('babysit', NEW)])
        self.assertEqual(h.spawned[0][2]['trigger'], 'verdict')

    def test_fix_verdict_with_a_chat_session_holding_the_branch_goes_to_a_human(self):
        chat = claim('chat-session-1', now_iso())
        h = Harness(self.m, ['fix-bot:queued', 'fix-bot:owns-branch'], [chat, verdict('FIX')])
        self.m.sweep_repo(REPO, [self.review_rec('FIX', time.time() - 60)], set())
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)
        self.assertNotIn('fix-bot:queued', h.labels)
        self.assertTrue(any('chat session holds this branch' in line for line in self.m.out), self.m.out)

    def test_fix_loop_cap_hands_over_to_a_human(self):
        comments = [verdict('FIX', OLD, 2), verdict('FIX', OLD, 3), verdict('FIX', NEW, 4)]
        h = Harness(self.m, ['fix-bot:queued'], comments)
        self.m.sweep_repo(REPO, [self.review_rec('FIX', time.time() - 60)], set())
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)
        self.assertTrue(any('asked for changes 3 times' in line for line in self.m.out), self.m.out)

    def test_fix_bot_escalation_moves_the_pr_to_a_human_label(self):
        tag = 'babysit-pr7-bbbbbbbb-9'
        self.result(tag, kind='babysit', input_head=NEW, head=NEW, status='ESCALATE', owner_decision=True)
        recs = [self.review_rec('FIX', time.time() - 120),
                {'ts': time.time() - 60, 'kind': 'babysit', 'repo': REPO, 'pr': 7, 'head': NEW, 'pid': 1,
                 'tag': tag, 'verdict_id': 2}]
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX')])
        self.m.sweep_repo(REPO, recs, set())
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)

    # --- fix round without a code push

    def no_code_round(self, ts, verdict_id=2, flag=True, head=NEW, result_head=None, status='FIXED', **more):
        tag = 'babysit-pr7-bbbbbbbb-5'
        fields = {'addressed_without_code': True} if flag else {}
        self.result(tag, kind='babysit', input_head=head, head=result_head or head, status=status, **fields, **more)
        return {'ts': ts, 'kind': 'babysit', 'repo': REPO, 'pr': 7, 'head': head, 'pid': 1, 'tag': tag,
                'verdict_id': verdict_id}

    def test_description_only_fix_round_goes_back_to_the_review_bot(self):
        # PR 557: FIX review at H, the fix bot edited the PR body, pushed nothing, said it is addressed.
        recs = [self.review_rec('FIX', time.time() - 120), self.no_code_round(time.time() - 60)]
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX')])
        self.m.sweep_repo(REPO, recs, set())
        self.assertEqual(h.kinds(), [('review', NEW)])
        self.assertIn('review-bot:running', h.labels)
        self.assertNotIn('needs-human:decision', h.labels)
        self.assertEqual(h.posted, [])

    def test_review_launched_after_a_description_only_round_is_not_launched_twice(self):
        recs = [self.review_rec('FIX', time.time() - 120), self.no_code_round(time.time() - 60),
                {'ts': time.time() - 30, 'kind': 'review', 'repo': REPO, 'pr': 7, 'head': NEW, 'pid': 1,
                 'tag': 'review-pr7-bbbbbbbb-2'}]
        h = Harness(self.m, ['review-bot:running'], [verdict('FIX')])
        self.m.alive = lambda pid: True
        self.m.sweep_repo(REPO, recs, set())
        self.assertEqual(h.spawned, [])
        self.assertEqual(h.posted, [])

    def test_fix_round_that_did_nothing_goes_to_the_owner_with_one_comment(self):
        recs = [self.review_rec('FIX', time.time() - 120), self.no_code_round(time.time() - 60, flag=False)]
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX')])
        reported = set()
        self.m.sweep_repo(REPO, recs, reported)
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)
        self.assertEqual(len(h.posted), 1, h.posted)
        body = h.posted[0]
        self.assertTrue(body.startswith('\U0001F916 **Needs your decision:'), body)
        self.assertIn('<details>', body)
        self.assertIn('without changing code', body)
        import comment_style
        self.assertEqual(comment_style.lint(body), [])
        self.m.sweep_repo(REPO, recs, reported)  # later ticks stay quiet
        self.m.sweep_repo(REPO, recs, set())  # even when the sent-list is lost: the marker dedupes
        self.assertEqual(len(h.posted), 1, h.posted)

    def test_review_that_repeats_the_fix_after_description_only_rounds_goes_to_the_owner(self):
        comments = [verdict('FIX', NEW, 2), verdict('FIX', NEW, 3), verdict('FIX', NEW, 4)]
        recs = [self.review_rec('FIX', time.time() - 300), self.no_code_round(time.time() - 200, verdict_id=4)]
        h = Harness(self.m, ['fix-bot:queued'], comments)
        self.m.sweep_repo(REPO, recs, set())
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)
        self.assertEqual(h.posted, [], 'the review comment is the one the person reads; the sweep adds none')
        self.assertEqual(len([l for l in self.m.out if 'needs-human:decision' in l]), 1)

    def test_description_only_round_with_review_bot_queued_launches_the_review(self):
        # babysit.md has the fix bot set review-bot:queued itself; the relaxed done_at_head must be enough.
        recs = [self.review_rec('FIX', time.time() - 120), self.no_code_round(time.time() - 60)]
        h = Harness(self.m, ['review-bot:queued'], [verdict('FIX')])
        self.m.sweep_repo(REPO, recs, set())
        self.assertEqual(h.kinds(), [('review', NEW)])
        self.assertNotIn('needs-human:decision', h.labels)
        self.assertEqual(h.posted, [])

    def test_no_code_claim_with_a_moved_head_goes_to_the_owner_with_one_comment(self):
        # The round pushed (result head != input head), so the claim proves nothing about the reviewed head.
        recs = [self.review_rec('FIX', time.time() - 120),
                self.no_code_round(time.time() - 60, result_head='c' * 40)]
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX')])
        self.m.sweep_repo(REPO, recs, set())
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)
        self.assertEqual(len(h.posted), 1, h.posted)

    def test_no_code_claim_on_an_escalated_round_goes_to_the_owner(self):
        # status ESCALATE is not FIXED: owner path; the fix bot's own comment is the one comment.
        recs = [self.review_rec('FIX', time.time() - 120),
                self.no_code_round(time.time() - 60, status='ESCALATE', owner_decision=True)]
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX')])
        self.m.sweep_repo(REPO, recs, set())
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)
        self.assertEqual(h.posted, [])

    def test_fix_escalated_posts_no_sweep_comment(self):
        # The fix bot already posted its own decision comment; the sweep only moves the label.
        tag = 'babysit-pr7-bbbbbbbb-6'
        self.result(tag, kind='babysit', input_head=NEW, head=NEW, status='ESCALATE', owner_decision=True)
        recs = [self.review_rec('FIX', time.time() - 120),
                {'ts': time.time() - 60, 'kind': 'babysit', 'repo': REPO, 'pr': 7, 'head': NEW, 'pid': 1,
                 'tag': tag, 'verdict_id': 2}]
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX')])
        self.m.sweep_repo(REPO, recs, set())
        self.assertIn('needs-human:decision', h.labels)
        self.assertEqual(h.posted, [])

    def test_wait_cap_handover_posts_one_comment(self):
        recs = []
        for i in range(self.m.WAIT_REVIEW_CAP):
            tag = f'review-pr7-bbbbbbbb-w{i}'
            self.result(tag, kind='review', head=NEW, verdict='BLOCKED', owner_decision=False,
                        blocked_reason='PENDING_CI', url='https://example.invalid/c2')
            recs.append({'ts': time.time() - 7200 + i, 'kind': 'review', 'repo': REPO, 'pr': 7, 'head': NEW,
                         'pid': 1, 'tag': tag})
        h = Harness(self.m, ['review-bot:queued'], [verdict('BLOCKED')])
        reported = set()
        self.m.sweep_repo(REPO, recs, reported)
        self.assertIn('needs-human:decision', h.labels)
        self.assertEqual(len(h.posted), 1, h.posted)
        self.m.sweep_repo(REPO, recs, reported)
        self.assertEqual(len(h.posted), 1, h.posted)

    def test_owner_fix_is_honoured_while_the_fix_bot_holds_an_idle_claim(self):
        fix = {'id': 3, 'user': {'login': 'owner'}, 'body': '@agent fix\npublish the schema first',
               'html_url': 'https://example.invalid/c3'}
        h = Harness(self.m, ['needs-human:decision', 'fix-bot:owns-branch'], [claim(), verdict('BLOCKED'), fix])
        self.m.sweep_repo(REPO, [], set())
        self.assertEqual(h.kinds(), [('babysit', NEW)])
        self.assertEqual(h.spawned[0][2]['trigger'], 'owner request')

    def test_already_reviewed_commit_takes_the_verdicts_state(self):
        h = Harness(self.m, ['review-bot:queued'], [verdict('BLOCKED')])
        self.m.sweep_repo(REPO, [self.review_rec('BLOCKED', time.time() - 60, owner_decision=True)], set())
        self.assertEqual(h.spawned, [])
        self.assertIn('needs-human:decision', h.labels)

    def test_new_commits_after_a_fix_verdict_go_back_to_review(self):
        h = Harness(self.m, ['fix-bot:queued'], [verdict('FIX', OLD)])
        self.m.sweep_repo(REPO, [], set())
        self.assertIn('review-bot:running', h.labels)
        self.assertEqual(h.kinds(), [('review', NEW)])

    def test_idle_tracked_pr_notifies_once_per_head_with_the_reply(self):
        # Claimed by the fix bot, no state label, no new push, nothing due: the owner is told once.
        h = Harness(self.m, ['fix-bot:owns-branch'], [claim()])
        rec = {'ts': time.time() - 7200, 'kind': 'babysit', 'repo': REPO, 'pr': 7, 'head': NEW, 'pid': 1,
               'tag': 'babysit-pr7-bbbbbbbb-3'}
        self.result(rec['tag'], kind='babysit', input_head=NEW, head=NEW, status='FIXED')
        reported = set()
        self.m.sweep_repo(REPO, [rec], reported)
        self.assertEqual(h.spawned, [], self.m.out)
        stalls = self.stalls()
        self.assertEqual(len(stalls), 1, self.m.out)
        self.assertIn('@agent fix', stalls[0])
        self.assertIn(f'https://github.com/{REPO}/pull/7', stalls[0])
        self.m.out.clear()
        self.m.sweep_repo(REPO, [rec], reported)
        self.assertFalse(self.stalls())

    def test_recent_activity_is_not_reported_as_a_stall(self):
        Harness(self.m, ['fix-bot:owns-branch'], [claim()])
        rec = {'ts': time.time() - 60, 'kind': 'babysit', 'repo': REPO, 'pr': 7, 'head': NEW, 'pid': 1,
               'tag': 'babysit-pr7-bbbbbbbb-4'}
        self.result(rec['tag'], kind='babysit', input_head=NEW, head=NEW, status='FIXED')
        self.m.sweep_repo(REPO, [rec], set())
        self.assertFalse(self.stalls())

    def test_chat_started_claim_without_state_label_stays_opt_in(self):
        h = Harness(self.m, ['fix-bot:owns-branch'], [claim('chat-session-1', now_iso())])
        self.m.sweep_repo(REPO, [], set())
        self.assertEqual(h.spawned, [])
        self.assertEqual(h.label_writes, [])


if __name__ == '__main__':
    unittest.main()
