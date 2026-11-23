#!/usr/bin/env python3
"""Board sync: deterministic tracker hygiene for one repository's GitHub Project. Script-only cron entry, no LLM.

    board-sync.py [--dry] [--only reconcile|intake|waiting]

Generic subset of gm-agent-pipeline `pipeline/board_sync.py` (Daniel Gehriger). Configuration and board access come
from gh-project.py beside it (same environment / GH_PROJECT_CONFIG; owners are required here).

Steps, in this order (`--only` runs one):
  intake     open issues not on the board: issues whose body carries `<!-- bot-created source=... -->` go to Inbox,
             every other one to Backlog (no bot reads Backlog; a person moves a card to Inbox). A card a person
             added without a Status is set to Inbox. BOARD_SYNC_INTAKE=all sends every off-board issue to Inbox.
  reconcile  closed issues -> Done (Canceled when closed as not planned); close proposals: closed after an owner
             `close` (or `approve`) reply, or after `auto_close_after=<UTC>` with no reply from a person; `keep`
             dismisses; related PRs are linked on the issue, and a merged PR that closes or names an open issue gets
             a close proposal (closing keyword: auto-closes after 48 h).
  waiting    `Waiting for` follows the card: in Your turn it shows the kind of wait (newest bot marker or PR
             labels), or `⏳ Bot's turn` once a valid reply waits for the dispatcher; it is cleared everywhere else.

Authority: it never moves a card into Up next or Later, never sets Bot approvals, never merges. Every comment it
writes starts with 🤖 and carries an HTML marker, so on a shared owner/agent account none of them counts as a
reply. stdout carries only the lines a person should see (all lines with --dry); routine lines go to
$BOARD_SYNC_STATE/board-sync.log. A run holds $BOARD_SYNC_STATE/board-sync.lock (waits up to 120 s).
"""
import calendar
import contextlib
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import commands  # noqa: E402  (scripts/commands.py)


