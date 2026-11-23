"""Unit tests for scripts/board-sync.py; no network (FakeBoard patches gh/graphql of the adapter).

Ported from gm-agent-pipeline test_board_sync / test_auto_close / test_close_proposal / test_backlog_lane /
test_board_sync_intake (generic subset).
Requirement: FR-001
"""
import contextlib
import importlib.util
import io
import pathlib
import sys
import time
import unittest
from unittest.mock import patch

HERE = pathlib.Path(__file__).resolve().parent
SCRIPTS = HERE.parents[1] / 'scripts'
sys.path.insert(0, str(HERE))
from fake_github import FakeBoard  # noqa: E402


def load(name, file, root=SCRIPTS):
    spec = importlib.util.spec_from_file_location(name, root / file)
    if spec is None or spec.loader is None:
        raise ImportError(file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bs = load('board_sync', 'board-sync.py')
gp = bs.gp
_shared = load('test_gh_project_shared', 'test_gh_project.py', HERE)
OWNER, config = _shared.OWNER, _shared.config
R = 'o/r'
PAST, FUTURE = '2020-01-01T00:00:00Z', '2999-01-01T00:00:00Z'


def c(i, body, login='bot'):
    return {'id': i, 'user': {'login': login}, 'body': body}


class References(unittest.TestCase):
    def test_closing_keywords_same_repo_only(self):
        closing, title, _ = bs.references(R, 9, 'fix thing', 'Closes #12 and fixes o/r#13, resolves other/x#14', 'feat/x')
        self.assertEqual((closing, title), ({12, 13}, set()))

    def test_title_body_and_branch_mentions(self):
        closing, title, body = bs.references(R, 9, 'feat: part of #5', 'see #6 and o/r#7', 'issue-8-thing')
        self.assertEqual((closing, title, body), (set(), {5}, {6, 7, 8}))
        self.assertIn(185, bs.references(R, 9, 't', '', 'feature/item-185')[2])
        self.assertIn(185, bs.references(R, 9, 't', '', 'item/185')[2])

    def test_own_number_and_urls_ignored(self):
        self.assertEqual(bs.references(R, 9, 'x', 'self #9 and https://x/y#15 ', ''), (set(), set(), set()))


class OwnerReply(unittest.TestCase):
    P, H, L = (OWNER, 'helper'), ('/devbot',), {'bot'}

    def reply(self, comments):
        return bs.owner_reply(comments, self.P, self.H, self.L)

    def test_close_and_keep_after_a_proposal(self):
        proposal = c(1, 'x\n<!-- close-proposal reason=fixed dup=- pr=4 -->')
        self.assertEqual(self.reply([proposal, c(2, '/devbot close', OWNER)]), (proposal, 'close'))
        self.assertEqual(self.reply([proposal, c(2, '/devbot kept', 'helper')]), (proposal, 'keep'))
        self.assertEqual(self.reply([proposal, c(2, '/devbot approve', OWNER)]), (proposal, 'approve'))

    def test_bot_text_strangers_and_questions_never_count(self):
        proposal = c(1, '<!-- close-proposal pr=4 -->')
        self.assertIsNone(self.reply([proposal, c(2, '/devbot close\n<!-- sync closed -->', OWNER)])[1])
        self.assertIsNone(self.reply([proposal, c(2, '/devbot close', 'mallory')])[1])
        self.assertIsNone(self.reply([proposal, c(2, '/devbot close?', OWNER)])[1])

    def test_a_later_marker_or_a_dismissal_ends_the_proposal(self):
        self.assertEqual(self.reply([c(1, '<!-- close-proposal pr=4 -->'), c(2, '<!-- gate stage=Plan -->'),
                                     c(3, '/devbot close', OWNER)]), (None, None))
        self.assertEqual(self.reply([c(1, '<!-- close-proposal dismissed pr=4 -->'), c(2, '/devbot close', OWNER)]),
                         (None, None))
        self.assertEqual(self.reply([c(1, '<!-- close-proposal pr=4 -->', 'mallory'), c(2, '/devbot close', OWNER)]),
                         (None, None))


class AutoClose(unittest.TestCase):
    P = (OWNER,)

    def proposal(self, deadline=PAST, extra=''):
        return c(1, f'<!-- close-proposal reason=duplicate dup=3 pr=- auto_close_after={deadline}{extra} -->')

    def test_due_after_deadline_without_reply(self):
        self.assertTrue(bs.auto_close_due(self.proposal(), [self.proposal()], self.P))

    def test_not_due_before_deadline_or_without_one(self):
        self.assertFalse(bs.auto_close_due(self.proposal(FUTURE), [], self.P))
        self.assertFalse(bs.auto_close_due(c(1, '<!-- close-proposal pr=4 -->'), [], self.P))
        self.assertFalse(bs.auto_close_due(self.proposal('garbage'), [], self.P))

    def test_minute_precision_deadline(self):
        self.assertTrue(bs.auto_close_due(self.proposal('2020-01-01T00:00Z'), [], self.P))

    def test_a_plain_comment_from_a_person_stops_the_timer_but_bot_text_and_strangers_do_not(self):
        p = self.proposal()
        self.assertFalse(bs.auto_close_due(p, [p, c(2, 'wait, not yet', OWNER)], self.P))
        self.assertTrue(bs.auto_close_due(p, [p, c(2, '🤖 still waiting', OWNER)], self.P))
        self.assertTrue(bs.auto_close_due(p, [p, c(2, 'drive-by', 'mallory')], self.P))

    def test_attrs(self):
        self.assertEqual(bs.close_proposal_attrs(self.proposal()), {'reason': 'duplicate', 'dup': '3', 'pr': ''})
        self.assertEqual(bs.close_proposal_attrs(c(1, '<!-- close-proposal pr=4 -->')),
                         {'reason': 'fixed', 'dup': '', 'pr': '4'})


class Sync(unittest.TestCase):
    def setUp(self):
        self.board = FakeBoard()
        self.config = config()
        for target, name, fake in ((gp, 'gh', self.board.gh), (gp, 'graphql', self.board.graphql),
                                   (gp.time, 'sleep', lambda s: None)):
            p = patch.object(target, name, fake)
            p.start()
            self.addCleanup(p.stop)

    def ctx(self, dry=False):
        return bs.Context(self.config, dry)

    def run_step(self, fn, dry=False, *args):
        ctx = self.ctx(dry)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            result = fn(ctx, *args)
        return ctx, out.getvalue(), result

    def assert_bot_comments(self):
        for body in self.board.bodies():
            self.assertTrue(body.startswith('🤖'), body)
            self.assertIn('<!--', body)


class Intake(Sync):
    def setUp(self):
        super().setUp()
        self.board.add_issue(1, '🤖 Inbox')
        self.board.add_issue(2, '🤖 Inbox', archived=True)
        self.board.add_issue(3, on_board=False, body='from a review\n<!-- bot-created source=o/r#1 -->')
        self.board.add_issue(4, on_board=False, body='a colleague filed this')
        self.board.add_issue(5, on_board=False, body='')
        self.board.add_issue(6)  # a person added it without a Status

    def test_bot_created_go_to_inbox_every_other_off_board_issue_to_backlog(self):
        self.run_step(lambda ctx: (bs.intake(ctx, 'inbox'), bs.intake(ctx, 'backlog')))
        self.assertEqual(self.board.value(3, 'Status'), '🤖 Inbox')
        self.assertEqual((self.board.value(4, 'Status'), self.board.value(5, 'Status')), ('🧑 Backlog', '🧑 Backlog'))
        self.assertEqual(self.board.value(6, 'Status'), '🤖 Inbox')
        self.assertNotIn(('add', 1), self.board.writes)
        self.assertNotIn(('add', 2), self.board.writes)  # archived: still on the board

    def test_dry_run_writes_nothing_and_reports_the_split(self):
        _, out, _ = self.run_step(lambda ctx: (bs.intake(ctx, 'inbox'), bs.intake(ctx, 'backlog')), True)
        self.assertEqual(self.board.writes, [])
        self.assertIn('1 to 🤖 Inbox, 0 to 🧑 Backlog', out)
        self.assertIn('0 to 🤖 Inbox, 2 to 🧑 Backlog', out)
        self.assertIn('#6: no status on the board', out)

    def test_cap_is_shared_and_inbox_goes_first(self):
        with patch.object(bs, 'MAX_INTAKE', 2):
            self.run_step(lambda ctx: (bs.intake(ctx, 'inbox'), bs.intake(ctx, 'backlog')))
        self.assertEqual([w for w in self.board.writes if w[0] == 'add'], [('add', 3), ('add', 4)])

    def test_intake_all_sends_everything_to_inbox(self):
        self.config['intake'] = 'all'
        self.run_step(lambda ctx: bs.intake(ctx, 'inbox'))
        self.assertEqual({self.board.value(n, 'Status') for n in (3, 4, 5)}, {'🤖 Inbox'})

    def test_a_card_the_list_omitted_keeps_its_status(self):
        omitted = self.board.add_issue(4, '🤖 In progress')
        real = self.board.graphql

        def hide(cfg, query, **v):  # the item list omits #4 (GitHub incident); add returns the existing card
            result = real(cfg, query, **v)
            if 'items(first:100' in query:
                nodes = [n for n in result['node']['items']['nodes'] if n['id'] != omitted['id']]
                result['node']['items'].update(nodes=nodes, totalCount=len(nodes))
            return result
        with patch.object(gp, 'graphql', hide):
            ctx, _, _ = self.run_step(lambda ctx: bs.intake(ctx, 'backlog'))
        self.assertEqual(self.board.value(4, 'Status'), '🤖 In progress')
        self.assertTrue(any('already on the board' in line for line in ctx.lines))


class Closed(Sync):
    def test_completed_to_done_not_planned_to_canceled_in_progress_left(self):
        self.board.add_issue(1, '🧑 📋 Ready to schedule', state='CLOSED')
        self.board.add_issue(2, '🤖 Inbox', state='CLOSED', state_reason='not_planned')
        self.board.add_issue(3, '🤖 In progress', state='CLOSED')
        self.board.closed = [
            {'number': 1, 'stateReason': 'COMPLETED', 'closedAt': '2026-01-02T00:00:00Z',
             'timelineItems': {'nodes': [{'closer': {'__typename': 'PullRequest', 'number': 9}}]}},
            {'number': 2, 'stateReason': 'NOT_PLANNED', 'closedAt': '2026-01-03T00:00:00Z', 'timelineItems': {'nodes': []}},
            {'number': 3, 'stateReason': 'COMPLETED', 'closedAt': '2026-01-03T00:00:00Z', 'timelineItems': {'nodes': []}}]
        self.run_step(bs.reconcile)
        self.assertEqual((self.board.value(1, 'Status'), self.board.value(2, 'Status'), self.board.value(3, 'Status')),
                         ('Done', 'Canceled', '🤖 In progress'))
        self.assertIn('by merged PR #9', self.board.bodies(1)[0])
        self.assertIn('<!-- sync closed reason=not_planned -->', self.board.bodies(2)[0])
        self.assert_bot_comments()

    def test_dry_run_writes_nothing(self):
        self.board.add_issue(1, '🤖 Inbox', state='CLOSED')
        self.board.closed = [{'number': 1, 'stateReason': 'COMPLETED', 'closedAt': '2026-01-02', 'timelineItems': {'nodes': []}}]
        _, out, _ = self.run_step(bs.reconcile, True)
        self.assertEqual(self.board.writes, [])
        self.assertIn('#1: 🤖 Inbox -> Done', out)


class CloseProposals(Sync):
    def proposal(self, n, deadline=None, reason='fixed', dup='-', pr='4'):
        attrs = f'reason={reason} dup={dup} pr={pr}' + (f' auto_close_after={deadline}' if deadline else '')
        return self.board.comment(n, 'bot', f'🤖 **Possibly done: close this issue?**\n\n<!-- close-proposal {attrs} -->')

    def test_close_reply_closes_completed_to_done(self):
        self.board.add_issue(1, '🧑 📋 Ready to schedule', labels=[gp.PROPOSE_LABEL])
        self.proposal(1)
        self.board.comment(1, OWNER, '/devbot close')
        _, out, _ = self.run_step(bs.reconcile)
        self.assertIn(('issue', 1, 'closed', 'completed'), self.board.writes)
        self.assertEqual(self.board.value(1, 'Status'), 'Done')
        self.assertIn('close reply received', out)
        self.assertNotIn(gp.PROPOSE_LABEL, {lab['name'] for lab in self.board.issues['1']['labels']})
        self.assert_bot_comments()

    def test_keep_dismisses_and_a_stranger_is_ignored(self):
        self.board.add_issue(1, '🤖 Inbox', labels=[gp.PROPOSE_LABEL])
        self.proposal(1)
        self.board.comment(1, 'mallory', '/devbot close')
        self.run_step(bs.reconcile)
        self.assertEqual(self.board.issues['1']['state'], 'open')
        self.board.comment(1, OWNER, '/devbot keep')
        self.run_step(bs.reconcile)
        self.assertEqual(self.board.issues['1']['state'], 'open')
        self.assertIn('<!-- close-proposal dismissed pr=4 -->', self.board.bodies(1)[-1])
        self.assertNotIn(gp.PROPOSE_LABEL, {lab['name'] for lab in self.board.issues['1']['labels']})
        self.run_step(bs.reconcile)
        self.assertEqual(len(self.board.bodies(1)), 2, 'a dismissed proposal is not handled again')

    def test_auto_close_duplicate_after_the_deadline_is_not_planned_and_canceled(self):
        self.board.add_issue(1, '🧑 Your turn')  # unlabelled triage proposal on a Your turn card
        self.proposal(1, deadline=PAST, reason='duplicate', dup='3', pr='-')
        _, out, _ = self.run_step(bs.reconcile)
        self.assertIn(('issue', 1, 'closed', 'not_planned'), self.board.writes)
        self.assertEqual(self.board.value(1, 'Status'), 'Canceled')
        self.assertIn('auto-closed as a duplicate of #3', out)
        self.assertIn('<!-- sync closed auto=1 -->', self.board.bodies(1)[-1])

    def test_no_auto_close_before_the_deadline_or_after_a_plain_reply(self):
        self.board.add_issue(1, '🤖 Inbox', labels=[gp.PROPOSE_LABEL])
        self.proposal(1, deadline=FUTURE)
        self.board.add_issue(2, '🤖 Inbox', labels=[gp.PROPOSE_LABEL])
        self.proposal(2, deadline=PAST)
        self.board.comment(2, OWNER, 'hm, let me check first')
        self.run_step(bs.reconcile)
        self.assertEqual((self.board.issues['1']['state'], self.board.issues['2']['state']), ('open', 'open'))

    def test_approve_on_a_your_turn_card_belongs_to_its_gate(self):
        self.board.add_issue(1, '🧑 Your turn', labels=[gp.PROPOSE_LABEL])
        self.proposal(1)
        self.board.comment(1, OWNER, '/devbot approve')
        self.run_step(bs.reconcile)
        self.assertEqual(self.board.issues['1']['state'], 'open')

    def test_a_newer_marker_removes_a_stale_label(self):
        self.board.add_issue(1, '🤖 Inbox', labels=[gp.PROPOSE_LABEL])
        self.proposal(1)
        self.board.comment(1, 'bot', '<!-- triage outcome=ready -->')
        self.run_step(bs.reconcile)
        self.assertIn(('label-', 1, gp.PROPOSE_LABEL), self.board.writes)


class LinkPrs(Sync):
    def pr(self, number, state='OPEN', title='t', body='', branch='x', author='dev'):
        return {'number': number, 'title': title, 'body': body, 'headRefName': branch, 'baseRefName': 'main',
                'state': state, 'isDraft': False, 'url': f'https://github.com/o/r/pull/{number}',
                'author': {'login': author, '__typename': 'User'}, 'closingIssuesReferences': {'nodes': []}}

    def test_open_pr_is_linked_once(self):
        self.board.add_issue(1, '🤖 In progress')
        self.board.prs = [self.pr(9, body='see #1')]
        self.run_step(bs.reconcile)
        self.assertIn('<!-- pr-link pr=9 -->', self.board.bodies(1)[0])
        self.run_step(bs.reconcile)
        self.assertEqual(len(self.board.bodies(1)), 1)
        self.assert_bot_comments()

    def test_merged_closing_pr_proposes_closing_with_a_deadline(self):
        self.board.add_issue(1, '🧑 📋 Ready to schedule')
        self.board.prs = [self.pr(9, state='MERGED', body='Fixes #1')]
        _, out, _ = self.run_step(bs.reconcile)
        body = self.board.bodies(1)[0]
        self.assertRegex(body, r'<!-- close-proposal reason=fixed dup=- pr=9 auto_close_after=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ -->')
        self.assertIn('/devbot close', body)
        self.assertIn(gp.PROPOSE_LABEL, {lab['name'] for lab in self.board.issues['1']['labels']})
        self.assertIn(gp.PROPOSE_LABEL, self.board.labels)
        self.assertIn('proposed closing it', out)
        marker = self.board.comments['1'][0]
        self.assertGreater(time.mktime(time.strptime(bs.AUTO_CLOSE.search(marker['body']).group(1), '%Y-%m-%dT%H:%M:%SZ')),
                           time.time() + 47 * 3600 - 86400)  # roughly 48 h out (timezone-insensitive bound)

    def test_title_mention_proposal_has_no_deadline_and_backlog_bots_and_closed_prs_are_ignored(self):
        self.board.add_issue(1, '🤖 Inbox')
        self.board.add_issue(2, '🧑 Backlog')
        self.board.prs = [self.pr(9, state='MERGED', title='part of #1 and #2'), self.pr(10, body='#1', author='dependabot[bot]'),
                          self.pr(11, state='CLOSED', body='#1')]
        self.run_step(bs.reconcile)
        self.assertEqual(len(self.board.bodies(1)), 1)
        self.assertNotIn('auto_close_after', self.board.bodies(1)[0])
        self.assertEqual(self.board.bodies(2), [])


class Waiting(Sync):
    def test_your_turn_shows_the_kind_then_bots_turn_and_other_cards_are_cleared(self):
        self.board.add_issue(1, '🧑 Your turn')
        self.board.comment(1, 'bot', '<!-- gate stage=Plan head=a branch=b plan=p -->')
        self.board.add_issue(2, '🧑 Your turn', links=[(20, 'OPEN')])
        self.board.issues['20'] = {'number': 20, 'node_id': 'x', 'state': 'open', 'state_reason': None, 'body': '',
                                   'title': 'pr', 'labels': [{'name': 'needs-human:merge'}], 'assignees': []}
        self.board.add_issue(3, '🤖 In progress', values={'Waiting for': '👍 approve'})
        self.board.add_issue(4, '🧑 Your turn', values={'Waiting for': '💬 answer'})  # no marker: nothing to show
        self.run_step(bs.waiting_for)
        self.assertEqual([self.board.value(n, 'Waiting for') for n in (1, 2, 3, 4)], ['👍 approve', '🔀 merge PR', '', ''])
        self.board.comment(1, OWNER, '/devbot approve')
        self.run_step(bs.waiting_for)
        self.assertEqual(self.board.value(1, 'Waiting for'), "⏳ Bot's turn")
        self.board.writes.clear()
        self.run_step(bs.waiting_for)
        self.assertEqual(self.board.writes, [], 'a second run changes nothing')

    def test_close_proposals_never_count_as_a_wait(self):
        self.board.add_issue(1, '🧑 Your turn')
        self.board.comment(1, 'bot', '<!-- close-proposal reason=fixed dup=- pr=4 -->')
        self.run_step(bs.waiting_for)
        self.assertEqual(self.board.value(1, 'Waiting for'), '')


class Main(Sync):
    def test_dry_run_prints_and_writes_nothing(self):
        self.board.add_issue(1, '🤖 In progress', values={'Waiting for': '👍 approve'})
        self.board.add_issue(2, on_board=False, body='<!-- bot-created source=o/r#1 -->')
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = bs.main(['--dry'], config=self.config)
        self.assertEqual((code, self.board.writes), (0, []))
        self.assertIn('Waiting for 👍 approve -> empty (DRY)', out.getvalue())
        self.assertIn('1 to 🤖 Inbox', out.getvalue())

    def test_only_runs_one_step(self):
        self.board.add_issue(1, '🤖 In progress', values={'Waiting for': '👍 approve'})
        self.board.add_issue(2, on_board=False, body='<!-- bot-created source=o/r#1 -->')
        with contextlib.redirect_stdout(io.StringIO()):
            bs.main(['--only', 'intake'], config=self.config)
        self.assertEqual(self.board.value(1, 'Waiting for'), '👍 approve')
        self.assertEqual(self.board.value(2, 'Status'), '🤖 Inbox')

    def test_a_held_lock_is_reported_and_nothing_runs(self):
        out = io.StringIO()
        with gp.file_lock(gp.lock_path(self.config)), patch.object(bs, 'SYNC_LOCK_WAIT', 0), \
                contextlib.redirect_stdout(out):
            code = bs.main([], config=self.config)
        self.assertEqual(code, 1)
        self.assertIn('FAILED to start', out.getvalue())
        self.assertEqual(self.board.writes, [])

    def test_owners_are_required(self):
        with self.assertRaisesRegex(ValueError, 'PIPELINE_OWNERS'):
            bs.main([], config=config(owners=()))

    def test_a_failing_step_is_loud_and_the_others_still_run(self):
        self.board.add_issue(1, '🤖 In progress', values={'Waiting for': '👍 approve'})
        out = io.StringIO()
        with patch.object(bs, 'reconcile', side_effect=RuntimeError('boom')), contextlib.redirect_stdout(out):
            code = bs.main([], config=self.config)
        self.assertEqual(code, 1)
        self.assertIn('reconcile FAILED: boom', out.getvalue())
        self.assertEqual(self.board.value(1, 'Waiting for'), '')


if __name__ == '__main__':
    unittest.main()
