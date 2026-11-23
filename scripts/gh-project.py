#!/usr/bin/env python3
"""GitHub Project v2 tracker adapter for the delivery pipeline, strictly scoped to one repository.

Generic port of gm-agent-pipeline `pipeline/gem-project.py` (Daniel Gehriger), without its instance/runtime layer.
Script-only (no LLM). It prints JSON on success; on failure it prints `gh-project: <reason>` to stderr and exits 1.

    gh-project.py list                         board items of the configured repository (JSON array)
    gh-project.py prs                          open PRs linked to those items (JSON array of numbers)
    gh-project.py check                        field schema + item counts (JSON object)
    gh-project.py move N STATUS [--comment TEXT] [--expect STATUS] [--ack-reply COMMENT_ID]
    gh-project.py set N FIELD VALUE [--comment TEXT]      (FIELD may be `Waiting for`; VALUE "" clears it)
    gh-project.py fields [--dry]               create/refresh the board fields and Status options
    gh-project.py labels [--dry]               create/rename/refresh the workflow labels on the repository
    gh-project.py migrate-your-turn [--dry] [--state PATH]   one-off: old person statuses -> Your turn

Statuses, fields and options have an internal name (used by the dispatcher, skills and markers) and a board name
(what people see). Every command accepts either; `list` prints internal names.

Configuration: environment variables override the JSON file named by GH_PROJECT_CONFIG (keys in brackets).
  PIPELINE_REPO            owner/repo whose issues are the backlog [repo] (required)
  GH_PROJECT_OWNER         user or organization that owns the project [project_owner] (default: repo owner)
  GH_PROJECT_NUMBER        project number [project_number] (required)
  GH_PROJECT_ID            project node id [project_id] (optional; resolved from owner + number otherwise)
  GH_BIN                   GitHub CLI binary [gh_bin] (default gh)
  PIPELINE_OWNERS          owner logins [owners]: gate decisions (approve, revise, discuss, reject) come from them
  PIPELINE_RESPONDERS      extra logins whose answer, unblock and close/keep replies count [responders] (the
                           item's assignees always count)
  PR_AGENT_HANDLE          command handles [handles] (default /devbot; `@name` also accepted)
  PIPELINE_BOT_LOGINS      logins the bots post as [bot_logins] (default: the '@' handles, the owners when
                           PIPELINE_SHARED_ACCOUNT=1, else the account `gh` is logged in as)
  PIPELINE_SHARED_ACCOUNT  1 when the owner and the bots post from the same login [shared_account]
  PIPELINE_BRANCH_TEMPLATE item branch, links open PRs to cards [branch_template] (default item/{n})
  PIPELINE_WIP             In progress limit shown in the Up next description [wip] (default 2)
  PIPELINE_PARK_LABEL      label that parks a `discuss` reply [park_label] (default needs-human:discussion)
  BOARD_SYNC_STATE         board-sync state and lock directory [state_dir] (default $HERMES_HOME/state/board-sync)

Guards (the dispatcher and the bot sessions rely on them):
  - `--expect S` is compare-and-set: when the card is no longer in S nothing changes and the error says `is no longer`.
  - A move into `Your turn`, `Done` or `Canceled` needs `--comment` (posted first, starting with 🤖, read back).
  - `Up next` needs `--ack-reply ID`: a reply on this issue from the owner (approve/revise) or an owner, assignee or
    responder (unblock) that is not bot text. `Later` (Icebox) and `Bot approvals` (Autonomy) are owner-only.
  - `Canceled` needs the latest reply to be `<handle> reject`, or the issue closed as not planned.
  - A card in the PR stage moves to `Done` only once its issue is closed by a merged PR.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from contextlib import contextmanager
from typing import Any

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import commands  # noqa: E402  (scripts/commands.py, the shared command parser)

# ---------------------------------------------------------------- vocabulary (internal names)

REQUIRED = {
    # Board column order. `Your turn` is the one column for every card that waits on a person; the display-only
    # `Waiting for` field says what the person does. Bots never read `Waiting for`. `Backlog` holds open issues
    # that nobody put on the board for a bot: no bot reads or moves it; a person moves a card to Inbox.
    'Status': ['Backlog', 'Inbox', 'Ready', 'Up next', 'In progress', 'Your turn', 'In review', 'Icebox', 'Done',
               'Canceled'],
    'Priority': ['P0', 'P1', 'P2', 'P3'],
    'Track': ['fast-path', 'standard-implementation', 'analysis-spike', 'docs-process'],
    'Kind': ['bug', 'feature', 'chore', 'docs', 'hardening', 'research', 'debt', 'idea'],
    'Origin': ['human-request', 'plan-follow-up', 'review-finding', 'agent-observation', 'external-issue'],
    'Stage': ['Design', 'Plan', 'Execute', 'Research', 'PR'],
    'Autonomy': ['gated', 'auto'],
}
# Board names. The adapter translates at the GitHub boundary and accepts either name.
BOARD_FIELD = {'Track': 'Size', 'Origin': 'Source', 'Autonomy': 'Bot approvals'}
BOARD_OPTION = {
    # Prefix = who acts next: 🧑 a person, 🤖 a bot, none = nobody (Later, Done, Canceled).
    'Status': {'Backlog': '🧑 Backlog', 'Inbox': '🤖 Inbox', 'Ready': '🧑 📋 Ready to schedule', 'Up next': '🤖 Up next',
               'In progress': '🤖 In progress', 'Your turn': '🧑 Your turn', 'In review': '🤖 In review',
               'Icebox': 'Later'},
    'Track': {'fast-path': 'small fix', 'standard-implementation': 'needs design',
              'analysis-spike': 'investigation', 'docs-process': 'docs'},
    'Origin': {'human-request': 'requested', 'plan-follow-up': 'from a plan', 'review-finding': 'from a review',
               'agent-observation': 'bot noticed', 'external-issue': 'external'},
    'Autonomy': {'gated': 'ask at each step', 'auto': 'proceed alone'},
}
_FIELD_FROM_BOARD = {board: old for old, board in BOARD_FIELD.items()}
_OPTION_FROM_BOARD = {field: {board: old for old, board in options.items()} for field, options in BOARD_OPTION.items()}
HUMAN_STATUSES = ('Your turn',)
BOT_STATUSES = ('Inbox', 'Up next', 'In progress', 'In review')
STATUS_COLORS = {'Backlog': 'GRAY', 'Inbox': 'BLUE', 'Ready': 'YELLOW', 'Up next': 'BLUE', 'In progress': 'BLUE',
                 'Your turn': 'ORANGE', 'In review': 'BLUE', 'Icebox': 'GRAY', 'Done': 'GREEN', 'Canceled': 'GRAY'}
OPTION_COLORS = {'P0': 'RED', 'P1': 'ORANGE', 'P2': 'YELLOW', 'P3': 'GRAY'}
PARKED_STATUS = 'Icebox'  # internal name of the board's `Later` column
# No bot acts on a card in these statuses, nor on the PRs it carries or links.
NO_BOT_STATUSES = frozenset({'Backlog', PARKED_STATUS, 'Done', 'Canceled'})

# Display-only single-select `Waiting for`: what the person in `Your turn` does. kind -> board option.
WAITING_FIELD = 'Waiting for'
WAITING_FOR = {'answer': '💬 answer', 'approve': '👍 approve', 'unblock': '🛠️ unblock',
               'decide': '⚖️ decide on PR', 'merge': '🔀 merge PR'}
WAITING_FOR_COLOR = 'ORANGE'
# Not a kind: board sync shows it once a person has replied in a way the dispatcher acts on.
WAITING_FOR_BOT = "⏳ Bot's turn"
WAITING_FOR_BOT_COLOR = 'BLUE'
WAITING_FOR_DESCRIPTIONS = {
    '💬 answer': 'Answer the numbered questions with `<handle> answer: ...`. A bot takes the card back on its next run.',
    '👍 approve': 'Reply approve | revise: ... | discuss | reject to the latest bot comment.',
    '🛠️ unblock': 'A bot is stuck. Reply `<handle> unblock: <what changed>` to the latest bot comment.',
    '⚖️ decide on PR': 'Answer the question in the latest bot comment on the PR.',
    '🔀 merge PR': 'Review passed and checks are green. Merge the PR.',
    WAITING_FOR_BOT: 'You replied; a bot picks this card up on its next run. Nothing to do.',
}

BOARD_DESCRIPTIONS = {
    'Size': 'How much process the item needs',
    'small fix': 'Clear, local change; no design step',
    'needs design': 'Design and plan, approved by you, before coding',
    'investigation': 'Measure or research; the result is findings, not code',
    'docs': 'Documentation or process change',
    'Source': 'Where the item came from',
    'requested': 'Asked for by a person',
    'from a plan': 'Follow-up recorded in an approved plan',
    'from a review': 'Found during a review',
    'bot noticed': 'Noticed by a bot while working on something else',
    'external': 'Reported by another team or project',
    'Bot approvals': 'Does the bot stop for your approval at each step?',
    'ask at each step': 'The bot waits for your approval after design and plan (default)',
    'proceed alone': 'The bot continues without approval, except for safety, scope or merge decisions',
}
# Status descriptions show as the column's hover text; the first words say who acts next.
STATUS_DESCRIPTIONS = {
    'Backlog': 'Not picked up by any bot. Move it to 🤖 Inbox when you want a bot to triage it.',
    'Inbox': 'A bot triages new items on its next run. No action needed.',
    'Ready': 'Triaged and clear. When you want it done, move it to 🤖 Up next (or to Later).',
    'Up next': 'Queued: a bot starts as soon as one is free ({wip} run at once). No action needed.',
    'In progress': 'A bot is working on it. No action needed.',
    'Your turn': 'Your turn. "Waiting for" on the card says what: answer the questions, approve the step, '
                 'unblock the bot, decide on the PR, or merge it. The latest bot comment has the exact reply.',
    'In review': 'A PR is open; the review bot and the fix bot are working on it. No action needed.',
    'Icebox': 'Parked; the bots leave it alone.',
    'Done': 'Completed: merged PR, or closed as completed.',
    'Canceled': 'Will not be done: an explicit reject, or the issue was closed as not planned.',
}

# PR workflow labels (generic subset of gm-agent-pipeline's set). `review-bot:` / `fix-bot:` (grey): a bot acts
# next. `needs-human:` (orange): a person acts next; the comment that added it says what to do.
BOT_COLOR, HUMAN_COLOR = 'cfd3d7', 'f28c28'
PROPOSE_LABEL = 'needs-human:approve-close'
WORKFLOW_LABELS = [
    ('review-bot:queued', BOT_COLOR, 'Automation: the review bot will check the latest commit. No action needed.'),
    ('review-bot:running', BOT_COLOR, 'Automation: the review bot is checking the latest commit. No action needed.'),
    ('fix-bot:queued', BOT_COLOR, 'Automation: the review found issues; the fix bot will fix them. No action needed.'),
    ('fix-bot:owns-branch', BOT_COLOR, "Automation pushes to this branch. Don't push by hand; remove this label to take over."),
    ('needs-human:merge', HUMAN_COLOR, 'Review passed, checks green. Merge the PR.'),
    ('needs-human:decision', HUMAN_COLOR, 'A person must decide. The latest bot comment says what, with a recommendation.'),
    ('needs-human:discussion', HUMAN_COLOR, 'Bots paused for a live discussion. Remove the label to resume.'),
    (PROPOSE_LABEL, HUMAN_COLOR, "Bot proposes closing this issue. Reply '{handle} close' or '{handle} keep'."),
]
# Pre-rename name -> current name. Renaming a label keeps it on every issue and PR.
LEGACY_LABELS = {'pr:ready-review': 'review-bot:queued', 'pr:in-review': 'review-bot:running',
                 'pr:re-review': 'fix-bot:queued', 'pr:babysat': 'fix-bot:owns-branch',
                 'pr:ready-merge': 'needs-human:merge', 'pr:escalated': 'needs-human:decision',
                 'pipeline:discuss': 'needs-human:discussion', 'pipeline:close-proposed': PROPOSE_LABEL}

# ---------------------------------------------------------------- markers and replies

# Automation text on a shared owner/agent account: an HTML marker, a 🤖 first line, or a claim line.
AGENT_MARK = re.compile(r"<!--|\A\s*🤖|^\s*(?:🤖\s*)?(work|babysit|fix-bot):\s", re.M)
GATE_RE = re.compile(r"<!--\s*gate stage=(\w+)((?:\s+\w+=\S+)*)\s*-->")
TRIAGE_RE = re.compile(r"<!--\s*triage outcome=(ready|clarify|left)\b[^>]*-->")  # `left` is historical, read only
# What a bot's marker says it waits for; the newest marker wins. Close proposals are deliberately absent.
WAIT_MARKERS = [
    (GATE_RE, 'approve'),
    (re.compile(r"<!--\s*(?:dispatcher )?blocked\b"), 'unblock'),
    (re.compile(r"<!--\s*triage outcome=clarify\b[^>]*-->"), 'answer'),
]
# Reply verbs by kind of wait; disjoint, so a reply answers exactly one question. close/keep answer close proposals.
REPLY_VERBS = {'answer': ('answer',), 'approve': ('approve', 'revise', 'discuss', 'reject'), 'unblock': ('unblock',)}
RESUME_VERBS = ('approve', 'revise', 'unblock')   # replies that may queue a card in Up next (--ack-reply)
OWNER_ONLY_VERBS = ('approve', 'revise', 'reject', 'discuss')   # gate replies: owner only
LEGACY_PARK = 'pipeline:discuss'


def bot_body(body):
    """Every comment the automation posts starts with the bot emoji."""
    return body if body.lstrip().startswith('🤖') else '🤖 ' + body


def _logins(raw):
    items = raw.replace(',', ' ').split() if isinstance(raw, str) else list(raw or ())
    return tuple(dict.fromkeys(i.strip().lstrip('@').lower() for i in items if i and i.strip().lstrip('@')))


def _flag(value):
    return str(value).strip().lower() in ('1', 'true', 'yes', 'on') if value not in (None, '') else False


def load_config(env=None):
    """Configuration from GH_PROJECT_CONFIG (a JSON object) overridden by the environment."""
    env = os.environ if env is None else env
    data = {}
    if env.get('GH_PROJECT_CONFIG'):
        data = json.loads(pathlib.Path(env['GH_PROJECT_CONFIG']).expanduser().read_text(encoding='utf-8'))
        if not isinstance(data, dict):
            raise ValueError('GH_PROJECT_CONFIG must hold a JSON object')

    def pick(key, var, default=None):
        value = env.get(var)
        return value if value not in (None, '') else data.get(key, default)

    repo = str(pick('repo', 'PIPELINE_REPO', '') or '')
    if not re.fullmatch(r'[\w.-]+/[\w.-]+', repo):
        raise ValueError('PIPELINE_REPO (or "repo" in GH_PROJECT_CONFIG) must be OWNER/REPO')
    number = pick('project_number', 'GH_PROJECT_NUMBER')
    if not str(number or '').isdigit():
        raise ValueError('GH_PROJECT_NUMBER (or "project_number" in GH_PROJECT_CONFIG) must be the project number')
    home = pathlib.Path(env.get('HERMES_HOME') or pathlib.Path.home())
    template = str(pick('branch_template', 'PIPELINE_BRANCH_TEMPLATE', 'item/{n}'))
    if template.count('{n}') != 1:
        raise ValueError('PIPELINE_BRANCH_TEMPLATE must contain {n} exactly once')
    return {
        'repo': repo,
        'project_owner': str(pick('project_owner', 'GH_PROJECT_OWNER', repo.split('/')[0])),
        'project_number': int(str(number)),
        'project_id': pick('project_id', 'GH_PROJECT_ID'),
        'project_title': data.get('project_title'),
        'gh_bin': str(pick('gh_bin', 'GH_BIN', 'gh')),
        'owners': _logins(pick('owners', 'PIPELINE_OWNERS', ())),
        'responders': _logins(pick('responders', 'PIPELINE_RESPONDERS', ())),
        'handles': commands.normalize_handles(pick('handles', 'PR_AGENT_HANDLE', '')),
        'bot_logins': _logins(pick('bot_logins', 'PIPELINE_BOT_LOGINS', ())),
        'shared_account': _flag(pick('shared_account', 'PIPELINE_SHARED_ACCOUNT')),
        'branch_template': template,
        'wip': int(pick('wip', 'PIPELINE_WIP', 2)),
        'park_label': str(pick('park_label', 'PIPELINE_PARK_LABEL', 'needs-human:discussion')),
        'state_dir': str(pathlib.Path(str(pick('state_dir', 'BOARD_SYNC_STATE', home / 'state' / 'board-sync')))
                         .expanduser()),
        'intake': str(pick('intake', 'BOARD_SYNC_INTAKE', 'bot-created')),
    }


def require_owners(config):
    if not config.get('owners'):
        raise ValueError('PIPELINE_OWNERS (or "owners" in GH_PROJECT_CONFIG) is required for this operation')
    return config['owners']


# ---------------------------------------------------------------- name translation

def internal_field(name):
    """Board or internal field name -> internal field name (case-insensitive)."""
    for key in list(REQUIRED) + list(_FIELD_FROM_BOARD) + [WAITING_FIELD]:
        if key.lower() == (name or '').lower():
            return _FIELD_FROM_BOARD.get(key, key)
    return name


def internal_value(field, value):
    """Board or internal option name -> internal option name. `Waiting for` also accepts a kind (approve, ...)."""
    field = internal_field(field)
    if field == WAITING_FIELD:
        return WAITING_FOR.get(value, value)
    return _OPTION_FROM_BOARD.get(field, {}).get(value, value)


def board_value(field, value):
    return BOARD_OPTION.get(internal_field(field), {}).get(value, value)


def in_pr_stage(item):
    """The PR stage: In review, or Your turn with a linked open PR (a merged PR moves it to Done)."""
    return item.get('status') == 'In review' or (item.get('status') == 'Your turn' and bool(item.get('prs')))


# ---------------------------------------------------------------- GitHub plumbing

def gh(config, *args) -> Any:
    slurp = '--slurp' in args
    args = [arg for arg in args if arg != '--slurp']
    result = subprocess.run([config['gh_bin'], *args], text=True, encoding='utf-8',
                            capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or 'GitHub CLI call failed')
    text = result.stdout.strip()
    if slurp:
        pages, decoder = [], json.JSONDecoder()
        while text:
            page, end = decoder.raw_decode(text)
            if not isinstance(page, list):
                raise ValueError('Expected paginated GitHub REST arrays')
            pages.append(page)
            text = text[end:].lstrip()
        return pages
    return json.loads(text) if text else None


def graphql(config, query, **variables) -> Any:
    args = ['api', 'graphql', '-f', 'query=' + query]
    for key, val in variables.items():
        # -F sends integers as numbers (Int! variables); -f always sends a string.
        args.extend(('-F', f'{key}={val}') if isinstance(val, int) and not isinstance(val, bool)
                    else ('-f', f'{key}={val}'))
    response = gh(config, *args) or {}
    if response.get('errors'):
        raise RuntimeError(json.dumps(response['errors']))
    return response['data']


def comments_of(config, number):
    pages = gh(config, 'api', '--paginate', '--slurp', f"repos/{config['repo']}/issues/{int(number)}/comments?per_page=100")
    return [c for page in pages or [] for c in page]


def issue_of(config, number):
    return gh(config, 'api', f"repos/{config['repo']}/issues/{int(number)}") or {}


PROJECT_QUERY = '''query($login:String!, $number:Int!) {repositoryOwner(login:$login) {
 ... on User {projectV2(number:$number) {id title}} ... on Organization {projectV2(number:$number) {id title}}}}'''


def resolve_project(config):
    """Fill in project_id (and the title the snapshot checks) from GH_PROJECT_OWNER + GH_PROJECT_NUMBER."""
    if config.get('project_id'):
        return config
    owner = graphql(config, PROJECT_QUERY, login=config['project_owner'], number=int(config['project_number']))
    project = ((owner or {}).get('repositoryOwner') or {}).get('projectV2')
    if not project or not project.get('id'):
        raise RuntimeError(f"project {config['project_owner']}#{config['project_number']} not found or not accessible")
    config['project_id'] = project['id']
    config.setdefault('project_title', None)
    config['project_title'] = config['project_title'] or project.get('title')
    return config


def bot_logins(config):
    """Logins whose markers the tools trust: configured bot logins, '@' handles, the owners on a shared account;
    otherwise the account `gh` is logged in as (resolved once)."""
    if config.get('_bot_logins') is None:
        def whoami():
            try:
                return (gh(config, 'api', 'user') or {}).get('login') or ''
            except (RuntimeError, ValueError, OSError):
                return ''
        config['_bot_logins'] = commands.bot_logins(
            config.get('bot_logins') or (), config.get('handles') or (), config.get('owners') or (),
            bool(config.get('shared_account')), whoami=whoami)
    return config['_bot_logins']


# ---------------------------------------------------------------- board reads

QUERY = '''query($id:ID!, $after:String) {node(id:$id) {
 ... on ProjectV2 {id title items(first:100, after:$after) {
  totalCount pageInfo {hasNextPage endCursor} nodes {id isArchived
   fieldValues(first:100) {pageInfo {hasNextPage} nodes {
    __typename ... on ProjectV2ItemFieldSingleSelectValue {name field {... on ProjectV2SingleSelectField {name}}}
   }}
   content {__typename
    ... on Issue {number title state updatedAt repository {nameWithOwner}
     closedByPullRequestsReferences(first:100, includeClosedPrs:true) {
      pageInfo {hasNextPage} nodes {number state repository {nameWithOwner}}
     }}
    ... on PullRequest {number state repository {nameWithOwner}}
   }
  }
 }}}}'''

OPEN_PRS_QUERY = '''query($owner:String!, $name:String!) {repository(owner:$owner, name:$name) {
 pullRequests(states:OPEN, first:100) {pageInfo {hasNextPage}
  nodes {number headRefName isCrossRepository headRepositoryOwner {login}}}}}'''

FIELDS_QUERY = '''query($id:ID!) {node(id:$id) {... on ProjectV2 {id fields(first:100) {totalCount nodes {
 ... on ProjectV2FieldCommon {id name dataType}
 ... on ProjectV2SingleSelectField {options {id name color description}}}}}}}'''


def project_fields(config):
    project = graphql(config, FIELDS_QUERY, id=config['project_id'])['node']
    if not project or project.get('id') != config['project_id']:
        raise RuntimeError('Unexpected or inaccessible project identity')
    nodes = [field for field in project['fields']['nodes'] if field]
    if len(nodes) != project['fields']['totalCount']:
        raise RuntimeError('Project field listing was truncated')
    return nodes


def read_fields(config):
    """Single-select fields keyed by internal name; each option also carries its internal name."""
    fields = {}
    for field in project_fields(config):
        key = internal_field(field['name'])
        if (key in REQUIRED or key == WAITING_FIELD) and field.get('options') is not None and key not in fields:
            fields[key] = {**field, 'options': [{**opt, 'internal': internal_value(key, opt['name'])}
                                                for opt in field.get('options', [])]}
    for name, required in REQUIRED.items():
        if name not in fields or not set(required).issubset({opt['internal'] for opt in fields[name]['options']}):
            raise RuntimeError(f'Project field schema does not satisfy contract: {name} (run `gh-project.py fields`)')
    return fields


def snapshot(config):
    nodes, cursor, expected = [], None, None
    while True:
        variables = {'id': config['project_id']}
        if cursor:
            variables['after'] = cursor
        project = graphql(config, QUERY, **variables)['node']
        if (not project or project.get('id') != config['project_id']
                or (config.get('project_title') and project.get('title') != config['project_title'])):
            raise RuntimeError('Unexpected or inaccessible project identity')
        page = project['items']
        expected = page['totalCount'] if expected is None else expected
        nodes.extend(page['nodes'])
        if not page['pageInfo']['hasNextPage']:
            break
        cursor = page['pageInfo']['endCursor']
    if len(nodes) != expected or len({item['id'] for item in nodes}) != len(nodes):
        raise RuntimeError('Incomplete or concurrently changed project; retry next tick')
    issues, prs = [], set()
    for item in nodes:
        if item.get('isArchived'):
            continue
        content = item.get('content') or {}
        if (item.get('fieldValues') or {}).get('pageInfo', {}).get('hasNextPage'):
            raise RuntimeError('Truncated project item fields')
        if (content.get('closedByPullRequestsReferences') or {}).get('pageInfo', {}).get('hasNextPage'):
            raise RuntimeError('Truncated linked PR list; refusing partial scope')
        issue, linked = normalize(item, config['repo'])
        if issue:
            issues.append(issue)
        prs.update(linked)
    prs.update(link_branch_prs(config, issues))
    return issues, sorted(prs), nodes


def link_branch_prs(config, issues):
    """Link open same-repository PRs on an item branch (branch_template) to their board issue.

    A plan-stage PR says `Refs #N`, so GitHub reports no closing reference; the item branch is the link."""
    owner, name = config['repo'].split('/', 1)
    page = graphql(config, OPEN_PRS_QUERY, owner=owner, name=name)['repository']['pullRequests']
    if page['pageInfo']['hasNextPage']:
        raise RuntimeError('Truncated open PR list; refusing partial scope')
    template = config.get('branch_template') or 'item/{n}'
    by_branch = {template.replace('{n}', str(issue['number'])): issue for issue in issues}
    linked = set()
    for pr in page['nodes']:
        issue = by_branch.get(pr.get('headRefName'))
        if (not issue or issue['status'] in NO_BOT_STATUSES or pr.get('isCrossRepository')
                or ((pr.get('headRepositoryOwner') or {}).get('login') or '').lower() != owner.lower()):
            continue
        issue['prs'] = sorted(set(issue['prs']) | {pr['number']})
        issue['pr_stage'] = in_pr_stage(issue)
        linked.add(pr['number'])
    return linked


def item_values(raw):
    """Internal field name -> internal value of a raw board item."""
    return {internal_field(v['field']['name']): internal_value(v['field']['name'], v['name'])
            for v in (raw.get('fieldValues') or {}).get('nodes', [])
            if v.get('__typename') == 'ProjectV2ItemFieldSingleSelectValue' and v.get('field')}


def stored_value(raw, field):
    """A raw item's value for `field` exactly as the board stores it ('' when empty)."""
    for v in (raw.get('fieldValues') or {}).get('nodes', []):
        if (v.get('__typename') == 'ProjectV2ItemFieldSingleSelectValue'
                and internal_field((v.get('field') or {}).get('name', '')) == field):
            return v.get('name') or ''
    return ''


