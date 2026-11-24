#!/usr/bin/env python3
"""Board sync: deterministic tracker hygiene for one repository's GitHub Project. Script-only cron entry, no LLM.

    board-sync.py [--dry] [--only reconcile|intake|waiting|jira]
    board-sync.py --digest          (owner digest: everything waiting on a person; read-only; daily cron)
    board-sync.py --jira-check      (Jira settings, token and project access; read-only)

Generic subset of gm-agent-pipeline `pipeline/board_sync.py` (Daniel Gehriger). Configuration and board access come
from gh-project.py beside it (same environment / GH_PROJECT_CONFIG; owners are required here).

Steps, in this order (`--only` runs one):
  intake     open issues not on the board: issues whose body carries `<!-- bot-created source=... -->` go to Inbox,
             every other one to Backlog (no bot reads Backlog; a person moves a card to Inbox). A card a person
             added without a Status is set to Inbox. BOARD_SYNC_INTAKE=all sends every off-board issue to Inbox.
  reconcile  PR cards a person put on the board follow the PR (merged -> Done, closed -> Canceled, open -> In review,
             or Your turn when its labels wait on a person); merged/closed PRs lose their workflow labels;
             closed issues -> Done (Canceled when closed as not planned); close proposals: closed after an owner
             `close` (or `approve`) reply, or after `auto_close_after=<UTC>` with no reply from a person; `keep`
             dismisses; related PRs are linked on the issue, an open unassigned PR that closes an issue is assigned
             to that issue's assignees (else the first owner), and a merged PR that closes or names an open issue
             gets a close proposal (closing keyword: auto-closes after 48 h).
  waiting    `Waiting for` follows the card: in Your turn it shows the kind of wait (newest bot marker or PR
             labels), or `⏳ Bot's turn` once a valid reply waits for the dispatcher; it is cleared everywhere else.
  jira       only with JIRA_BASE_URL + JIRA_PROJECTS (or "jira" in GH_PROJECT_CONFIG) and JIRA_PAT (Jira Server /
             Data Center token): open issues and PRs that name a Jira key (or, with JIRA_MATCH_TITLES, share one
             Jira summary) get an "implemented by" link on the Jira issue and one comment with the Jira link.

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
import urllib.error
import urllib.parse
import urllib.request

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

MAX_MOVES = 10       # status / Waiting for changes per run
MAX_COMMENTS = 8     # PR-link and close-proposal comments per run
MAX_INTAKE = 40      # issues added per run; Inbox and Backlog additions count together
MAX_LABEL_CLEANUPS = 20  # merged/closed PRs whose workflow labels are removed per run
MAX_JIRA = 20       # Jira links per run
PR_HUMAN_LABELS = ('needs-human:merge', 'needs-human:decision')
SYNC_LOCK_WAIT = 120
AUTO_CLOSE_HOURS = 48
STEPS = ('intake', 'reconcile', 'waiting', 'jira')

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
        self.moves = self.comments = self.intake_added = self.jira_links = 0
        self.lines = []
        self.failures = []  # failed parts of a step that still ran the rest (main reports them)

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
   assignees(first:10) {nodes {login}}
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


def assign_pr(ctx, pr, issue_numbers):
    """Assign an open, unassigned PR to the people responsible for the issues it closes: their assignees, or the
    first owner when they have none. Assigned people may command the bots on the PR (pr-sweep-dispatch.py
    pr_people). Returns the logins assigned (empty when nothing changed)."""
    if pr.get('state') != 'OPEN' or (pr.get('assignees') or {}).get('nodes') or not issue_numbers:
        return []
    people = []
    for n in sorted(issue_numbers):
        try:
            issue = gp.issue_of(ctx.config, n)
        except (RuntimeError, ValueError, subprocess.SubprocessError):
            continue
        people += [a['login'] for a in issue.get('assignees') or [] if a.get('login') and a['login'] not in people]
    people = people or list(ctx.config['owners'][:1])
    if not people:
        return []
    ctx.say(f'PR #{pr["number"]}: assigned to ' + ', '.join(f'@{p}' for p in people))
    if not ctx.dry:
        ctx.gh('api', '-X', 'POST', f'repos/{ctx.repo}/issues/{pr["number"]}/assignees',
               *[x for p in people for x in ('-f', f'assignees[]={p}')])
    return people


def pr_cards(ctx, nodes):
    """PR cards a person put on the board follow the PR, so Your turn never shows a PR that waits on nobody.

    The bots work on issue cards only; nothing else moves a PR card. Merged -> Done, closed -> Canceled (closing
    the PR was a person's decision), open -> In review, or Your turn with its Waiting for when the PR labels say
    a person acts (needs-human:decision, needs-human:merge). A card in Later stays there while the PR is open."""
    fields = None
    for node in nodes:
        content = node.get('content') or {}
        if (node.get('isArchived') or content.get('__typename') != 'PullRequest'
                or (content.get('repository') or {}).get('nameWithOwner') != ctx.repo):
            continue
        current = gp.item_values(node).get('Status', '')
        state, kind = content.get('state'), None
        if state == 'MERGED':
            want = 'Done'
        elif state == 'CLOSED':
            want = 'Canceled'
        elif current == gp.PARKED_STATUS:
            continue
        else:
            labels = {(lbl or {}).get('name') for lbl in gp.issue_of(ctx.config, content['number']).get('labels') or []}
            kind = gp.review_status([labels])
            want = 'Your turn' if kind in ('decide', 'merge') else 'In review'
        want_wait = gp.WAITING_FOR.get(kind, '') if want == 'Your turn' else ''
        has_wait = gp.stored_value(node, gp.WAITING_FIELD)
        if current == want and has_wait == want_wait:
            continue
        fields = fields or gp.read_fields(ctx.config)
        waiting = fields.get(gp.WAITING_FIELD)
        option = next((o['id'] for o in waiting['options'] if o['name'] == want_wait), None) if waiting and want_wait else None
        can_wait = bool(waiting) and (option is not None or not want_wait)
        if current == want and not can_wait:
            continue  # only Waiting for differs and the board cannot show it (no field or option): nothing to write
        if ctx.moves >= MAX_MOVES:
            return
        why = {'Done': 'merged', 'Canceled': 'closed without merge'}.get(want, 'open; its labels say ' + (want_wait or 'a bot acts'))
        ctx.say(f'PR #{content["number"]} card: {gp.board_value("Status", current) if current else "No Status"} -> '
                f'{gp.board_value("Status", want)}' + (f', waiting for {want_wait}' if want_wait else '') + f' ({why})')
        if not ctx.dry:
            status = fields['Status']
            if current != want:
                gp.set_item_option(ctx.config, node['id'], status,
                                   next(o['id'] for o in status['options'] if o['internal'] == want))
            if has_wait != want_wait and can_wait:
                gp.set_item_option(ctx.config, node['id'], waiting, option)
        ctx.moves += 1


def closed_pr_labels(ctx):
    """A merged or closed PR loses its workflow labels (`review-bot:*`, `fix-bot:*`, needs-human:merge and
    needs-human:decision, and their legacy names). The PR sweep reads open PRs only, so without this a merged PR
    kept saying a person or a bot still has to act. Every other label stays."""
    current = [name for name, _, _ in gp.WORKFLOW_LABELS
               if name.startswith(('review-bot:', 'fix-bot:')) or name in PR_HUMAN_LABELS]
    stale = set(current) | {old for old, new in gp.LEGACY_LABELS.items() if new in current}
    owner, name = ctx.repo.split('/')
    query = ('query($o:String!,$n:String!){repository(owner:$o,name:$n){pullRequests(first:50,states:[MERGED,CLOSED],'
             'labels:' + json.dumps(sorted(stale)) + ',orderBy:{field:UPDATED_AT,direction:DESC}){'
             'nodes{number labels(first:50){nodes{name}}}}}}')
    removed = 0
    for pr in ctx.gql(query, o=owner, n=name)['repository']['pullRequests']['nodes']:
        drop = [lbl['name'] for lbl in pr['labels']['nodes'] if lbl['name'] in stale]
        if not drop:
            continue
        if removed >= MAX_LABEL_CLEANUPS:
            return
        ctx.say(f'PR #{pr["number"]} closed: removed ' + ', '.join(drop))
        for label in drop:
            set_label(ctx, pr['number'], label, False)
        removed += 1


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
        try:
            assign_pr(ctx, pr, closing & set(candidates))
        except (RuntimeError, ValueError, subprocess.SubprocessError) as exc:
            ctx.say(f'PR #{pr["number"]}: assigning FAILED: {exc}')
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
                body = (f'🤖 **Possibly done: close this issue? [PR #{pr["number"]}]({pr["url"]}) merged**\n\n- {ask}\n\n'
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
    issues, _, nodes = gp.snapshot(ctx.config)
    by_number = {i['number']: i for i in issues}
    moved = {}
    # The PR features are extras: their failure is reported but never holds up the issue cards.
    for name, part in (('PR cards', lambda: pr_cards(ctx, nodes)), ('closed PR labels', lambda: closed_pr_labels(ctx))):
        try:
            part()
        except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
            ctx.failures.append(f'[{ctx.repo}] reconcile ({name}) FAILED: {exc}')
            ctx.log(ctx.failures[-1])
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
                label_sets = [{lbl['name'] for lbl in gp.issue_of(config, pr).get('labels', [])} for pr in issue.get('prs') or []]
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


# ---------------------------------------------------------------- owner digest

DIGEST_ORDER = ('approve', 'unblock', 'answer', 'decide', 'merge')


def age_days(stamp, now=None):
    try:
        then = calendar.timegm(time.strptime((stamp or '')[:19], '%Y-%m-%dT%H:%M:%S'))
    except ValueError:
        return 0
    return max(0, int(((time.time() if now is None else now) - then) / 86400))


def backlog_trend(ctx, days=7):
    """One line on whether the backlog shrinks: issues opened vs closed in the last `days` days (2 search calls).
    '' when the counts cannot be read, so the digest never fails on it."""
    since = time.strftime('%Y-%m-%d', time.gmtime(time.time() - days * 86400))
    try:
        opened, closed = (int(ctx.gh('api', '-X', 'GET', 'search/issues', '-f',
                                     f'q=repo:{ctx.repo} is:issue {q}:>={since}', '-f', 'per_page=1')['total_count'])
                          for q in ('created', 'closed'))
    except (RuntimeError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        ctx.log(f'backlog trend unavailable: {exc}')
        return ''
    net = opened - closed
    verdict = 'shrinking' if net < 0 else 'flat' if net == 0 else 'growing'
    return f'Backlog, last {days} days: {opened} opened, {closed} closed (net {net:+d}, {verdict})'


def not_on_board(ctx, issues, nodes, days=7):
    """Open issues opened in the last `days` days that are not on the board. Never raises."""
    since = time.strftime('%Y-%m-%d', time.gmtime(time.time() - days * 86400))
    have = {i['number'] for i in issues} | {
        (n.get('content') or {}).get('number') for n in nodes
        if ((n.get('content') or {}).get('repository') or {}).get('nameWithOwner') == ctx.repo}
    try:
        recent = ctx.gh('issue', 'list', '-R', ctx.repo, '--state', 'open', '--search', f'created:>={since}',
                        '--limit', '50', '--json', 'number,title,url') or []
    except (RuntimeError, ValueError, subprocess.SubprocessError) as exc:
        ctx.log(f'recent issues unavailable: {exc}')
        return []
    return [f'#{i["number"]} {i["title"][:70]} {i["url"]}'
            for i in sorted(recent, key=lambda i: i['number']) if i['number'] not in have]


def digest(ctx, weekly=None):
    """One message listing everything that waits on a person (stdout). Silent when nothing waits, except that
    on Mondays (`weekly`) the backlog lines are sent even then."""
    config, handle = ctx.config, ctx.config['handles'][0]
    logins = gp.bot_logins(config)
    waiting = {kind: [] for kind in DIGEST_ORDER}
    issues, _, nodes = gp.snapshot(config)
    offboard = not_on_board(ctx, issues, nodes)
    for issue in issues:
        if issue['state'] != 'OPEN' or issue['status'] != 'Your turn':
            continue
        n = issue['number']
        line = f'#{n} {issue["title"][:70]} ({age_days(issue.get("updatedAt"))}d) https://github.com/{ctx.repo}/issues/{n}'
        kind = gp.wait_kind(gp.comments_of(config, n), (), logins)[0]
        if kind in waiting:
            waiting[kind].append(line)
        elif not issue.get('prs'):  # a card with a PR is listed from the PR labels below
            waiting['unblock'].append(line + ' [no bot request found; a bot should have posted one]')
    seen = set()
    for label, key in (('needs-human:decision', 'decide'), ('needs-human:merge', 'merge')):
        for pr in ctx.gh('pr', 'list', '-R', ctx.repo, '--label', label, '--state', 'open',
                         '--json', 'number,title,url,updatedAt') or []:
            if pr['number'] in seen:
                continue
            seen.add(pr['number'])
            waiting[key].append(f'PR #{pr["number"]} {pr["title"][:70]} ({age_days(pr.get("updatedAt"))}d) {pr["url"]}')
    total = sum(len(v) for v in waiting.values())
    trend = backlog_trend(ctx)
    weekly = time.localtime().tm_wday == 0 if weekly is None else weekly
    lines = []
    if total or (weekly and (trend or offboard)):
        lines.append(f'[{ctx.repo}] ' + (f'{total} item(s) waiting on you' if total else 'nothing waiting on you'))
        if trend:
            lines += ['', trend]
        if offboard:
            lines += ['', f'Not on the board ({len(offboard)}, opened in the last 7 days): add the ones you want a bot '
                      'to handle'] + ['- ' + x for x in offboard[:10]]
            if len(offboard) > 10:
                lines.append(f'- ...and {len(offboard) - 10} more')
    hints = {'approve': f'reply `{handle} approve`, `revise: ...`, `discuss` or `reject` (owners only)',
             'unblock': f'reply `{handle} unblock: <what changed>`',
             'answer': f'reply `{handle} answer: 1A, 2 yes, ...` (or `answer: approve`)',
             'decide': f'read the latest bot comment on the PR, then reply `{handle} fix` (your decision below it) '
                       f'or `{handle} review`',
             'merge': 'review passed and checks are green: merge the PR'}
    for key, found in waiting.items():
        if found:
            lines += ['', f'{gp.WAITING_FOR[key]} ({len(found)}): {hints[key]}'] + ['- ' + x for x in found[:12]]
            if len(found) > 12:
                lines.append(f'- ...and {len(found) - 12} more (see the board)')
    if lines:
        print('\n'.join(lines), flush=True)
    return lines


# ---------------------------------------------------------------- entry point

# ---------------------------------------------------------------- Jira links (optional)

def jira_keys(projects, *texts):
    """Jira keys of the configured projects (ABC-123) in the texts, upper case, in order, without repeats."""
    pattern = r'\b(?:' + '|'.join(re.escape(p) for p in projects) + r')-[0-9]+\b'
    found = []
    for text in texts:
        for key in re.findall(pattern, text or '', re.I | re.ASCII):
            if key.upper() not in found:
                found.append(key.upper())
    return found


def normalize_title(text, projects=()):
    """A title reduced for matching: Jira key prefixes removed, lower case, words only."""
    text = text or ''
    for project in projects:
        text = re.sub(r'(?ai)\b' + re.escape(project) + r'-[0-9]+\s*[:\-]?\s*', '', text)
    return re.sub(r'[^a-z0-9]+', ' ', text.lower()).strip()


class JiraError(RuntimeError):
    """A failed Jira call; `status` is the HTTP status, or None when Jira was not reached. Never holds the token."""

    def __init__(self, text, status=None):
        super().__init__(text)
        self.status = status


def jira_token(env=None):
    """JIRA_PAT from the environment, else from $HERMES_HOME/.env (a cron job may not export it), stripped.
    Never logged: a value a token cannot hold (spaces, control characters) raises without showing it."""
    env = os.environ if env is None else env
    token = (env.get('JIRA_PAT') or '').strip()
    env_file = pathlib.Path(env.get('HERMES_HOME') or pathlib.Path.home() / '.hermes') / '.env'
    if not token and env_file.is_file():
        for line in env_file.read_text(encoding='utf-8', errors='replace').splitlines():
            m = re.match(r'\s*(?:export\s+)?JIRA_PAT\s*=\s*(.*)$', line)
            if m:
                token = m.group(1).strip().strip('"\'').strip()
                break
    if token and not re.fullmatch(r'[\x21-\x7e]+', token):
        raise ValueError('JIRA_PAT holds characters a token cannot contain (spaces, quotes or control characters)')
    return token or None


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Jira calls never follow a redirect: urllib would resend the Authorization header to the new host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_JIRA_OPENER = urllib.request.build_opener(_NoRedirect)


def jira_request(base, token, method, path, payload=None):
    """One Jira REST call (Jira Server / Data Center personal access token). Errors never include the token."""
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'Content-Type': 'application/json'})
    where = f'Jira {method} {path.split("?")[0]}'
    try:
        with _JIRA_OPENER.open(req, timeout=30) as response:
            text = response.read().decode('utf-8', 'replace')
            return json.loads(text) if text.strip() else None
    except urllib.error.HTTPError as exc:
        raise JiraError(f'{where} -> HTTP {exc.code}', exc.code) from None
    except urllib.error.URLError as exc:
        raise JiraError(f'{where}: Jira unreachable ({exc.reason})') from None
    except Exception as exc:  # anything else (a bad header value, bad JSON) may quote the request: drop its text
        raise JiraError(f'{where} failed ({type(exc).__name__})') from None


def jira_check(ctx):
    """`--jira-check`: is Jira configured, is the token valid, are the projects readable? Read-only."""
    jira = ctx.config.get('jira')
    if not jira:
        print('jira: not configured (set JIRA_BASE_URL and JIRA_PROJECTS, or "jira" in GH_PROJECT_CONFIG)')
        return 1
    token = jira_token()
    if not token:
        print(f'jira: {jira["base_url"]} configured for {jira["projects"]}, but no JIRA_PAT in the environment '
              'or $HERMES_HOME/.env')
        return 1
    me = jira_request(jira['base_url'], token, 'GET', '/rest/api/2/myself') or {}
    print(f'jira: authenticated as {me.get("name") or me.get("displayName")}')
    for project in jira['projects']:
        info = jira_request(jira['base_url'], token, 'GET', f'/rest/api/2/project/{project}') or {}
        print(f'jira: project {project} readable ({info.get("name")})')
    return 0


def jira_titles(base, token, projects):
    """{normalized summary: key} of every issue in the projects; a summary used twice never matches."""
    out, start = {}, 0
    jql = 'project in (' + ','.join(projects) + ') ORDER BY key'
    while True:
        page = jira_request(base, token, 'GET', '/rest/api/2/search?fields=summary&maxResults=100&startAt=%d&jql=%s' % (
            start, urllib.parse.quote(jql))) or {}
        issues = page.get('issues') or []
        for issue in issues:
            norm = normalize_title(issue['fields']['summary'], projects)
            out[norm] = None if norm in out else issue['key']
        start += len(issues)
        if not issues or start >= page.get('total', 0):
            return {k: v for k, v in out.items() if v}


JIRA_TITLES_TTL = 3600  # seconds the Jira summaries for title matching are reused


def cached_titles(ctx, base, token, projects):
    """jira_titles, kept in state for JIRA_TITLES_TTL so a keyless item does not re-read Jira on every run."""
    cache = ctx.state.get('jira_titles') or {}
    if cache.get('projects') == list(projects) and time.time() - cache.get('at', 0) < JIRA_TITLES_TTL:
        return cache.get('titles') or {}
    titles = jira_titles(base, token, projects)
    ctx.state['jira_titles'] = {'projects': list(projects), 'at': time.time(), 'titles': titles}
    return titles


def plain(text, limit=200):
    """Untrusted Jira or GitHub text for a link title or a bot comment: one line, at most `limit` characters, no
    `<`, `>` or backticks. Without `<` and `>` no hidden marker can be built (a bot comment's markers are trusted by
    every script); without backticks it fits in a code span (see `code`)."""
    text = re.sub(r'[<>`]', '', text or '')
    return re.sub(r'\s+', ' ', text).strip()[:limit]


def code(text, limit=200):
    """Untrusted text shown in a bot comment as inline code: no @mention, #N backlink, link or image renders."""
    text = plain(text, limit)
    return f'`{text}`' if text else '(none)'


def jira_sync(ctx):
    """Link open board issues and open PRs of this repository to the Jira issues they name, one way: the Jira issue
    gets an "implemented by" link to the GitHub item, the GitHub item one comment with the Jira link and status.
    Keys come from the title and body; with match_titles (summaries cached for an hour), an item without a key is matched to the one Jira issue
    with the same summary. Each link is made once (state `jira_linked`), at most MAX_JIRA per run. Statuses are
    not synced. Off unless Jira is configured; inactive (said once) without JIRA_PAT."""
    jira = ctx.config.get('jira')
    if not jira:
        return
    base, projects = jira['base_url'], jira['projects']
    token = jira_token()
    if not token:
        if not ctx.state.get('jira_unconfigured_reported'):
            ctx.say(f'jira: {base} is configured for {", ".join(projects)} but JIRA_PAT is not set; '
                    'Jira links are off until it is', loud=True)
            ctx.state['jira_unconfigured_reported'] = True
        return
    ctx.state.pop('jira_unconfigured_reported', None)
    done = ctx.state.setdefault('jira_linked', {})
    bodies = {i['number']: i.get('body') or '' for i in ctx.gh(
        'issue', 'list', '-R', ctx.repo, '--state', 'open', '--limit', '1000', '--json', 'number,body') or []}
    items = [(i['number'], i['title'], bodies.get(i['number'], ''),
              f'https://github.com/{ctx.repo}/issues/{i["number"]}', 'issue')
             for i in gp.snapshot(ctx.config)[0] if i.get('state') == 'OPEN']
    for pr in ctx.gh('pr', 'list', '-R', ctx.repo, '--state', 'open', '--limit', '100',
                     '--json', 'number,title,body,url') or []:
        items.append((pr['number'], pr['title'], pr.get('body') or '', pr['url'], 'PR'))
    titles = None
    logins = gp.bot_logins(ctx.config)
    for number, title, body, url, kind in items:
        keys = jira_keys(projects, title, body)
        if not keys and jira.get('match_titles'):
            titles = titles if titles is not None else cached_titles(ctx, base, token, projects)
            match = titles.get(normalize_title(title, projects))
            keys = [match] if match else []
        for key in keys:
            marker = f'{ctx.repo}#{number}:{key}'
            if marker in done:
                continue
            if ctx.jira_links >= MAX_JIRA:
                return
            try:
                issue = jira_request(base, token, 'GET', f'/rest/api/2/issue/{key}?fields=summary,status') or {}
            except JiraError as exc:
                if exc.status != 404:  # an outage or a bad token fails the step; the next run tries again
                    raise
                ctx.say(f'{kind} #{number}: {key} not usable ({exc})')
                done[marker] = 'unreadable'
                continue
            ctx.say(f'{kind} #{number} <-> {key}')
            ctx.jira_links += 1
            if ctx.dry:
                continue
            links = jira_request(base, token, 'GET', f'/rest/api/2/issue/{key}/remotelink') or []
            if not any((link.get('object') or {}).get('url') == url for link in links):
                jira_request(base, token, 'POST', f'/rest/api/2/issue/{key}/remotelink', {
                    'globalId': f'github:{url}', 'relationship': 'implemented by',
                    'object': {'url': url, 'title': f'GitHub {ctx.repo}#{number}: {plain(title)}'}})
            own = re.compile(r'<!--\s*jira-link\s+' + re.escape(key) + r'\s*-->')
            if not any(gp.by_agent(c, logins) and own.search(c.get('body') or '')
                       for c in gp.comments_of(ctx.config, number)):
                fields = issue.get('fields') or {}
                post_comment(ctx, number, f'🤖 **No action needed: linked Jira issue {key}**\n\n'
                             f'- [{key}]({base}/browse/{key}): {code(fields.get("summary"))} '
                             f'(status {code((fields.get("status") or {}).get("name"), 40)})\n\n'
                             f'<!-- jira-link {key} -->')
            done[marker] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def run(ctx, only=None):
    """All steps (or one); returns (steps run, failure lines). A failure is logged here and printed by main."""
    failures, ran = [], 0
    moved = {}
    plan = [('intake', lambda: intake(ctx, only='inbox')), ('intake', lambda: intake(ctx, only='backlog')),
            ('reconcile', lambda: moved.update(reconcile(ctx) or {})), ('waiting', lambda: waiting_for(ctx, moved))]
    if ctx.config.get('jira'):  # an optional step only counts (for the stopped alert) where it is configured
        plan.append(('jira', lambda: jira_sync(ctx)))
    for name, step in plan:
        if only not in (None, name):
            continue
        ran += 1
        try:
            step()
        except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
            failures.append(f'[{ctx.repo}] {name} FAILED: {exc}')
            ctx.log(failures[-1])
    return ran, failures


def report(ctx, ran, failures):
    """Print what a person must see about failures: every step failing is one plain alert (repeated hourly, then
    one line when the sync runs again); a single failing step or part of one (ctx.failures) repeats its line at
    most once per 6 hours."""
    if ctx.dry:
        lines = failures + ctx.failures
    else:
        health = ctx.state_dir / 'health'
        down = bool(failures) and len(failures) == ran
        status = (pipeline_runtime.job_down(health, f'Board sync ({ctx.repo})', '; '.join(failures)) if down
                  else pipeline_runtime.job_up(health, f'Board sync ({ctx.repo})'))
        lines = status + pipeline_runtime.fresh_lines(health, 'errors', ([] if down else failures) + ctx.failures)
    if lines:
        print('\n'.join(lines), flush=True)


def main(argv=None, config=None):
    import argparse
    parser = argparse.ArgumentParser(prog='board-sync.py', description=(__doc__ or '').split('\n')[0])
    parser.add_argument('--dry', action='store_true', help='print intended changes; write nothing')
    parser.add_argument('--only', choices=STEPS)
    parser.add_argument('--digest', action='store_true',
                        help='print the owner digest (everything waiting on a person) instead of syncing; read-only')
    parser.add_argument('--jira-check', action='store_true',
                        help='check the Jira settings, token and projects instead of syncing; read-only')
    args = parser.parse_args(argv)
    config = gp.resolve_project(dict(gp.load_config() if config is None else config))
    gp.require_owners(config)
    ctx = Context(config, args.dry)
    if args.digest:
        digest(ctx)
        return 0
    if args.jira_check:
        return jira_check(ctx)
    started = time.time()
    try:
        with gp.file_lock(gp.lock_path(config), wait=0 if args.dry else SYNC_LOCK_WAIT):
            try:
                ran, failures = run(ctx, args.only)
            finally:
                ctx.save_state()
    except gp.LockBusy:
        print(f'[{config["repo"]}] board sync FAILED to start: another run held the board lock for over '
              f'{SYNC_LOCK_WAIT} s. Nothing changed; the next run retries.', flush=True)
        return 1
    report(ctx, ran, failures)
    ctx.log(f'[{config["repo"]}] run done in {time.time() - started:.0f} s'
            + ('; FAILED steps above' if failures else ''))
    return 1 if failures else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print('board-sync: ' + str(exc), file=sys.stderr)
        sys.exit(1)
