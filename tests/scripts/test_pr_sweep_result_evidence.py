"""Review results: evidence must exist (empty logs allowed) and a rejected result must say why (PR 214).

Ported from gm-agent-pipeline (pipeline/test_result_evidence.py).
Requirement: FR-001
"""
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest

SCRIPTS = __import__('pathlib').Path(__file__).resolve().parents[2] / 'scripts'
ROOT = Path(__file__).resolve().parent
HEAD = 'd' * 40


def dispatcher():
    spec = importlib.util.spec_from_file_location('sweep_evidence', SCRIPTS / 'pr-sweep-dispatch.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ResultEvidenceTests(unittest.TestCase):
    def setup(self, temp):
        d = dispatcher()
        d.RESULTS = Path(temp) / 'results'
        d.RESULTS.mkdir()
        d.LOGS = Path(temp) / 'logs'
        d.LOGS.mkdir()
        d.alive = lambda pid: False
        return d

    def write_result(self, d, tag, artifacts):
        (d.RESULTS / f'{tag}.json').write_text(json.dumps({
            'repo': 'o/r', 'kind': 'review', 'pr': 214, 'head': HEAD, 'verdict': 'READY',
            'verification_artifacts': artifacts}))
        return {'repo': 'o/r', 'pr': 214, 'head': HEAD, 'kind': 'review', 'tag': tag, 'pid': 5, 'ts': time.time()}

    def test_pr214_artifact_shapes(self):
        with tempfile.TemporaryDirectory() as temp:
            d = self.setup(temp)
            gone = self.write_result(d, 'gone', [(Path(temp) / 'pruned' / 'verify.log').as_posix()])
            self.assertFalse(d.has_result(gone))
            self.assertIn('verification log missing', d.result_problem(gone))
            msys = self.write_result(d, 'msys', ['/tmp/pr214-d1087f29/fmt.log'])
            self.assertFalse(d.has_result(msys))
            for tag in ('mixed', 'empty', 'one'):  # each round writes its logs under LOGS/<tag>
                art = d.LOGS / tag
                art.mkdir()
                (art / 'fmt.log').write_text('')
                (art / 'test.log').write_text('ok')
                (art / 'test-elmo.log').write_text('ok')
            mixed = self.write_result(d, 'mixed', [(d.LOGS / 'mixed' / n).as_posix()
                                                    for n in ('fmt.log', 'test.log', 'test-elmo.log')])
            self.assertTrue(d.has_result(mixed), 'an empty fmt.log next to non-empty logs is evidence')
            only_empty = self.write_result(d, 'empty', [(d.LOGS / 'empty' / 'fmt.log').as_posix()])
            self.assertFalse(d.has_result(only_empty))
            missing_one = self.write_result(d, 'one', [(d.LOGS / 'one' / 'test.log').as_posix(),
                                                       (d.LOGS / 'one' / 'nope.log').as_posix()])
            self.assertFalse(d.has_result(missing_one), 'a listed but missing file still rejects')
            borrowed = self.write_result(d, 'borrowed', [(d.LOGS / 'mixed' / 'test.log').as_posix()])
            self.assertIn('outside the artifacts directory', d.result_problem(borrowed),
                          "another round's log, or any other existing file, is not this round's evidence")

    def test_spawn_gives_artifacts_dir(self):
        text = (SCRIPTS / 'pr-sweep-prompts/review.md').read_text(encoding='utf-8')
        text += (SCRIPTS / 'pr-sweep-prompts/babysit.md').read_text(encoding='utf-8')
        self.assertGreaterEqual(text.count('{artifacts_dir}'), 2)

    def test_exhausted_review_says_why_and_owner_can_retry(self):
        with tempfile.TemporaryDirectory() as temp:
            d = self.setup(temp)
            d.DRY = False
            d.DISPATCH = Path(temp) / 'dispatches.jsonl'
            d.set_state_label = lambda *a: None
            d.remove_label = lambda *a: None
            launched = []
            d.spawn = lambda kind, *a, **k: (launched.append(kind), (0, 'new'))[1]
            d.react = lambda *a: None
            recs = [self.write_result(d, f'r{i}', ['/tmp/x/fmt.log']) for i in range(3)]
            pr = {'number': 214, 'title': 'T', 'headRefName': 'b', 'headRefOid': HEAD, 'labels': [{'name': 'review-bot:queued'}],
                  'isDraft': False, 'statusCheckRollup': []}
            comments = []
            d.gh = lambda *args, **kw: [pr] if args[0] == 'pr' else (comments if '/comments' in args[1] else [])
            reported = set()
            d.sweep_repo('o/r', recs, reported)
            text = '\n'.join(d.out)
            self.assertIn('rejected: verification log missing: /tmp/x/fmt.log', text)
            self.assertEqual(text.count('rejected: verification log missing'), 3)
            self.assertIn('3 review runs on dddddddd failed: verification log missing', text)
            self.assertIn('review` to retry', text)
            self.assertNotIn('no bot is due to act', text)
            self.assertEqual(launched, [])
            # An explicit owner request launches past the cap.
            comments.append({'id': 99, 'body': f'{d.HANDLE} review', 'user': {'login': 'owner'}})
            d.sweep_repo('o/r', recs, reported)
            self.assertEqual(launched, ['review'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
