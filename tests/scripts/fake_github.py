"""In-memory GitHub fake for the board tools tests (no network). TEST ONLY data.

Two uses:
  - unit tests patch `gh` and `graphql` of scripts/gh-project.py with FakeBoard.gh / FakeBoard.graphql;
  - as an executable (`python3 fake_github.py <gh args>`), it serves the same routes from the JSON state file named
    by FAKE_GH_STATE and saves every write back, so the CLI can be driven end to end through GH_BIN.
"""
import json
import os
import re
import sys
from typing import Any
from urllib.parse import unquote

SINGLE = 'ProjectV2ItemFieldSingleSelectValue'
OPTION_LITERAL = re.compile(r'\{(?:id:("[^"]*"),)?name:("(?:[^"\\]|\\.)*"),color:(\w+),description:("(?:[^"\\]|\\.)*")\}')

BOARD_STATUS = ['🧑 Backlog', '🤖 Inbox', '🧑 📋 Ready to schedule', '🤖 Up next', '🤖 In progress', '🧑 Your turn',
                '🤖 In review', 'Later', 'Done', 'Canceled']
OTHER_FIELDS = {
    'Priority': ['P0', 'P1', 'P2', 'P3'],
    'Size': ['small fix', 'needs design', 'investigation', 'docs'],
    'Kind': ['bug', 'feature', 'chore', 'docs', 'hardening', 'research', 'debt', 'idea'],
    'Source': ['requested', 'from a plan', 'from a review', 'bot noticed', 'external'],
    'Stage': ['Design', 'Plan', 'Execute', 'Research', 'PR'],
    'Bot approvals': ['ask at each step', 'proceed alone'],
}
WAITING = ['💬 answer', '👍 approve', '🛠️ unblock', '⚖️ decide on PR', '🔀 merge PR', "⏳ Bot's turn"]


