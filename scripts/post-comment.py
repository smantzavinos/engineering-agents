#!/usr/bin/env python3
"""Post (or edit) a bot comment on an issue or PR after checking it against the house style.

    post-comment.py --repo OWNER/REPO --number N --body-file FILE [--kind KIND] [--edit COMMENT_ID] [--dry]

- Adds the 🤖 prefix if missing.
- Checks the comment with comment_style.lint (rules: docs/references/comment-style.md).
- Before COMMENT_STYLE_ENFORCE_FROM (YYYY-MM-DD; unset = never): posts anyway and prints the problems
  (warn mode). From that date: refuses to post (exit 2) until the problems are fixed.
- A still-waiting notice must link an existing comment of the same issue (always enforced).
- Every check except --dry is logged to $COMMENT_STYLE_LOG (default $HERMES_HOME/state/style.log).
Prints the comment URL on success. Exit codes: 0 posted, 2 refused by the style check, 1 other error.

Environment: GH_BIN (default gh), COMMENT_STYLE_ENFORCE_FROM, COMMENT_STYLE_LOG, HERMES_HOME.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import comment_style  # noqa: E402

ENV = os.environ


def enforcing(start=None, today=None):
    start = ENV.get("COMMENT_STYLE_ENFORCE_FROM", "") if start is None else start
    if not start:
        return False
    today = today or datetime.date.today()
    return today >= datetime.date.fromisoformat(start)


def log_check(entry):
    default = Path(ENV.get("HERMES_HOME", str(Path.home()))) / "state" / "style.log"
    path = Path(ENV.get("COMMENT_STYLE_LOG", str(default)))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def gh(*args):
    r = subprocess.run([ENV.get("GH_BIN", "gh"), *args], capture_output=True, text=True, encoding="utf-8", timeout=90)
    if r.returncode:
        raise RuntimeError((r.stderr or r.stdout).strip()[:300] or "gh failed")
    try:
        return json.loads(r.stdout) if r.stdout.strip() else {}
    except ValueError as error:
        raise RuntimeError(f"gh returned invalid JSON: {error}") from error


def main(argv=None):
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument("--repo", required=True)
    ap.add_argument("--number", type=int, required=True)
    ap.add_argument("--body-file", required=True)
    ap.add_argument("--kind", choices=sorted(comment_style.BUDGETS))
    ap.add_argument("--edit", type=int, help="edit this existing comment id instead of posting a new one")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args(argv)
    body = Path(a.body_file).read_text(encoding="utf-8").strip()
    if not body.lstrip().startswith("🤖"):
        body = "🤖 " + body
    kind = a.kind or comment_style.infer_kind(body)
    problems = comment_style.lint(body, kind)
    # Hard rule, enforced even in warn mode: a still-waiting notice links an existing comment of this issue, and a
    # notice about answers links the open question comment. Everything else follows enforce/warn.
    hard = comment_style.hard_question_problems(body, kind)
    warnings = []
    if not hard:
        problems += comment_style.question_link_problems(body)
    if not hard and comment_style.is_still_waiting(body, kind):
        wants_question = comment_style.asks_for_answers(body)
        for number, comment_id in comment_style.question_links(body):
            try:
                found = gh("api", f"repos/{a.repo}/issues/comments/{comment_id}")
            except RuntimeError as error:
                if re.search(r"\b404\b|not found", str(error), re.I):
                    hard.append(f"the linked comment {comment_id} does not exist on {a.repo}#{a.number}")
                else:  # transport problem: cannot verify, so do not block a correct notice
                    warnings.append(f"could not verify the linked comment {comment_id} ({str(error)[:80]})")
                continue
            if not ((found or {}).get("issue_url", "").endswith(f"/issues/{number}") and number == a.number):
                hard.append(f"the linked comment {comment_id} does not exist on {a.repo}#{a.number}")
            elif wants_question and not comment_style.is_question_comment((found or {}).get("body")):
                hard.append(f"the linked comment {comment_id} holds no open questions (no triage clarify marker); "
                            "link the question comment, or do not post a notice that waits for answers")
    if hard:
        print("REFUSED (open questions); see the comment-style reference:", file=sys.stderr)
        for p in hard:
            print(f"- {p}", file=sys.stderr)
        return 2
    for w in warnings:
        print(f"WARNING: {w}", file=sys.stderr)
    if not a.edit and comment_style.is_still_waiting(body, kind):
        try:
            pages = gh("api", "--paginate", "--slurp", f"repos/{a.repo}/issues/{a.number}/comments?per_page=100")
            duplicate = comment_style.duplicate_waiting_url(body, [c for page in pages for c in page], a.number)
        except (RuntimeError, ValueError, TypeError, KeyError):
            duplicate = None  # lookup failed: post as before
        if duplicate:
            print(f"skipped duplicate waiting notice: {duplicate} is already the latest comment")
            return 0
    enforce = enforcing()
    if not a.dry:
        log_check({"ts": datetime.datetime.now().isoformat(timespec="seconds"), "repo": a.repo, "number": a.number,
                   "kind": kind, "words": len(comment_style.visible(body).split()), "problems": problems,
                   "mode": "enforce" if enforce else "warn", "source": "helper"})
    if problems:
        print(("REFUSED" if enforce else "STYLE WARNINGS") + f" ({kind}); see the comment-style reference:",
              file=sys.stderr)
        for p in problems:
            print(f"- {p}", file=sys.stderr)
        if enforce:
            return 2
    if a.dry:
        print(f'DRY: would {"edit" if a.edit else "post"} a {kind} comment on {a.repo}#{a.number}')
        return 0
    if a.edit:
        got = gh("api", "-X", "PATCH", f"repos/{a.repo}/issues/comments/{a.edit}", "-f", f"body={body}")
    else:
        got = gh("api", "-X", "POST", f"repos/{a.repo}/issues/{a.number}/comments", "-f", f"body={body}")
    check = gh("api", f"repos/{a.repo}/issues/comments/{got['id']}")
    if check.get("body") != body:
        print("comment read-back failed", file=sys.stderr)
        return 1
    print(got.get("html_url", ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
