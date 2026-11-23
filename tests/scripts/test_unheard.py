"""Unit tests for scripts/unheard.py; no network (FakeBoard patches gh/graphql of the adapter).

Ported from gm-agent-pipeline test_unheard (generic subset).
Requirement: FR-001
"""
import contextlib
import importlib.util
import io
import pathlib
import sys
import types
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


uh = load('unheard', 'unheard.py')
gp = uh.gp
_shared = load('test_gh_project_shared_unheard', 'test_gh_project.py', HERE)
OWNER, config = _shared.OWNER, _shared.config
H = ('/devbot',)
OWNERS = (OWNER,)
T0 = '2026-01-01T00:00:00Z'
NOW = uh.ts('2026-01-01T01:00:00Z')


def c(i, body, who='dev', at='2026-01-01T00:30:00Z', eyes=0):
    return {'id': i, 'user': {'login': who}, 'body': body, 'created_at': at, 'reactions': {'eyes': eyes},
            'html_url': f'https://github.com/o/r/issues/1#issuecomment-{i}'}


def item(status, prs=()):
    return {'number': 1, 'status': status, 'prs': list(prs)}


def reason(comment, status, kind=None, prs=(), listened=(OWNER, 'dev'), proposal=False, labels=()):
    return uh.issue_reason(comment, item(status, prs), OWNERS, set(listened), H, labels, kind, proposal)


class Pending(unittest.TestCase):
    def test_comment_after_the_last_bot_comment_is_pending_after_the_grace_period(self):
        comments = [c(1, '🤖 **Your turn** <!-- gate stage=Plan -->', 'bot', '2026-01-01T00:10:00Z'), c(2, 'hello')]
        self.assertEqual([x['id'] for x in uh.pending(comments, NOW, {'bot'})], [2])
        self.assertEqual(uh.pending(comments, uh.ts('2026-01-01T00:32:00Z'), {'bot'}), [])  # still in grace

    def test_eyes_answered_older_than_the_bot_bot_accounts_and_the_cutoff_are_not_pending(self):
        comments = [c(1, 'before', at='2026-01-01T00:05:00Z'),
                    c(2, '🤖 x <!-- triage outcome=ready -->', 'bot', '2026-01-01T00:10:00Z'),
                    c(3, 'seen', eyes=1), c(4, 'answered'), c(5, '🤖 x\n<!-- unheard comment=4 -->', 'bot'),
                    {**c(6, 'dependabot says'), 'user': {'login': 'dependabot[bot]', 'type': 'Bot'}},
                    c(7, 'fresh')]
        self.assertEqual([x['id'] for x in uh.pending(comments, NOW, {'bot'})], [7])
        self.assertEqual(uh.pending(comments, NOW, {'bot'}, since=NOW), [])

    def test_link_comments_do_not_count_as_reading_the_thread(self):
        comments = [c(1, 'please also do x', at='2026-01-01T00:05:00Z'),
                    c(2, '🤖 **No action needed: related PR #9**\n<!-- pr-link pr=9 -->', 'bot')]
        self.assertEqual([x['id'] for x in uh.pending(comments, NOW, {'bot'})], [1])

    def test_a_claim_line_is_automation_not_a_person(self):
        self.assertEqual(uh.pending([c(1, 'fix-bot: owns this branch; session=x last-active=y', OWNER)], NOW, {'bot'}), [])