def normalize(item, repo):
    content = item.get('content') or {}
    if (content.get('repository') or {}).get('nameWithOwner') != repo:
        return None, set()
    fields = {key.lower(): value for key, value in item_values(item).items()}
    if content.get('__typename') == 'PullRequest':
        if fields.get('status') in NO_BOT_STATUSES:
            return None, set()
        return None, {content['number']} if content.get('state') == 'OPEN' else set()
    if content.get('__typename') != 'Issue':
        return None, set()
    if fields.get('status') == PARKED_STATUS:
        # Later cards are invisible to every bot, together with their PRs.
        return None, set()
    links = (content.get('closedByPullRequestsReferences') or {}).get('nodes', [])
    links = [pr for pr in links if (pr.get('repository') or {}).get('nameWithOwner') == repo]
    result = {'number': content['number'], 'title': content['title'],
              'updatedAt': content.get('updatedAt'), 'state': content.get('state'),
              'item_id': item['id'], 'status': fields.get('status', 'Inbox'),
              'stage': fields.get('stage', ''), 'track': fields.get('track', ''),
              'priority': fields.get('priority', ''), 'autonomy': fields.get('autonomy', 'gated'),
              'waiting_for': fields.get('waiting for', ''),
              'prs': sorted(pr['number'] for pr in links if pr.get('state') == 'OPEN')}
    if result['status'] in NO_BOT_STATUSES:
        result['prs'] = []
        return result, set()
    result['pr_stage'] = in_pr_stage(result)
    # Closed without a merged closing PR is not the T17 completion.
    if result['state'] == 'CLOSED' and not any(pr.get('state') == 'MERGED' for pr in links):
        result['state'] = 'CLOSED_WITHOUT_MERGE'
    return result, {pr['number'] for pr in links if pr.get('state') == 'OPEN'}


