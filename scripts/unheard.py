#!/usr/bin/env python3
"""Reply to people whose comments no bot will act on. Script-only cron entry, no LLM.

    unheard.py [--dry] [--only issues|prs]

Ported from gm-agent-pipeline `pipeline/unheard.py` (Daniel Gehriger); generic subset.

Every comment a bot acts on gets an eyes reaction. A comment no bot will ever read or act on (a request on a
card no bot reads, a command in the wrong place or with a mistyped handle, a request from someone the bots do
not take instructions from) would otherwise sit there in silence. This script finds those comments and posts
one plain-language reply per batch that says why nothing will happen and what to do instead. It never acts on
the request itself.

It also keeps bot comments honest: an automation comment a bot login posted without the leading 🤖 gets it added
(a session forgot it; on a shared account the comment would otherwise read as the owner's), and house-style
problems of bot comments are logged to $BOARD_SYNC_STATE/style.log (never edited).

Configuration and board access come from gh-project.py beside it (owners are required). State:
$BOARD_SYNC_STATE/unheard.json. Cheap: an issue or PR is re-read only when its updatedAt changed (or a comment
on it is still inside the grace period). stdout carries only failures (everything with --dry); replies go to
GitHub and routine lines to $BOARD_SYNC_STATE/unheard.log.

Install: copy beside gh-project.py and commands.py, then
  hermes cron create "every 5m" --no-agent --script unheard.py --name unheard
Without Hermes: docs/t3/README.md (systemd timers, PIPELINE_LAUNCHER=t3).
"""
import datetime
import difflib
import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import commands  # noqa: E402  (scripts/commands.py)
import pipeline_runtime  # noqa: E402  (stopped alerts and repeat filter: scripts/pipeline_runtime.py)


def load_gp():
    spec = importlib.util.spec_from_file_location('gh_project', HERE / 'gh-project.py')
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load {HERE / "gh-project.py"}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gp = load_gp()

GRACE_SECONDS = 5 * 60          # give the tick that would act on a comment time to react first
FIRST_RUN_LOOKBACK = 3 * 3600   # on the very first run, look this far back (never older history)
MAX_REPLIES = 10                # replies per run
MARKER = '<!-- unheard comment={ids} -->'
MARKER_RE = re.compile(r'<!--\s*unheard comment=([\d,]+)\s*-->')
BOT_PREFIX = '🤖 '
# Automation comments that do not read the thread: a human comment after them is still pending.
NON_READING = re.compile(r'<!--\s*(pr-link|jira-link|sync closed|unheard)\b')
ISSUE_VERBS = ('approve', 'revise', 'discuss', 'reject', 'unblock', 'answer', 'close', 'keep')
GATE_VERBS = ('approve', 'revise', 'discuss', 'reject')
PR_VERBS = ('review', 'fix', 'babysit')
NEW_ITEM = re.compile(r'\b(create|open|file|add|raise|make)\b[^.\n]{0,40}\b(issue|item|bug|ticket|card)\b', re.I)
NEW_ITEM_TIP = ('To report a separate problem, open a new issue yourself and add it to the board; triage picks '
                'it up within a few minutes.')
PR_PEOPLE = ('query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){'
             'assignees(first:20){nodes{login}} closingIssuesReferences(first:10){nodes{repository{nameWithOwner} '
             'assignees(first:10){nodes{login}}}}}}}')


# ---------------------------------------------------------------- pure helpers (unit tested)

def ts(value):
    return datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


def login(c):
    return ((c.get('user') or {}).get('login') or '').lower()


def is_bot_account(c):
    u = c.get('user') or {}
    return u.get('type') == 'Bot' or (u.get('login') or '').endswith('[bot]')


def is_automation(c):
    return bool(gp.AGENT_MARK.search(c.get('body') or ''))


def first_line(body):
    return next((ln.strip() for ln in (body or '').splitlines() if ln.strip()), '')


