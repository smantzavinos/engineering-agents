"""Unit tests for scripts/pipeline_runtime.py (repeat filter, stopped alerts, quiet hours, shared WIP).

Requirement: FR-001
"""
import datetime
import importlib.util
import json
import pathlib
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / 'scripts'
_spec = importlib.util.spec_from_file_location('pipeline_runtime', SCRIPTS / 'pipeline_runtime.py')
if _spec is None or _spec.loader is None:
    raise ImportError('pipeline_runtime.py')
rt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rt)

T0 = 1_800_000_000.0
MONDAY_NOON = datetime.datetime(2026, 1, 5, 12, 0)
SATURDAY_NOON = datetime.datetime(2026, 1, 10, 12, 0)


def tmp():
    return pathlib.Path(tempfile.mkdtemp(prefix='pipeline-runtime-test-'))


class FreshLines(unittest.TestCase):
    def test_a_line_is_sent_once_per_ttl_and_blank_lines_never(self):
        d = tmp()
        self.assertEqual(rt.fresh_lines(d, 'k', ['a', '', 'b'], now=T0), ['a', 'b'])
        self.assertEqual(rt.fresh_lines(d, 'k', ['a', 'c'], now=T0 + 60), ['c'])
        self.assertEqual(rt.fresh_lines(d, 'k', ['a'], now=T0 + rt.DEDUPE_TTL + 1), ['a'])

    def test_keys_are_separate_and_a_damaged_file_starts_over(self):
        d = tmp()
        rt.fresh_lines(d, 'one', ['a'], now=T0)
        self.assertEqual(rt.fresh_lines(d, 'two', ['a'], now=T0), ['a'])
        (d / 'notify-dedupe-one.json').write_text('{broken', encoding='utf-8')
        self.assertEqual(rt.fresh_lines(d, 'one', ['a'], now=T0), ['a'])


class Stopped(unittest.TestCase):
    def test_alert_once_then_hourly_then_one_recovery_line(self):
        d = tmp()
        first = rt.job_down(d, 'work dispatch', 'gh: bad credentials', now=T0)
        self.assertEqual(len(first), 1)
        self.assertIn('🛑 **work dispatch stopped since', first[0])
        self.assertIn('gh: bad credentials', first[0])
        self.assertEqual(rt.job_down(d, 'work dispatch', 'gh: bad credentials', now=T0 + 600), [])
        later = rt.job_down(d, 'work dispatch', 'gh: still bad', now=T0 + rt.STOP_ALERT_EVERY + 1)
        self.assertIn('(1 h)', later[0])
        self.assertIn('still bad', later[0])
        up = rt.job_up(d, 'work dispatch', now=T0 + 2 * 3600 + 300)
        self.assertEqual(len(up), 1)
        self.assertIn('✅ **work dispatch runs again** after 2 h 5 min stopped', up[0])
        self.assertEqual(rt.job_up(d, 'work dispatch', now=T0 + 3 * 3600), [])
        self.assertIsNone(rt.stopped(d))


class QuietHours(unittest.TestCase):
    def test_off_unless_configured(self):
        self.assertFalse(rt.quiet_now({}, 'work', MONDAY_NOON))

    def test_a_window_that_wraps_midnight(self):
        env = {'PIPELINE_QUIET_HOURS': '22:00-07:00'}
        at = lambda h, m=0: datetime.datetime(2026, 1, 5, h, m)  # noqa: E731
        self.assertTrue(rt.quiet_now(env, 'work', at(23)))
        self.assertTrue(rt.quiet_now(env, 'work', at(6, 59)))
        self.assertFalse(rt.quiet_now(env, 'work', at(7)))
        self.assertFalse(rt.quiet_now(env, 'work', at(21, 59)))
        self.assertTrue(rt.quiet_now({'PIPELINE_QUIET_HOURS': '09:00-17:00'}, 'pr', MONDAY_NOON))

    def test_weekends_modes_and_force(self):
        env = {'PIPELINE_QUIET_WEEKENDS': '1'}
        self.assertTrue(rt.quiet_now(env, 'work', SATURDAY_NOON))
        self.assertFalse(rt.quiet_now(env, 'work', MONDAY_NOON))
        self.assertFalse(rt.quiet_now(env, 'triage', SATURDAY_NOON), 'triage is not quiet by default')
        self.assertTrue(rt.quiet_now({**env, 'PIPELINE_QUIET_MODES': 'triage,work'}, 'triage', SATURDAY_NOON))
        self.assertFalse(rt.quiet_now({**env, 'PIPELINE_FORCE': '1'}, 'work', SATURDAY_NOON))

    def test_a_malformed_window_is_an_error(self):
        for bad in ('late', '22-07', '25:00-07:00'):
            with self.assertRaisesRegex(ValueError, 'PIPELINE_QUIET_HOURS'):
                rt.quiet_now({'PIPELINE_QUIET_HOURS': bad}, 'work', MONDAY_NOON)