def current_item(config, number):
    issues, _, nodes = snapshot(config)
    matches = [item for item in issues if item['number'] == number]
    if len(matches) != 1:
        raise ValueError(f"Issue #{number} must occur exactly once on the board for {config['repo']}")
    raw = next(item for item in nodes if item['id'] == matches[0]['item_id'])
    return matches[0], raw


# ---------------------------------------------------------------- replies and kinds of wait (pure)

def by_agent(comment, logins):
    return ((comment.get('user') or {}).get('login') or '').lower() in logins


def human_comment(comment, people):
    """Written by one of `people` and not automation text (shared-account safe)."""
    return (((comment.get('user') or {}).get('login') or '').lower() in people
            and not AGENT_MARK.search(comment.get('body') or ''))


def parse_reply(comment, people, handles):
    """(verb, rest) for a human reply `<handle> <verb>[: rest]` from one of `people`, else None."""
    if not comment or not human_comment(comment, people):
        return None
    found = commands.parse(comment.get('body') or '', handles)
    return (found[1], found[2]) if found else None


def review_status(label_sets):
    """'decide' | 'merge' (a person's turn; decide wins) or 'In review', from the labels of an item's open PRs."""
    names = {name for labels in label_sets for name in labels}
    if any(n.startswith('needs-human:') and n != 'needs-human:merge' for n in names) or 'pr:escalated' in names:
        return 'decide'
    if names & {'needs-human:merge', 'pr:ready-merge'}:
        return 'merge'
    return 'In review'


