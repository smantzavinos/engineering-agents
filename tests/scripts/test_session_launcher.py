"""Contract tests for scripts/session_launcher.py (launcher-contract.md).

Requirement: FR-001
"""
import contextlib
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

LAUNCHER = pathlib.Path(__file__).resolve().parents[2] / 'scripts' / 'session_launcher.py'
TITLE = 'PR #17 review @abc1234 o/r'
PROMPT = 'Review the change — read this first.\n\nSecond line.\n'
LINK = 'https://example.test/threads/thread-test'

# The CLI stub reads canned replies beside itself, so probes need not pass their
# configuration mapping as the child environment. Only `start` reads stdin.
FAKE_SESSION = r'''
import json, os, pathlib, select, subprocess, sys

root = pathlib.Path(__file__).resolve().parent
args = sys.argv[1:]
is_start = args[:2] == ['thread', 'start']
is_hermes = args[:1] == ['chat']
record = {'argv': args, 'stdin': sys.stdin.read() if is_start else None,
          'server': os.getenv('T3CODE_HOME')}
if is_hermes:
    record.update(pid=os.getpid(), sid=os.getsid(0), cwd=os.getcwd(),
                  stdin=sys.stdin.read(1) if select.select([sys.stdin], [], [], 0)[0] else None)
if checkout := os.getenv('CHECK_AUTHOR_IN'):
    record['author'] = [subprocess.run(
        ['git', '-C', checkout, 'config', '--local', '--get', key],
        capture_output=True, text=True, check=False).stdout.strip() or None
        for key in ('user.name', 'user.email')]
with (root / 'calls.jsonl').open('a') as f:
    f.write(json.dumps(record) + '\n')
if is_hermes:
    print('Hermes stdout')
    print('Hermes stderr', file=sys.stderr)
else:
    reply = json.loads((root / 'reply.json').read_text())
    print(reply['output'], file=sys.stderr if reply['code'] else sys.stdout)
    sys.exit(reply['code'])
'''


def thread_show(**fields):
    return {'thread': fields, 'messages': []}