class LiveAuthors(unittest.TestCase):
    def test_counts_live_work_and_fix_rounds_from_both_state_dirs(self):
        pipe, pr = tmp(), tmp()
        (pipe / 'dispatches.jsonl').write_text('\n'.join(json.dumps(r) for r in (
            {'kind': 'work', 'item': 1, 'reason': 'start', 'pid': 11},
            {'kind': 'work', 'item': 2, 'reason': 'resume', 'pid': 12},
            {'kind': 'work', 'item': 3, 'reason': 'start', 'pid': 13},   # dead
            {'kind': 'triage', 'items': [4], 'pid': 14},                  # not an author session
            {'kind': 'work', 'item': 5, 'reason': 'start'},               # never started
        )) + '\n{torn', encoding='utf-8')
        (pr / 'dispatches.jsonl').write_text(json.dumps({'kind': 'babysit', 'pr': 9, 'pid': 21}), encoding='utf-8')
        live = rt.live_authors([pipe, pr, tmp() / 'missing'], lambda pid: pid != 13)
        self.assertEqual(live, {11: 'coding', 12: 'maintenance', 21: 'maintenance'})

    def test_keeps_t3_and_numeric_handles_as_ledger_keys(self):
        with tempfile.TemporaryDirectory() as state:
            records = (
                {'kind': 'work', 'item': 1, 'reason': 'start', 'pid': 't3:work-thread'},
                {'kind': 'babysit', 'pr': 9, 'pid': 't3:fix-thread'},
                {'kind': 'work', 'item': 2, 'reason': 'resume', 'pid': 12},
                {'kind': 'work', 'item': 3, 'reason': 'resume', 'pid': '13'},
            )
            (pathlib.Path(state) / 'dispatches.jsonl').write_text(
                '\n'.join(map(json.dumps, records)), encoding='utf-8')
            self.assertEqual(rt.live_authors([state], lambda _: True),
                             {'t3:work-thread': 'coding', 't3:fix-thread': 'maintenance',
                              12: 'maintenance', '13': 'maintenance'})


class Repositories(unittest.TestCase):
    def test_one_repository_without_a_map(self):
        self.assertEqual(rt.repositories({'PIPELINE_REPO': 'o/a'}), ('o/a', {'o/a': {}}))
        self.assertEqual(rt.board_states({'PIPELINE_REPO': 'o/a'}, '/s'), [pathlib.Path('/s')])

    def test_map_from_env_or_config_file_with_per_repo_state(self):
        repos = {'o/a': {'checkout': '/a'}, 'o/b': {'checkout': '/b', 'base': 'develop'}}
        env = {'PIPELINE_REPO': 'o/a', 'PIPELINE_REPOSITORIES': json.dumps(repos)}
        self.assertEqual(rt.repositories(env), ('o/a', repos))
        self.assertEqual(rt.board_states(env, '/s'), [pathlib.Path('/s'), pathlib.Path('/s/repositories/o__b')])
        path = tmp() / 'board.json'
        path.write_text(json.dumps({'repo': 'o/b', 'repositories': repos}), encoding='utf-8')
        primary, found = rt.repositories({'GH_PROJECT_CONFIG': str(path)})
        self.assertEqual((primary, list(found)), ('o/b', ['o/a', 'o/b']))
        self.assertEqual(rt.repo_state('/s', 'o/a', 'o/b'), pathlib.Path('/s/repositories/o__a'))

    def test_given_board_states_win(self):
        import os
        env = {'PIPELINE_REPO': 'o/a', 'PIPELINE_BOARD_STATES': os.pathsep.join(['/x', '/y'])}
        self.assertEqual(rt.board_states(env, '/s'), [pathlib.Path('/x'), pathlib.Path('/y')])

    def test_bad_maps_are_refused(self):
        for raw, error in (('[1]', 'must map'), ('{"bad": {}}', 'not owner/repo'), ('{"o/a": {"chekout": 1}}', 'chekout'),
                           ('{"o/b": {}}', 'primary repository o/a'), ('{', 'not JSON'),
                           ('{"o/a": {"checkout": 1}}', 'non-empty string'),
                           ('{"o/a": {"branch_template": "item"}}', 'exactly once'),
                           ('{"o/a": {"checkout": "/c"}, "o/b": {"checkout": "/c/"}}', 'share a checkout'),
                           ('{"o/a": {"worktree_root": "/w"}, "o/b": {"worktree_root": "/w"}}', 'share a worktree_root')):
            with self.assertRaisesRegex(ValueError, error):
                rt.repositories({'PIPELINE_REPO': 'o/a', 'PIPELINE_REPOSITORIES': raw})


if __name__ == '__main__':
    unittest.main()
