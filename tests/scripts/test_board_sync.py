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
REAL_JIRA_TOKEN, REAL_JIRA_REQUEST = bs.jira_token, bs.jira_request  # the Jira tests patch them
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

    def test_an_unassigned_open_pr_gets_the_assignees_of_the_issues_it_closes_else_the_owner(self):
        self.board.add_issue(1, '🤖 In progress', assignees=('dev',))
        self.board.add_issue(2, '🤖 In progress')
        self.board.add_pr(9)
        self.board.add_pr(10)
        self.board.add_pr(11, assignees=('someone',))
        self.board.prs = [dict(self.pr(9, body='Fixes #1'), assignees={'nodes': []}),
                          dict(self.pr(10, body='Closes #2'), assignees={'nodes': []}),
                          dict(self.pr(11, body='Fixes #1'), assignees={'nodes': [{'login': 'someone'}]}),
                          dict(self.pr(12, body='see #1'), assignees={'nodes': []})]
        self.run_step(bs.reconcile)
        assigned = [w for w in self.board.writes if w[0] == 'assign']
        self.assertEqual(assigned, [('assign', 9, ('dev',)), ('assign', 10, (OWNER,))])

    def test_assigning_in_a_dry_run_writes_nothing(self):
        self.board.add_issue(1, '🤖 In progress', assignees=('dev',))
        self.board.prs = [dict(self.pr(9, body='Fixes #1'), assignees={'nodes': []})]
        _, out, _ = self.run_step(bs.reconcile, True)
        self.assertIn('PR #9: assigned to @dev', out)
        self.assertFalse([w for w in self.board.writes if w[0] == 'assign'])


class PrCards(Sync):
    def test_pr_cards_follow_the_pr(self):
        self.board.add_pr_card(20, '🤖 In progress', state='MERGED')
        self.board.add_pr_card(21, '🧑 Your turn', state='CLOSED', waiting='🔀 merge PR')
        self.board.add_pr_card(22, None, labels=('review-bot:queued',))
        self.board.add_pr_card(23, '🤖 In review', labels=('needs-human:merge',))
        self.board.add_pr_card(24, '🤖 In review', labels=('needs-human:decision', 'needs-human:merge'))
        self.board.add_pr_card(25, 'Later', labels=('needs-human:merge',))
        self.board.add_pr_card(26, '🤖 In review', labels=('review-bot:running',))
        self.run_step(bs.reconcile)
        status = {n: self.board.value(n, 'Status') for n in range(20, 27)}
        self.assertEqual(status, {20: 'Done', 21: 'Canceled', 22: '🤖 In review', 23: '🧑 Your turn',
                                  24: '🧑 Your turn', 25: 'Later', 26: '🤖 In review'})
        waiting = {n: self.board.value(n, 'Waiting for') for n in (21, 23, 24)}
        self.assertEqual(waiting, {21: '', 23: gp.WAITING_FOR['merge'], 24: gp.WAITING_FOR['decide']})
        self.assertEqual(self.board.bodies(), [])  # PR cards move silently
        writes = len(self.board.writes)
        self.run_step(bs.reconcile)
        self.assertEqual(len(self.board.writes), writes)  # settled: nothing more to do

    def test_pr_card_moves_respect_the_cap_and_dry_runs(self):
        for n in range(20, 24):
            self.board.add_pr_card(n, '🤖 In progress', state='MERGED')
        _, out, _ = self.run_step(bs.reconcile, True)
        self.assertIn('PR #20 card: 🤖 In progress -> Done (merged)', out)
        self.assertEqual(self.board.writes, [])
        with patch.object(bs, 'MAX_MOVES', 2):
            self.run_step(bs.reconcile)
        self.assertEqual([self.board.value(n, 'Status') for n in range(20, 24)],
                         ['Done', 'Done', '🤖 In progress', '🤖 In progress'])

    def test_a_waiting_value_the_board_cannot_show_is_not_a_move(self):
        self.board = FakeBoard(waiting=False)
        for target, name, fake in ((gp, 'gh', self.board.gh), (gp, 'graphql', self.board.graphql)):
            p = patch.object(target, name, fake)
            p.start()
            self.addCleanup(p.stop)
        self.board.add_pr_card(23, '🧑 Your turn', labels=('needs-human:merge',))
        ctx, out, _ = self.run_step(bs.reconcile, True)
        self.assertEqual((ctx.moves, out), (0, ''))
        self.run_step(bs.reconcile)
        self.assertEqual(self.board.writes, [])

    def test_a_failing_pr_feature_is_reported_and_issue_cards_still_move(self):
        self.board.add_issue(1, '🧑 📋 Ready to schedule', state='CLOSED')
        self.board.closed = [{'number': 1, 'stateReason': 'COMPLETED', 'closedAt': '2026-01-02T00:00:00Z',
                              'timelineItems': {'nodes': []}}]
        with patch.object(bs, 'pr_cards', side_effect=RuntimeError('HTTP 502')):
            ctx, _, _ = self.run_step(bs.reconcile)
        self.assertEqual(self.board.value(1, 'Status'), 'Done')
        self.assertEqual(ctx.failures, ['[o/r] reconcile (PR cards) FAILED: HTTP 502'])