def load_gp():
    spec = importlib.util.spec_from_file_location('gh_project', HERE / 'gh-project.py')
    if spec is None or spec.loader is None:
        raise ImportError(f'cannot load {HERE / "gh-project.py"}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gp = load_gp()

MAX_MOVES = 10       # status / Waiting for changes per run
MAX_COMMENTS = 8     # PR-link and close-proposal comments per run
MAX_INTAKE = 40      # issues added per run; Inbox and Backlog additions count together
SYNC_LOCK_WAIT = 120
AUTO_CLOSE_HOURS = 48
STEPS = ('intake', 'reconcile', 'waiting')

CLOSING = re.compile(r'(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+((?:[\w.-]+/[\w.-]+)?)#(\d+)')
MENTION = re.compile(r'(?<![\w/&])((?:[\w.-]+/[\w.-]+)?)#(\d+)\b')
BRANCH = re.compile(r'(?i)(?:^|/)(?:item|issue)[-/](\d+)(?:\b|$)')
# Close proposals: `close` / `keep`; the older `approve` / `reject` still work except on a card in Your turn,
# where they belong to its approval step.
CLOSE_VERB = {'close': 'approve', 'keep': 'reject', 'approve': 'approve', 'reject': 'reject'}
AUTO_CLOSE = re.compile(r'auto_close_after=(\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d)?Z?)')
MARKER_RE = re.compile(r'<!--\s*(gate|triage|close-proposal|sync)')
BOT_CREATED = re.compile(r'<!--\s*bot-created\b')


# ---------------------------------------------------------------- pure helpers (unit tested)

def references(repo, number, title, body, branch):
    """(closing, title_mentions, body_mentions): issue numbers in `repo` this PR points at."""
    def same(prefix):
        return not prefix or prefix.lower() == repo.lower()
    text = (title or '') + '\n' + (body or '')
    closing = {int(n) for p, n in CLOSING.findall(text) if same(p)}
    in_title = {int(n) for p, n in MENTION.findall(title or '') if same(p)}
    in_body = {int(n) for p, n in MENTION.findall(body or '') if same(p)}
    m = BRANCH.search(branch or '')
    if m:
        in_body.add(int(m.group(1)))
    drop = {number}
    return closing - drop, (in_title - closing) - drop, ((in_body | in_title) - closing - in_title) - drop


def owner_reply(comments, people, handles, logins):
    """(proposal comment, verb) when the newest bot marker comment is a live close proposal; verb is the latest
    close/keep/approve/reject reply from one of `people` after it (or None)."""
    last_marker = None
    for c in comments:
        if gp.by_agent(c, logins) and MARKER_RE.search(c.get('body') or ''):
            last_marker = c
    if not last_marker or 'close-proposal' not in last_marker['body'] or 'dismissed' in last_marker['body']:
        return None, None
    verb = None
    for c in comments:
        if c['id'] <= last_marker['id'] or not gp.human_comment(c, people):
            continue
        found = commands.parse(c.get('body'), handles)
        if found and found[1] in CLOSE_VERB:
            verb = found[1]
    return last_marker, verb


def auto_close_due(marker, comments, people, now=None):
    """True when a close proposal carries `auto_close_after=<UTC>`, the deadline has passed and none of `people`
    wrote anything but bot text since the proposal. Any plain comment from them stops the timer."""
    m = AUTO_CLOSE.search((marker or {}).get('body') or '')
    if not m:
        return False
    stamp = m.group(1) if m.group(1).endswith('Z') else m.group(1) + 'Z'
    if len(stamp) == 17:  # YYYY-MM-DDTHH:MMZ
        stamp = stamp[:-1] + ':00Z'
    try:
        deadline = calendar.timegm(time.strptime(stamp, '%Y-%m-%dT%H:%M:%SZ'))
    except ValueError:
        return False
    if (time.time() if now is None else now) < deadline:
        return False
    return not any(c['id'] > marker['id'] and gp.human_comment(c, people) for c in comments)


def close_proposal_attrs(marker):
    body = (marker or {}).get('body') or ''

    def get(key):
        m = re.search(r'\b' + key + r'=(\S+)', body)
        return m.group(1).rstrip('-').strip() if m else ''
    return {'reason': get('reason') or 'fixed', 'dup': get('dup'), 'pr': get('pr')}


# ---------------------------------------------------------------- plumbing

class Context:
    def __init__(self, config, dry=False):
        self.config, self.dry = config, dry
        self.state_dir = pathlib.Path(config['state_dir'])
        self.state_file = self.state_dir / 'board-sync.json'
        try:
            self.state = json.loads(self.state_file.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            self.state = {}
        self.moves = self.comments = self.intake_added = 0
        self.lines = []

    @property
    def repo(self):
        return self.config['repo']

    def say(self, text, loud=False):
        """Lines a person should see go to stdout; routine lines to the log (everything is printed with --dry)."""
        text = f'[{self.repo}] {text}' + (' (DRY)' if self.dry else '')
        self.lines.append(text)
        if loud or self.dry:
            print(text, flush=True)
        else:
            self.log(text)

    def log(self, text):
        if self.dry:
            return
        self.state_dir.mkdir(parents=True, exist_ok=True)
        with (self.state_dir / 'board-sync.log').open('a', encoding='utf-8') as handle:
            handle.write(time.strftime('%Y-%m-%dT%H:%M:%S ') + text + '\n')

    def save_state(self):
        if self.dry:
            return
        self.state_dir.mkdir(parents=True, exist_ok=True)
        tmp = self.state_file.with_suffix('.tmp')
        tmp.write_text(json.dumps(self.state, indent=2, sort_keys=True), encoding='utf-8')
        os.replace(tmp, self.state_file)

    def gh(self, *args):
        return gp.gh(self.config, *args)

    def gql(self, query, **variables):
        return gp.graphql(self.config, query, **variables)

    def people(self, issue=None):
        return gp.responders(self.config, issue)


def post_comment(ctx, number, body):
    if not ctx.dry:
        gp.post_comment(ctx.config, number, body)


def set_label(ctx, number, label, on):
    if ctx.dry:
        return
    if on:
        ctx.gh('api', '-X', 'POST', f'repos/{ctx.repo}/issues/{number}/labels', '-f', 'labels[]=' + label)
    else:
        with contextlib.suppress(RuntimeError):
            ctx.gh('api', '-X', 'DELETE', f'repos/{ctx.repo}/issues/{number}/labels/' + label.replace(':', '%3A'))


def move(ctx, number, status, body, moved):
    """Guarded move through the adapter; returns True when it moved (or would, in dry mode)."""
    if not ctx.dry:
        try:
            gp.mutate_field(ctx.config, number, 'Status', status, body)
        except (RuntimeError, ValueError) as exc:
            ctx.say(f'#{number}: move to {gp.board_value("Status", status)} FAILED: {exc}', loud=True)
            return False
        moved[number] = status
    ctx.moves += 1
    return True


# ---------------------------------------------------------------- intake

ADD_ITEM = ('mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,contentId:$c}){item{id '
            'fieldValues(first:20){nodes{__typename ... on ProjectV2ItemFieldSingleSelectValue{name '
            'field{... on ProjectV2FieldCommon{name}}}}}}}}')


def ingest(ctx, limit=None, only=None):
    """Add off-board open issues; `only`: None (both), 'inbox' (also sets a blank Status) or 'backlog'.
    Returns (inbox added, backlog added)."""
    repo, config = ctx.repo, ctx.config
    status = gp.read_fields(config)['Status']
    inbox = next(o['id'] for o in status['options'] if o['internal'] == 'Inbox')
    backlog = next((o['id'] for o in status['options'] if o['internal'] == 'Backlog'), None)
    issues, _, nodes = gp.snapshot(config)
    # Archived cards are skipped by the issue list but are still on the board: never re-add them.
    have = {i['number'] for i in issues} | {
        (n.get('content') or {}).get('number') for n in nodes
        if ((n.get('content') or {}).get('repository') or {}).get('nameWithOwner') == repo}
    everything = config.get('intake') == 'all'
    open_issues = ctx.gh('issue', 'list', '-R', repo, '--state', 'open', '--limit', '1000', '--json', 'id,number,body') or []
    todo = sorted(((i, inbox if everything or BOT_CREATED.search(i.get('body') or '') else backlog)
                   for i in open_issues if i['number'] not in have),
                  key=lambda pair: (pair[1] != inbox, pair[0]['number']))
    todo = [(i, o) for i, o in todo if o]  # no Backlog option yet (`fields` not run): only Inbox intake
    if only:
        todo = [(i, o) for i, o in todo if (o == inbox) == (only == 'inbox')]
    if limit is not None:
        todo = todo[:max(0, limit)]
    # A card a person added shows "No Status" while the bots read it as Inbox: make the board say so.
    blank = [] if only == 'backlog' else [
        n for n in nodes if not n.get('isArchived') and not gp.stored_value(n, 'Status')
        and ((n.get('content') or {}).get('repository') or {}).get('nameWithOwner') == repo
        and (n.get('content') or {}).get('__typename') == 'Issue' and (n.get('content') or {}).get('state') == 'OPEN']
    for n in blank:
        ctx.say(f"#{n['content']['number']}: no status on the board -> {gp.board_value('Status', 'Inbox')}")
        if not ctx.dry:
            gp.set_item_option(config, n['id'], status, inbox)
    if ctx.dry:
        return sum(1 for _, o in todo if o == inbox), sum(1 for _, o in todo if o != inbox)
    added = [0, 0]
    for i, option in todo:
        # addProjectV2ItemById returns the EXISTING card when the issue is already on the board (the item list can
        # omit cards): never overwrite a Status somebody already set.
        item = ctx.gql(ADD_ITEM, p=config['project_id'], c=i['id'])['addProjectV2ItemById']['item']
        current = gp.stored_value(item, 'Status')
        if current:
            ctx.say(f"#{i['number']}: already on the board as {current}; left as is")
            continue
        gp.set_item_option(config, item['id'], status, option)
        added[0 if option == inbox else 1] += 1
    return tuple(added)


def intake(ctx, only=None):
    room = MAX_INTAKE - ctx.intake_added
    if room <= 0:
        return
    inbox_n, backlog_n = ingest(ctx, limit=room, only=only)
    if inbox_n or backlog_n:
        ctx.say(f'intake added {inbox_n + backlog_n} open issue(s): {inbox_n} to {gp.board_value("Status", "Inbox")}, '
                f'{backlog_n} to {gp.board_value("Status", "Backlog")}', loud=bool(inbox_n))
        ctx.intake_added += inbox_n + backlog_n


# ---------------------------------------------------------------- reconcile

CLOSED = '''query($o:String!,$n:String!,$after:String) {repository(owner:$o,name:$n) {
 issues(first:100, after:$after, states:CLOSED, orderBy:{field:UPDATED_AT,direction:DESC}) {
  pageInfo {hasNextPage endCursor} nodes {number stateReason closedAt url
   timelineItems(last:5, itemTypes:[CLOSED_EVENT]) {nodes {... on ClosedEvent {closer {__typename
    ... on PullRequest {number} ... on Commit {abbreviatedOid}}}}}}}}}'''
PRS = '''query($o:String!,$n:String!,$after:String) {repository(owner:$o,name:$n) {
 pullRequests(first:100, after:$after, orderBy:{field:UPDATED_AT,direction:DESC}) {pageInfo {hasNextPage endCursor}
  nodes {number title body headRefName baseRefName state mergedAt isDraft url author {login __typename}
   closingIssuesReferences(first:20) {nodes {number repository {nameWithOwner}}}}}}}'''


def pages(ctx, query, path, limit=3):
    owner, name = ctx.repo.split('/')
    after, out = None, []
    for _ in range(limit):
        variables = {'o': owner, 'n': name}
        if after:
            variables['after'] = after
        node = ctx.gql(query, **variables)['repository']
        for key in path:
            node = node[key]
        out.extend(node['nodes'])
        if not node['pageInfo']['hasNextPage']:
            break
        after = node['pageInfo']['endCursor']
    return out


def closed_issues(ctx, issues, moved):
    """Closed on GitHub but not Done/Canceled on the board: completed -> Done, not planned -> Canceled.
    In progress is left to its work session."""
    closed = [i for i in issues if i['state'] in ('CLOSED', 'CLOSED_WITHOUT_MERGE')
              and i['status'] not in ('Done', 'Canceled', 'In progress')]
    if not closed:
        return
    details = {c['number']: c for c in pages(ctx, CLOSED, ('issues',))}
    for i in closed:
        d = details.get(i['number'])
        if not d:
            ctx.say(f"#{i['number']} closed but not in the recent closed list; skipped")
            continue
        if ctx.moves >= MAX_MOVES:
            return
        was = gp.board_value('Status', i['status'])
        date = (d.get('closedAt') or '')[:10]
        if d.get('stateReason') == 'NOT_PLANNED':
            want = 'Canceled'
            body = (f'🤖 **No action needed: closed as not planned, moved to Canceled**\n\n'
                    f'- closed on {date}; the board showed `{was}`\n\n<!-- sync closed reason=not_planned -->')
            how = 'closed as not planned'
        else:
            want = 'Done'
            closer = ((d.get('timelineItems') or {}).get('nodes') or [{}])[-1].get('closer') or {}
            via = f' by merged PR #{closer["number"]}' if closer.get('number') else ''
            body = (f'🤖 **No action needed: closed as completed{via}, moved to Done**\n\n'
                    f'- closed on {date}; the board showed `{was}`\n\n<!-- sync closed -->')
            how = f'closed as completed{via}'
        ctx.say(f"#{i['number']}: {was} -> {gp.board_value('Status', want)} ({how})")
        move(ctx, i['number'], want, body, moved)


def close_issue(ctx, number, item, attrs, body, moved):
    """Close an issue for a close proposal: duplicates as not planned (Canceled), the rest as completed (Done)."""
    duplicate = attrs['reason'] == 'duplicate'
    reason, status = ('not_planned', 'Canceled') if duplicate else ('completed', 'Done')
    if ctx.dry:
        return
    ctx.gh('api', '-X', 'PATCH', f'repos/{ctx.repo}/issues/{number}', '-f', 'state=closed', '-f', f'state_reason={reason}')
    set_label(ctx, number, gp.PROPOSE_LABEL, False)
    if item and item['status'] not in ('Done', 'Canceled'):
        move(ctx, number, status, body, moved)
    else:
        post_comment(ctx, number, body)


def close_replies(ctx, issues, by_number, moved):
    """Replies (close/keep) to close proposals, and the auto-close after the deadline."""
    repo, config = ctx.repo, ctx.config
    logins = gp.bot_logins(config)
    labelled = {e['number'] for e in ctx.gh('issue', 'list', '-R', repo, '--label', gp.PROPOSE_LABEL, '--state', 'open',
                                            '--json', 'number') or []}
    # A triage close proposal may lack the label: read the open Your turn cards without it too.
    unlabelled = [i['number'] for i in issues
                  if i['state'] == 'OPEN' and i['status'] == 'Your turn' and i['number'] not in labelled]
    for n in [*sorted(labelled), *unlabelled]:
        comments = gp.comments_of(config, n)
        people = ctx.people(gp.issue_of(config, n))
        marker, verb = owner_reply(comments, people, config['handles'], logins)
        if not marker:
            if n in labelled:
                set_label(ctx, n, gp.PROPOSE_LABEL, False)  # a newer gate/triage marker superseded the proposal
            continue
        if n not in labelled:
            set_label(ctx, n, gp.PROPOSE_LABEL, True)
        item = by_number.get(n)
        if verb in ('approve', 'reject') and (item or {}).get('status') == 'Your turn':
            verb = None  # belongs to the card's approval step; only close/keep answer the proposal there
        verb = CLOSE_VERB.get(verb) if verb else None
        attrs = close_proposal_attrs(marker)
        why = (f'a duplicate of #{attrs["dup"]}' if attrs['reason'] == 'duplicate' and attrs['dup']
               else 'a duplicate' if attrs['reason'] == 'duplicate'
               else f'already done by PR #{attrs["pr"]}' if attrs['pr'] else 'already fixed')
        if not verb:
            if not auto_close_due(marker, comments, people):
                continue
            if ctx.moves >= MAX_MOVES:
                return
            ctx.say(f'#{n}: auto-closed as {why} (no reply within {AUTO_CLOSE_HOURS} hours of the close proposal)',
                    loud=True)
            close_issue(ctx, n, item, attrs, f'🤖 **No action needed: closed as {why}**\n\n'
                        f'- no reply within {AUTO_CLOSE_HOURS} h of the close proposal; reopen it if that is wrong\n\n'
                        '<!-- sync closed auto=1 -->', moved)
        elif verb == 'approve':
            if ctx.moves >= MAX_MOVES:
                return
            ctx.say(f'#{n}: close reply received -> closed as {why}', loud=True)
            close_issue(ctx, n, item, attrs, f'🤖 **No action needed: closed as {why} after your close reply**\n\n'
                        '<!-- sync closed -->', moved)
        else:
            pr = attrs['pr'] or '-'
            ctx.say(f'#{n}: keep reply received -> close proposal dismissed', loud=True)
            post_comment(ctx, n, '🤖 **No action needed: kept open**\n\n'
                         + (f'- PR #{pr} is not proposed again\n\n' if attrs['pr'] else '')
                         + f'<!-- close-proposal dismissed pr={pr} -->')
            set_label(ctx, n, gp.PROPOSE_LABEL, False)


def ensure_propose_label(ctx):
    try:
        ctx.gh('api', gp.label_path(ctx.repo, gp.PROPOSE_LABEL))
    except RuntimeError:
        gp.ensure_labels(ctx.config, only=gp.PROPOSE_LABEL)


def link_prs(ctx, issues):
    """Link related PRs on open issues; propose closing an open issue a merged PR closes or names in its title.
    Backlog cards are never touched."""
    repo = ctx.repo
    candidates = {i['number']: i for i in issues
                  if i['state'] == 'OPEN' and i['status'] not in ('Done', 'Canceled', 'Backlog')}
    if not candidates:
        return
    seen = ctx.state.setdefault('links', {})
    handle = ctx.config['handles'][0]
    for pr in pages(ctx, PRS, ('pullRequests',)):
        author = pr.get('author') or {}
        if author.get('__typename') == 'Bot' or (author.get('login') or '').endswith('[bot]') or pr['state'] == 'CLOSED':
            continue
        closing, in_title, in_body = references(repo, pr['number'], pr['title'], pr['body'], pr['headRefName'])
        closing |= {r['number'] for r in (pr.get('closingIssuesReferences') or {}).get('nodes', [])
                    if r['repository']['nameWithOwner'] == repo}
        for n in sorted((closing | in_title | in_body) & set(candidates)):
            if ctx.comments >= MAX_COMMENTS:
                return
            key = f'{repo}#{n}<-{pr["number"]}'
            if key in seen:
                continue
            existing = gp.comments_of(ctx.config, n)
            if any(f'pr={pr["number"]}' in (c.get('body') or '')
                   and re.search(r'<!--\s*(pr-link|close-proposal)', c.get('body') or '') for c in existing):
                seen[key] = 'present'
                continue
            issue = candidates[n]
            kind = 'closing' if n in closing else 'title' if n in in_title else 'mention'
            merged = pr['state'] == 'MERGED'
            state_word = 'merged' if merged else 'draft' if pr.get('isDraft') else 'open'
            if merged and kind in ('closing', 'title') and issue['status'] not in ('In progress', 'Your turn'):
                auto = kind == 'closing'  # a closing keyword is high confidence: closes after 48 h unanswered
                deadline = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() + AUTO_CLOSE_HOURS * 3600))
                ask = (f'it closes by itself after {AUTO_CLOSE_HOURS} h ({deadline[:16].replace("T", " ")} UTC) '
                       'unless you reply' if auto else 'the PR only names this issue: check that it covers it')
                body = (f'🤖 **Your turn: close this issue? [PR #{pr["number"]}]({pr["url"]}) merged**\n\n- {ask}\n\n'
                        f'<details>\n<summary><b>Reply with</b> <code>{handle} close</code> or '
                        f'<code>{handle} keep</code></summary>\n\n| Reply | Effect |\n|---|---|\n'
                        f'| `{handle} close` | Close as completed and move to Done |\n'
                        f'| `{handle} keep` | Keep it open; this PR is not proposed again |\n</details>\n\n'
                        f'<!-- close-proposal reason=fixed dup=- pr={pr["number"]}'
                        + (f' auto_close_after={deadline}' if auto else '') + ' -->')
                ctx.say(f'#{n}: proposed closing it (merged PR #{pr["number"]}); '
                        + (f'it closes by itself after {AUTO_CLOSE_HOURS} hours unless you reply' if auto
                           else f'reply `{handle} close` on the issue to close it'), loud=True)
                if not ctx.dry:
                    ensure_propose_label(ctx)
                    post_comment(ctx, n, body)
                    set_label(ctx, n, gp.PROPOSE_LABEL, True)
            else:
                body = (f'🤖 **No action needed: related {state_word} PR #{pr["number"]}**\n\n'
                        f'- {pr["title"]} ({kind} reference): {pr["url"]}\n\n<!-- pr-link pr={pr["number"]} -->')
                ctx.say(f'#{n}: link {state_word} PR #{pr["number"]} ({kind})')
                post_comment(ctx, n, body)
            ctx.comments += 1
            if not ctx.dry:
                seen[key] = 'posted'


