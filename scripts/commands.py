"""One parser for owner commands (`/devbot approve`, `@bot-name fix rebase`, ...).

Ported from gm-agent-pipeline `pipeline/commands.py` (Daniel Gehriger). The handle defaults to `/devbot`;
`PR_AGENT_HANDLE` (space- or comma-separated) configures others; see normalize_handles().

Only the spelling is normalised here: sigil variants (`\\devbot` for a '/' handle), surrounding backticks, case,
`/devbot:` with or without a space, trailing punctuation, and verb inflections (`approved`, `fixes`, `re-review`).
Each caller keeps its own set of allowed verbs, ownership rules and what a verb does. No fuzzy matching: a word
is a verb only through the alias table or the conservative suffix rule below; anything else is None.

Standalone on purpose (stdlib only): the dispatcher and board scripts import it from their own directory.
"""
import re

DEFAULT_HANDLES = ('/devbot',)

# canonical verb -> accepted variants (irregular forms and listed synonyms; regular inflections are handled below)
ALIASES = {
    'approve': ('approved', 'approves', 'approving', 'approval'),
    'revise': ('revised', 'revises', 'revising'),
    'discuss': ('discussed', 'discusses', 'discussing'),
    'reject': ('rejected', 'rejects', 'rejecting'),
    'unblock': ('unblocked', 'unblocks', 'unblocking'),
    'answer': ('answered', 'answers', 'answering'),
    'close': ('closed', 'closes', 'closing'),
    'keep': ('kept', 'keeps', 'keeping'),
    'review': ('reviewed', 'reviews', 'reviewing', 're-review', 'rereview', 're-reviewed', 'rereviewed',
               're-reviews', 'rereviews', 're-reviewing', 'rereviewing'),
    'fix': ('fixed', 'fixes', 'fixing'),
    'babysit': ('babysat', 'babysits', 'babysitting'),
    'rebase': ('rebased', 'rebases', 'rebasing'),
    'merge': ('merged', 'merges', 'merging'),
}
VERBS = tuple(v for v in ALIASES if v not in ('rebase', 'merge'))   # command verbs
STRATEGIES = ('rebase', 'merge')                                    # words after `fix`, not commands
_LOOKUP = {variant: canon for canon, variants in ALIASES.items() for variant in variants}
_LOOKUP.update({canon: canon for canon in ALIASES})
# regular inflections of the canonical verbs only: stem + s | es | d | ed | ing (a dropped final 'e' is restored)
_SUFFIXES = ('ing', 'ed', 'es', 'd', 's')
_WORD = re.compile(r'([A-Za-z][A-Za-z-]*)')
_PUNCT = ' \t:.!,;'


def canonical(word):
    """The canonical verb or strategy word for a spelling, or None."""
    low = (word or '').lower()
    if low in _LOOKUP:
        return _LOOKUP[low]
    for suffix in _SUFFIXES:
        if low.endswith(suffix) and len(low) > len(suffix):
            stem = low[:-len(suffix)]
            for candidate in (stem, stem + 'e'):
                if candidate in ALIASES:
                    return candidate
    return None


def strategy(word):
    """'rebase' | 'merge' for a strategy word in any inflection, else None."""
    word = canonical(word)
    return word if word in STRATEGIES else None


def first_line(text):
    line = next((ln.strip() for ln in (text or '').splitlines() if ln.strip()), '')
    return line.strip('`').strip()


def _name_variants(handle):
    """The spellings of a handle's name with the sigils that stand for it: '/' also as '\\'; '@' only as '@'."""
    name = handle[1:]
    return [('/' + name, '/'), ('\\' + name, '/')] if handle.startswith('/') else [(handle, '@')]


def split(text, handles):
    """(handle, word, rest) for a first line that starts with one of the handles (any accepted sigil spelling,
    whole token), else None. `word` is the lower-cased first word after it with trailing punctuation dropped; it
    is not checked against any verb list. `rest` is what follows, leading punctuation and blanks removed."""
    line = first_line(text)
    low = line.lower()
    for handle in handles:
        for spelling, _ in _name_variants(handle):
            if not low.startswith(spelling):
                continue
            tail = line[len(spelling):]
            if tail and not (tail[0].isspace() or tail[0] == ':'):
                continue  # `/devbotx`, `/devbot-x`
            tail = tail.lstrip(' \t')
            if tail.startswith(':'):
                tail = tail[1:].lstrip(' \t')
            m = _WORD.match(tail)
            if not m:
                return None
            after = tail[m.end():]
            if '?' in re.split(r'\s', after, maxsplit=1)[0]:
                return None  # `approve?`, `approve.?`: a question, never an action
            if after and not (after[0].isspace() or after[0] in ':.!,;'):
                return None  # `approve_x`, `approve2`
            return handle, m.group(1).lower(), after.lstrip(_PUNCT).strip()
    return None


def parse(text, handles):
    """(handle, canonical_verb, rest) for a first line `<handle> <verb>[: rest]` in any accepted spelling, else None.
    The verb is one of VERBS; callers check it against their own allowed set."""
    found = split(text, handles)
    if not found:
        return None
    handle, word, rest = found
    verb = canonical(word)
    return (handle, verb, rest) if verb in VERBS else None


def normalize_handle(token):
    """A command handle token with its sigil: '/' or '@' kept, a bare name becomes '@name'; lower case."""
    token = (token or '').strip().strip('`').lower()
    if not token:
        return ''
    return token if token[0] in '/@' else '@' + token


def normalize_handles(raw):
    """Normalised, de-duplicated handle tokens in order (the first is the primary) from a string such as
    PR_AGENT_HANDLE ('/devbot @bot-name', commas allowed) or a list; `('/devbot',)` when none is configured."""
    tokens = raw.replace(',', ' ').split() if isinstance(raw, str) else list(raw or ())
    out = tuple(dict.fromkeys(t for t in (normalize_handle(t) for t in tokens) if t))
    return out or DEFAULT_HANDLES


def handle_logins(handles):
    """GitHub logins named by the '@' tokens (accounts the bots may post as); '/' tokens are not logins."""
    return {h[1:] for h in handles if h.startswith('@') and len(h) > 1}


def bot_logins(configured=(), handles=(), owners=(), shared=False, whoami=None):
    """Logins whose markers the tools trust (lower case): configured bot logins (PIPELINE_BOT_LOGINS), the
    '@' handles, and the owners when they share the bot's account; when none is known, the login `whoami()`
    returns (the account `gh` is logged in as). A '/' handle names no account, so the default `/devbot`
    alone relies on that fallback."""
    if isinstance(configured, str):
        configured = configured.replace(',', ' ').split()
    logins = {c.strip().lstrip('@').lower() for c in configured if c.strip().lstrip('@')}
    logins |= handle_logins(handles)
    if shared:
        logins |= {o.lower() for o in owners}
    if not logins and whoami is not None:
        me = (whoami() or '').strip().lower()
        if me:
            logins.add(me)
    return frozenset(logins)