def wait_kind(comments, label_sets=(), logins=()):
    """(kind, anchor comment or None) for a card waiting on a person.

    kind is 'approve' | 'unblock' | 'answer' | 'decide' | 'merge' | None. PR labels win; otherwise the newest marker
    posted by a bot login decides (nobody else can forge one). A newer triage `ready` (or historical `left`) ends an
    older clarify question. Close proposals never count."""
    if label_sets:
        status = review_status(label_sets)
        if status in ('decide', 'merge'):
            return status, None
    for c in reversed(comments):
        if not by_agent(c, logins):
            continue
        t = TRIAGE_RE.search(c.get('body') or '')
        if t and t.group(1) != 'clarify':
            return None, None
        for rx, kind in WAIT_MARKERS:
            if rx.search(c.get('body') or ''):
                return kind, c
    return None, None


def responders(config, issue=None):
    """Owners, configured responders and the issue's assignees (lower case)."""
    return tuple(dict.fromkeys((*config.get('owners', ()), *config.get('responders', ()),
                                *[((a or {}).get('login') or '').lower() for a in (issue or {}).get('assignees') or []])))


def bot_turn(config, comments, label_sets=(), issue=lambda: {}):
    """(kind, True when a person already replied so that a bot will act on it). The newest human comment after the
    wait anchor must carry a verb for that kind of wait (gate replies from an owner only). `discuss` and a parked
    card stay with the person; PR-label waits (decide, merge) never count. `issue()` is fetched only when needed."""
    kind, anchor = wait_kind(comments, label_sets, bot_logins(config))
    if anchor is None or kind not in REPLY_VERBS:
        return kind, False
    data = issue() or {}
    labels = {(l or {}).get('name') for l in data.get('labels') or []}
    if kind == 'approve' and labels & {config.get('park_label') or 'needs-human:discussion', LEGACY_PARK}:
        return kind, False
    people = tuple(config.get('owners', ())) if kind == 'approve' else responders(config, data)
    newest = next((c for c in reversed(comments) if c['id'] > anchor['id'] and human_comment(c, people)), None)
    reply = parse_reply(newest, people, config['handles']) if newest else None
    return kind, bool(reply and reply[0] in REPLY_VERBS[kind] and reply[0] != 'discuss')