class IssueReasons(unittest.TestCase):
    def test_in_progress_card_gets_a_reply_and_triage_statuses_are_left_to_triage(self):
        why, todo = reason(c(1, 'please also handle y'), 'In progress')
        self.assertIn('in the middle of a step', why)
        self.assertIn('/devbot revise', todo)
        self.assertIsNone(reason(c(1, 'more context'), 'Inbox'))
        self.assertIsNone(reason(c(1, '/devbot answer: 1 yes'), 'Your turn', kind='answer'))

    def test_answers_without_the_command_are_explained(self):
        why, todo = reason(c(1, 'yes to all'), 'Your turn', kind='answer')
        self.assertIn('/devbot answer:', why)
        self.assertIn('/devbot answer: approve', todo)

    def test_gate_replies_are_left_to_the_dispatcher_but_a_non_owner_gate_reply_is_explained(self):
        self.assertIsNone(reason(c(1, '/devbot approve', OWNER), 'Your turn', kind='approve'))
        self.assertIsNone(reason(c(1, 'what about z?'), 'Your turn', kind='approve'))
        self.assertIsNone(reason(c(1, '/devbot unblock: done'), 'Your turn', kind='unblock'))
        why, _ = reason(c(1, '/devbot approve'), 'Your turn', kind='approve')
        self.assertIn('Only the owners (@owner)', why)

    def test_a_command_on_the_wrong_status_says_where_it_works(self):
        why, _ = reason(c(1, '/devbot approve', OWNER), 'Ready')
        self.assertIn('only works while the card is in', why)
        self.assertIn(gp.board_value('Status', 'Ready'), why)

    def test_your_turn_with_a_pr_and_in_review_point_at_the_pr(self):
        why, todo = reason(c(1, 'change the name'), 'Your turn', kind=None, prs=(9,))
        self.assertIn('#9', why)
        self.assertIn('/devbot fix', todo)
        self.assertIn('its pull request', reason(c(1, 'x'), 'In review')[0])

    def test_close_proposal_replies_are_left_to_board_sync(self):
        self.assertIsNone(reason(c(1, '/devbot close'), 'Ready', proposal=True))
        self.assertIsNone(reason(c(1, '/devbot keep'), 'Your turn', labels=(gp.PROPOSE_LABEL,)))

    def test_strangers_are_answered_only_when_they_address_a_bot(self):
        self.assertIsNone(reason(c(1, 'nice work', 'mallory'), 'In progress'))
        why, _ = reason(c(1, '/devbot approve', 'mallory'), 'Your turn', kind='approve')
        self.assertIn('I only take instructions', why)

    def test_finished_items_answer_only_comments_that_address_a_bot(self):
        self.assertIsNone(reason(c(1, 'thanks!'), 'Done'))
        self.assertIn('finished', reason(c(1, '/devbot revise: more'), 'Done')[0])

    def test_backlog_and_later_say_how_to_get_triage(self):
        self.assertIn(gp.board_value('Status', 'Inbox'), reason(c(1, 'x'), 'Backlog')[1])
        self.assertIn('parked', reason(c(1, 'x'), gp.PARKED_STATUS)[0])


class PrReasons(unittest.TestCase):
    ALLOWED = {OWNER, 'dev'}

    def test_valid_commands_and_bot_owned_prs_are_left_alone(self):
        self.assertIsNone(uh.pr_reason(c(1, '/devbot fix'), None, OWNERS, H, self.ALLOWED))
        self.assertIsNone(uh.pr_reason(c(1, 'looks fine'), 'review-bot:queued', OWNERS, H, self.ALLOWED))

    def test_a_command_the_sweep_drops_as_automation_is_explained(self):
        for body in ('/devbot fix\nthe arrow `-->` breaks', '/devbot fix\nwork: keep the API stable'):
            why, todo = uh.pr_reason(c(1, body, 'dev'), None, OWNERS, H, self.ALLOWED)
            self.assertIn('text only the bots may write', why)
            self.assertIn('without that text', todo)
        # An owner's claim line further down is an instruction the sweep reads (mentions()).
        self.assertIsNone(uh.pr_reason(c(1, '/devbot fix\nwork: keep the API stable', OWNER), None, OWNERS, H, self.ALLOWED))

    def test_a_person_s_claim_line_below_the_command_is_still_pending(self):
        self.assertEqual([x['id'] for x in uh.pending([c(1, '/devbot fix\nwork: keep it')], NOW, {'bot'})], [1])

    def test_plain_comment_while_a_person_is_waited_on_and_a_stranger_command_get_replies(self):
        why, todo = uh.pr_reason(c(1, 'please rename it'), 'needs-human:merge', OWNERS, H, self.ALLOWED)
        self.assertIn('waits for a person', why)
        self.assertIn('/devbot fix', todo)
        why, _ = uh.pr_reason(c(1, '/devbot fix', 'mallory'), None, OWNERS, H, self.ALLOWED)
        self.assertIn('the people working on it (@dev)', why)

    def test_a_fork_pr_is_explained_to_anyone_who_addresses_a_bot(self):
        why, _ = uh.pr_reason(c(1, '/devbot review', OWNER), None, OWNERS, H, self.ALLOWED, fork=True)
        self.assertIn('fork', why)
        self.assertIsNone(uh.pr_reason(c(1, 'lgtm', OWNER), None, OWNERS, H, self.ALLOWED, fork=True))

    def test_mistyped_handles_wrong_verbs_and_misplaced_commands_get_the_exact_fix(self):
        self.assertEqual(uh.near_miss('/devbto fix', H), '/devbto')
        self.assertIsNone(uh.near_miss('/deploy now', H))
        self.assertIn('`/devbto` is not a name', uh.syntax_hint([c(1, '/devbto fix')], H, uh.PR_VERBS, 'on a pull request'))
        self.assertIn('Leave out the colon', uh.syntax_hint([c(1, '/devbot: fix')], H, uh.PR_VERBS, 'on a pull request'))
        self.assertIn('`merge` is not a command', uh.syntax_hint([c(1, '/devbot merge')], H, uh.PR_VERBS, 'on a pull request'))
        self.assertIn('first line', uh.syntax_hint([c(1, 'hey\n/devbot fix')], H, uh.PR_VERBS, 'on a pull request'))
        at = ('@helper-bot',)
        self.assertEqual(uh.near_miss('thanks @helper-bto', at), '@helper-bto')
        self.assertIsNone(uh.near_miss('thanks @dependabot', at))