def near_miss(body, handles):
    """The mistyped handle (sigil included) in the comment, or None: an '@' name anywhere in the text, or a '/'
    word at the start of the first line, that is close to a configured handle of the same sigil but not one."""
    def close(token):
        low = token.lower()
        return low not in handles and any(
            h[0] == low[0] and difflib.SequenceMatcher(None, low[1:], h[1:]).ratio() >= 0.75 for h in handles)
    for m in re.finditer(r'(?<![\w/])@[\w-]+', body or ''):
        if close(m.group(0)):
            return m.group(0)
    s = re.match(r'/[\w-]+', first_line(body))
    if s and close(s.group(0)):
        return s.group(0)
    return None


def command_of(body, handles, verbs):
    """(token, verb, well_formed) for the first line, or None when it does not address a bot."""
    found = commands.split(body, handles)  # any accepted spelling of a configured handle
    if found:
        token, word, _ = found
        verb = commands.canonical(word)
        word = verb if verb in commands.VERBS else word
        return token, word, word in verbs
    m = re.match(r'^([/@][\w-]+)(:?)\s+([\w-]+:?)', first_line(body))
    if not m:
        return None
    token, colon, word = m.group(1).lower(), m.group(2), m.group(3).lower().rstrip(':')
    if token not in handles and not near_miss(first_line(body), handles):
        return None
    return token, word, token in handles and not colon and word in verbs


def mentions_bot(body, handles):
    low = (body or '').lower()
    named = any(re.search(r'(?<![\w/])' + re.escape(h) + r'(?![\w-])', low) for h in handles)
    return named or commands.split(body, handles) is not None or near_miss(body, handles) is not None


def pending(comments, now, logins, grace=GRACE_SECONDS, since=0.0):
    """Human comments posted after the last thread-reading bot comment, past the grace period, without an eyes
    reaction and not yet answered by this script."""
    answered = {int(i) for c in comments for m in [MARKER_RE.search(c.get('body') or '')] if m
                for i in m.group(1).split(',')}
    last_bot = 0.0
    for c in comments:
        if login(c) in logins and is_automation(c) and not NON_READING.search(c.get('body') or ''):
            last_bot = max(last_bot, ts(c['created_at']))
    out = []
    for c in comments:
        created = ts(c['created_at'])
        # A bot login's automation is the bot's; anyone else's comment is skipped only when it reads as a bot's at
        # first sight (a claim line further down is still a person talking, and may need an answer).
        bots = is_automation(c) if login(c) in logins else commands.automation_start(c.get('body'))
        if (created <= last_bot or created < since or now - created < grace or c['id'] in answered
                or is_bot_account(c) or bots or ((c.get('reactions') or {}).get('eyes') or 0) > 0):
            continue
        out.append(c)
    return out


LIVE_PROPOSAL = re.compile(r'<!--\s*close-proposal\b(?!\s+dismissed)')
LAST_MARKER = re.compile(r'<!--\s*(gate|triage|close-proposal|sync)')


def live_close_proposal(comments, logins):
    """True when the newest bot marker comment is a close proposal that is not dismissed."""
    last = None
    for c in comments:
        if login(c) in logins and LAST_MARKER.search(c.get('body') or ''):
            last = c
    return bool(last and LIVE_PROPOSAL.search(last['body']))


def names(logins):
    return ', '.join(f'@{p}' for p in logins) or 'nobody'