def reply_menu(kind, handle):
    if kind == 'unblock':
        return f'`{handle} unblock: <what changed>`'
    if kind == 'answer':
        return f'`{handle} answer: <your answers>`'
    return f'`{handle} approve`, `{handle} revise: <changes>`, `{handle} discuss` or `{handle} reject`'


# ---------------------------------------------------------------- writes

def verify_ack_reply(config, number, comment_id):
    """A reply a bot has read may queue its item in Up next. Only a human comment on this issue whose first line is
    `<handle> approve|revise|unblock` qualifies (approve/revise from an owner), so no bot session can schedule work."""
    comment = gh(config, 'api', f"repos/{config['repo']}/issues/comments/{int(comment_id)}") or {}
    verb = None
    if comment.get('issue_url', '').endswith(f'/issues/{int(number)}'):
        reply = parse_reply(comment, responders(config, issue_of(config, number)), config['handles'])
        verb = reply[0] if reply else None
        if verb in OWNER_ONLY_VERBS and not parse_reply(comment, tuple(config.get('owners', ())), config['handles']):
            verb = None
    if verb not in RESUME_VERBS:
        raise ValueError('Up next needs --ack-reply with a reply on this issue: approve or revise from an owner, '
                         'or unblock from an owner, an assignee or a configured responder')


def cancel_allowed(config, number):
    """Canceled: the issue was closed as not planned, or the latest owner reply is `<handle> reject` (reject is
    owner-only, like every gate decision)."""
    issue = issue_of(config, number)
    if issue.get('state') == 'closed' and issue.get('state_reason') == 'not_planned':
        return True
    people = tuple(config.get('owners', ()))
    replies = [c for c in comments_of(config, number) if human_comment(c, people)]
    found = commands.parse(replies[-1].get('body') or '', config['handles']) if replies else None
    return bool(found and found[1] == 'reject')


def validate_change(field, current, value, comment, ack=False):
    if field == 'Autonomy' or (field == 'Status' and value == PARKED_STATUS) or (field == 'Status' and value == 'Up next' and not ack):
        raise ValueError(f'{field}/{value} is owner-controlled')
    if field == 'Status' and value in ('Your turn', 'Done', 'Canceled') and not comment:
        raise ValueError(f'{value} requires an audit comment (--comment)')
    if field not in ('Status', 'Stage', WAITING_FIELD) and current and current != value:
        if not (field == 'Track' and current == 'fast-path' and value == 'standard-implementation' and comment):
            raise ValueError('Cannot overwrite an owner-selected nonempty field')


def post_comment(config, number, body):
    """Post a bot comment (🤖 first) and read it back; returns the posted comment."""
    body = bot_body(body)
    posted = gh(config, 'api', '-X', 'POST', f"repos/{config['repo']}/issues/{int(number)}/comments", '-f', 'body=' + body)
    checked = gh(config, 'api', f"repos/{config['repo']}/issues/comments/{posted['id']}")
    if (checked or {}).get('body') != body:
        raise RuntimeError('Audit comment readback failed')
    return checked


SET_OPTION = '''mutation($project:ID!, $item:ID!, $field:ID!, $option:String!) {
 updateProjectV2ItemFieldValue(input:{projectId:$project,itemId:$item,fieldId:$field,
  value:{singleSelectOptionId:$option}}) {projectV2Item {id}}}'''
CLEAR_OPTION = '''mutation($project:ID!, $item:ID!, $field:ID!) {
 clearProjectV2ItemFieldValue(input:{projectId:$project,itemId:$item,fieldId:$field}) {projectV2Item {id}}}'''


