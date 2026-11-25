"""Start Hermes or T3 sessions and check their dispatch handles (stdlib only)."""

import contextlib
import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
from collections.abc import Mapping, Sequence
from typing import Literal, TypedDict

Env = Mapping[str, str]
Path = str | os.PathLike[str]
Handle = int | str
State = Literal["live", "dead", "asked", "unknown"]
T3_TIMEOUT = 30


class Probe(TypedDict):
    state: State
    link: str
    detail: str


_probes: dict[str, Probe] = {}  # One observation per handle per tick process.
_dead_markers: set[pathlib.Path] = set()


def kind(env: Env) -> Literal["hermes", "t3"]:
    launcher = env.get("PIPELINE_LAUNCHER", "hermes")
    if launcher not in ("hermes", "t3"):
        raise ValueError(f"PIPELINE_LAUNCHER must be hermes or t3, not {launcher!r}")
    return launcher


def _t3(env: Env, action: str) -> list[str]:
    return [env.get("T3_BIN", "t3"), "thread", action, "--json"]


def _json_object(text: str) -> dict:
    try:
        value = json.loads(text)
    except ValueError:
        return {}
    return value if isinstance(value, dict) else {}


def _tail(output: str) -> str:
    return output.strip()[-600:]


def _timeout_output(exc: subprocess.TimeoutExpired) -> str:
    return "\n".join(part.decode("utf-8", errors="replace") if isinstance(part, bytes) else part
                     for part in (exc.stdout, exc.stderr) if part)


def check(env: Env, checkout: Path) -> None:
    """Check that T3 can reach the project before the tick changes anything there."""
    if kind(env) == "hermes":
        return
    try:
        result = subprocess.run(_t3(env, "list") + ["--project", os.fspath(checkout)], stdin=subprocess.DEVNULL,
                                capture_output=True, encoding="utf-8", errors="replace",
                                timeout=T3_TIMEOUT, env={**os.environ, **env})
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"T3 readiness check timed out: {_tail(_timeout_output(e)) or e}") from e
    except OSError as e:
        raise RuntimeError(f"T3 readiness check failed: {e}") from e
    if result.returncode:
        detail = _tail(result.stdout + result.stderr) or f"exit {result.returncode}"
        raise RuntimeError(f"T3 readiness check failed: {detail}")


def launch(env: Env, *, hermes_argv: Sequence[str], prompt_file: Path, title: str,
           checkout: Path, log_file: Path, cwd: Path | None = None, model: str = "",
           provider: str = "", child_env: Env | None = None) -> Handle:
    launcher = kind(env)
    for setting, key in (("PIPELINE_GIT_NAME", "user.name"), ("PIPELINE_GIT_EMAIL", "user.email")):
        if env.get(setting):  # an empty value counts as unset
            subprocess.run(["git", "-C", os.fspath(checkout), "config", "--local", "--", key, env[setting]],
                           check=True, env=child_env)
    # Log open failures propagate so the dispatcher can record a failed spawn.
    log_path = pathlib.Path(log_file)
    if launcher == "hermes":
        with log_path.open("w") as log:
            p = subprocess.Popen(hermes_argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=log,
                                 stderr=subprocess.STDOUT, env=child_env, start_new_session=True, close_fds=True)
        return p.pid

    argv = _t3(env, "start")
    if model:
        if provider:
            argv += ["--provider", provider]
        argv += ["--model", model]
    argv += ["--title", title, os.fspath(checkout), "-"]
    with log_path.open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(argv, input=pathlib.Path(prompt_file).read_text(encoding="utf-8"),
                                    capture_output=True, encoding="utf-8", errors="replace",
                                    timeout=T3_TIMEOUT, env=child_env)
        except subprocess.TimeoutExpired as e:
            output = _timeout_output(e)
            log.write(output)
            raise RuntimeError(f"T3 thread start timed out: {_tail(output) or e}") from e
        output = result.stdout + result.stderr
        log.write(output)
    if result.returncode == 0:
        # The response is the final JSON object; stdout may start with notices.
        lines = result.stdout.splitlines()
        for i in range(len(lines) - 1, -1, -1):
            if lines[i].lstrip().startswith("{"):
                thread_id = _json_object("\n".join(lines[i:])).get("threadId")
                if isinstance(thread_id, str) and thread_id.strip():
                    return "t3:" + thread_id
    raise RuntimeError(f"T3 thread start failed: {_tail(output) or f'exit {result.returncode}, no threadId'}")