def reconcile(ctx):
    issues, _, _ = gp.snapshot(ctx.config)
    by_number = {i['number']: i for i in issues}
    moved = {}
    closed_issues(ctx, issues, moved)
    close_replies(ctx, issues, by_number, moved)
    link_prs(ctx, [i for i in issues if i['number'] not in moved])
    return moved


# ---------------------------------------------------------------- Waiting for

def waiting_for(ctx, moved=None):
    """Display only (bots never read it). Reads comments only for cards in Your turn."""
    moved = moved or {}
    config = ctx.config
    issues, _, _ = gp.snapshot(config)
    for issue in issues:
        n, have = issue['number'], issue.get('waiting_for', '')
        if moved.get(n, issue['status']) == 'Your turn':
            try:
                label_sets = [{l['name'] for l in gp.issue_of(config, pr).get('labels', [])} for pr in issue.get('prs') or []]
                kind, replied = gp.bot_turn(config, gp.comments_of(config, n), label_sets,
                                            lambda n=n: gp.issue_of(config, n))
            except (RuntimeError, ValueError, KeyError, OSError) as exc:
                ctx.say(f'#{n} Waiting for not checked: {exc}')
                continue
            want = gp.WAITING_FOR_BOT if replied else gp.WAITING_FOR.get(kind, '')
        else:
            want = ''
        if have == want:
            continue
        if ctx.moves >= MAX_MOVES:
            return
        ctx.say(f'#{n}: Waiting for {have or "empty"} -> {want or "empty"}')
        if not ctx.dry:
            try:
                gp.mutate_field(config, n, gp.WAITING_FIELD, want, '')
            except (RuntimeError, ValueError, KeyError) as exc:
                ctx.say(f'#{n} Waiting for update FAILED: {exc}', loud=True)
                continue
        ctx.moves += 1