def set_item_option(config, item_id, field, option_id):
    """Write a single-select value on a card by option id (None clears it). No guards: internal use only."""
    if option_id is None:
        graphql(config, CLEAR_OPTION, project=config['project_id'], item=item_id, field=field['id'])
    else:
        graphql(config, SET_OPTION, project=config['project_id'], item=item_id, field=field['id'], option=option_id)


def mutate_field(config, number, field, value, comment, expect=None, ack_reply=None):
    field, value = internal_field(field), internal_value(field, value)
    fields = read_fields(config)
    if field not in fields:
        raise ValueError(f'the board has no {field!r} field; run `gh-project.py fields` first')
    item, raw = current_item(config, number)
    values = item_values(raw)
    if expect is not None and values.get(field, 'Inbox' if field == 'Status' else '') != internal_value(field, expect):
        # Compare-and-set: a person or a bot session moved the item since the caller looked.
        raise ValueError(f'{field} is no longer {internal_value(field, expect)!r}; not changed')
    if ack_reply is not None and field == 'Status' and value == 'Up next':
        verify_ack_reply(config, number, ack_reply)
    validate_change(field, values.get(field, ''), value, comment, ack=ack_reply is not None)
    clear = value == ''
    if clear and field in ('Status', 'Priority', 'Track', 'Origin', 'Autonomy'):
        raise ValueError(f'{field} cannot be cleared')
    option = None if clear else next((opt for opt in fields[field]['options']
                                      if opt.get('internal', opt['name']) == value), None)
    if not option and not clear:
        raise ValueError(f'Unsupported value {value!r} for {field}')
    if field == 'Status' and value == 'Canceled' and not cancel_allowed(config, number):
        raise ValueError('Canceled requires the latest reply (owner, assignee or responder) to be an explicit reject, '
                         'or the issue closed as not planned')
    if field == 'Status' and value == 'Done' and in_pr_stage(item) and item['state'] != 'CLOSED':
        raise ValueError('In review -> Done requires a merged linked PR closing the issue')
    if comment:
        post_comment(config, number, comment)  # audit first: no unexplained transition
    set_item_option(config, item['item_id'], fields[field], option['id'] if option else None)
    for attempt in range(4):
        _, reread = current_item(config, number)
        if item_values(reread).get(field, '') == value:
            break
        if attempt == 3:
            raise RuntimeError('Project field readback does not match write')
        time.sleep(1)
    return {'ok': True, 'number': number, 'field': field, 'value': value}


# ---------------------------------------------------------------- fields

def status_usage(config):
    """Names of the Status options any card holds (archived cards included); None when unreadable."""
    names, cursor = set(), None
    while True:
        variables = {'id': config['project_id']}
        if cursor:
            variables['after'] = cursor
        project = (graphql(config, QUERY, **variables) or {}).get('node') or {}
        page = project.get('items')
        if page is None:
            return None
        for node in page['nodes']:
            value = stored_value(node, 'Status')
            if value:
                names.add(value)
        if not page['pageInfo']['hasNextPage']:
            return names
        cursor = page['pageInfo']['endCursor']


def desired_options(config, internal, field, used=None):
    """Wanted options of a field in board order as (existing option or None, name, colour, description).

    Existing options keep their id, so every card keeps its value. Status: an option outside the plan is dropped
    only when no card holds it (`used` None = unknown keeps it). Other fields keep every extra option."""
    existing = list((field or {}).get('options') or [])
    if internal == WAITING_FIELD:
        plan = [(name, WAITING_FOR_COLOR, WAITING_FOR_DESCRIPTIONS[name].replace('<handle>', config['handles'][0]))
                for name in WAITING_FOR.values()]
        plan.append((WAITING_FOR_BOT, WAITING_FOR_BOT_COLOR, WAITING_FOR_DESCRIPTIONS[WAITING_FOR_BOT]))
        by_key = {o['name'].lower(): o for o in existing}
        out = [(by_key.pop(n.lower(), None), n, c, d) for n, c, d in plan]
        return out + [(o, o['name'], o.get('color') or 'GRAY', o.get('description') or '') for o in by_key.values()]
    by_internal = {}
    for o in existing:
        by_internal.setdefault(internal_value(internal, o['name']), o)
    out = []
    for value in REQUIRED[internal]:
        opt, name = by_internal.pop(value, None), str(board_value(internal, value))
        if internal == 'Status':
            color = STATUS_COLORS[value]
            desc = STATUS_DESCRIPTIONS[value].format(wip=config.get('wip', 2))
        else:
            color = (opt or {}).get('color') or OPTION_COLORS.get(value, 'GRAY')
            desc = BOARD_DESCRIPTIONS.get(name, (opt or {}).get('description') or '')
        out.append((opt, name, color, desc))
    keep = [o for o in by_internal.values() if internal != 'Status' or used is None or o['name'] in used]
    return out + [(o, o['name'], o.get('color') or 'GRAY', o.get('description') or '') for o in keep]


def _options_literal(options):
    return ','.join('{' + (f'id:{json.dumps(o["id"])},' if o else '')
                    + f'name:{json.dumps(n, ensure_ascii=False)},color:{c},'
                    f'description:{json.dumps(d, ensure_ascii=False)}' + '}' for o, n, c, d in options)


def ensure_fields(config, dry=False):
    """Create or refresh every board field (board names, options in order, colours, descriptions) and the
    `Waiting for` field. Keeps option ids (and so every card's value). Idempotent; reads back the result."""
    nodes = [f for f in project_fields(config) if f.get('options') is not None]
    by_internal = {}
    for f in nodes:
        by_internal.setdefault(internal_field(f['name']), f)
    used = status_usage(config)
    changes, plans = [], {}
    for internal in [*REQUIRED, WAITING_FIELD]:
        field = by_internal.get(internal)
        name = BOARD_FIELD.get(internal, internal)
        desired = desired_options(config, internal, field, used)
        plans[internal] = (field, name, desired)
        if field is None:
            changes.append(f'add field {name}: ' + ', '.join(n for _, n, _, _ in desired))
            if not dry:
                graphql(config, 'mutation($p:ID!,$n:String!){createProjectV2Field(input:{projectId:$p,'
                        'dataType:SINGLE_SELECT,name:$n,singleSelectOptions:[' + _options_literal(desired)
                        + ']}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}',
                        p=config['project_id'], n=name)
            continue
        current = [(o['id'], o['name'], o.get('color'), o.get('description') or '') for o in field['options']]
        wanted = [((o or {}).get('id'), n, c, d) for o, n, c, d in desired]
        kept = [o['name'] for o, *_ in desired[len(REQUIRED.get(internal, ())):] if o and internal == 'Status']
        note = [f"Status: kept {', '.join(kept)} because cards still hold them; run migrate-your-turn, then "
                'fields again'] if kept else []
        if field['name'] == name and current == wanted:
            changes.extend([f'{name}: up to date'] + note)
            continue
        wanted_ids = {o['id'] for o, *_ in desired if o}
        parts = ([f"{field['name']} -> {name}"] if field['name'] != name else []) \
            + [f"{o['name']} -> {n}" for o, n, _, _ in desired if o and o['name'] != n] \
            + [f'add {n}' for o, n, _, _ in desired if not o] \
            + [f"remove {o['name']} (no cards)" for o in field['options'] if o['id'] not in wanted_ids]
        changes.extend([f"{name}: " + (', '.join(parts) or 'colours, descriptions or order')] + note)
        if not dry:
            graphql(config, 'mutation($f:ID!,$n:String!){updateProjectV2Field(input:{fieldId:$f,name:$n,'
                    'singleSelectOptions:[' + _options_literal(desired)
                    + ']}){projectV2Field{... on ProjectV2SingleSelectField{id}}}}', f=field['id'], n=name)
    if dry:
        return changes
    after = {}
    for f in project_fields(config):
        if f.get('options') is not None:
            after.setdefault(internal_field(f['name']), f)
    for internal, (field, name, desired) in plans.items():
        got = after.get(internal)
        if not got or got['name'] != name or [o['name'] for o in got['options']] != [n for _, n, _, _ in desired]:
            raise RuntimeError(f'board field read-back failed for {name}: '
                               + ', '.join(o['name'] for o in (got or {}).get('options', [])))
        ids = {o['id']: o['name'] for o in got['options']}
        for o, n, _, _ in desired:
            if o and ids.get(o['id']) != n:
                raise RuntimeError(f"board field read-back failed for {name}: option {o['name']} lost its id")
    changes.append('read back: OK')
    return changes