def _probe_t3(env: Env, thread_id: str) -> Probe:
    try:
        result = subprocess.run(_t3(env, "show") + [thread_id], stdin=subprocess.DEVNULL,
                                capture_output=True, encoding="utf-8", errors="replace",
                                timeout=T3_TIMEOUT, env={**os.environ, **env})
    except subprocess.TimeoutExpired as e:
        return Probe(state="unknown", link="", detail=_tail(_timeout_output(e)) or str(e))
    except OSError as e:
        return Probe(state="unknown", link="", detail=str(e))
    fields = _json_object(result.stdout).get("thread")
    thread = fields if isinstance(fields, dict) else {}
    status = thread.get("status")
    link = thread.get("link")
    output = result.stdout + result.stderr
    reply = Probe(state="dead", link=link if isinstance(link, str) else "", detail="")
    if result.returncode and "no longer available" in output.lower():
        return reply
    if result.returncode or not isinstance(status, str) or not status:
        return Probe(state="unknown", link=reply["link"], detail=_tail(output) or f"exit {result.returncode}, no thread status")
    active = status in ("preparing", "queued", "starting", "running")
    count = thread.get("pendingRequestCount")
    if (active or status == "waiting") and isinstance(count, int) and count > 0:
        reply["state"] = "asked"
    elif active or (status == "waiting" and (thread.get("pendingBackgroundTasks")
                                            or thread.get("blockedOnThreadWait") is True)):
        reply["state"] = "live"
    return reply


def _remember_dead(path: pathlib.Path, handle: str) -> None:
    # One atomic marker per thread avoids dropping entries if two ticks write at once.
    tmp = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as f:
            tmp = pathlib.Path(f.name)
            f.write(handle)
        tmp.replace(path)
    except OSError:
        pass  # The cache is optional; the next tick can ask the server again.
    finally:
        if tmp is not None:
            with contextlib.suppress(OSError):
                tmp.unlink(missing_ok=True)


def probe(env: Env, handle: Handle, state_dir: Path | None = None) -> Probe:
    key = str(handle)
    # Persist only durable thread IDs: an OS PID can be reused by a later Hermes launch.
    marker = None
    if key.startswith("t3:") and state_dir is not None:
        digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
        marker = pathlib.Path(state_dir) / "dead-t3-threads" / digest
    if key not in _probes:
        if marker is not None:
            with contextlib.suppress(OSError, ValueError):
                if marker.read_text(encoding="utf-8") == key:
                    _dead_markers.add(marker)
                    _probes[key] = Probe(state="dead", link="", detail="")
                    return _probes[key]
        if key.startswith("t3:"):
            _probes[key] = _probe_t3(env, key[3:])
        else:
            running = False
            if key.isascii() and key.isdigit():
                with contextlib.suppress(OSError):
                    running = b"hermes" in pathlib.Path(f"/proc/{key}/cmdline").read_bytes()
            _probes[key] = Probe(state="live" if running else "dead", link="", detail="")
    reply = _probes[key]
    if marker is not None and reply["state"] == "dead" and marker not in _dead_markers:
        _remember_dead(marker, key)
        _dead_markers.add(marker)
    return reply


def alive(env: Env, handle: Handle, state_dir: Path | None = None) -> bool:
    return probe(env, handle, state_dir)["state"] in ("live", "unknown")


def rename_step(env: Env, *, hermes_bin: str, number: int, short_head: str) -> str:
    if kind(env) == "t3":
        return ""
    name = f"PR #{number} review @{short_head}"
    return (f"Last step: run `{hermes_bin} sessions list --source pr-automation --limit 20`, "
            f"find the session titled `{name} …`, and rename it with "
            f'`{hermes_bin} sessions rename <id> "{name} — <VERDICT>"`.')
