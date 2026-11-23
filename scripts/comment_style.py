"""House-style checker for every comment the board bots post (rules: docs/references/comment-style.md).

lint(body, kind=None) -> list of problems (empty = fine).  kind is inferred from the hidden marker when not given.
Used by post-comment.py, which every bot session posts through.  Pure functions; no I/O.
"""
import re

BUDGETS = {'gate': 200, 'blocked': 120, 'triage-ready': 40, 'triage-clarify': 160, 'close-proposal': 40,
           'pr-review': 150, 'fix-round': 60, 'notice': 60, 'machine': 40}
SECTION_LIMITS = {'Done': 6, 'Blockers': 3, 'Decisions made': 8}
ORDER = ['Must fix', 'Should fix', 'Done', 'Waiting on', 'Blockers', 'Decisions made', 'Questions', 'Proposed new issues']
WHO = ('Needs your decision', 'Needs your approval', 'Needs your help', 'Ready to schedule', 'No action needed',
       'Review passed', 'Changes needed', 'Waiting for checks', 'Still waiting', 'Paused', 'Possibly done', 'Closed', 'Back to you')
MENU_KINDS = ('gate', 'blocked', 'triage-clarify', 'close-proposal', 'pr-review')
# Order matters: a triage close proposal carries both the close-proposal and the clarify marker.
INFER = [('gate', r'<!--\s*gate stage='), ('pr-review', r'<!--\s*pr-review verdict='),
         ('close-proposal', r'<!--\s*close-proposal\b(?!\s+dismissed)'), ('triage-ready', r'<!--\s*triage outcome=ready'),
         ('triage-clarify', r'<!--\s*triage outcome=(clarify|left)'), ('notice', r'<!--\s*dispatcher blocked\b'), ('blocked', r'<!--\s*blocked\b'),
         ('fix-round', r'<!--\s*babysit-round\b'),
         ('notice', r'<!--\s*unheard\b'),  # replies to people: person-facing
         ('machine', r'<!--\s*(pr-link|jira-link|sync|work-claim|close-proposal dismissed)\b'),
         ('machine', r'^\s*(?:🤖\s*)?(work|fix-bot|babysit):\s')]
BANNED = ['gate:', 'artifacts (pushed', 'what is done on the branch', 'what went wrong', 'all tests green',
          'fields set', 'decided for you', 'the merge was aborted', 'nothing was changed', 'i did not touch',
          'note that', 'as expected', 're-checked', 'plain comment', 'fail-closed', 'owner ruling',
          'current head', 'exact head']


def question_links(body):
    """[(issue number, comment id)] of every link to an issue comment, markdown or bare URL."""
    return [(int(n), int(i)) for n, i in re.findall(
        r'https://github\.com/[^/\s)]+/[^/\s)]+/(?:issues|pull)/(\d+)#issuecomment-(\d+)', body or '')]


def prose(body):
    """Visible text without fenced or inline code and quoted lines: what the bot itself says."""
    text = re.sub(r'```.*?```', '', visible(body), flags=re.S)
    text = re.sub(r'`[^`]*`', '', text)
    return '\n'.join(l for l in text.splitlines() if not l.lstrip().startswith('>'))


def refers_above(body):
    """The bot points at text 'above' (anywhere in its own words)."""
    return bool(re.search(r'\babove\b', prose(body), re.I))


def is_still_waiting(body, kind=None):
    """A notice that the card still waits on the person ('Waiting for your …', 'Still waiting for …'), or a triage
    clarify comment that points 'above' instead of asking."""
    if re.search(r'\b(still )?waiting (for|on) (your|the owner)', prose(body), re.I):
        return True
    return (kind or infer_kind(body)) == 'triage-clarify' and refers_above(body)


def duplicate_waiting_url(body, comments, number=None):
    """URL of the linked comment when `body` is a still-waiting notice whose linked comment is already the newest
    comment of the issue (nothing after it, by anyone): the notice would only repeat it.  None otherwise.
    Gate comments are never duplicates.  `comments` is the issue's comments, oldest first."""
    if not comments or not is_still_waiting(body) or infer_kind(body) == 'gate':
        return None
    last = comments[-1].get('id')
    for n, i in question_links(body):
        if i == last and (number is None or n == int(number)):
            m = re.search(r'https://github\.com/[^/\s)]+/[^/\s)]+/(?:issues|pull)/%d#issuecomment-%d' % (n, i), body)
            return m.group(0)
    return None


def refers_to_questions(body):
    return is_still_waiting(body) or refers_above(body)


def is_question_comment(body):
    return bool(re.search(r'<!--\s*triage outcome=clarify\b', body or ''))


def asks_for_answers(body):
    """The text waits for answers: still-waiting or answer phrasing, not any loose 'answer'/'question' word."""
    return bool(re.search(r'\bwaiting (?:for|on) (?:your|the owner(?:\'s)?) (?:answers?|questions?)\b|\b(?:your|the|my) answers? to\b|\banswers? (?:the|my|these) questions?\b'
                          r'|\bquestions? above\b', prose(body), re.I))


def hard_question_problems(body, kind=None):
    """Always refused (even in warn mode): a still-waiting notice without a link to the comment it means."""
    if is_still_waiting(body, kind) and not question_links(body):
        return ['a still-waiting notice must link the comment it waits on: write [questions](comment url) to the real '
                'comment, or do not post it when nothing is asked']
    return []