# ---------------------------------------------------------------- labels

def label_path(repo, name):
    from urllib.parse import quote
    return f'repos/{repo}/labels/' + quote(name, safe='')


def ensure_labels(config, dry=False, only=None):
    """Create, rename (legacy name, keeps it on every issue/PR) or refresh the workflow labels."""
    repo = config['repo']
    existing = {l['name']: l for l in gh(config, 'label', 'list', '-R', repo, '--limit', '300',
                                         '--json', 'name,color,description') or []}
    legacy_for = {new: old for old, new in LEGACY_LABELS.items()}
    changes = []
    for name, color, desc in WORKFLOW_LABELS:
        if only and name != only:
            continue
        desc = desc.replace('{handle}', config['handles'][0])
        old = legacy_for.get(name)
        if name not in existing and old in existing:
            changes.append(f'rename {old} -> {name}')
            if not dry:
                gh(config, 'api', '-X', 'PATCH', label_path(repo, old), '-f', f'new_name={name}',
                   '-f', f'color={color}', '-f', f'description={desc}')
        elif name not in existing:
            changes.append(f'create {name}')
            if not dry:
                gh(config, 'label', 'create', name, '-R', repo, '--color', color, '--description', desc)
        elif existing[name].get('color', '').lower() != color or (existing[name].get('description') or '') != desc:
            changes.append(f'refresh {name}')
            if not dry:
                gh(config, 'api', '-X', 'PATCH', label_path(repo, name), '-f', f'color={color}', '-f', f'description={desc}')
        else:
            continue
        if not dry and (gh(config, 'api', label_path(repo, name)) or {}).get('name') != name:
            raise RuntimeError(f'label read-back failed for {repo} {name}')
    return changes


# ---------------------------------------------------------------- state lock (shared with board-sync.py)

class LockBusy(RuntimeError):
    pass


@contextmanager
def file_lock(path, wait=0.0):
    """Exclusive kernel lock on `path` (released on crash); waits up to `wait` seconds, else raises LockBusy."""
    import fcntl
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + max(0.0, wait)
    with path.open('a+b') as handle:
        while True:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as exc:
                if time.monotonic() >= deadline:
                    raise LockBusy(f'{path} is held by another run') from exc
                time.sleep(2)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def lock_path(config):
    return pathlib.Path(config['state_dir']) / 'board-sync.lock'


# ---------------------------------------------------------------- one-off migration to Your turn
# The ONLY place that knows the old person statuses. Delete once every board is migrated.
# old status -> (names it had on a board, kind of wait it becomes).
OLD_PERSON_STATUSES = {
    'Clarification needed': (('🧑 💬 Clarify', '🧑 Clarify', 'Clarify'), 'answer'),
    'Awaiting approval': (('🧑 👍 Approve step', '🧑 Approve step', 'Approve step'), 'approve'),
    'Blocked': (('🧑 🛠️ Unblock', '🧑 Unblock', '🧑 Blocked', 'Unblock'), 'unblock'),
    'PR decision': (('🧑 ⚖️ Decide on PR', '🧑 Decide on PR', 'Decide on PR'), 'decide'),
    'PR merge': (('🧑 🔀 Merge PR', '🧑 Merge PR', 'Merge PR'), 'merge'),
}
_OLD_BY_NAME = {name.lower(): old for old, (names, _) in OLD_PERSON_STATUSES.items() for name in (old, *names)}
# The marker a bot comment must carry so a reply is read after it (see wait_kind). An approval needs stage and
# head, so none is ever invented for it.
MIGRATION_MARKERS = {'unblock': '<!-- blocked reason=migration -->', 'answer': '<!-- triage outcome=clarify -->'}
MIGRATION_NOTE = 'moved to 🧑 Your turn (board simplification); nothing else changed'
MIGRATION_WHO = {'approve': 'Needs your approval', 'decide': 'Needs your decision', 'merge': 'Review passed'}
MIGRATION_ASKS = {'unblock': 'the bot was already waiting for you to unblock it',
                  'answer': 'the bot was already waiting for your answers'}


def old_person_status(name):
    """Internal old status for a Status value as stored on a board, or None."""
    return _OLD_BY_NAME.get((name or '').strip().lower())


def migration_comment(config, kind, marker):
    """Audit comment of a migrated card; carries the wait marker and the reply menu only when `marker` is set."""
    first = f'🤖 **{MIGRATION_WHO.get(kind, "Needs your help")}: {MIGRATION_NOTE}**'
    if not marker:
        return first + '\n\n<!-- sync migrated -->'
    handle = config['handles'][0]
    reply = {'unblock': f'{handle} unblock: <what changed>', 'answer': f'{handle} answer: <your answers>'}[kind]
    return (f'{first}\n\n- {MIGRATION_ASKS[kind]}; reply {reply_menu(kind, handle)} when ready\n\n'
            f'<details>\n<summary><b>Reply with</b> <code>{reply.replace("<", "&lt;").replace(">", "&gt;")}</code>'
            f'</summary>\n\n| Reply | Effect |\n|---|---|\n| `{reply}` | Continue |\n</details>\n'
            f'{MIGRATION_MARKERS[kind]}')


def rewrite_last_status(target, dry, say=print):
    """Map old status names to Your turn in a dispatcher last-status.json (a file, or every one under a directory).
    Atomic writes. Returns (files, entries) changed."""
    target = pathlib.Path(target)
    paths = sorted(target.glob('**/last-status.json')) if target.is_dir() else [target] if target.exists() else []
    files = entries = 0
    for path in paths:
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
            changed = {k: 'Your turn' for k, v in data.items() if old_person_status(v)}
        except (OSError, ValueError, AttributeError) as exc:
            say(f'last-status: could not read {path}: {exc}')
            continue
        if not changed:
            continue
        files += 1
        entries += len(changed)
        if dry:
            say(f'DRY: would rewrite {len(changed)} entries in {path}')
            continue
        tmp = path.with_suffix('.tmp')
        tmp.write_text(json.dumps({**data, **changed}, sort_keys=True), encoding='utf-8')
        os.replace(tmp, path)
    return files, entries