def issue_reason(c, item, owners, listened, handles, labels=(), kind=None, proposal=False):
    """(why, what_to_do) for an issue comment no bot will act on, or None when a bot will handle it.

    `item` is the board card (internal status, open PRs); `kind` is what a card in Your turn waits for
    ('answer' | 'approve' | 'unblock' | None, gh-project.py wait_kind): triage reads `answer`, the work dispatcher
    the other kinds. Gate replies (approve, revise, discuss, reject) count from owners only."""
    status, prs, h = item['status'], item.get('prs') or [], handles[0]
    board = lambda s: gp.board_value('Status', s)  # noqa: E731
    who = login(c)
    cmd = command_of(c.get('body'), handles, ISSUE_VERBS)
    addressed = cmd is not None or mentions_bot(c.get('body'), handles)
    close_verbs = ('close', 'keep') if status == 'Your turn' else ('close', 'keep', 'approve', 'reject')
    if who in listened and cmd and cmd[2] and cmd[1] in close_verbs and (proposal or gp.PROPOSE_LABEL in labels):
        return None  # board sync acts on replies to its close proposal
    if who not in listened:
        if not addressed:
            return None  # people talking to each other
        return (f'I only take instructions on this item from the owners ({names(owners)}), its assignees and '
                "the board's listed responders.", 'Ask one of them to make the request here.')
    if status == 'Inbox':
        return None  # triage reads the whole thread of an untriaged card
    if status == 'Your turn' and kind == 'answer':
        if cmd and cmd[2] and cmd[1] == 'answer':
            return None  # triage acts on it
        if proposal:
            return (f'This item has a close proposal open. It is answered with `{h} close` or `{h} keep`; triage '
                    f'reads only `{h} answer:`.',
                    f'Reply `{h} close` or `{h} keep` to the proposal, or `{h} answer: <your answers>` for triage.')
        return (f'Triage only reads answers that start with `{h} answer:`.',
                f'Post your answers again with `{h} answer: <answers by number>` on the first line, or '
                f'`{h} answer: approve` to accept every recommendation.')
    if status == 'Your turn' and kind == 'approve' and cmd and cmd[2] and cmd[1] in GATE_VERBS and who not in owners:
        return (f'Only the owners ({names(owners)}) can approve, revise, discuss or reject an approval request.',
                'Ask an owner to reply, or leave your view here for them to read.')
    if status == 'Your turn' and kind in ('approve', 'unblock'):
        return None  # the work dispatcher acts on the reply, or posts its own "can't read your reply" notice
    wrong = (f'`{h} {cmd[1]}` only works while the card is in {board("Your turn")}; this card is in '
             f'{board(status)}. ') if cmd and cmd[2] else ''
    if status == 'In progress':
        return (wrong + 'A bot is in the middle of a step on this item. It does not read new comments until that '
                'step ends at its next approval request.',
                f'You can change the work at its next approval request ({board("Your turn")}) with `{h} revise: ...`.')
    if status in ('Ready', 'Up next'):
        return (wrong + f'No bot reads comments on cards in {board(status)}. A later design step sees them only '
                'as background; it does not carry out requests in them.',
                f'To change what triage agreed, move the card back to {board("Inbox")}; triage re-reads the thread '
                'within a few minutes.')
    if status == 'In review' or (status == 'Your turn' and prs):
        where = ', '.join(f'#{p}' for p in prs) or 'its pull request'
        return (wrong + f'Work on this item continues on {where}, so comments here are not read.',
                f'Comment on the pull request instead: start a comment there with `{h} fix` and your instructions '
                f'below it to have the fix bot change code, or `{h} review` to re-run the review.')
    if status == 'Backlog':
        return (wrong + f'This card is in {board("Backlog")}; no bot reads or acts on it.',
                f'Move it to {board("Inbox")} to have it triaged.')
    if status == gp.PARKED_STATUS:
        return (wrong + f'This card is parked in {board(gp.PARKED_STATUS)}; bots leave it alone.',
                f'Move it to {board("Inbox")} to have it triaged again.')
    if status in ('Done', 'Canceled'):
        if not addressed:
            return None  # remarks and closing notes on finished items are not requests
        return (wrong + 'This item is finished, so comments here are not read.',
                'Open a new issue for anything still needed.')
    return (wrong + f'No bot reads comments on cards in {board(status)}.',
            f'Move the card to {board("Inbox")} to have it triaged again.')