def question_link_problems(body):
    """Advisory/enforced like the style rules: any text pointing 'above' (or a waiting notice) needs a link.

    This stops a bot telling a person to answer 'the questions above' when nothing was asked."""
    if refers_to_questions(body) and not question_links(body):
        return ['names questions or text "above" without a link: write [questions](comment url) to the real comment, '
                'or do not post it when nothing is asked']
    return []


def current_anchor(comments):
    """(kind, comment) the card waits on, newest agent comment decides (like the dispatcher's wait_kind):
    'answer' (triage clarify), 'gate' or 'blocked'; (None, None) when a newer triage outcome ready/left ended it.
    Move/status notes (`gate-move`) are not anchors. Agent comments start with the bot emoji."""
    for c in reversed(comments):
        body = c.get('body') or ''
        if not body.lstrip().startswith('🤖'):
            continue
        if re.search(r'<!--\s*triage outcome=(ready|left)\b', body) and not is_question_comment(body):
            return None, None
        for kind, pattern in (('answer', r'<!--\s*triage outcome=clarify\b'), ('gate', r'<!--\s*gate stage='),
                              ('blocked', r'<!--\s*blocked\b')):
            if re.search(pattern, body):
                return kind, c
    return None, None


def infer_kind(body):
    for kind, pattern in INFER:
        if re.search(pattern, body or '', re.M | re.I):
            return kind
    return 'notice'


def visible(body):
    """Text a reader sees without expanding anything: no HTML comments, no <details> blocks."""
    text = re.sub(r'<!--.*?-->', '', body or '', flags=re.S)
    text = re.sub(r'<details>.*?</details>', '', text, flags=re.S | re.I)
    return text.strip()


def sections(text):
    """{heading: body} for '## ' headings, in order of appearance."""
    out, current = {}, None
    for line in text.splitlines():
        m = re.match(r'^##\s+(.+?)\s*$', line)
        if m:
            current = m.group(1)
            out[current] = []
        elif current is not None:
            out[current].append(line)
    return out


def lint(body, kind=None):
    kind = kind or infer_kind(body)
    problems = []
    text = visible(body)
    words = len(re.findall(r'\S+', text))
    if kind == 'machine':
        if words > BUDGETS['machine']:
            problems.append(f'{words} visible words; status/claim/link comments stay one line (≤ {BUDGETS["machine"]})')
        return problems
    first = next((l.strip() for l in text.splitlines() if l.strip()), '')
    m = re.match(r'^🤖\s+\*\*(.+?)\*\*', first)
    if not m or not m.group(1).startswith(WHO):
        problems.append('first line must be "🤖 **<who acts>: <what>**" with who acts one of: ' + ', '.join(WHO))
    else:
        what = m.group(1).split(':', 1)[1] if ':' in m.group(1) else ''
        if len(what.split()) > 12:
            problems.append(f'first line has {len(what.split())} words after the colon (≤ 12)')
    budget = BUDGETS.get(kind, BUDGETS['notice'])
    if words > budget:
        problems.append(f'{words} visible words; budget for {kind} is {budget} (move details into <details> or drop them)')
    found = sections(text)
    unknown = [h for h in found if h not in ORDER]
    if unknown:
        problems.append('unknown headings ' + ', '.join(f'"## {h}"' for h in unknown) + '; allowed: '
                        + ', '.join(f'## {h}' for h in ORDER))
    known = [ORDER.index(h) for h in found if h in ORDER]
    if known != sorted(known):
        problems.append('sections out of order; use: ' + ' → '.join(ORDER))
    for heading, lines in found.items():
        content = ' '.join(l.strip() for l in lines if l.strip()).strip(' -*').lower()
        if not content or content in ('none', 'none.', 'n/a'):
            problems.append(f'"## {heading}" is empty; drop a section that has no entries')
    for heading, limit in SECTION_LIMITS.items():
        bullets = [l for l in found.get(heading, []) if re.match(r'^\s*[-*]\s', l)]
        if len(bullets) > limit:
            problems.append(f'## {heading} has {len(bullets)} bullets (≤ {limit})')
    questions = re.split(r'(?m)^\d+\.\s', '\n'.join(found.get('Questions', [])))[1:]
    if len(questions) > 3:
        problems.append(f'{len(questions)} questions (≤ 3)')
    for i, q in enumerate(questions, 1):
        if '⭐' not in q:
            problems.append(f'question {i} has no ⭐ recommendation (options as "- _Option A_: … _[⭐ reason]_")')
    if re.search(r'(?<![(<])https?://\S+', text):
        problems.append('bare URL in visible text; write [PR #N](url) / [issue #N](url) / [design](url)')
    if '[!TIP]' in (body or ''):
        problems.append('no [!TIP] callouts; put the reply menu in <details>')
    if kind in MENU_KINDS and not re.search(r'<details>', body or '', re.I):
        problems.append('the reply menu must be collapsed in <details> (see the comment-style reference)')
    low = text.lower()
    hits = [b for b in BANNED if b in low]
    if hits:
        problems.append('avoid: ' + ', '.join(f'"{b}"' for b in hits))
    outside = re.sub(r'(?ms)^##\s+Decisions made\s*$.*?(?=^##\s|\Z)', '', text)
    outside = re.sub(r'`[^`]*`', '', outside)
    ids = sorted(set(re.findall(r'\b[TF]\d{1,2}\b', outside)))
    if ids:
        problems.append('bare IDs ' + ', '.join(ids) + ': name the thing instead')
    return problems
