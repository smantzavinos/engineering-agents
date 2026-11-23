"""Owner command parser (scripts/commands.py) and its callers in both dispatchers.

Ported from gm-agent-pipeline (pipeline/test_commands.py): one tolerant parser for `<handle> <verb>` first lines.
Requirement: FR-001
"""
import os
import pathlib
import runpy
import sys
import unittest
from unittest import mock

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import commands  # noqa: E402

H = ('/devbot', '@bot-name')
ENV = {"PIPELINE_OWNERS": "owner", "PR_AGENT_HANDLE": "/devbot", "PR_SWEEP_REPOS": "o/r"}


class th:  # the helpers the upstream tests import from test_command_handles
    @staticmethod
    def load(name, env=ENV):
        with mock.patch.dict(os.environ, env, clear=False):
            return runpy.run_path(str(SCRIPTS / name))

    @staticmethod
    def comment(body, login='owner', cid=1):
        return {'id': cid, 'user': {'login': login}, 'body': body}


class Parser(unittest.TestCase):
    def test_table(self):
        table = [
            ('/devbot approve', ('/devbot', 'approve', '')),
            ('\\devbot approved', ('/devbot', 'approve', '')),
            ('`/devbot approves`', ('/devbot', 'approve', '')),
            ('/DevBot Fix rebase', ('/devbot', 'fix', 'rebase')),
            ('/devbot: approve', ('/devbot', 'approve', '')),
            ('/devbot:approve', ('/devbot', 'approve', '')),
            ('/devbot approve.', ('/devbot', 'approve', '')),
            ('/devbot approve!', ('/devbot', 'approve', '')),
            ('/devbot approve: go', ('/devbot', 'approve', 'go')),
            ('\n\n  /devbot reviewed\nmore', ('/devbot', 'review', '')),
            ('/devbot re-review', ('/devbot', 'review', '')),
            ('/devbot rereview', ('/devbot', 'review', '')),
            ('/devbot fixing it', ('/devbot', 'fix', 'it')),
            ('/devbot babysat', ('/devbot', 'babysit', '')),
            ('/devbot revised: shorter', ('/devbot', 'revise', 'shorter')),
            ('/devbot revise:shorter', ('/devbot', 'revise', 'shorter')),
            ('/devbot unblocked: bench ok', ('/devbot', 'unblock', 'bench ok')),
            ('/devbot answers: 42', ('/devbot', 'answer', '42')),
            ('/devbot rejected', ('/devbot', 'reject', '')),
            ('/devbot discussed', ('/devbot', 'discuss', '')),
            ('/devbot closed', ('/devbot', 'close', '')),
            ('/devbot kept', ('/devbot', 'keep', '')),
            ('/devbot approval', ('/devbot', 'approve', '')),
            ('@Bot-Name approved', ('@bot-name', 'approve', '')),
        ]
        for text, expect in table:
            self.assertEqual(commands.parse(text, H), expect, text)

    def test_ignored(self):
        for text in ('', 'approve', 'please /devbot approve', 'x/devbot approve', '/devbotx approve',
                     '/devbot approvedly', '/devbot approvex', '/devbot', '/devbot lgtm', '/devbot maybe approve',
                     '\\bot-name approve', 'devbot approve', '/devbot-x approve', 'I think /devbot should approve',
                     '/devbot approve?', '/devbot closed?', '/devbot closing?', '/devbot: approve?', '/devbot approve?!',
                     '/devbot approve.?', '/devbot fix?'):
            self.assertIsNone(commands.parse(text, H), text)

    def test_split_names_the_command_even_for_unknown_words(self):
        self.assertEqual(commands.split('\\devbot lgtm there', H), ('/devbot', 'lgtm', 'there'))
        self.assertIsNone(commands.split('/devbotx lgtm', H))

    def test_strategy(self):
        for word, expect in (('rebase', 'rebase'), ('rebased', 'rebase'), ('Rebasing', 'rebase'), ('merged', 'merge'),
                             ('merging', 'merge'), ('squash', None), ('rebasedly', None)):
            self.assertEqual(commands.strategy(word), expect, word)


class Callers(unittest.TestCase):
    def test_pipeline_dispatch_parse_reply(self):
        parse = th.load('pipeline-dispatch.py')['parse_reply']
        want = parse(th.comment('/devbot approve'))
        self.assertEqual(want, ('approve', ''))
        for body in ('\\devbot approved', '`/devbot approve`', '/DevBot approves', '/devbot: approve.'):
            self.assertEqual(parse(th.comment(body)), want, body)
        self.assertEqual(parse(th.comment('\\devbot revised: shorter\nmore')), ('revise', 'shorter\nmore'))
        self.assertEqual(parse(th.comment('/devbot unblocked: ok')), ('unblock', 'ok'))
        self.assertEqual(parse(th.comment('/devbot closed')), ('close', ''))
        for body in ('/devbotx approve', '/devbot approvedly', 'we approved /devbot', '/devbot fix'):
            self.assertIsNone(parse(th.comment(body)), body)
        self.assertIsNone(parse(th.comment('/devbot approve', login='bot-name'), handles=H, owners=('bot-name',), shared=False))

    def test_pr_sweep_mentions_and_strategy(self):
        g = th.load('pr-sweep-dispatch.py')
        mentions, strat, h = g['mentions'], g['integrate_strategy'], g['HANDLES']
        for body, expect in (('\\devbot reviewed', 'review'), ('/devbot re-review', 'review'), ('`/devbot review`', 'review'),
                             ('/DevBot Fix rebase', 'fix'), ('/devbot fixed', 'fix'), ('/devbot babysat', 'fix'),
                             ('/devbot: fixing', 'fix')):
            review, fix = mentions([th.comment(body, 'matt')], h, set())
            self.assertEqual((review is not None, fix is not None), (expect == 'review', expect == 'fix'), body)
        for body in ('/devbotx fix', '/devbot fixedly', '/devbot approve', 'I said /devbot fix', '/devbot lgtm'):
            self.assertEqual(mentions([th.comment(body, 'matt')], h, set()), (None, None), body)
        self.assertEqual(mentions([th.comment('/devbot fix', 'bot-name')], ('@bot-name', '/devbot'), set()), (None, None))
        for body, expect in (('/devbot fix rebase', 'rebase'), ('/DevBot Fix rebase', 'rebase'),
                             ('\\devbot fixed rebasing', 'rebase'), ('/devbot babysat rebased', 'rebase'),
                             ('/devbot fix merged', 'merge'), ('/devbot fix', 'merge'),
                             ('/devbot fix squash', 'merge'), ('/devbot review rebase', 'merge')):
            self.assertEqual(strat(th.comment(body), h), expect, body)


if __name__ == '__main__':
    unittest.main(verbosity=2)