def migrate_your_turn(config, dry=False, state=None, say=print):
    """One-off: every card in an old person status (Clarification needed, Awaiting approval, Blocked, ...) -> Your
    turn with an audit comment and `Waiting for` from the old status; then rewrite the dispatcher's last-status.json.
    Run `fields` first (adds Your turn and Waiting for) and again afterwards (removes the emptied options).
    Idempotent. The per-card `--expect` is check-then-write: pause the dispatcher and board sync while it runs."""
    fields = {}
    try:
        fields = read_fields(config)
        problem = '' if WAITING_FIELD in fields else 'the board has no Waiting for field'
    except RuntimeError as exc:
        problem = str(exc)
    if problem:
        say(f'migrate-your-turn REFUSED: {problem}.\n'
            'Run `gh-project.py fields` first (it adds the Your turn status and the Waiting for field), then run this again.')
        return 1
    logins = bot_logins(config)
    repo = config['repo']
    moved = skipped = warned = 0
    issues, _, nodes = snapshot(config)
    handled = {i['item_id'] for i in issues}
    for i in issues:
        old = old_person_status(i['status'])
        if not old:
            continue
        n, kind = i['number'], OLD_PERSON_STATUSES[old][1]
        label_sets = [{l['name'] for l in issue_of(config, pr).get('labels', [])} for pr in i.get('prs') or []]
        found = wait_kind(comments_of(config, n), label_sets, logins)[0]
        if found != kind:
            say(f'[{repo}] #{n}: old status {old} says {kind}, the comments say {found or "nothing"}; using {kind}')
        marker = kind in MIGRATION_MARKERS and found != kind
        if kind == 'approve' and found != 'approve':
            warned += 1
            say(f'[{repo}] #{n}: WARNING waiting for approval, but no approval request from a bot is on the issue; '
                'moved anyway, left for you to look at')
        body = migration_comment(config, kind, marker)
        word = WAITING_FOR[kind]
        if dry:
            say(f'DRY: would move [{repo}] #{n} from {i["status"]} to Your turn'
                + (f' (comment carries {MIGRATION_MARKERS[kind]})' if marker else ''))
            say(f'DRY: would set Waiting for on [{repo}] #{n} to {word}')
            moved += 1
            continue
        try:
            mutate_field(config, n, 'Status', 'Your turn', body, expect=i['status'])
        except ValueError as exc:
            if 'is no longer' not in str(exc):
                raise
            skipped += 1
            say(f'[{repo}] #{n}: moved by someone meanwhile; skipped')
            continue
        moved += 1
        try:
            mutate_field(config, n, WAITING_FIELD, word, '')
        except (RuntimeError, ValueError, KeyError) as exc:
            say(f'[{repo}] #{n}: Waiting for not set ({exc}); board sync sets it on its next run')
    # Other cards (PR cards, archived cards, other repositories' cards) hold the old options too, and removing an
    # option clears it from every card: move them as well, without a comment.
    status, waiting = fields['Status'], fields[WAITING_FIELD]
    for node in nodes:
        old = old_person_status(stored_value(node, 'Status'))
        if not old or node['id'] in handled:
            continue
        content = node.get('content') or {}
        what = f'{content.get("__typename", "card")} #{content.get("number", "?")}' + (' (archived)' if node.get('isArchived') else '')
        word = WAITING_FOR[OLD_PERSON_STATUSES[old][1]]
        if dry:
            say(f'DRY: would move {what} from {old} to Your turn')
            say(f'DRY: would set Waiting for on {what} to {word}')
        else:
            set_item_option(config, node['id'], status, next(o['id'] for o in status['options'] if o['internal'] == 'Your turn'))
            option = next((o['id'] for o in waiting['options'] if o['name'] == word), None)
            if option:
                set_item_option(config, node['id'], waiting, option)
        moved += 1
    if state:
        files, entries = rewrite_last_status(state, dry, say)
        say(('DRY: would rewrite' if dry else 'Rewrote') + f' {entries} last-status entries in {files} file(s)')
    say(('DRY: ' if dry else '') + f'migrate-your-turn: {"would move" if dry else "moved"} {moved} card(s) to Your turn, '
        f'{skipped} skipped, {warned} approval warning(s)')
    if moved and not dry:
        say('Next: run `gh-project.py fields` again to remove the emptied options and order the Status list.')
    return 0


# ---------------------------------------------------------------- CLI

def build_parser():
    parser = argparse.ArgumentParser(prog='gh-project.py', description=(__doc__ or '').split('\n')[0])
    sub = parser.add_subparsers(dest='action', required=True)
    for action in ('check', 'list', 'prs'):
        sub.add_parser(action)
    move = sub.add_parser('move')
    move.add_argument('number', type=int)
    move.add_argument('value')
    move.add_argument('--comment', default='')
    move.add_argument('--expect', default=None, help='Only move if the current status is this one (compare-and-set)')
    move.add_argument('--ack-reply', type=int, default=None, help='Comment id of the reply that queues this item (Up next)')
    change = sub.add_parser('set')
    change.add_argument('number', type=int)
    change.add_argument('field', type=internal_field,
                        choices=[field for field in REQUIRED if field != 'Autonomy'] + [WAITING_FIELD],
                        help='Field, by board name (Size, Source) or internal name (Track, Origin)')
    change.add_argument('value')
    change.add_argument('--comment', default='')
    change.add_argument('--expect', default=None)
    for action in ('fields', 'labels'):
        sub.add_parser(action).add_argument('--dry', action='store_true')
    migrate = sub.add_parser('migrate-your-turn')
    migrate.add_argument('--dry', action='store_true')
    migrate.add_argument('--state', default=None,
                         help="The dispatcher's last-status.json (or a directory searched for it) to rewrite")
    return parser


def main(argv=None, config=None):
    args = build_parser().parse_args(argv)
    config = resolve_project(dict(load_config() if config is None else config))
    if args.action == 'move':
        result = mutate_field(config, args.number, 'Status', args.value, args.comment,
                              expect=args.expect, ack_reply=args.ack_reply)
    elif args.action == 'set':
        result = mutate_field(config, args.number, args.field, args.value, args.comment, expect=args.expect)
    elif args.action == 'fields':
        for line in ensure_fields(config, args.dry):
            print(line + (' (DRY)' if args.dry else ''))
        return 0
    elif args.action == 'labels':
        changes = ensure_labels(config, args.dry)
        print(f"[{config['repo']}] labels: " + (', '.join(changes) if changes else 'up to date') + (' (DRY)' if args.dry else ''))
        return 0
    elif args.action == 'migrate-your-turn':
        try:
            with file_lock(lock_path(config), wait=0 if args.dry else 120):
                return migrate_your_turn(config, args.dry, args.state)
        except LockBusy:
            print('migrate-your-turn REFUSED: a board sync holds the board lock; run it again in a few minutes.')
            return 1
    else:
        if args.action == 'check':
            read_fields(config)
        issues, prs, nodes = snapshot(config)
        result = issues if args.action == 'list' else prs if args.action == 'prs' else {
            'ok': True, 'project': config['project_id'], 'title': config.get('project_title'),
            'item_count': len(nodes), 'repo_issue_count': len(issues), 'open_linked_pr_count': len(prs)}
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print('gh-project: ' + str(exc), file=sys.stderr)
        sys.exit(1)
