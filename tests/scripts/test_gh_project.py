"""Unit tests for scripts/gh-project.py (GitHub Project v2 adapter); no network. commands.py: test_commands.py.

Ported from gm-agent-pipeline test_gem_project / test_board_columns / test_board_names / test_migrate_your_turn.
Requirement: FR-001
"""
import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = pathlib.Path(__file__).resolve().parent
SCRIPTS = HERE.parents[1] / 'scripts'
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(SCRIPTS))
from fake_github import FakeBoard  # noqa: E402


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    if spec is None or spec.loader is None:
        raise ImportError(file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gp = load('gh_project', 'gh-project.py')
commands = load('commands', 'commands.py')
OWNER = 'owner'


def config(**extra):
    base = {'repo': 'o/r', 'project_owner': 'o', 'project_number': 1, 'project_id': 'P', 'project_title': None,
            'gh_bin': 'gh', 'owners': (OWNER,), 'responders': ('helper',), 'handles': ('/devbot',),
            'bot_logins': ('bot',), 'shared_account': False, 'branch_template': 'item/{n}', 'wip': 2,
            'park_label': 'needs-human:discussion', 'state_dir': tempfile.mkdtemp(prefix='board-tools-test-'),
            'intake': 'bot-created'}
    base.update(extra)
    return base


class Board(unittest.TestCase):
    """Patches the adapter's gh/graphql with a FakeBoard for each test."""

    def setUp(self):
        self.board = FakeBoard()
        self.config = config()
        for name, fake in (('gh', self.board.gh), ('graphql', self.board.graphql)):
            p = patch.object(gp, name, fake)
            p.start()
            self.addCleanup(p.stop)
        p = patch.object(gp.time, 'sleep', lambda s: None)
        p.start()
        self.addCleanup(p.stop)


class Config(unittest.TestCase):
    def test_env_is_required_and_handles_default_to_devbot(self):
        with self.assertRaisesRegex(ValueError, 'PIPELINE_REPO'):
            gp.load_config({'GH_PROJECT_NUMBER': '3'})
        with self.assertRaisesRegex(ValueError, 'GH_PROJECT_NUMBER'):
            gp.load_config({'PIPELINE_REPO': 'o/r'})
        cfg = gp.load_config({'PIPELINE_REPO': 'o/r', 'GH_PROJECT_NUMBER': '3', 'PIPELINE_OWNERS': '@Owner, other'})
        self.assertEqual((cfg['project_owner'], cfg['project_number'], cfg['gh_bin']), ('o', 3, 'gh'))
        self.assertEqual(cfg['owners'], ('owner', 'other'))
        self.assertEqual(cfg['handles'], ('/devbot',))
        self.assertEqual(cfg['branch_template'], 'item/{n}')

    def test_json_config_file_and_env_override(self):
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as handle:
            json.dump({'repo': 'a/b', 'project_number': 7, 'project_owner': 'org', 'handles': ['bot-name'],
                       'owners': ['x']}, handle)
        cfg = gp.load_config({'GH_PROJECT_CONFIG': handle.name, 'GH_BIN': '/bin/gh'})
        self.assertEqual((cfg['repo'], cfg['project_owner'], cfg['project_number']), ('a/b', 'org', 7))
        self.assertEqual((cfg['handles'], cfg['gh_bin'], cfg['owners']), (('@bot-name',), '/bin/gh', ('x',)))
        cfg = gp.load_config({'GH_PROJECT_CONFIG': handle.name, 'PIPELINE_REPO': 'c/d', 'PR_AGENT_HANDLE': '/x @y'})
        self.assertEqual((cfg['repo'], cfg['handles']), ('c/d', ('/x', '@y')))
        pathlib.Path(handle.name).unlink()

    def test_jira_settings_are_optional_and_checked(self):
        env = {'PIPELINE_REPO': 'o/r', 'GH_PROJECT_NUMBER': '3'}
        self.assertIsNone(gp.load_config(env)['jira'])
        cfg = gp.load_config({**env, 'JIRA_BASE_URL': 'https://jira.example/', 'JIRA_PROJECTS': 'abc, OPS'})
        self.assertEqual(cfg['jira'], {'base_url': 'https://jira.example', 'projects': ['ABC', 'OPS'], 'match_titles': False})
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as handle:
            json.dump({'repo': 'a/b', 'project_number': 7,
                       'jira': {'base_url': 'https://j', 'projects': ['ABC'], 'match_titles': True}}, handle)
        self.assertTrue(gp.load_config({'GH_PROJECT_CONFIG': handle.name})['jira']['match_titles'])
        pathlib.Path(handle.name).unlink()
        with self.assertRaisesRegex(ValueError, 'JIRA_PROJECTS'):
            gp.load_config({**env, 'JIRA_BASE_URL': 'https://j'})
        with self.assertRaisesRegex(ValueError, 'JIRA_BASE_URL'):
            gp.load_config({**env, 'JIRA_BASE_URL': 'jira.example', 'JIRA_PROJECTS': 'ABC'})
        with self.assertRaisesRegex(ValueError, 'https'):
            gp.load_config({**env, 'JIRA_BASE_URL': 'http://jira.example', 'JIRA_PROJECTS': 'ABC'})

    def test_project_id_is_resolved_from_owner_and_number(self):
        board = FakeBoard()
        with patch.object(gp, 'graphql', board.graphql):
            cfg = gp.resolve_project(config(project_id=None))
        self.assertEqual((cfg['project_id'], cfg['project_title']), ('P', 'Board'))


class Names(unittest.TestCase):
    def test_mapping_is_complete_and_reversible(self):
        for field, options in gp.BOARD_OPTION.items():
            for internal, board in options.items():
                self.assertEqual(gp.internal_value(field, board), internal)
                self.assertEqual(gp.internal_value(field, internal), internal)
                self.assertEqual(gp.board_value(field, internal), board)
        self.assertEqual([gp.internal_field(n) for n in ('Size', 'source', 'Bot approvals', 'Track', 'Waiting for')],
                         ['Track', 'Origin', 'Autonomy', 'Track', 'Waiting for'])

    def test_contract_status_board_names(self):
        self.assertEqual([gp.board_value('Status', s) for s in gp.REQUIRED['Status']],
                         ['🧑 Backlog', '🤖 Inbox', '🧑 📋 Ready to schedule', '🤖 Up next', '🤖 In progress',
                          '🧑 Your turn', '🤖 In review', 'Later', 'Done', 'Canceled'])
        for gone in ('Clarification needed', 'Awaiting approval', 'Blocked'):
            self.assertNotIn(gone, gp.REQUIRED['Status'])

    def test_waiting_for_accepts_kinds_and_values(self):
        self.assertEqual(gp.internal_value('Waiting for', 'approve'), '👍 approve')
        self.assertEqual(gp.internal_value('Waiting for', '🔀 merge PR'), '🔀 merge PR')
        self.assertEqual(gp.internal_value('Waiting for', ''), '')


class Normalize(unittest.TestCase):
    def item(self, status, repo='o/r', state='OPEN', links=()):
        return {'id': 'x', 'content': {'__typename': 'Issue', 'number': 42, 'title': 'T', 'state': state,
                'updatedAt': 'u', 'repository': {'nameWithOwner': repo},
                'closedByPullRequestsReferences': {'nodes': [{'number': n, 'state': s, 'repository': {'nameWithOwner': repo}}
                                                             for n, s in links]}},
                'fieldValues': {'nodes': [{'__typename': gp.SINGLE if hasattr(gp, 'SINGLE') else 'ProjectV2ItemFieldSingleSelectValue',
                                           'name': status, 'field': {'name': 'Status'}}]}}

    def test_repository_scope_and_internal_names(self):
        issue, prs = gp.normalize(self.item('🧑 Your turn', links=[(5, 'OPEN')]), 'o/r')
        self.assertEqual((issue['number'], issue['status'], issue['autonomy'], issue['prs']), (42, 'Your turn', 'gated', [5]))
        self.assertTrue(issue['pr_stage'])
        self.assertEqual(prs, {5})
        self.assertEqual(gp.normalize(self.item('Ready', repo='x/y'), 'o/r'), (None, set()))

    def test_later_is_invisible_and_closed_without_merge_is_marked(self):
        for name in ('Later', 'Icebox'):
            self.assertEqual(gp.normalize(self.item(name, links=[(5, 'OPEN')]), 'o/r'), (None, set()))
        issue, _ = gp.normalize(self.item('🤖 In review', state='CLOSED', links=[(5, 'CLOSED')]), 'o/r')
        self.assertEqual(issue['state'], 'CLOSED_WITHOUT_MERGE')
        issue, _ = gp.normalize(self.item('🤖 In review', state='CLOSED', links=[(5, 'MERGED')]), 'o/r')
        self.assertEqual(issue['state'], 'CLOSED')

    def test_pr_cards_in_no_bot_statuses_are_invisible(self):
        for status in ('Later', '🧑 Backlog', 'Done', 'Canceled'):
            card = {'id': 'x', 'content': {'__typename': 'PullRequest', 'number': 7, 'state': 'OPEN',
                    'repository': {'nameWithOwner': 'o/r'}},
                    'fieldValues': {'nodes': [{'__typename': 'ProjectV2ItemFieldSingleSelectValue', 'name': status,
                                               'field': {'name': 'Status'}}]}}
            self.assertEqual(gp.normalize(card, 'o/r'), (None, set()), status)


class BranchLinks(Board):
    def test_item_branch_pr_is_linked_and_others_are_not(self):
        self.board.add_issue(7, '🤖 In review')
        self.board.add_issue(8, '🧑 Backlog')
        self.board.open_prs = [
            {'number': 70, 'headRefName': 'item/7', 'isCrossRepository': False, 'headRepositoryOwner': {'login': 'o'}},
            {'number': 71, 'headRefName': 'item/7', 'isCrossRepository': True, 'headRepositoryOwner': {'login': 'fork'}},
            {'number': 80, 'headRefName': 'item/8', 'isCrossRepository': False, 'headRepositoryOwner': {'login': 'o'}},
            {'number': 90, 'headRefName': 'item/9', 'isCrossRepository': False, 'headRepositoryOwner': {'login': 'o'}}]
        issues, prs, _ = gp.snapshot(self.config)
        self.assertEqual(prs, [70])
        self.assertEqual({i['number']: i['prs'] for i in issues}, {7: [70], 8: []})

    def test_branch_template_is_configurable(self):
        self.board.add_issue(7, '🧑 Your turn')
        self.board.open_prs = [{'number': 70, 'headRefName': 'feature/item-7', 'isCrossRepository': False,
                                'headRepositoryOwner': {'login': 'o'}}]
        issues, prs, _ = gp.snapshot({**self.config, 'branch_template': 'feature/item-{n}'})
        self.assertEqual((prs, issues[0]['pr_stage']), ([70], True))


class Guards(unittest.TestCase):
    def test_field_write_guards(self):
        with self.assertRaisesRegex(ValueError, 'owner-controlled'):
            gp.validate_change('Autonomy', '', 'auto', '')
        with self.assertRaisesRegex(ValueError, 'owner-controlled'):
            gp.validate_change('Status', 'Ready', 'Up next', '')
        with self.assertRaisesRegex(ValueError, 'owner-controlled'):
            gp.validate_change('Status', 'Ready', 'Icebox', 'c')
        for target in ('Your turn', 'Done', 'Canceled'):
            with self.assertRaisesRegex(ValueError, 'comment'):
                gp.validate_change('Status', 'In progress', target, '')
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            gp.validate_change('Priority', 'P1', 'P2', '')
        gp.validate_change('Track', 'fast-path', 'standard-implementation', 'Needs design')
        gp.validate_change('Waiting for', '👍 approve', '', '')


class Move(Board):
    def test_compare_and_set_refuses_when_the_card_moved(self):
        self.board.add_issue(5, '🤖 In progress')
        with self.assertRaisesRegex(ValueError, 'is no longer'):
            gp.mutate_field(self.config, 5, 'Status', 'Your turn', 'why', expect='Inbox')
        self.assertEqual(self.board.writes, [])

    def test_move_into_your_turn_needs_a_comment_and_posts_it_first_with_the_bot_prefix(self):
        self.board.add_issue(5, '🤖 In progress')
        with self.assertRaisesRegex(ValueError, 'audit comment'):
            gp.mutate_field(self.config, 5, 'Status', 'Your turn', '', expect='In progress')
        result = gp.mutate_field(self.config, 5, 'Status', '🧑 Your turn', 'Needs your approval',
                                 expect='🤖 In progress')
        self.assertEqual(result, {'ok': True, 'number': 5, 'field': 'Status', 'value': 'Your turn'})
        self.assertEqual(self.board.value(5, 'Status'), '🧑 Your turn')
        self.assertEqual(self.board.writes[0][0], 'comment')
        self.assertEqual(self.board.bodies(5), ['🤖 Needs your approval'])

    def test_empty_status_reads_as_inbox_for_expect(self):
        self.board.add_issue(5)
        gp.mutate_field(self.config, 5, 'Status', 'Ready', '', expect='Inbox')
        self.assertEqual(self.board.value(5, 'Status'), '🧑 📋 Ready to schedule')

    def test_waiting_for_is_set_by_kind_or_value_and_cleared(self):
        self.board.add_issue(5, '🧑 Your turn')
        gp.mutate_field(self.config, 5, 'Waiting for', 'approve', '')
        self.assertEqual(self.board.value(5, 'Waiting for'), '👍 approve')
        gp.mutate_field(self.config, 5, 'Waiting for', "⏳ Bot's turn", '')
        self.assertEqual(self.board.value(5, 'Waiting for'), "⏳ Bot's turn")
        gp.mutate_field(self.config, 5, 'Waiting for', '', '')
        self.assertEqual(self.board.value(5, 'Waiting for'), '')

    def test_waiting_for_needs_the_field(self):
        self.board = FakeBoard(waiting=False)
        self.board.add_issue(5, '🧑 Your turn')
        with patch.object(gp, 'gh', self.board.gh), patch.object(gp, 'graphql', self.board.graphql), \
                self.assertRaisesRegex(ValueError, 'gh-project.py fields'):
            gp.mutate_field(self.config, 5, 'Waiting for', 'approve', '')

    def test_up_next_needs_a_verified_reply(self):
        self.board.add_issue(5, '🧑 Your turn', assignees=['dev'])
        self.board.add_issue(6, '🧑 Your turn')
        gate = self.board.comment(5, 'bot', '🤖 gate\n<!-- gate stage=Plan head=a branch=b plan=p -->')
        with self.assertRaisesRegex(ValueError, 'owner-controlled'):
            gp.mutate_field(self.config, 5, 'Status', 'Up next', '')
        cases = [
            (5, 'mallory', '/devbot approve', False),          # stranger
            (5, 'dev', '/devbot approve', False),              # approvals are owner-only
            (5, OWNER, '/devbot approve <!-- x -->', False),   # bot text
            (5, OWNER, '/devbot answer: 42', False),           # not a resume verb
            (6, OWNER, '/devbot approve', False),              # wrong issue (reply on #6, card #5)
            (5, 'dev', '/devbot unblock: done', True),         # assignee may unblock
            (5, 'helper', '\\devbot unblocked: ok', True),     # configured responder, tolerant spelling
            (5, OWNER, '/devbot approved', True),
        ]
        reply = {}
        for number, login, body, ok in cases:
            reply = self.board.comment(number, login, body)
            with self.subTest(login=login, body=body):
                if ok:
                    gp.verify_ack_reply(self.config, 5, reply['id'])
                else:
                    with self.assertRaisesRegex(ValueError, 'Up next needs'):
                        gp.verify_ack_reply(self.config, 5, reply['id'])
        self.assertTrue(gate)
        gp.mutate_field(self.config, 5, 'Status', 'Up next', '', expect='Your turn', ack_reply=reply['id'])
        self.assertEqual(self.board.value(5, 'Status'), '🤖 Up next')

    def test_canceled_needs_a_reject_reply_or_closed_not_planned(self):
        self.board.add_issue(5, '🧑 Your turn', assignees=['dev'])
        self.board.comment(5, OWNER, '/devbot approve')
        with self.assertRaisesRegex(ValueError, 'explicit reject'):
            gp.mutate_field(self.config, 5, 'Status', 'Canceled', 'why')
        self.board.comment(5, 'dev', '/devbot reject')  # reject is owner-only: an assignee's does not cancel
        with self.assertRaisesRegex(ValueError, 'explicit reject'):
            gp.mutate_field(self.config, 5, 'Status', 'Canceled', 'why')
        self.board.comment(5, OWNER, '/devbot rejected')
        gp.mutate_field(self.config, 5, 'Status', 'Canceled', 'Rejected')
        self.assertEqual(self.board.value(5, 'Status'), 'Canceled')
        self.board.add_issue(6, '🤖 Inbox', state='CLOSED', state_reason='not_planned')
        gp.mutate_field(self.config, 6, 'Status', 'Canceled', 'closed as not planned')
        self.assertEqual(self.board.value(6, 'Status'), 'Canceled')

    def test_done_from_the_pr_stage_needs_a_merged_pr(self):
        self.board.add_issue(5, '🤖 In review', links=[(9, 'OPEN')])
        with self.assertRaisesRegex(ValueError, 'merged linked PR'):
            gp.mutate_field(self.config, 5, 'Status', 'Done', 'done')

    def test_readback_retries_index_lag_without_repeating_the_write(self):
        self.board.add_issue(5, '🤖 Inbox')
        real = gp.current_item
        calls = []

        def lagging(cfg, number):
            item, raw = real(cfg, number)
            calls.append(1)
            if len(calls) == 2:  # first read-back still shows the old value
                raw = json.loads(json.dumps(raw))
                for v in raw['fieldValues']['nodes']:
                    v['name'] = '🤖 Inbox'
            return item, raw
        with patch.object(gp, 'current_item', lagging):
            gp.mutate_field(self.config, 5, 'Status', 'Ready', '')
        self.assertEqual(len([w for w in self.board.writes if w[0] == 'set']), 1)
        self.assertEqual(len(calls), 3)


class Cli(Board):
    def run_main(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = gp.main(list(argv), config=self.config)
        return code, out.getvalue()

    def test_list_prints_internal_names(self):
        self.board.add_issue(5, '🧑 Your turn', values={'Size': 'small fix', 'Priority': 'P1', 'Bot approvals': 'proceed alone',
                                                        'Waiting for': '👍 approve'})
        code, out = self.run_main('list')
        item = json.loads(out)[0]
        self.assertEqual(code, 0)
        for key in ('number', 'title', 'status', 'stage', 'track', 'priority', 'autonomy', 'updatedAt', 'state'):
            self.assertIn(key, item)
        self.assertEqual((item['status'], item['track'], item['autonomy'], item['waiting_for']),
                         ('Your turn', 'fast-path', 'auto', '👍 approve'))

    def test_move_and_set_subcommands(self):
        self.board.add_issue(5, '🤖 In progress')
        code, out = self.run_main('move', '5', 'Your turn', '--comment', 'why', '--expect', 'In progress')
        self.assertEqual((code, json.loads(out)['value']), (0, 'Your turn'))
        code, out = self.run_main('set', '5', 'Waiting for', 'unblock')
        self.assertEqual(self.board.value(5, 'Waiting for'), '🛠️ unblock')
        code, out = self.run_main('set', '5', 'Size', 'needs design')
        self.assertEqual(self.board.value(5, 'Size'), 'needs design')


class WaitKind(unittest.TestCase):
    def c(self, i, body, login='bot'):
        return {'id': i, 'user': {'login': login}, 'body': body}

    def test_newest_bot_marker_decides(self):
        cs = [self.c(1, '<!-- triage outcome=clarify -->'), self.c(2, '<!-- gate stage=Plan head=a -->')]
        self.assertEqual(gp.wait_kind(cs, (), {'bot'})[0], 'approve')
        cs.append(self.c(3, '<!-- blocked reason=tests -->'))
        self.assertEqual(gp.wait_kind(cs, (), {'bot'})[0], 'unblock')
        self.assertEqual(gp.wait_kind([self.c(1, '<!-- triage outcome=clarify fields="x" -->')], (), {'bot'})[0], 'answer')

    def test_markers_from_other_people_and_close_proposals_do_not_count(self):
        self.assertEqual(gp.wait_kind([self.c(1, '<!-- gate stage=Plan -->', 'mallory')], (), {'bot'}), (None, None))
        cs = [self.c(1, '<!-- gate stage=Plan -->'), self.c(2, '<!-- close-proposal reason=fixed dup=- pr=4 -->')]
        self.assertEqual(gp.wait_kind(cs, (), {'bot'})[0], 'approve')

    def test_triage_ready_or_historical_left_ends_a_question(self):
        for outcome in ('ready', 'left'):
            cs = [self.c(1, '<!-- triage outcome=clarify -->'), self.c(2, f'<!-- triage outcome={outcome} -->')]
            self.assertEqual(gp.wait_kind(cs, (), {'bot'}), (None, None))

    def test_pr_labels_win(self):
        cs = [self.c(1, '<!-- gate stage=Plan -->')]
        self.assertEqual(gp.wait_kind(cs, [{'needs-human:merge'}], {'bot'}), ('merge', None))
        self.assertEqual(gp.wait_kind(cs, [{'needs-human:merge'}, {'needs-human:decision'}], {'bot'}), ('decide', None))
        self.assertEqual(gp.wait_kind(cs, [{'pr:ready-merge'}], {'bot'}), ('merge', None))
        self.assertEqual(gp.wait_kind(cs, [{'review-bot:queued'}], {'bot'})[0], 'approve')

    def test_reply_verbs_are_disjoint(self):
        seen = [v for verbs in gp.REPLY_VERBS.values() for v in verbs]
        self.assertEqual(len(seen), len(set(seen)))
        self.assertNotIn('close', seen)
        self.assertNotIn('keep', seen)


class BotTurn(unittest.TestCase):
    def setUp(self):
        self.config = config()

    def c(self, i, body, login='bot'):
        return {'id': i, 'user': {'login': login}, 'body': body}

    def turn(self, comments, issue=None, labels=()):
        return gp.bot_turn(self.config, comments, labels, lambda: issue or {})

    def test_valid_reply_hands_the_card_to_the_bot(self):
        gate = self.c(1, '<!-- gate stage=Plan head=a -->')
        self.assertEqual(self.turn([gate]), ('approve', False))
        self.assertEqual(self.turn([gate, self.c(2, '/devbot approve', OWNER)]), ('approve', True))
        self.assertEqual(self.turn([gate, self.c(2, '/devbot revise: shorter', OWNER)]), ('approve', True))

    def test_discuss_parked_wrong_verb_and_non_owner_approval_stay_with_the_person(self):
        gate = self.c(1, '<!-- gate stage=Plan head=a -->')
        self.assertEqual(self.turn([gate, self.c(2, '/devbot discuss', OWNER)]), ('approve', False))
        self.assertEqual(self.turn([gate, self.c(2, '/devbot approve', OWNER)],
                                   issue={'labels': [{'name': 'needs-human:discussion'}]}), ('approve', False))
        self.assertEqual(self.turn([gate, self.c(2, '/devbot unblock: x', OWNER)]), ('approve', False))
        self.assertEqual(self.turn([gate, self.c(2, '/devbot approve', 'helper')]), ('approve', False))
        self.assertEqual(self.turn([gate, self.c(2, '/devbot approve?', OWNER)]), ('approve', False))

    def test_answers_from_assignees_and_responders_count(self):
        ask = self.c(1, '<!-- triage outcome=clarify -->')
        self.assertEqual(self.turn([ask, self.c(2, '/devbot answer: 42', 'dev')], issue={'assignees': [{'login': 'dev'}]}),
                         ('answer', True))
        self.assertEqual(self.turn([ask, self.c(2, '/devbot answer: 42', 'helper')]), ('answer', True))
        self.assertEqual(self.turn([ask, self.c(2, 'just a plain comment', OWNER)]), ('answer', False))

    def test_pr_label_waits_never_count(self):
        self.assertEqual(self.turn([self.c(2, '/devbot approve', OWNER)], labels=[{'needs-human:merge'}]), ('merge', False))

    def test_shared_account_reply_without_marker_counts(self):
        self.config = config(bot_logins=(), shared_account=True)
        cs = [self.c(1, '<!-- blocked reason=x -->', OWNER), self.c(2, '/devbot unblock: fixed', OWNER)]
        self.assertEqual(self.turn(cs), ('unblock', True))
        cs = [self.c(1, '<!-- blocked reason=x -->', OWNER), self.c(2, '🤖 /devbot unblock: fixed', OWNER)]
        self.assertEqual(self.turn(cs), ('unblock', False))


class Fields(Board):
    OLD = ['🤖 Inbox', '🧑 💬 Clarify', '🧑 📋 Ready to schedule', '🤖 Up next', '🤖 In progress', '🧑 👍 Approve step',
           '🧑 🛠️ Unblock', '🤖 In review', 'Icebox', 'Done', 'Canceled']

    def setUp(self):
        super().setUp()
        self.board = FakeBoard(status=self.OLD, waiting=False, fields={
            'Priority': ['P0', 'P1', 'P2', 'P3'], 'Track': ['fast-path', 'standard-implementation', 'analysis-spike', 'docs-process'],
            'Origin': ['human-request', 'plan-follow-up', 'review-finding', 'agent-observation', 'external-issue'],
            'Autonomy': ['gated', 'auto']})
        for name, fake in (('gh', self.board.gh), ('graphql', self.board.graphql)):
            p = patch.object(gp, name, fake)
            p.start()
            self.addCleanup(p.stop)
        self.board.add_issue(1, '🧑 💬 Clarify', values={'Track': 'fast-path'})
        self.board.add_issue(2, 'Icebox')

    def test_dry_run_lists_changes_and_writes_nothing(self):
        changes = gp.ensure_fields(self.config, dry=True)
        self.assertEqual(self.board.writes, [])
        text = '\n'.join(changes)
        for needle in ('add field Kind', 'add field Stage', 'add field Waiting for', 'Track -> Size',
                       'Origin -> Source', 'Autonomy -> Bot approvals', 'add 🧑 Your turn', 'add 🧑 Backlog',
                       'Icebox -> Later', 'remove 🧑 👍 Approve step (no cards)', 'kept 🧑 💬 Clarify'):
            self.assertIn(needle, text)

    def test_apply_keeps_ids_and_values_orders_status_and_is_idempotent(self):
        before = {o['name']: o['id'] for o in self.board.field('Status')['options']}
        changes = gp.ensure_fields(self.config)
        self.assertEqual(changes[-1], 'read back: OK')
        names = [o['name'] for o in self.board.field('Status')['options']]
        self.assertEqual(names, ['🧑 Backlog', '🤖 Inbox', '🧑 📋 Ready to schedule', '🤖 Up next', '🤖 In progress',
                                 '🧑 Your turn', '🤖 In review', 'Later', 'Done', 'Canceled', '🧑 💬 Clarify'])
        after = {o['name']: o['id'] for o in self.board.field('Status')['options']}
        self.assertEqual(after['Later'], before['Icebox'])
        self.assertEqual(after['🧑 💬 Clarify'], before['🧑 💬 Clarify'])
        self.assertEqual(self.board.value(1, 'Status'), '🧑 💬 Clarify')   # card kept its value
        self.assertEqual(self.board.value(2, 'Status'), 'Later')
        self.assertEqual(self.board.value(1, 'Size'), 'small fix')
        colors = {o['name']: o['color'] for o in self.board.field('Status')['options']}
        self.assertEqual((colors['🧑 Your turn'], colors['Done']), ('ORANGE', 'GREEN'))
        self.assertEqual([o['name'] for o in self.board.field('Waiting for')['options']],
                         ['💬 answer', '👍 approve', '🛠️ unblock', '⚖️ decide on PR', '🔀 merge PR', "⏳ Bot's turn"])
        self.board.writes.clear()
        again = gp.ensure_fields(self.config)
        self.assertEqual([w for w in self.board.writes if w[0] != 'set'], [])
        self.assertIn('Status: up to date', again)
        gp.read_fields(self.config)  # the schema now satisfies the contract


class Labels(Board):
    def test_create_rename_refresh_and_up_to_date(self):
        self.board.labels = {'pr:ready-review': {'name': 'pr:ready-review', 'color': 'ffffff', 'description': ''},
                             'needs-human:merge': {'name': 'needs-human:merge', 'color': '000000', 'description': 'x'}}
        dry = gp.ensure_labels(self.config, dry=True)
        self.assertEqual(self.board.writes, [])
        self.assertIn('rename pr:ready-review -> review-bot:queued', dry)
        self.assertIn('refresh needs-human:merge', dry)
        changes = gp.ensure_labels(self.config)
        self.assertEqual(changes, dry)
        for name in ('review-bot:queued', 'review-bot:running', 'fix-bot:queued', 'fix-bot:owns-branch',
                     'needs-human:merge', 'needs-human:decision', 'needs-human:discussion'):
            self.assertIn(name, self.board.labels)
        self.assertNotIn('pr:ready-review', self.board.labels)
        self.assertIn("'/devbot close'", self.board.labels[gp.PROPOSE_LABEL]['description'])
        self.assertEqual(gp.ensure_labels(self.config), [])


class Migration(Board):
    STATUS = ['🧑 Backlog', '🤖 Inbox', '🧑 💬 Clarify', '🧑 📋 Ready to schedule', '🤖 Up next', '🤖 In progress',
              '🧑 Your turn', '🧑 👍 Approve step', '🧑 🛠️ Unblock', '🤖 In review', 'Later', 'Done', 'Canceled']

    def setUp(self):
        super().setUp()
        self.board = FakeBoard(status=self.STATUS)
        for name, fake in (('gh', self.board.gh), ('graphql', self.board.graphql)):
            p = patch.object(gp, name, fake)
            p.start()
            self.addCleanup(p.stop)
        self.board.add_issue(1, '🧑 💬 Clarify')
        self.board.add_issue(2, '🧑 👍 Approve step')
        self.board.comment(2, 'bot', '🤖 Plan\n<!-- gate stage=Plan head=a branch=b plan=p -->')
        self.board.add_issue(3, '🧑 🛠️ Unblock')
        self.board.add_issue(4, '🤖 In progress')
        self.board.add_pr_card(50, '🧑 🛠️ Unblock')
        self.state = pathlib.Path(tempfile.mkdtemp(prefix='board-tools-last-status-'))
        (self.state / 'last-status.json').write_text(json.dumps({'1': 'Clarification needed', '4': 'In progress'}))

    def migrate(self, dry):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = gp.migrate_your_turn(self.config, dry, str(self.state))
        return code, out.getvalue()

    def test_dry_run_writes_nothing(self):
        code, out = self.migrate(True)
        self.assertEqual((code, self.board.writes), (0, []))
        self.assertEqual(out.count('DRY: would move'), 4)
        self.assertIn('DRY: would rewrite 1 last-status entries', out)
        self.assertEqual(json.loads((self.state / 'last-status.json').read_text())['1'], 'Clarification needed')

    def test_cards_move_with_comment_waiting_for_and_a_marker_when_missing(self):
        code, out = self.migrate(False)
        self.assertEqual(code, 0)
        for n, wait in ((1, '💬 answer'), (2, '👍 approve'), (3, '🛠️ unblock')):
            self.assertEqual(self.board.value(n, 'Status'), '🧑 Your turn')
            self.assertEqual(self.board.value(n, 'Waiting for'), wait)
            body = self.board.bodies(n)[-1]
            self.assertTrue(body.startswith('🤖 **'), body)
            self.assertIn('nothing else changed', body)
        self.assertIn('<!-- triage outcome=clarify -->', self.board.bodies(1)[-1])
        self.assertIn('<!-- blocked reason=migration -->', self.board.bodies(3)[-1])
        self.assertNotIn('gate', self.board.bodies(2)[-1])  # an approval marker is never invented
        self.assertEqual(self.board.value(4, 'Status'), '🤖 In progress')
        pr = next(i for i in self.board.items if i['content']['number'] == 50)
        self.assertEqual(pr['values'][self.board.field('Status')['id']], self.board.option_id('Status', '🧑 Your turn'))
        self.assertEqual(json.loads((self.state / 'last-status.json').read_text()), {'1': 'Your turn', '4': 'In progress'})
        # the migrated cards now read as the right kind of wait
        logins = gp.bot_logins(self.config)
        self.assertEqual(gp.wait_kind(self.board.comments['3'], (), logins)[0], 'unblock')
        code, out = self.migrate(False)
        self.assertIn('moved 0 card(s)', out)

    def test_refuses_without_the_waiting_for_field(self):
        board = FakeBoard(status=self.STATUS, waiting=False)
        with patch.object(gp, 'gh', board.gh), patch.object(gp, 'graphql', board.graphql):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = gp.migrate_your_turn(self.config, False)
        self.assertEqual(code, 1)
        self.assertIn('REFUSED', out.getvalue())


if __name__ == '__main__':
    unittest.main()
