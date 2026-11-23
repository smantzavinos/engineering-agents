"""Shared tick helpers for the dispatchers and board sync (stdlib only).

Ported from gm-agent-pipeline `pipeline/runtime.py` (Daniel Gehriger); generic subset:

- fresh_lines   drop output lines already sent within a TTL (a failing repo or step repeats every tick; the cron
                output is what the owner reads, so it says each thing once per TTL).
- job_down/up   a job whose every tick fails says so plainly: one alert, repeated at most hourly, then one
                recovery line when it runs again.
- quiet_now     quiet hours: no new bot sessions at night or on weekends (PIPELINE_QUIET_*).
- live_authors  author sessions (work sessions and fix-bot rounds) that are running now, from both dispatchers'
                dispatch records, so both share one PIPELINE_WIP limit.

Install: copy beside pipeline-dispatch.py, pr-sweep-dispatch.py and board-sync.py.
"""
import datetime
import hashlib
import json
import os
import pathlib
import time

DEDUPE_TTL = 6 * 3600
STOP_ALERT_EVERY = 3600
DEFAULT_QUIET_MODES = ('work', 'pr')


def _write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data), encoding='utf-8')
    os.replace(tmp, path)


def _read(path, default):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return default


def fresh_lines(state_dir, key, lines, ttl=DEDUPE_TTL, now=None):
    """The lines not already sent within `ttl` (blank lines dropped); records them as sent."""
    now = time.time() if now is None else now
    path = pathlib.Path(state_dir) / f'notify-dedupe-{key}.json'
    seen = _read(path, {})
    seen = {k: t for k, t in (seen.items() if isinstance(seen, dict) else ()) if now - t < ttl}
    fresh = []
    for line in lines:
        if not line.strip():
            continue
        digest = hashlib.sha256(line.strip().encode('utf-8')).hexdigest()
        if digest not in seen:
            seen[digest] = now
            fresh.append(line.rstrip())
    _write(path, seen)
    return fresh


def duration(seconds):
    minutes = int(seconds // 60)
    if minutes < 60:
        return f'{minutes} min'
    return f'{minutes // 60} h' + (f' {minutes % 60} min' if minutes % 60 else '')


def _since(stamp):
    return datetime.datetime.fromtimestamp(stamp).strftime('%a %H:%M')


def stopped(state_dir):
    """The stopped record ({since, reason, last_alert}) while every tick of this job fails, else None."""
    record = _read(pathlib.Path(state_dir) / 'stopped.json', None)
    return record if isinstance(record, dict) else None


def job_down(state_dir, job, reason, now=None):
    """Record a stopped job; return the alert lines that are due (first failure, then at most hourly)."""
    now = time.time() if now is None else now
    record = stopped(state_dir) or {'since': now, 'last_alert': 0}
    record['reason'] = reason
    due = now - record.get('last_alert', 0) >= STOP_ALERT_EVERY
    if due:
        record['last_alert'] = now
    _write(pathlib.Path(state_dir) / 'stopped.json', record)
    if not due:
        return []
    held = now - record['since']
    return [f"🛑 **{job} stopped since {_since(record['since'])}" + (f' ({duration(held)})' if held >= 60 else '')
            + f'**: {reason}. Nothing this job does happens until this is fixed.']


def job_up(state_dir, job, now=None):
    """Clear a stopped record; return the one recovery line (none when the job was not stopped)."""
    now = time.time() if now is None else now
    record = stopped(state_dir)
    if not record:
        return []
    try:
        (pathlib.Path(state_dir) / 'stopped.json').unlink()
    except OSError:
        return []
    return [f"✅ **{job} runs again** after {duration(now - record['since'])} stopped "
            f"(since {_since(record['since'])})."]


def _minutes(text):
    hours, minutes = text.strip().split(':')
    value = int(hours) * 60 + int(minutes)
    if not 0 <= value < 24 * 60:
        raise ValueError(text)
    return value


def quiet_now(env, mode, now=None):
    """True when `mode` ('triage' | 'work' | 'pr' | ...) must start no new sessions now (local time).

    PIPELINE_QUIET_HOURS  "22:00-07:00" (may wrap midnight); PIPELINE_QUIET_WEEKENDS=1 adds Saturday and Sunday;
    PIPELINE_QUIET_MODES  the jobs it applies to (default "work pr"); PIPELINE_FORCE=1 overrides for one run.
    A malformed PIPELINE_QUIET_HOURS raises ValueError (the tick reports it rather than running at night)."""
    hours = (env.get('PIPELINE_QUIET_HOURS') or '').strip()
    weekends = (env.get('PIPELINE_QUIET_WEEKENDS') or '').strip().lower() in ('1', 'true', 'yes')
    modes = (env.get('PIPELINE_QUIET_MODES') or '').replace(',', ' ').split() or DEFAULT_QUIET_MODES
    if (not hours and not weekends) or mode not in modes or (env.get('PIPELINE_FORCE') or '') == '1':
        return False
    now = now or datetime.datetime.now()
    if weekends and now.weekday() >= 5:
        return True
    if not hours:
        return False
    try:
        start, end = (_minutes(part) for part in hours.split('-'))
    except ValueError as exc:
        raise ValueError(f'PIPELINE_QUIET_HOURS must look like 22:00-07:00, not {hours!r}') from exc
    t = now.hour * 60 + now.minute
    return (start <= t < end) if start < end else (t >= start or t < end)


def live_authors(state_dirs, alive):
    """{pid: 'coding' | 'maintenance'} for author sessions running now, from the dispatch records in
    `state_dirs` (dispatches.jsonl). coding = a new item started from Up next (kind work, reason start);
    maintenance = every other work session (resume after a reply, unblock, retry) and fix-bot rounds (babysit)."""
    live = {}
    for state_dir in state_dirs:
        path = pathlib.Path(state_dir) / 'dispatches.jsonl'
        try:
            text = path.read_text(encoding='utf-8')
        except OSError:
            continue
        for line in text.splitlines():
            try:
                rec = json.loads(line) if line.strip() else None
            except ValueError:
                rec = None
            if not isinstance(rec, dict) or rec.get('kind') not in ('work', 'babysit') or not rec.get('pid'):
                continue
            if alive(rec['pid']):
                live.setdefault(int(rec['pid']), 'coding' if rec['kind'] == 'work' and rec.get('reason') == 'start'
                                else 'maintenance')
    return live
