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


if __name__ == '__main__':
    unittest.main()