def load_launcher():
    spec = importlib.util.spec_from_file_location('session_launcher', LAUNCHER)
    if spec is None or spec.loader is None:
        raise ImportError(str(LAUNCHER))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class LauncherContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not LAUNCHER.is_file():
            raise AssertionError('contract module does not exist: scripts/session_launcher.py')
        cls.launcher = load_launcher()

    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='launcher-test-')
        self.addCleanup(temp.cleanup)
        self.root = pathlib.Path(temp.name)
        self.t3 = self.root / 'custom-t3'
        self.t3.write_text(f'#!{sys.executable}\n{FAKE_SESSION}', encoding='utf-8')
        self.t3.chmod(0o755)
        self.hermes = self.root / 'hermes-stand-in'
        self.hermes.symlink_to(self.t3)
        # Never reach an installed launcher if the command incorrectly falls back to PATH.
        for name in ('t3', 'hermes'):
            fallback = self.root / name
            fallback.write_text('#!/bin/sh\nexit 99\n')
            fallback.chmod(0o755)
        path = mock.patch.dict(os.environ, {'PATH': f'{self.root}{os.pathsep}{os.environ["PATH"]}'})
        path.start()
        self.addCleanup(path.stop)
        self.env = {'PIPELINE_LAUNCHER': 't3', 'T3_BIN': str(self.t3)}
        self.child_env = {**os.environ, 'T3CODE_HOME': str(self.root / 'fake server')}
        self.checkout = self.root / 'project checkout'
        self.checkout.mkdir()
        self.prompt = self.root / 'prompt.md'
        self.prompt.write_text(PROMPT, encoding='utf-8')
        self.log = self.root / 'session.log'
        self.reply({'threadId': 'thread-test'})

    def reply(self, output, code=0):
        if isinstance(output, dict):
            output = json.dumps(output)
        (self.root / 'reply.json').write_text(json.dumps({'output': output, 'code': code}))

    def calls(self):
        path = self.root / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def launch(self, **kwargs):
        opts = {'hermes_argv': [str(self.hermes), 'chat', 'unchanged argument'],
                'prompt_file': self.prompt, 'title': TITLE, 'checkout': self.checkout,
                'log_file': self.log, 'cwd': self.root, 'child_env': self.child_env}
        return self.launcher.launch(kwargs.pop('env', self.env), **{**opts, **kwargs})

    def finish_hermes(self, pid):
        self.assertIs(type(pid), int)
        with contextlib.suppress(ChildProcessError):  # The launcher may already have reaped the fake.
            _, status = os.waitpid(pid, 0)
            self.assertEqual(os.waitstatus_to_exitcode(status), 0)

    def test_kind_defaults_to_hermes_and_accepts_explicit_launchers(self):
        for env, expected in (({}, 'hermes'), ({'PIPELINE_LAUNCHER': 'hermes'}, 'hermes'), (self.env, 't3')):
            with self.subTest(env=env):
                self.assertEqual(self.launcher.kind(env), expected)

    def test_kind_rejects_an_invalid_launcher(self):
        with self.assertRaisesRegex(ValueError, 'PIPELINE_LAUNCHER'):
            self.launcher.kind({'PIPELINE_LAUNCHER': 'invalid'})

    def test_t3_start_protocol_and_log(self):
        for provider, model, flags in (
            ('pi', 'example-model', ['--provider', 'pi', '--model', 'example-model']),
            ('', 'example-model', ['--model', 'example-model']),
            ('pi', '', []),
            ('', '', []),
        ):
            with self.subTest(provider=provider, model=model):
                handle = self.launch(provider=provider, model=model)
                self.assertEqual(handle, 't3:thread-test')
                self.assertEqual(self.calls()[-1], {
                    'argv': ['thread', 'start', '--json', *flags, '--title', TITLE, str(self.checkout), '-'],
                    'stdin': PROMPT, 'server': self.child_env['T3CODE_HOME'],
                })
                self.assertIn('"thread-test"', self.log.read_text(encoding='utf-8'))

    def test_t3_bin_defaults_to_t3_on_path(self):
        fallback = self.root / 't3'
        fallback.unlink()
        fallback.symlink_to(self.t3)
        self.assertEqual(self.launch(env={'PIPELINE_LAUNCHER': 't3'}), 't3:thread-test')

    def test_t3_start_raises_with_output_tail_even_if_failure_has_an_id(self):
        for output, code, tail in (({'threadId': 'unusable', 'error': 'could not start'}, 7, 'could not start'),
                                   ({'message': 'no id returned'}, 0, 'no id returned')):
            with self.subTest(code=code):
                self.reply(output, code)
                with self.assertRaisesRegex(RuntimeError, tail):
                    self.launch()
                self.assertIn(tail, self.log.read_text(encoding='utf-8'))

    def test_hermes_starts_given_argv_in_a_detached_session(self):
        pid = self.launch(env={})
        self.finish_hermes(pid)
        self.assertEqual(self.calls(), [{
            'argv': ['chat', 'unchanged argument'], 'pid': pid, 'sid': pid,
            'cwd': str(self.root), 'stdin': '', 'server': self.child_env['T3CODE_HOME'],
        }])
        log = self.log.read_text(encoding='utf-8')
        self.assertIn('Hermes stdout', log)
        self.assertIn('Hermes stderr', log)

    def test_author_config_is_local_and_visible_at_session_start(self):
        name, email = 'Review Bot', 'review@example.test'
        keys = ('PIPELINE_GIT_NAME', 'PIPELINE_GIT_EMAIL')
        for launcher in ('hermes', 't3'):
            for values in ((name, email), (name, None), (None, email), (None, None)):
                with (self.subTest(launcher=launcher, author=values),
                      tempfile.TemporaryDirectory(dir=self.root) as repo):
                    checkout = pathlib.Path(repo)
                    subprocess.run(['git', 'init', '-q', '--template=', repo], check=True)
                    config = checkout / '.git' / 'config'
                    before = config.read_bytes()
                    env = {**self.env, 'PIPELINE_LAUNCHER': launcher,
                           **{k: v for k, v in zip(keys, values, strict=True) if v is not None}}
                    handle = self.launch(env=env, checkout=checkout,
                                         child_env={**self.child_env, 'CHECK_AUTHOR_IN': repo})
                    if launcher == 'hermes':
                        self.finish_hermes(handle)
                    self.assertEqual(self.calls()[-1]['author'], list(values))
                    if values == (None, None):
                        self.assertEqual(config.read_bytes(), before)

    def test_git_config_failure_prevents_either_session_from_starting(self):
        subprocess.run(['git', 'init', '-q', '--template=', str(self.checkout)], check=True)
        (self.checkout / '.git' / 'config.lock').touch()
        for launcher in ('hermes', 't3'):
            with self.subTest(launcher=launcher):
                try:
                    handle = self.launch(env={**self.env, 'PIPELINE_LAUNCHER': launcher,
                                              'PIPELINE_GIT_NAME': 'Review Bot'})
                except Exception:  # The contract does not prescribe the git failure's exception type.
                    self.assertEqual(self.calls(), [])
                else:
                    if launcher == 'hermes':
                        self.finish_hermes(handle)
                    self.fail('launch succeeded after the local git config write failed')

    def assert_probe(self, env, handle, state, link='', detail: str | None = ''):
        result = self.launcher.probe(env, handle)
        self.assertEqual(result['state'], state)
        self.assertEqual(result['link'], link)
        self.assertIsInstance(result['detail'], str)
        if detail:  # Only check a diagnostic tail when the command produced one.
            self.assertIn(detail, result['detail'])
        elif detail == '':
            self.assertEqual(result['detail'], '')
        self.assertIs(self.launcher.alive(env, handle), state in ('live', 'unknown'))

    def test_t3_status_table_uses_the_handle_not_the_configured_launcher(self):
        rows = [({'status': s}, 'live') for s in ('preparing', 'queued', 'starting', 'running')]
        rows += [({'status': s}, 'dead') for s in
                 ('completed', 'failed', 'interrupted', 'cancelled', 'idle', 'unlisted')]
        rows += [({'status': 'waiting', **fields}, expected) for fields, expected in (
            ({'pendingRequestCount': 1}, 'asked'),
            ({'pendingRequestCount': 1, 'pendingBackgroundTasks': ['task'], 'blockedOnThreadWait': True}, 'asked'),
            ({'pendingBackgroundTasks': ['task']}, 'live'),
            ({'blockedOnThreadWait': True}, 'live'),
            ({'pendingRequestCount': 0, 'pendingBackgroundTasks': [], 'blockedOnThreadWait': False}, 'dead'),
        )]
        env = {**self.env, 'PIPELINE_LAUNCHER': 'hermes'}
        for i, (reply, state) in enumerate(rows):
            with self.subTest(reply=reply):
                self.reply(thread_show(**reply, link=LINK))
                self.assert_probe(env, f't3:table-{i}', state, LINK)
                self.assertEqual(self.calls()[-1]['argv'], ['thread', 'show', '--json', f'table-{i}'])

    def test_t3_probe_failure_table(self):
        for i, (output, code, state, detail) in enumerate((
            ('thread is no longer available', 1, 'dead', ''),
            ('transport failed: connection refused', 1, 'unknown', 'connection refused'),
            ('not JSON', 0, 'unknown', 'not JSON'),
        )):
            with self.subTest(output=output):
                self.reply(output, code)
                self.assert_probe(self.env, f't3:error-{i}', state, detail=detail)

    def test_missing_t3_binary_is_unknown(self):
        env = {**self.env, 'T3_BIN': str(self.root / 'not-installed')}
        self.assert_probe(env, 't3:missing-bin', 'unknown', detail=None)

    def test_t3_timeout_is_unknown(self):
        # Inject the CLI timeout rather than waiting for its (unspecified) duration.
        with mock.patch('subprocess.run', side_effect=subprocess.TimeoutExpired(
                [str(self.t3), 'thread', 'show', '--json', 'timeout'], 1, output=b'last output')):
            self.assert_probe(self.env, 't3:timeout', 'unknown', detail='last output')

    def test_numeric_handles_follow_proc_even_with_t3_configured(self):
        for marker, state in (('hermes-stand-in', 'live'), ('ordinary-process', 'dead')):
            with subprocess.Popen([sys.executable, '-c', 'import sys; sys.stdin.read()', marker],
                                  stdin=subprocess.PIPE) as child:
                for handle in (child.pid, str(child.pid)):
                    with self.subTest(handle=handle, marker=marker):
                        self.assert_probe(self.env, handle, state)
        self.assertEqual(self.calls(), [])

    def test_probe_and_alive_share_one_cli_check_per_handle(self):
        handle = 't3:once-per-process'
        self.reply(thread_show(status='running'))
        self.assert_probe(self.env, handle, 'live')
        self.reply(thread_show(status='completed'))
        self.assert_probe(self.env, handle, 'live')
        self.assertEqual([c['argv'] for c in self.calls()], [['thread', 'show', '--json', 'once-per-process']])

    def probe_in_fresh_process(self, handle, state_dir):
        code = ('import json, runpy, sys; '
                'launcher = runpy.run_path(sys.argv[1])["load_launcher"](); '
                'print(json.dumps(launcher.probe(*json.loads(sys.argv[2]))))')
        result = subprocess.run([sys.executable, '-B', '-c', code, __file__,
                                 json.dumps([self.env, handle, str(state_dir)])],
                                capture_output=True, text=True, check=True, timeout=10)
        return json.loads(result.stdout)['state']

    def test_only_dead_is_remembered_across_processes(self):
        for prior, output, code in (('dead', thread_show(status='completed'), 0),
                                    ('asked', thread_show(status='waiting', pendingRequestCount=1), 0),
                                    ('unknown', 'unreachable', 1)):
            with self.subTest(prior=prior):
                handle = f't3:persist-{prior}'
                state_dir = self.root / prior
                state_dir.mkdir()
                self.reply(output, code)
                self.assertEqual(self.probe_in_fresh_process(handle, state_dir), prior)
                self.reply(thread_show(status='running'))
                self.assertEqual(self.probe_in_fresh_process(handle, state_dir),
                                 'dead' if prior == 'dead' else 'live')
                self.assertEqual(sum(c['argv'] == ['thread', 'show', '--json', f'persist-{prior}']
                                     for c in self.calls()), 1 if prior == 'dead' else 2)

    def test_zero_exit_json_without_thread_is_unknown_and_not_remembered(self):
        state_dir = self.root / 'invalid-reply-state'
        state_dir.mkdir()
        handle = 't3:flat-reply'
        self.reply({'status': 'running'})  # Valid JSON, but not a thread show answer.
        self.assertEqual(self.probe_in_fresh_process(handle, state_dir), 'unknown')
        self.reply(thread_show(status='running'))
        self.assertEqual(self.probe_in_fresh_process(handle, state_dir), 'live')
        self.assertEqual([c['argv'] for c in self.calls()], [['thread', 'show', '--json', 'flat-reply']] * 2)

    def test_rename_step_uses_hermes_only(self):
        args = {'hermes_bin': '/fake/hermes-custom', 'number': 17, 'short_head': 'abc1234'}
        with self.subTest(launcher='hermes'):
            step = self.launcher.rename_step({}, **args)
            self.assertIn('/fake/hermes-custom sessions rename', step)
            self.assertIn('PR #17 review @abc1234', step)
        with self.subTest(launcher='t3'):
            self.assertEqual(self.launcher.rename_step(self.env, **args), '')


if __name__ == '__main__':
    unittest.main()