# ---------------------------------------------------------------- entry point

def run(ctx, only=None):
    """All steps (or one); returns 0, or 1 when a step failed."""
    failed = False
    moved = {}
    plan = [('intake', lambda: intake(ctx, only='inbox')), ('intake', lambda: intake(ctx, only='backlog')),
            ('reconcile', lambda: moved.update(reconcile(ctx) or {})), ('waiting', lambda: waiting_for(ctx, moved))]
    for name, step in plan:
        if only not in (None, name):
            continue
        try:
            step()
        except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
            ctx.say(f'{name} FAILED: {exc}', loud=True)
            failed = True
    return 1 if failed else 0


def main(argv=None, config=None):
    import argparse
    parser = argparse.ArgumentParser(prog='board-sync.py', description=(__doc__ or '').split('\n')[0])
    parser.add_argument('--dry', action='store_true', help='print intended changes; write nothing')
    parser.add_argument('--only', choices=STEPS)
    args = parser.parse_args(argv)
    config = gp.resolve_project(dict(gp.load_config() if config is None else config))
    gp.require_owners(config)
    ctx = Context(config, args.dry)
    started = time.time()
    try:
        with gp.file_lock(gp.lock_path(config), wait=0 if args.dry else SYNC_LOCK_WAIT):
            try:
                code = run(ctx, args.only)
            finally:
                ctx.save_state()
    except gp.LockBusy:
        print(f'[{config["repo"]}] board sync FAILED to start: another run held the board lock for over '
              f'{SYNC_LOCK_WAIT} s. Nothing changed; the next run retries.', flush=True)
        return 1
    ctx.log(f'[{config["repo"]}] run done in {time.time() - started:.0f} s'
            + ('; FAILED steps above' if code else ''))
    return code


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print('board-sync: ' + str(exc), file=sys.stderr)
        sys.exit(1)