def pr_reason(c, label, owners, handles, allowed, fork=False):
    """(why, what_to_do or None) for a PR conversation comment no bot will act on, or None.

    `allowed`: everyone who may command the bots on this PR (owners, responders, the PR's assignees and the
    assignees of the issues it closes); pr-sweep-dispatch.py applies the same rule. No bot acts on a PR from a
    fork (`fork`), whoever asks."""
    who = login(c)
    cmd = command_of(c.get('body'), handles, PR_VERBS)
    addressed = cmd is not None or mentions_bot(c.get('body'), handles)
    if fork:
        if not addressed:
            return None
        return ('This pull request comes from a fork. The bots never check out, run or push to a fork\'s branch.',
                'A person reviews it; to have the bots work on it, push the branch to this repository and open the '
                'pull request from there.')
    if who not in allowed:
        if not addressed:
            return None  # reviewers talking to each other
        others = sorted(set(allowed) - set(owners))
        return (f'I only take instructions on this pull request from the owners ({names(owners)})'
                + (f' and the people working on it ({names(others)})' if others else '') + '.',
                'Ask one of them to post the command, or ask to be assigned.')
    if addressed and (commands.automation_start if who in owners else commands.looks_automated)(c.get('body')):
        return ('This comment contains text only the bots may write (`<!--`, `-->`, a 🤖 first line, a claim or '
                'verdict line), so no bot reads it.', 'Post the command again without that text.')
    if cmd and cmd[2]:
        return None  # the PR sweep acts on it (possibly after waiting for a free bot)
    if addressed:
        return 'This comment addresses a bot, but not in a form any bot reads.', None
    if not (label or '').startswith('needs-human:'):
        return None  # no bot owns this PR's next step, or the next fix round reads owner comments
    return ('No bot reads plain comments on this pull request while it waits for a person.',
            f'To have the fix bot act on it, put `{handles[0]} fix` on the first line and your instructions below it.')


def syntax_hint(comments, handles, verbs, place):
    """One sentence naming the exact mistake in a comment that tries to address a bot, or None."""
    h = handles[0]
    listing = ', '.join(f'`{h} {v}`' for v in verbs)
    for c in comments:
        body = c.get('body') or ''
        m = re.match(r'^([/@][\w-]+)(:?)\s+([\w-]+)', first_line(body))
        near = near_miss(body, handles)
        if near:
            return f'`{near}` is not a name any bot answers to; the bots answer to `{h}`.'
        if m and m.group(1).lower() in handles:
            if m.group(2):
                return f'Leave out the colon after the name: `{h} {m.group(3).lower()}`, not `{h}: {m.group(3).lower()}`.'
            if m.group(3).lower() not in verbs:
                return f'`{m.group(3)}` is not a command {place}. Commands {place}: {listing}.'
        elif mentions_bot(body, handles) and not m:
            return f'A command has to be the first line of the comment, for example `{h} {verbs[0]}`.'
    return None


def compose(comments, why, todo, hint, new_item_tip):
    links = ', '.join(f'[this comment]({c.get("html_url", "")})' if len(comments) == 1 else
                      f'[comment by @{login(c)}]({c.get("html_url", "")})' for c in comments)
    people = ' '.join(dict.fromkeys(f'@{(c.get("user") or {}).get("login")}' for c in comments))
    lines = [f'{BOT_PREFIX}**Still waiting: no bot will act on {links}.** {people}: {why}']
    tips = [t for t in (hint, todo, new_item_tip) if t]
    if tips:
        lines += [''] + [f'- {t}' for t in tips]
    lines += ['', MARKER.format(ids=','.join(str(c['id']) for c in comments))]
    return '\n'.join(lines)


# ---------------------------------------------------------------- GitHub plumbing