class FakeBoard:
    def __init__(self, repo='o/r', status=None, fields=None, waiting=True, me='bot', state=None):
        if state is not None:
            self.__dict__.update(state)
            return
        self.repo, self.project_id, self.title, self.me = repo, 'P', 'Board', me
        self.seq = 100
        self.fields = []
        for name, options in {'Status': status or BOARD_STATUS, **(OTHER_FIELDS if fields is None else fields)}.items():
            self.add_field(name, options)
        if waiting:
            self.add_field('Waiting for', WAITING)
        self.items, self.comments, self.issues = [], {}, {}
        self.open_prs, self.prs, self.closed, self.labels, self.writes = [], [], [], {}, []
        self.search_counts = {}  # search/issues total_count by 'created' / 'closed'
        self.closed_prs = []  # merged/closed PRs with labels: {'number', 'labels': {'nodes': [{'name'}]}}

    # ------------------------------------------------------------ setup helpers
    def new_id(self, prefix):
        self.seq += 1
        return f'{prefix}{self.seq}'

    def add_field(self, name, options, color='GRAY'):
        field = {'id': self.new_id('F'), 'name': name, 'dataType': 'SINGLE_SELECT',
                 'options': [{'id': self.new_id('O'), 'name': n, 'color': color, 'description': ''} for n in options]}
        self.fields.append(field)
        return field

    def field(self, name):
        return next(f for f in self.fields if f['name'] == name)

    def option_id(self, field, name):
        return next(o['id'] for o in self.field(field)['options'] if o['name'] == name)

    def add_issue(self, number, status=None, title='t', state='OPEN', body='', links=(), values=None, archived=False,
                  labels=(), assignees=(), on_board=True, state_reason=None, repo=None) -> Any:
        repo = repo or self.repo
        node_id = f'I_{repo}_{number}'
        self.issues[str(number)] = {'number': number, 'node_id': node_id, 'state': state.lower() if state != 'CLOSED_WITHOUT_MERGE' else 'closed',
                                    'state_reason': state_reason, 'body': body, 'title': title,
                                    'labels': [{'name': name} for name in labels],
                                    'assignees': [{'login': a} for a in assignees]}
        self.comments.setdefault(str(number), [])
        if on_board:
            vals = dict(values or {})
            if status is not None:
                vals['Status'] = status
            item = {'id': self.new_id('PVTI'), 'isArchived': archived, 'values': {},
                    'content': {'__typename': 'Issue', 'number': number, 'title': title, 'state': state,
                                'updatedAt': '2026-01-01T00:00:00Z', 'repository': {'nameWithOwner': repo},
                                'id': node_id,
                                'closedByPullRequestsReferences': {'pageInfo': {'hasNextPage': False}, 'nodes': [
                                    {'number': n, 'state': s, 'repository': {'nameWithOwner': repo}} for n, s in links]}}}
            for name, value in vals.items():
                item['values'][self.field(name)['id']] = self.option_id(name, value)
            self.items.append(item)
            return item
        return None

    def add_pr_card(self, number, status, state='OPEN', labels=(), waiting=None):
        values = {self.field('Status')['id']: self.option_id('Status', status)} if status else {}
        if waiting:
            values[self.field('Waiting for')['id']] = self.option_id('Waiting for', waiting)
        item = {'id': self.new_id('PVTI'), 'isArchived': False, 'values': values,
                'content': {'__typename': 'PullRequest', 'number': number, 'state': state,
                            'repository': {'nameWithOwner': self.repo}}}
        self.items.append(item)
        self.add_pr(number, labels)
        return item

    def add_pr(self, number, labels=(), assignees=(), closes=(), fork=False, updated='2026-01-01T00:00:00Z'):
        """The PR's issue record (GitHub serves a PR's labels and assignees through the issues API)."""
        self.issues[str(number)] = {'number': number, 'node_id': f'PR_{number}', 'state': 'pr', 'state_reason': None,
                                    'body': '', 'title': 't', 'labels': [{'name': n} for n in labels],
                                    'assignees': [{'login': a} for a in assignees], 'closes': list(closes),
                                    'fork': fork, 'updatedAt': updated}
        self.comments.setdefault(str(number), [])
        return self.issues[str(number)]

    def add_closed_pr(self, number, labels):
        self.add_pr(number, labels)
        self.closed_prs.append({'number': number, 'labels': {'nodes': [{'name': n} for n in labels]}})

    def comment(self, number, login, body, created='2026-01-01T00:00:00Z', eyes=0):
        c = {'id': self.new_seq(), 'user': {'login': login}, 'body': body, 'created_at': created,
             'reactions': {'eyes': eyes},
             'issue_url': f'https://api.github.com/repos/{self.repo}/issues/{number}',
             'html_url': f'https://github.com/{self.repo}/issues/{number}#issuecomment-x'}
        self.comments.setdefault(str(number), []).append(c)
        return c

    def new_seq(self):
        self.seq += 1
        return self.seq

    # ------------------------------------------------------------ reads used by assertions
    def value(self, number, field):
        item = next(i for i in self.items if (i['content'] or {}).get('number') == number)
        fid = self.field(field)['id']
        oid = item['values'].get(fid)
        return next((o['name'] for o in self.field(field)['options'] if o['id'] == oid), '')

    def bodies(self, number=None):
        keys = [str(number)] if number is not None else list(self.comments)
        return [c['body'] for k in keys for c in self.comments.get(k, []) if c['user']['login'] == self.me]

    # ------------------------------------------------------------ GraphQL
    def node(self, item):
        values = []
        for fid, oid in item['values'].items():
            field = next((f for f in self.fields if f['id'] == fid), None)
            option = next((o for o in (field or {}).get('options', []) if o['id'] == oid), None)
            if field and option:
                values.append({'__typename': SINGLE, 'name': option['name'], 'field': {'name': field['name']}})
        return {'id': item['id'], 'isArchived': item['isArchived'], 'content': item['content'],
                'fieldValues': {'pageInfo': {'hasNextPage': False}, 'nodes': values}}

    def graphql(self, config, query, **v) -> Any:
        if query.lstrip().startswith('mutation'):
            return {**self.mutate(query, v)}
        if 'repositoryOwner' in query:
            return {'repositoryOwner': {'projectV2': {'id': self.project_id, 'title': self.title}}}
        if 'fields(first:100)' in query:
            return {'node': {'id': self.project_id, 'fields': {'totalCount': len(self.fields), 'nodes': json.loads(json.dumps(self.fields))}}}
        if 'items(first:100' in query:
            nodes = [self.node(i) for i in self.items]
            return {'node': {'id': self.project_id, 'title': self.title, 'items': {
                'totalCount': len(nodes), 'pageInfo': {'hasNextPage': False, 'endCursor': None}, 'nodes': nodes}}}
        if 'pullRequests(states:OPEN' in query:
            return {'repository': {'pullRequests': {'pageInfo': {'hasNextPage': False}, 'nodes': self.open_prs}}}
        if 'states:CLOSED' in query:
            return {'repository': {'issues': {'pageInfo': {'hasNextPage': False, 'endCursor': None}, 'nodes': self.closed}}}
        if 'pullRequest(number:' in query:
            pr = self.issues.get(str(v.get('p')), {})
            here = f"{v.get('o')}/{v.get('r')}"
            # An entry 'other/repo#N' closes issue N of another repository (its assignees are the local issue N's).
            closing = [{'repository': {'nameWithOwner': str(n).split('#')[0] if '#' in str(n) else here},
                        'assignees': {'nodes': self.issues[str(n).split('#')[-1]]['assignees']}}
                       for n in pr.get('closes', ())]
            return {'repository': {'pullRequest': {'assignees': {'nodes': pr.get('assignees', [])},
                                                   'closingIssuesReferences': {'nodes': closing}}}}
        if 'states:[MERGED,CLOSED]' in query:
            nodes = [{'number': p['number'], 'labels': {'nodes': self.issues[str(p['number'])]['labels']}}
                     for p in getattr(self, 'closed_prs', [])]
            return {'repository': {'pullRequests': {'nodes': nodes}}}
        if 'pullRequests(first:100' in query:
            return {'repository': {'pullRequests': {'pageInfo': {'hasNextPage': False, 'endCursor': None}, 'nodes': self.prs}}}
        raise AssertionError('unexpected query: ' + query[:80])

    def parse_options(self, query):
        out = []
        for oid, name, color, desc in OPTION_LITERAL.findall(query):
            out.append({'id': json.loads(oid) if oid else self.new_id('O'), 'name': json.loads(name), 'color': color,
                        'description': json.loads(desc)})
        return out

    def mutate(self, query, v):
        if 'updateProjectV2ItemFieldValue' in query:
            item = next(i for i in self.items if i['id'] == v['item'])
            item['values'][v['field']] = v['option']
            self.writes.append(('set', v['item'], v['field'], v['option']))
            return {'updateProjectV2ItemFieldValue': {'projectV2Item': {'id': v['item']}}}
        if 'clearProjectV2ItemFieldValue' in query:
            item = next(i for i in self.items if i['id'] == v['item'])
            item['values'].pop(v['field'], None)
            self.writes.append(('clear', v['item'], v['field']))
            return {'clearProjectV2ItemFieldValue': {'projectV2Item': {'id': v['item']}}}
        if 'updateProjectV2Field' in query:
            field = next(f for f in self.fields if f['id'] == v['f'])
            options = self.parse_options(query)
            kept = {o['id'] for o in options}
            for item in self.items:  # removing an option clears it from every card
                if item['values'].get(field['id']) and item['values'][field['id']] not in kept:
                    item['values'].pop(field['id'])
            field.update(name=v['n'], options=options)
            self.writes.append(('field', v['n']))
            return {'updateProjectV2Field': {'projectV2Field': {'id': field['id']}}}
        if 'createProjectV2Field' in query:
            field = {'id': self.new_id('F'), 'name': v['n'], 'dataType': 'SINGLE_SELECT', 'options': self.parse_options(query)}
            self.fields.append(field)
            self.writes.append(('create-field', v['n']))
            return {'createProjectV2Field': {'projectV2Field': {'id': field['id']}}}
        if 'addProjectV2ItemById' in query:
            item = next((i for i in self.items if (i['content'] or {}).get('id') == v['c']), None)
            if item is None:
                issue = next(i for i in self.issues.values() if i['node_id'] == v['c'])
                item = {'id': self.new_id('PVTI'), 'isArchived': False, 'values': {},
                        'content': {'__typename': 'Issue', 'number': issue['number'], 'title': issue['title'],
                                    'state': 'OPEN', 'updatedAt': '2026-01-01T00:00:00Z', 'id': v['c'],
                                    'repository': {'nameWithOwner': self.repo},
                                    'closedByPullRequestsReferences': {'pageInfo': {'hasNextPage': False}, 'nodes': []}}}
                self.items.append(item)
                self.writes.append(('add', issue['number']))
            return {'addProjectV2ItemById': {'item': self.node(item)}}
        raise AssertionError('unexpected mutation: ' + query[:80])

    # ------------------------------------------------------------ REST / gh CLI
    def gh(self, config, *args):
        args = list(args)
        flags = {}
        rest = []
        i = 0
        while i < len(args):
            if args[i] in ('-f', '-F', '-X', '-R', '--json', '--limit', '--state', '--label', '--color', '--description'):
                flags.setdefault(args[i], []).append(args[i + 1])
                i += 2
            else:
                rest.append(args[i])
                i += 1
        fields = dict(f.split('=', 1) for f in flags.get('-f', []))
        method = (flags.get('-X') or ['GET'])[0]
        if rest[:2] == ['issue', 'list'] and '--search' in rest:
            return [{'number': i['number'], 'title': i['title'], 'url': f'https://github.com/{self.repo}/issues/{i["number"]}'}
                    for i in self.issues.values() if i['state'] == 'open' and i.get('recent')]
        if rest[:2] == ['issue', 'list']:
            label = (flags.get('--label') or [None])[0]
            out = [{'id': i['node_id'], 'number': i['number'], 'body': i['body']} for i in self.issues.values()
                   if i['state'] == 'open' and (label is None or label in {lab['name'] for lab in i['labels']})]
            return sorted(out, key=lambda i: -i['number'])
        if rest[:2] == ['pr', 'list']:
            label = (flags.get('--label') or [None])[0]
            return [{'number': p['number'], 'title': p['title'], 'url': f'https://github.com/{self.repo}/pull/{p["number"]}',
                     'labels': p['labels'], 'updatedAt': p.get('updatedAt', ''), 'isCrossRepository': p.get('fork', False)}
                    for p in self.issues.values()
                    if p['state'] == 'pr' and (label is None or label in {lab['name'] for lab in p['labels']})]
        if rest[:2] == ['label', 'list']:
            return list(self.labels.values())
        if rest[:2] == ['label', 'create']:
            name = rest[2]
            self.labels[name] = {'name': name, 'color': flags['--color'][0], 'description': flags['--description'][0]}
            self.writes.append(('label-create', name))
            return None
        assert rest[0] == 'api', args
        path = [p for p in rest[1:] if p not in ('--paginate', '--slurp')][0]
        slurp = '--slurp' in rest
        if path == 'user':
            return {'login': self.me}
        if path == 'search/issues':
            q = fields['q']
            return {'total_count': self.search_counts.get('created' if 'created:' in q else 'closed', 0)}
        m = re.fullmatch(r'repos/[^/]+/[^/]+/labels/(.+)', path)
        if m:
            name = unquote(m.group(1))
            if method == 'PATCH':
                label = self.labels.pop(name)
                label.update(name=fields.get('new_name', name), color=fields['color'], description=fields['description'])
                self.labels[label['name']] = label
                self.writes.append(('label-patch', name, label['name']))
                return label
            if name not in self.labels:
                raise RuntimeError('HTTP 404: Not Found')
            return self.labels[name]
        m = re.fullmatch(r'repos/[^/]+/[^/]+/issues/comments/(\d+)', path)
        if m:
            c = next(c for cs in self.comments.values() for c in cs if c['id'] == int(m.group(1)))
            if method == 'PATCH':
                c['body'] = fields['body']
                self.writes.append(('edit', c['id'], fields['body']))
            return c
        m = re.fullmatch(r'repos/[^/]+/[^/]+/issues/(\d+)/comments(?:\?per_page=100)?', path)
        if m:
            if method == 'POST':
                c = self.comment(int(m.group(1)), self.me, fields['body'])
                self.writes.append(('comment', int(m.group(1)), fields['body']))
                return c
            cs = self.comments.get(m.group(1), [])
            return [cs] if slurp else cs
        m = re.fullmatch(r'repos/[^/]+/[^/]+/issues/(\d+)/assignees', path)
        if m and method == 'POST':
            people = [v.split('=', 1)[1] for v in flags.get('-f', []) if v.startswith('assignees[]=')]
            self.issues[m.group(1)]['assignees'] += [{'login': a} for a in people]
            self.writes.append(('assign', int(m.group(1)), tuple(people)))
            return self.issues[m.group(1)]
        m = re.fullmatch(r'repos/[^/]+/[^/]+/issues/(\d+)/labels(?:/(.+))?', path)
        if m:
            issue = self.issues[m.group(1)]
            if method == 'POST':
                name = fields['labels[]']
                if name not in {lab['name'] for lab in issue['labels']}:
                    issue['labels'].append({'name': name})
                self.writes.append(('label+', int(m.group(1)), name))
            elif method == 'DELETE':
                name = unquote(m.group(2))
                issue['labels'] = [lab for lab in issue['labels'] if lab['name'] != name]
                self.writes.append(('label-', int(m.group(1)), name))
            return issue['labels']
        m = re.fullmatch(r'repos/[^/]+/[^/]+/issues/(\d+)', path)
        if m:
            issue = self.issues[m.group(1)]
            if method == 'PATCH':
                issue.update(state=fields['state'], state_reason=fields.get('state_reason'))
                self.writes.append(('issue', int(m.group(1)), fields['state'], fields.get('state_reason')))
            return issue
        raise AssertionError('unexpected gh call: ' + ' '.join(args))


def cli(argv):
    """Fake `gh` executable: state in $FAKE_GH_STATE (JSON); prints the JSON result like `gh` does."""
    path = os.environ['FAKE_GH_STATE']
    with open(path, encoding='utf-8') as handle:
        board = FakeBoard(state=json.load(handle))
    try:
        if argv[:2] == ['api', 'graphql']:
            pairs = [argv[i + 1] for i in range(2, len(argv) - 1) if argv[i] in ('-f', '-F')]
            v = dict(p.split('=', 1) for p in pairs)
            query = v.pop('query')
            v = {k: int(x) if x.isdigit() else x for k, x in v.items()}
            result = {'data': board.graphql(None, query, **v)}
        else:
            result = board.gh(None, *argv)
            if '--slurp' in argv:  # gh --paginate prints each page; gh-project.py decodes the concatenation
                print('\n'.join(json.dumps(page, ensure_ascii=False) for page in result or []))
                return 0
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        with open(path, 'w', encoding='utf-8') as handle:
            json.dump(board.__dict__, handle, ensure_ascii=False)
    if result is not None:
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(cli(sys.argv[1:]))