class FakeJira:
    """Jira REST stand-in for bs.jira_request: issues by key, remote links, and every write."""

    def __init__(self, issues):
        self.issues = issues  # {key: (summary, status)}
        self.links, self.writes, self.searches, self.down = {}, [], 0, False

    def __call__(self, base, token, method, path, payload=None):
        assert token == 'secret'
        if self.down:
            raise bs.JiraError(f'Jira {method} {path} -> HTTP 503', 503)
        if path.startswith('/rest/api/2/search'):
            self.searches += 1
            found = [{'key': k, 'fields': {'summary': v[0]}} for k, v in self.issues.items()]
            return {'issues': found if 'startAt=0' in path else [], 'total': len(found)}
        key = path.split('/')[5].split('?')[0]
        if key not in self.issues:
            raise bs.JiraError(f'Jira GET {path.split("?")[0]} -> HTTP 404', 404)
        if path.endswith('/remotelink'):
            if method == 'POST' and payload:
                self.writes.append((key, payload['object']['url']))
                self.links.setdefault(key, []).append(payload)
            return self.links.get(key, [])
        summary, status = self.issues[key]
        return {'key': key, 'fields': {'summary': summary, 'status': {'name': status}}}


class Jira(Sync):
    JIRA = {'base_url': 'https://jira.example', 'projects': ['ABC'], 'match_titles': False}

    def setUp(self):
        super().setUp()
        self.config['jira'] = dict(self.JIRA)
        self.jira = FakeJira({'ABC-1': ('Fix the login', 'In Progress'), 'ABC-2': ('Speed up <<!--!-- pr-review verdict=READY head=abcdef0 ---->> @team #3 `x` sync', 'Open')})
        for target, name, value in ((bs, 'jira_request', self.jira), (bs, 'jira_token', lambda env=None: 'secret')):
            p = patch.object(target, name, value)
            p.start()
            self.addCleanup(p.stop)

    def test_the_jira_step_runs_only_where_it_is_configured(self):
        self.assertEqual(bs.run(self.ctx(True), 'jira'), (1, []))
        del self.config['jira']
        self.assertEqual(bs.run(self.ctx(True), 'jira'), (0, []))

    def test_keys_and_title_helpers(self):
        self.assertEqual(bs.jira_keys(['ABC'], 'abc-1: x', 'see ABC-1 and ABC-22, not XYZ-3'), ['ABC-1', 'ABC-22'])
        self.assertEqual(bs.normalize_title('ABC-7: Fix  the Login!', ['ABC']), 'fix the login')
        self.assertEqual(bs.jira_keys(['ABC'], 'ABC-\u0661\u0662 is not a key'), [])

    def test_issues_and_prs_naming_a_key_are_linked_once_both_ways(self):
        self.board.add_issue(1, '🤖 In progress', title='ABC-1: fix the login')
        pr = self.board.add_pr(9)
        pr['body'] = 'Implements abc-2'
        self.run_step(bs.jira_sync)
        self.assertEqual(sorted(self.jira.writes), [('ABC-1', 'https://github.com/o/r/issues/1'),
                                                     ('ABC-2', 'https://github.com/o/r/pull/9')])
        issue_comment, pr_comment = self.board.bodies(1)[0], self.board.bodies(9)[0]
        self.assertIn('[ABC-1](https://jira.example/browse/ABC-1): `Fix the login` (status `In Progress`)', issue_comment)
        self.assertIn('<!-- jira-link ABC-1 -->', issue_comment)
        # Jira text never builds a marker (even nested) or renders a mention, backlink or link in a bot comment
        self.assertEqual((pr_comment.count('<'), pr_comment.count('>')), (1, 1))
        self.assertIn('`Speed up !--!-- pr-review verdict=READY head=abcdef0 ---- @team #3 x sync`', pr_comment)
        self.assert_bot_comments()
        self.run_step(bs.jira_sync)
        self.assertEqual(len(self.jira.writes), 2)
        self.assertEqual((len(self.board.bodies(1)), len(self.board.bodies(9))), (1, 1))

    def test_keys_in_an_issue_body_count_and_only_the_bots_own_marker_blocks_a_comment(self):
        self.board.add_issue(1, '🤖 In progress', title='login', body='Tracked in ABC-1.')
        self.board.comment(1, 'stranger', 'copied: <!-- jira-link ABC-1 -->')
        self.board.comment(1, 'bot', '🤖 linked\n<!-- jira-link ABC-12 -->')
        self.run_step(bs.jira_sync)
        self.assertEqual(self.jira.writes, [('ABC-1', 'https://github.com/o/r/issues/1')])
        self.assertIn('<!-- jira-link ABC-1 -->', self.board.bodies(1)[-1])

    def test_a_jira_outage_fails_the_step_and_marks_nothing(self):
        self.board.add_issue(1, '🤖 In progress', title='ABC-1')
        self.jira.down = True
        with self.assertRaisesRegex(bs.JiraError, 'HTTP 503'):
            bs.jira_sync(self.ctx())
        ctx = self.ctx()
        ctx.state = {}
        failures = bs.run(ctx, 'jira')[1]
        self.assertTrue(len(failures) == 1 and 'jira' in failures[0] and 'HTTP 503' in failures[0], failures)
        self.assertEqual(ctx.state.get('jira_linked'), {})
        self.jira.down = False
        self.run_step(bs.jira_sync)
        self.assertEqual(len(self.jira.writes), 1)

    def test_requests_never_show_the_token_or_follow_a_redirect(self):
        def boom(req, timeout):
            raise ValueError("Invalid header value b'Bearer secret\\n'")
        with patch.object(bs._JIRA_OPENER, 'open', boom):
            with self.assertRaises(bs.JiraError) as caught:
                REAL_JIRA_REQUEST('https://jira.example', 'secret', 'GET', '/rest/api/2/myself')
        self.assertNotIn('secret', str(caught.exception))
        self.assertIn('ValueError', str(caught.exception))
        self.assertIsNone(bs._NoRedirect().redirect_request(None, None, 302, '', {}, 'https://elsewhere'))

    def test_an_existing_link_or_comment_is_not_repeated(self):
        self.board.add_issue(1, '🤖 In progress', title='ABC-1 login')
        self.jira.links['ABC-1'] = [{'object': {'url': 'https://github.com/o/r/issues/1'}}]
        self.board.comment(1, 'bot', '🤖 linked\n<!-- jira-link ABC-1 -->')
        self.run_step(bs.jira_sync)
        self.assertEqual((self.jira.writes, len(self.board.bodies(1))), ([], 1))

    def test_unknown_keys_are_reported_once_and_dry_runs_write_nothing(self):
        self.board.add_issue(1, '🤖 In progress', title='ABC-404 and ABC-1')
        _, out, _ = self.run_step(bs.jira_sync, True)
        self.assertIn('issue #1 <-> ABC-1', out)
        self.assertIn('ABC-404 not usable (Jira GET /rest/api/2/issue/ABC-404 -> HTTP 404)', out)
        self.assertEqual((self.jira.writes, self.board.writes), ([], []))
        ctx, _, _ = self.run_step(bs.jira_sync)
        self.assertEqual(ctx.state['jira_linked']['o/r#1:ABC-404'], 'unreadable')
        self.assertEqual(len(self.jira.writes), 1)

    def test_links_are_capped_per_run(self):
        for n in range(1, 5):
            self.board.add_issue(n, '🤖 In progress', title=f'ABC-1 part {n}')
        with patch.object(bs, 'MAX_JIRA', 3):
            self.run_step(bs.jira_sync)
        self.assertEqual(len(self.jira.writes), 3)

    def test_title_matching_is_opt_in_and_needs_one_unique_summary(self):
        self.board.add_issue(1, '🤖 In progress', title='Fix the login')
        self.run_step(bs.jira_sync)
        self.assertEqual((self.jira.writes, self.jira.searches), ([], 0))
        self.config['jira']['match_titles'] = True
        ctx = self.ctx()  # one state across the runs below, as board-sync.json keeps it
        bs.jira_sync(ctx)
        self.assertEqual(self.jira.writes, [('ABC-1', 'https://github.com/o/r/issues/1')])
        self.assertEqual(self.jira.searches, 1)
        self.jira.issues['ABC-3'] = ('Fix the login', 'Open')  # now ambiguous
        self.board.add_issue(2, '🤖 In progress', title='fix the LOGIN')
        bs.jira_sync(ctx)
        self.assertEqual((len(self.jira.writes), self.jira.searches), (2, 1))  # the cached summaries still match
        ctx.state['jira_titles']['at'] = 0  # an hour later the summaries are read again
        self.board.add_issue(3, '🤖 In progress', title='Fix the login')
        bs.jira_sync(ctx)
        self.assertEqual((len(self.jira.writes), self.jira.searches), (2, 2))

    def test_off_without_settings_and_said_once_without_a_token(self):
        self.board.add_issue(1, '🤖 In progress', title='ABC-1')
        del self.config['jira']
        self.run_step(bs.jira_sync)
        self.config['jira'] = dict(self.JIRA)
        with patch.object(bs, 'jira_token', lambda env=None: None):
            ctx = self.ctx()
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                bs.jira_sync(ctx)
                bs.jira_sync(ctx)
        self.assertEqual(out.getvalue().count('JIRA_PAT is not set'), 1)
        self.assertEqual(self.jira.writes, [])

    def test_the_token_comes_from_the_environment_or_the_hermes_env_file(self):
        home = pathlib.Path(self.config['state_dir'])
        (home / '.env').write_text('OTHER=1\nexport JIRA_PAT="from-file"\n', encoding='utf-8')
        self.assertEqual(REAL_JIRA_TOKEN({'JIRA_PAT': 'from-env', 'HERMES_HOME': str(home)}), 'from-env')
        self.assertEqual(REAL_JIRA_TOKEN({'HERMES_HOME': str(home)}), 'from-file')
        self.assertIsNone(REAL_JIRA_TOKEN({'HERMES_HOME': str(home / 'none')}))
        self.assertEqual(REAL_JIRA_TOKEN({'JIRA_PAT': 'tok\n', 'HERMES_HOME': str(home)}), 'tok')
        with self.assertRaises(ValueError) as caught:
            REAL_JIRA_TOKEN({'JIRA_PAT': 'to k', 'HERMES_HOME': str(home)})
        self.assertNotIn('to k', str(caught.exception))