class Run:
    def __init__(self, config, dry=False, now=None):
        self.config, self.dry, self.now = config, dry, now or time.time()
        self.repo = config['repo']
        self.owners = tuple(config['owners'])
        self.handles = tuple(config['handles'])
        self.logins = gp.bot_logins(config)
        self.state_dir = pathlib.Path(config['state_dir'])
        self.path = self.state_dir / 'unheard.json'
        try:
            self.state = json.loads(self.path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            self.state = {}
        self.state.setdefault('since', self.now - FIRST_RUN_LOOKBACK)
        self.replies = 0
        self.failures = []
        self._me = None

    def guarded(self, number, fn):
        """One item failing (a read, a post) is logged and reported; the other items still run. The failed item
        is not marked as read, so the next run tries it again."""
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 — malformed API data (TypeError, ...) must not starve the rest
            self.failures.append(f'[{self.repo}] unheard #{number} FAILED: {exc}')
            self.log(self.failures[-1])

    def gh(self, *args):
        return gp.gh(self.config, *args)

    def log(self, text):
        text = f'[{self.repo}] {text}' + (' (DRY)' if self.dry else '')
        if self.dry:
            print(text, flush=True)
            return
        self.state_dir.mkdir(parents=True, exist_ok=True)
        with (self.state_dir / 'unheard.log').open('a', encoding='utf-8') as handle:
            handle.write(time.strftime('%Y-%m-%dT%H:%M:%S ') + text + '\n')

    def save(self):
        if self.dry:
            return
        self.state_dir.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix('.tmp')
        tmp.write_text(json.dumps(self.state, indent=1, sort_keys=True), encoding='utf-8')
        tmp.replace(self.path)

    def me(self):
        """The login this script posts as (resolved once; '' when it cannot be read)."""
        if self._me is None:
            try:
                self._me = ((self.gh('api', 'user') or {}).get('login') or '').lower()
            except (RuntimeError, ValueError, OSError, subprocess.SubprocessError):
                self._me = ''
        return self._me

    def mark_bot_comments(self, number, comments):
        """Add the bot emoji to automation comments this login posted without it (a session forgot). Comments of
        other bot logins are left alone (this token cannot edit them); a failed edit is logged, never fatal."""
        for c in comments:
            body = c.get('body') or ''
            if (not self.me() or login(c) != self.me() or not is_automation(c) or body.lstrip().startswith('🤖')
                    or ts(c['created_at']) < self.state['since']):
                continue
            if self.dry:
                self.log(f'would add the bot emoji to comment {c["id"]} on #{number}')
                continue
            new = BOT_PREFIX + body
            try:
                got = self.gh('api', '-X', 'PATCH', f'repos/{self.repo}/issues/comments/{c["id"]}', '-f', f'body={new}')
            except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as exc:
                self.log(f'could not add the bot emoji to comment {c["id"]} on #{number}: {exc}')
                continue
            if (got or {}).get('body') != new:
                self.log(f'bot emoji read-back failed for comment {c["id"]} on #{number}')
                continue
            c['body'] = new
            self.log(f'added the bot emoji to comment {c["id"]} on #{number}')

    def audit_style(self, number, comments):
        """Log house-style problems of bot comments (catches sessions that skipped post-comment.py). Never edits."""
        import comment_style
        seen = self.state.setdefault('style_checked', [])
        for c in comments:
            if (login(c) not in self.logins or not is_automation(c) or c['id'] in seen
                    or ts(c['created_at']) < self.state['since']):
                continue
            problems = comment_style.lint(c.get('body') or '')
            seen.append(c['id'])
            if problems and not self.dry:
                self.state_dir.mkdir(parents=True, exist_ok=True)
                with (self.state_dir / 'style.log').open('a', encoding='utf-8') as handle:
                    handle.write(json.dumps({'ts': c['created_at'], 'number': number, 'comment': c['id'],
                                             'kind': comment_style.infer_kind(c.get('body') or ''),
                                             'problems': problems, 'source': 'audit'}, ensure_ascii=False) + '\n')
        del seen[:-2000]

    def post(self, number, body):
        self.replies += 1
        if self.dry:
            self.log(f'would reply on #{number}: {body.splitlines()[0][:160]}')
            return
        posted = gp.post_comment(self.config, number, body)
        self.log(f'replied on #{number} (comment {(posted or {}).get("id")})')

    def changed(self, kind, number, updated):
        """True when the item changed since the last read, or a comment on it was still inside the grace period."""
        return (self.state.setdefault(kind, {}).get(str(number)) != updated
                or str(number) in self.state.get(kind + '_waiting', {}))

    def seen(self, kind, number, updated, comments):
        young = [c for c in pending(comments, self.now, self.logins, grace=0, since=self.state['since'])
                 if self.now - ts(c['created_at']) < GRACE_SECONDS]
        waiting = self.state.setdefault(kind + '_waiting', {})
        if young:
            waiting[str(number)] = True
        else:
            waiting.pop(str(number), None)
        self.state[kind][str(number)] = updated

    def issues(self):
        issues, _, _ = gp.snapshot(self.config)
        for item in issues:
            if self.replies >= MAX_REPLIES:
                return  # not marked as read: the next run picks the rest up
            n, updated = item['number'], item.get('updatedAt') or ''
            if self.changed('issues', n, updated):
                self.guarded(n, lambda item=item, n=n, updated=updated: self.issue_item(item, n, updated))

    def issue_item(self, item, n, updated):
        issue = gp.issue_of(self.config, n)
        assignees = {((a or {}).get('login') or '').lower() for a in issue.get('assignees') or []}
        labels = [(lbl or {}).get('name') for lbl in issue.get('labels') or []]
        listened = set(gp.responders(self.config, issue)) | assignees
        comments = gp.comments_of(self.config, n)
        self.mark_bot_comments(n, comments)
        self.audit_style(n, comments)
        kind = gp.wait_kind(comments, (), self.logins)[0] if item['status'] == 'Your turn' else None
        proposal = live_close_proposal(comments, self.logins)
        groups = {}
        for c in pending(comments, self.now, self.logins, since=self.state['since']):
            r = issue_reason(c, item, self.owners, listened, self.handles, labels, kind, proposal)
            if r:
                groups.setdefault(r, []).append(c)
        for (why, todo), cs in groups.items():
            tip = NEW_ITEM_TIP if any(NEW_ITEM.search(c.get('body') or '') for c in cs) else None
            hint = syntax_hint(cs, self.handles, ISSUE_VERBS, 'on an issue')
            self.post(n, compose(cs, why, todo, hint, tip))
        self.seen('issues', n, updated, comments)  # after the replies: a failed post is retried next run

    def pr_people(self, number):
        """Owners, responders, the PR's assignees and the assignees of the issues it closes (lower case)."""
        found = set(self.owners) | set(self.config.get('responders') or ())
        owner, name = self.repo.split('/')
        try:
            pull = gp.graphql(self.config, PR_PEOPLE, o=owner, r=name, p=number)['repository']['pullRequest'] or {}
        except (RuntimeError, ValueError, KeyError, TypeError):
            return found
        nodes = list((pull.get('assignees') or {}).get('nodes') or [])
        for issue in (pull.get('closingIssuesReferences') or {}).get('nodes') or []:
            # Only issues of this repository: "Closes someone/else#1" must not make its assignees people of the PR.
            if ((issue.get('repository') or {}).get('nameWithOwner') or '').lower() == self.repo.lower():
                nodes += (issue.get('assignees') or {}).get('nodes') or []
        return found | {(a.get('login') or '').lower() for a in nodes if a and a.get('login')}

    def prs(self):
        pulls = self.gh('pr', 'list', '-R', self.repo, '--state', 'open', '--limit', '100',
                        '--json', 'number,labels,updatedAt,isCrossRepository') or []
        for pr in pulls:
            if self.replies >= MAX_REPLIES:
                return
            n, updated = pr['number'], pr.get('updatedAt') or ''
            if self.changed('prs', n, updated):
                self.guarded(n, lambda pr=pr, n=n, updated=updated: self.pr_item(pr, n, updated))

    def pr_item(self, pr, n, updated):
        labels = [(lbl or {}).get('name') or '' for lbl in pr.get('labels') or []]
        label = next((x for x in labels if x.startswith(('review-bot:', 'fix-bot:queued', 'needs-human:'))), None)
        comments = gp.comments_of(self.config, n)
        self.mark_bot_comments(n, comments)
        self.audit_style(n, comments)
        due = pending(comments, self.now, self.logins, since=self.state['since'])
        fork = bool(pr.get('isCrossRepository'))
        allowed = set(self.owners) if fork or not due else self.pr_people(n)
        groups = {}
        for c in due:
            r = pr_reason(c, label, self.owners, self.handles, allowed, fork)
            if r:
                groups.setdefault(r, []).append(c)
        for (why, todo), cs in groups.items():
            hint = None if fork else syntax_hint(cs, self.handles, PR_VERBS, 'on a pull request')
            if todo is None:
                todo = (f'Commands (first line of a comment): `{self.handles[0]} fix` starts the fix bot '
                        f'(instructions below the first line), `{self.handles[0]} review` re-runs the review.')
            self.post(n, compose(cs, why, todo, hint, None))
        self.seen('prs', n, updated, comments)  # after the replies: a failed post is retried next run


def main(argv=None, config=None):
    import argparse
    parser = argparse.ArgumentParser(prog='unheard.py', description=(__doc__ or '').split('\n')[0])
    parser.add_argument('--dry', action='store_true', help='print intended replies; write nothing')
    parser.add_argument('--only', choices=('issues', 'prs'))
    args = parser.parse_args(argv)
    config = gp.resolve_project(dict(gp.load_config() if config is None else config))
    gp.require_owners(config)
    # One board, several repositories: each is checked in turn, with its own state (the primary first).
    runs = [Run(gp.repo_config(config, repo), args.dry) for repo in gp.board_repos(config)]
    results = []
    try:
        with gp.file_lock(pathlib.Path(config['state_dir']) / 'unheard.lock', wait=0):
            for run in runs:
                results.append(run_steps(run, args.only))
    except gp.LockBusy:
        return 0  # the previous run is still going; the next one catches up
    code = 0
    for run, failed in zip(runs, results):
        code = report(run, failed, args) or code
    return code


def run_steps(run, only):
    """Run the steps for one repository; the failure lines of whole steps."""
    failed = []
    for name, step in (('issues', run.issues), ('prs', run.prs)):
        if only not in (None, name):
            continue
        try:
            step()
        except (RuntimeError, ValueError, KeyError, TypeError, AttributeError, OSError,
                subprocess.SubprocessError) as exc:
            failed.append(f'[{run.repo}] unheard {name} FAILED: {exc}')
    run.save()
    return failed


def report(run, failed, args):
    if args.dry:
        lines = failed + run.failures
    else:
        # Every step failing: one alert, repeated at most hourly, then one line when it runs again. Other
        # failures (one step, single items) repeat their line at most once per 6 hours.
        health = run.state_dir / 'health-unheard'
        steps = 1 if args.only else 2
        down = len(failed) == steps
        status = (pipeline_runtime.job_down(health, f'Unheard replies ({run.repo})', '; '.join(failed)) if down
                  else pipeline_runtime.job_up(health, f'Unheard replies ({run.repo})'))
        lines = status + pipeline_runtime.fresh_lines(health, 'errors', ([] if down else failed) + run.failures)
    if lines:
        print('\n'.join(lines), flush=True)
    return 1 if failed or run.failures else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, KeyError, TypeError, AttributeError, OSError,
            subprocess.SubprocessError) as exc:
        print('unheard: ' + str(exc), file=sys.stderr)
        sys.exit(1)