class Runs(unittest.TestCase):
    def setUp(self):
        self.board = FakeBoard()
        self.config = config()
        for target, name, fake in ((gp, 'gh', self.board.gh), (gp, 'graphql', self.board.graphql)):
            p = patch.object(target, name, fake)
            p.start()
            self.addCleanup(p.stop)

    def run_unheard(self, dry=False, now=NOW, only=None):
        run = uh.Run(self.config, dry, now)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            for name in ('issues', 'prs'):
                if only in (None, name):
                    getattr(run, name)()
            run.save()
        return out.getvalue()

    def test_one_reply_per_batch_with_marker_and_new_issue_tip_then_silence(self):
        self.board.add_issue(1, '🤖 In progress', assignees=('dev',))
        self.board.comment(1, 'dev', 'please also handle y', created='2026-01-01T00:30:00Z')
        self.board.comment(1, OWNER, 'and open an issue for the crash', created='2026-01-01T00:31:00Z')
        self.run_unheard()
        bodies = self.board.bodies(1)
        self.assertEqual(len(bodies), 1)
        self.assertTrue(bodies[0].startswith('🤖 **Still waiting: no bot will act on'))
        self.assertIn('<!-- unheard comment=', bodies[0])
        self.assertIn('open a new issue yourself', bodies[0])
        self.assertIn('@dev @owner', bodies[0])
        self.board.items[0]['content']['updatedAt'] = '2026-01-01T00:40:00Z'
        self.run_unheard(now=NOW + 600)
        self.assertEqual(len(self.board.bodies(1)), 1)  # answered comments are never answered again

    def test_dry_runs_write_nothing(self):
        self.board.add_issue(1, '🤖 In progress')
        self.board.comment(1, OWNER, 'please also handle y', created='2026-01-01T00:30:00Z')
        out = self.run_unheard(dry=True)
        self.assertIn('would reply on #1', out)
        self.assertEqual(self.board.writes, [])

    def test_an_unprefixed_bot_comment_gets_the_emoji_and_a_person_s_does_not(self):
        self.board.add_issue(1, '🤖 In progress')
        mine = self.board.comment(1, 'bot', '**Your turn**\n<!-- gate stage=Plan -->', created='2026-01-01T00:30:00Z')
        theirs = self.board.comment(1, OWNER, 'note <!-- mine -->', created='2026-01-01T00:31:00Z')
        self.run_unheard()
        self.assertTrue(mine['body'].startswith('🤖 '))
        self.assertFalse(theirs['body'].startswith('🤖'))

    def test_style_problems_of_bot_comments_are_logged_once(self):
        self.board.add_issue(1, '🤖 In progress')
        self.board.comment(1, 'bot', '🤖 hello\n<!-- gate stage=Plan -->', created='2026-01-01T00:30:00Z')
        style = types.SimpleNamespace(lint=lambda body: ['no headline'], infer_kind=lambda body: 'gate')
        with patch.dict(sys.modules, {'comment_style': style}):
            self.run_unheard()
            self.board.items[0]['content']['updatedAt'] = 'changed'
            self.run_unheard()
        log = (pathlib.Path(self.config['state_dir']) / 'style.log').read_text(encoding='utf-8').splitlines()
        self.assertEqual(len(log), 1)
        self.assertIn('no headline', log[0])

    def test_pr_commands_from_assignees_are_left_to_the_sweep_and_strangers_are_told(self):
        self.board.add_issue(5, '🤖 In progress', assignees=('dev',))
        self.board.add_pr(9, closes=(5,))
        self.board.comment(9, 'dev', '/devbot fix', created='2026-01-01T00:30:00Z')
        self.board.comment(9, 'mallory', '/devbot review', created='2026-01-01T00:31:00Z')
        self.run_unheard(only='prs')
        bodies = self.board.bodies(9)
        self.assertEqual(len(bodies), 1)
        self.assertIn('@mallory', bodies[0])
        self.assertIn('the people working on it (@dev, @helper)', bodies[0])

    def test_assignees_of_an_issue_in_another_repository_are_not_people_of_the_pr(self):
        self.board.add_issue(5, '🤖 In progress', assignees=('dev',))
        self.board.add_pr(9, closes=('someone/else#5',))
        self.board.comment(9, 'dev', '/devbot fix', created='2026-01-01T00:30:00Z')
        self.run_unheard(only='prs')
        bodies = self.board.bodies(9)
        self.assertEqual(len(bodies), 1)
        self.assertIn('@dev', bodies[0])

    def test_one_failing_item_does_not_stop_the_others_and_is_read_again(self):
        for n in (1, 2):
            self.board.add_issue(n, '🤖 In progress')
            self.board.comment(n, OWNER, 'please', created='2026-01-01T00:30:00Z')
        real = gp.post_comment

        def flaky(config, number, body):
            if number == 1:
                raise RuntimeError('HTTP 502')
            return real(config, number, body)
        run = uh.Run(self.config, False, NOW)
        with patch.object(gp, 'post_comment', flaky), contextlib.redirect_stdout(io.StringIO()):
            run.issues()
            run.save()
        self.assertEqual((len(self.board.bodies(1)), len(self.board.bodies(2))), (0, 1))
        self.assertIn('unheard #1 FAILED: HTTP 502', run.failures[0])
        self.run_unheard()  # the failed post is retried; the answered item stays answered
        self.assertEqual((len(self.board.bodies(1)), len(self.board.bodies(2))), (1, 1))

    def test_malformed_api_data_fails_only_its_item(self):
        for n in (1, 2):
            self.board.add_issue(n, '🤖 In progress')
            self.board.comment(n, OWNER, 'please', created='2026-01-01T00:30:00Z')
        real = gp.comments_of
        run = uh.Run(self.config, False, NOW)
        with patch.object(gp, 'comments_of', lambda config, n: None if n == 1 else real(config, n)), \
                contextlib.redirect_stdout(io.StringIO()):
            run.issues()
        self.assertEqual(len(self.board.bodies(2)), 1)
        self.assertIn('unheard #1 FAILED', run.failures[0])

    def test_only_comments_of_its_own_login_get_the_emoji(self):
        self.board.add_issue(1, '🤖 In progress')
        other = self.board.comment(1, 'devbot', '**Your turn**\n<!-- gate stage=Plan -->', created='2026-01-01T00:30:00Z')
        with patch.dict(self.config, {'bot_logins': ('bot', 'devbot')}):
            self.run_unheard()
        self.assertFalse(other['body'].startswith('🤖'))

    def test_unchanged_items_are_not_read_again(self):
        self.board.add_issue(1, '🤖 In progress')
        self.run_unheard()
        self.board.comment(1, OWNER, 'late', created='2026-01-01T00:30:00Z')  # updatedAt unchanged
        self.run_unheard()
        self.assertEqual(self.board.bodies(1), [])

    def test_replies_are_capped_per_run_and_the_rest_wait_for_the_next(self):
        for n in (1, 2, 3):
            self.board.add_issue(n, '🤖 In progress')
            self.board.comment(n, OWNER, 'please', created='2026-01-01T00:30:00Z')
        with patch.object(uh, 'MAX_REPLIES', 2):
            self.run_unheard()
            self.assertEqual(sum(len(self.board.bodies(n)) for n in (1, 2, 3)), 2)
            self.run_unheard()
        self.assertEqual(sum(len(self.board.bodies(n)) for n in (1, 2, 3)), 3)


class Main(unittest.TestCase):
    def test_owners_are_required(self):
        with self.assertRaises(ValueError):
            uh.main([], config=config(owners=()))


if __name__ == '__main__':
    unittest.main()