class ClosedPrLabels(Sync):
    def test_merged_and_closed_prs_lose_their_workflow_labels_only(self):
        self.board.add_closed_pr(30, ('needs-human:merge', 'bug', 'pr:babysat'))
        self.board.add_closed_pr(31, ('review-bot:queued', 'fix-bot:owns-branch', 'needs-human:discussion'))
        self.run_step(bs.reconcile)
        self.assertEqual({lab['name'] for lab in self.board.issues['30']['labels']}, {'bug'})
        self.assertEqual({lab['name'] for lab in self.board.issues['31']['labels']}, {'needs-human:discussion'})

    def test_cleanup_is_capped_per_run_and_dry_runs_write_nothing(self):
        for n in range(30, 34):
            self.board.add_closed_pr(n, ('needs-human:merge',))
        _, out, _ = self.run_step(bs.closed_pr_labels, True)
        self.assertIn('PR #30 closed: removed needs-human:merge', out)
        self.assertEqual(self.board.writes, [])
        with patch.object(bs, 'MAX_LABEL_CLEANUPS', 3):
            self.run_step(bs.closed_pr_labels)
        self.assertEqual(len([w for w in self.board.writes if w[0] == 'label-']), 3)


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


class Digest(Sync):
    def test_lists_everything_waiting_on_a_person_by_kind(self):
        self.board.add_issue(1, '🧑 Your turn', title='plan it')
        self.board.comment(1, 'bot', '🤖 **Your turn**\n<!-- gate stage=Plan head=a branch=b plan=p -->')
        self.board.add_issue(2, '🧑 Your turn', title='no request')
        self.board.add_issue(3, '🤖 In progress')
        self.board.add_pr(20, labels=('needs-human:merge',))
        self.board.add_pr(21, labels=('needs-human:decision', 'needs-human:merge'))
        self.board.add_issue(9, on_board=False, title='fresh bug')
        self.board.issues['9']['recent'] = True
        self.board.search_counts.update(created=3, closed=5)
        ctx, out, lines = self.run_step(bs.digest, False, False)
        self.assertIn('[o/r] 4 item(s) waiting on you', out)
        self.assertIn('Backlog, last 7 days: 3 opened, 5 closed (net -2, shrinking)', out)
        self.assertIn('#9 fresh bug', out)
        self.assertIn(f'{gp.WAITING_FOR["approve"]} (1)', out)
        self.assertIn('#2 no request', out)
        self.assertIn(f'{gp.WAITING_FOR["decide"]} (1)', out)
        self.assertIn(f'{gp.WAITING_FOR["merge"]} (1)', out)
        self.assertNotIn('#3', out)
        self.assertEqual(self.board.writes, [])

    def test_silent_when_nothing_waits_except_the_weekly_backlog_lines(self):
        self.board.add_issue(3, '🤖 In progress')
        self.board.search_counts.update(created=1, closed=1)
        _, out, _ = self.run_step(bs.digest, False, False)
        self.assertEqual(out, '')
        _, out, _ = self.run_step(bs.digest, False, True)
        self.assertIn('nothing waiting on you', out)
        self.assertIn('(net +0, flat)', out)

    def test_digest_flag_runs_only_the_digest(self):
        self.board.add_issue(1, '🤖 In progress', values={'Waiting for': '👍 approve'})
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(bs.main(['--digest'], config=self.config), 0)
        self.assertEqual(self.board.writes, [])


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

    def test_each_repository_of_the_board_syncs_with_its_own_state(self):
        self.config = {**self.config, 'primary': 'o/r', 'repositories': {'o/r': {}, 'o/s': {}}}
        self.board.add_issue(1, '🤖 In progress', values={'Waiting for': '👍 approve'})
        self.board.add_issue(5, '🤖 In progress', values={'Waiting for': '👍 approve'}, repo='o/s')
        with contextlib.redirect_stdout(io.StringIO()):
            code = bs.main([], config=self.config)
        self.assertEqual((code, self.board.value(1, 'Waiting for'), self.board.value(5, 'Waiting for')), (0, '', ''))
        root = pathlib.Path(self.config['state_dir'])
        self.assertTrue((root / 'board-sync.json').exists())
        self.assertTrue((root / 'repositories' / 'o__s' / 'board-sync.json').exists())
        self.assertEqual(gp.repo_config({**self.config, 'repositories': {'o/s': {'branch_template': 'x/{n}'}}},
                                        'o/s')['branch_template'], 'x/{n}')

    def test_cards_from_a_repository_nobody_serves_are_reported_once_a_day(self):
        self.board.add_issue(1, '🤖 In progress', repo='o/x')
        outs = []
        for _ in range(2):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                bs.main([], config=self.config)
            outs.append(out.getvalue())
        self.assertIn('The board has cards from o/x, which this pipeline does not serve', outs[0])
        self.assertNotIn('o/x', outs[1])

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

    def run_main(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = bs.main([], config=self.config)
        return code, out.getvalue()

    def test_a_repeating_step_failure_is_printed_once(self):
        with patch.object(bs, 'reconcile', side_effect=RuntimeError('boom')):
            self.assertIn('reconcile FAILED: boom', self.run_main()[1])
            code, out = self.run_main()
        self.assertEqual((code, out), (1, ''))

    def test_every_step_failing_alerts_once_then_says_when_it_runs_again(self):
        boom = RuntimeError('bad credentials')
        with patch.object(bs, 'intake', side_effect=boom), patch.object(bs, 'reconcile', side_effect=boom), \
                patch.object(bs, 'waiting_for', side_effect=boom):
            code, out = self.run_main()
            self.assertEqual(code, 1)
            self.assertIn('🛑 **Board sync (o/r) stopped since', out)
            self.assertIn('bad credentials', out)
            self.assertEqual(self.run_main()[1], '')
        self.assertIn('✅ **Board sync (o/r) runs again**', self.run_main()[1])
        self.assertEqual(self.run_main()[1], '')


if __name__ == '__main__':
    unittest.main()
