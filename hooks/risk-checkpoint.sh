#!/usr/bin/env bash
# PreToolUse(Bash|Edit|Write) risk-class checkpoint. Paxel report #1 growth-area #3.
# Hard-pauses high-blast-radius commands until a plan+rollback is stated.
#
# Bypass (one-shot, consumed only when it actually suppresses a match).
#
# TWO SEPARATE CALLS, ALWAYS. This is a PreToolUse hook: it reads the sentinel
# BEFORE the call it is judging runs. A sentinel armed inside that same call does
# not exist yet at check time, so `echo ... > <sentinel> && <op>` is always
# blocked and the echo half never executes. Arm in one call, re-run in the next.
#
#   SCOPED (preferred): echo "force push" > /tmp/risk-checkpoint-bypass.<session>
#                       -> skips ONLY that rule; every other rule stays armed.
#                       Comma/newline separated for several. `rule@/abs/path`
#                       scopes the grant to one target, `rule@*` to any path.
#   BLANKET:            echo ALL > /tmp/risk-checkpoint-bypass.<session>
#                       -> skips all rules. Logged loudly. A bare `touch` leaves
#                       the file EMPTY, which is REJECTED, not read as blanket.
#   The sentinel is per-session. Never hardcode the path above: the block message
#   quotes the one actually in force, which under a harness override differs.
#   Every use is appended to ~/.claude/logs/risk-checkpoint-bypass.log
# Disable entirely: touch /tmp/risk-checkpoint-off
RC_INPUT="$(cat)"
export RC_INPUT
python3 <<'PY'
import sys, json, os, re, time

# OFF SWITCH. Operator escape hatch, documented above: touch /tmp/risk-checkpoint-off.
#
# HARNESS SEAM (<phone>). risk-checkpoint-payload-test.sh has to prove this
# switch survives a payload that never parses, so it must flip a real one. It
# flipped the REAL path, which disarms this guard for every process on the box
# and not just for the test holding it. Inside one pre-commit run the serial lane
# keeps that window away from the sibling suites, but the lane is INTRA-INVOCATION
# and the path is global: a second session committing at the same moment (routine
# in ~/.claude, which several sessions share and commit to concurrently) opens the
# window under everyone else's feet.
# Observed <phone>: risk-checkpoint-test.sh reported mv-out-hook exp=BLOCK
# got=ALLOW once inside the gate, then passed 25/25 standalone and across three
# clean gate runs. The flaky FAIL is the mild half. The real cost is that every
# guarded op in every live session is waved through, unlogged, for the width of
# that window, and nothing in the log distinguishes it from a quiet minute.
# RC_OFF moves the harness's switch onto a private path. Same reasoning as
# RC_BYPASS below: a hook's environment comes from Claude Code, not from the
# command being judged, so the thing under judgement cannot set it. The basename
# is pinned, and anything else falls back to the real path, so a stray value
# leaves the guard armed rather than pointing it at an unrelated file.
_off = "/tmp/risk-checkpoint-off"
_off_env = os.environ.get("RC_OFF", "").strip()
if _off_env and os.path.basename(_off_env) == "risk-checkpoint-off":
    _off = _off_env
if os.path.exists(_off):
    sys.exit(0)
# FAIL CLOSED (<phone>). This was `except Exception: sys.exit(0)`, so ANY
# payload the parser choked on silently disarmed every rule in the guard, with
# nothing logged. The one input a bug most easily corrupts was also the one that
# turned the guard off. A guard that cannot read its input does not know whether
# the op is safe, and "unknown" must not resolve to "allowed".
#
# Recoverable BY DESIGN: /tmp/risk-checkpoint-off is checked ABOVE this block, so
# the escape hatch still works when the payload never parses. A persistent
# malformed-payload loop therefore cannot wedge every session with no way out,
# and the message below names the hatch rather than leaving it to be rediscovered.
#
# The isinstance check is not pedantry: a bare `null` or `[]` parses fine, then
# dies later on data.get(...) with an AttributeError, which exits NONZERO but not
# 2, so Claude Code does not treat it as a block. That is a fail-open wearing a
# traceback.
_raw = os.environ.get("RC_INPUT", "")
try:
    data = json.loads(_raw)
    if not isinstance(data, dict):
        raise ValueError("payload is %s, expected object" % type(data).__name__)
except Exception as _e:
    sys.stderr.write(
        "RISK-CHECKPOINT could not parse its hook payload, so it is FAILING "
        "CLOSED rather than waving this op through.\n"
        "  reason: %s\n"
        "  bytes:  %d\n"
        "This is a guard malfunction, not a risky command. If it persists and is "
        "not a transient shape change, disable deliberately with:\n"
        "  touch /tmp/risk-checkpoint-off\n" % (_e, len(_raw))
    )
    sys.exit(2)

# ---------------------------------------------------------------------------
# Tool dispatch.
#
# Bash       -> scan COMMAND TEXT (regex rules) + TOKENIZED WRITE TARGETS.
# Edit/Write -> scan TARGET PATH ONLY, never file content.
#
# <phone>: widened the matcher to Edit/Write, which had been rewriting any
# script in ~/.claude/hooks with no checkpoint and no audit line.
#
# <phone> (later, this file): the Bash side had the SAME hole from the other
# direction. The tool surface was guarded; the shell surface was not. cp, mv,
# tee, install, rsync, sed -i and plain `>` redirects into ~/.claude/hooks all
# passed, and settings.json's permissions block explicitly allows Bash(cp:*),
# Bash(mv:*), Bash(tee:*), Bash(sed:*) under defaultMode bypassPermissions, so
# nothing stopped them at either layer. Verified by probe: the install cp that
# first placed this very file left the bypass sentinel unspent and wrote no
# SCOPED line. Any agent that shells out could disarm every guard here.
#
# Regex on raw text cannot answer "is this path the TARGET of a write?": it
# cannot tell `cp hooks/x.sh /tmp/bak` (read) from `cp /tmp/x hooks/x.sh`
# (write), and every backup I take is the former. So the Bash side now tokenizes
# the command and asks about argument POSITION per verb. Same reason the Edit
# side checks the path and not the content: a target either is protected or is
# not.
# ---------------------------------------------------------------------------
TOOL = data.get("tool_name") or ""
TI = data.get("tool_input") or {}
WRITE_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")

def _norm(p):
    if not p:
        return ""
    try:
        return os.path.realpath(os.path.abspath(os.path.expanduser(str(p))))
    except Exception:
        return str(p)

HOME = os.path.expanduser("~")
CLAUDE_DIR = _norm(os.path.join(HOME, ".claude"))
HOOKS_DIR = os.path.join(CLAUDE_DIR, "hooks") + os.sep
SETTINGS_FILES = {
    os.path.join(CLAUDE_DIR, "settings.json"),
    os.path.join(CLAUDE_DIR, "settings.local.json"),
    os.path.join(CLAUDE_DIR, ".claude.json"),
    _norm(os.path.join(HOME, ".claude.json")),
}

# Rule NAMES are shared across Bash and Edit/Write where the risk class is
# identical, so one scoped-bypass string works for either surface.
R_SETTINGS = "account/harness settings write"
R_HOOK = "hook script write"

PATH_RULES = [
    (R_SETTINGS, lambda p: p in SETTINGS_FILES),
    (R_HOOK, lambda p: p.startswith(HOOKS_DIR)),
]

cmd = ""
if TOOL == "Bash":
    cmd = (TI.get("command", "") or "")
    if not cmd.strip():
        sys.exit(0)
elif TOOL not in WRITE_TOOLS:
    sys.exit(0)

# ---------------------------------------------------------------------------
# Sentinel path. Overridable ONLY so the test harness can use a private one.
#
# WHY (<phone>): the suite drives this hook for real, against the real
# sentinel. So a run would (a) fail spuriously whenever a bypass happened to be
# armed, since the probe `mv <hook> /tmp/` is indistinguishable from the
# operator's own, and (b) CONSUME that live bypass on the way past. Both
# observed. A suite whose verdict depends on ambient machine state is not a
# suite, and one that silently eats a real bypass is worse than a flaky one.
#
# Two constraints, both load-bearing:
#   1. BASENAME MUST MATCH. Consuming a sentinel is os.remove(BP), and the
#      BLANKET branch below fires on a file that is merely EMPTY. So an
#      unrestricted override is an arbitrary-empty-file-delete primitive that
#      ALSO disarms every rule in one step. Pinning the basename means the only
#      file this can ever unlink is one already named risk-checkpoint-bypass.
#   2. A BAD OVERRIDE FAILS CLOSED, to "" -> os.path.exists("") is False -> no
#      bypass is honored at all. Falling back to the default would silently
#      recreate the exact bug above by pointing a stray harness at the real one.
#
# This does not widen the live guard. A hook's environment comes from Claude
# Code, NOT from the command being judged, so `RC_BYPASS=... <cmd>` cannot move
# the sentinel out from under the running guard. Only a process that spawns
# this hook directly (the harness) can set it, and every use is audited with
# the path it used.
BP_NAME = "risk-checkpoint-bypass"
# PER-SESSION SENTINEL (<phone>). It was ONE global /tmp file shared by every
# concurrent session, so session A armed a scoped bypass and session B's guarded
# op consumed it first. Observed with 5 sessions live in ~/.claude: three arms in
# a row were eaten by another session editing a DIFFERENT file, and the audit log
# looked like it was misattributing when it was in fact telling the truth.
# The session id is sanitized before it lands in a path that reaches os.remove():
# an unfiltered id here is an arbitrary-file-delete primitive via "../".
# No session_id (hook run outside Claude Code) falls back to the shared path and
# SAYS SO below, rather than failing closed and leaving no way to bypass at all.
_sid = re.sub(r"[^A-Za-z0-9_-]", "", str(data.get("session_id") or ""))[:64]
BP = "/tmp/" + BP_NAME + ("." + _sid if _sid else "")
_bp_env = os.environ.get("RC_BYPASS", "").strip()
if _bp_env:
    _b = os.path.basename(_bp_env)
    BP = _bp_env if (_b == BP_NAME or _b.startswith(BP_NAME + ".")) else ""
LOG = os.path.expanduser("~/.claude/logs/risk-checkpoint-bypass.log")
# SENTINEL TTL (<phone>). Consumption is deliberately tied to SUPPRESSION: a
# sentinel is spent only when it actually waves a hit through (below). That is
# the right rule for the arm->re-run flow, but it leaves an arm that suppresses
# NOTHING never spent at all, so the grant stays live for the rest of the
# session and silently waves through the next unrelated op that trips that rule.
# Walked into by this agent: armed "account/harness settings write", then re-ran
# a corpus that no longer carried the vector. Nothing fired, so nothing was
# consumed, and the grant sat there armed against a rule it was never spent on.
# Neither the audit log nor the block message showed anything wrong, because
# from the guard's side nothing HAD happened yet.
# An arm and its re-run are seconds apart. Anything older is not the operator
# still driving that decision, it is residue from one that went another way.
# Stale sentinels are removed on sight and audited, never quietly honoured:
# expiry is a thing that happened TO a grant and has to be visible as one.
# <phone>: ASYMMETRIC, and the asymmetry is the point. Was one symmetric
# BP_TTL=90 used for both directions, which conflates two unrelated risks.
#
# PAST 90 -> 300, from the audit log, not from taste. Of 612 real bypass
# failures, 330 (54%) were EXPIRED: a sentinel armed, then the guarded call
# arrived past the window and was blocked anyway. Every one of those is a grant
# the operator DID intend, thrown away on a stopwatch. The arm->act round trip
# is not always seconds: deriving the scoped rule@path form, or an intervening
# tool call, routinely eats more than 90s. Widening the past side costs little,
# because a sentinel is single-use (removed the moment it is spent), per-session
# and per-path; the past bound only ever catches a FORGOTTEN grant.
#
# FUTURE stays TIGHT (5s, clock jitter only) and is now 18x STRICTER than the
# 90 it inherited. A future mtime is not a slow operator, it is a skewed clock
# or a hand-set timestamp, and under the old symmetric bound it minted a grant
# valid for the whole window. Raising the past side to 300 would have widened
# that to 300s too. Caught by tests/risk-checkpoint-test.sh ttl-future on the
# first attempt at this change, which asserted +200s must BLOCK and got ALLOW.
BP_TTL_PAST = 300
BP_TTL_FUTURE = 5
# Retained: the block message and audit both quote it as the operator-facing
# limit, and the past bound is the one an operator actually races.
BP_TTL = BP_TTL_PAST

# ---------------------------------------------------------------------------
# Tokenizer. Shell-shaped enough for the two questions asked of it:
#   1. which words are the TARGET of a write operator or write verb
#   2. which character ranges are inert quoted DATA
# Records absolute offsets so quoted spans can be blanked in place, keeping
# every other offset valid.
# ---------------------------------------------------------------------------
# NEWLINE IS AN OPERATOR, not whitespace. <phone>: it was whitespace, so
# `cd ~/.claude/hooks || exit 1` + newline + `cp /tmp/x rc.sh` parsed as ONE
# trailing segment whose verb was `exit`, and no target was ever extracted.
# Fail-open on exactly the multi-line shape most real commands take. Caught by
# the install of this file passing unblocked with the sentinel unspent.
# FIFTH and SIXTH instances of the destination steal, <phone>.
#
# GROUPING. `(` `)` `{` `}` were not operators, so `( cp src GUARDED )`
# tokenized with `(` glued to the verb: the segment verb became `(cp`, the
# LAST_ARG_VERBS lookup missed, and no destination was ever extracted.
# Verified writing in bash 5.3.9 and zsh 5.9, tight and spaced and nested.
# Same blind spot as substitution: the walker never descended into a
# grouped command. Parens are unconditional here because an unquoted paren
# cannot legally sit inside a word; braces are conditional, see tokenize.
#
# CLOBBER OVERRIDE. `>|` bypasses noclobber and is a real write sink. It
# was absent from OP_RE, so it tokenized as `>` then `|` and the PIPE split
# the segment, carrying the destination off into a new one where nothing
# looked for it. `2>|` truncates. `&>|` and `>>|` are zsh-only, and this
# box runs zsh, so they are covered too.
#
# NOTE the shape of this miss: p2 proves CLOSURE over the operators OP_RE
# can emit. `>|` was never emitted, so closure was vacuously true for it.
# Closure over the emitted set can never find an operator missing from the
# set. That is what p10 below tests against the SHELL, not against OP_RE.
OP_RE = re.compile(r"(\|\||&&|\|&|\||;;|;|&>>\||&>>|&>\||&>|\d*>>\||\d*>>|\d*>&|\d*>\||\d*>|<<<|<<-|<<|<&|<|&|\(|\)|\n)")
SUBST = re.compile(r"\$\(|`|\$\{")

def tokenize(text):
    toks, i, n = [], 0, len(text)
    cur, spans, started = "", [], False

    def flush():
        nonlocal cur, spans, started
        if started:
            fullq = bool(spans) and sum(len(s["body"]) for s in spans) == len(cur)
            toks.append({"t": "w", "v": cur, "spans": spans, "q": fullq})
        cur, spans, started = "", [], False

    while i < n:
        ch = text[i]
        if ch in " \t\r":
            flush(); i += 1; continue
        # Brace GROUP `{ cmd; }` is a command boundary. Brace EXPANSION
        # `{a,b}` inside a word is NOT, and splitting there would tear
        # `hooks/{a,b}.sh` in half and drop the guarded prefix, turning a
        # correct block into an allow. bash requires the group brace to be
        # a standalone reserved word, which is exactly this test: nothing
        # accumulated yet, and whitespace following.
        if ch == "{" and not started and i + 1 < n and text[i + 1] in " \t\r\n":
            flush(); toks.append({"t": "o", "v": "{"}); i += 1; continue
        if ch == "}" and not started:
            flush(); toks.append({"t": "o", "v": "}"}); i += 1; continue
        m = OP_RE.match(text, i)
        if m:
            flush()
            toks.append({"t": "o", "v": m.group(1)})
            i = m.end(); continue
        if ch == "\\":
            started = True
            if i + 1 < n:
                cur += text[i + 1]; i += 2
            else:
                i += 1
            continue
        if ch == "'":
            j = text.find("'", i + 1)
            if j == -1:
                j = n
            body = text[i + 1:j]
            spans.append({"body": body, "a0": i, "a1": min(j + 1, n), "sub": False})
            cur += body; started = True; i = j + 1
            continue
        if ch == '"':
            j, body = i + 1, ""
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    body += text[j + 1]; j += 2; continue
                if text[j] == '"':
                    break
                body += text[j]; j += 1
            spans.append({"body": body, "a0": i, "a1": min(j + 1, n),
                          "sub": bool(SUBST.search(body))})
            cur += body; started = True; i = j + 1
            continue
        cur += ch; started = True; i += 1
    flush()
    return toks

# ---------------------------------------------------------------------------
# Normalize step 1: drop heredoc bodies that are provably inert DATA.
#
# WHY (<phone>): the gate matched raw command text, so a command that merely
# MENTIONED a risk op was indistinguishable from one that performed it. Writing
# a test fixture containing "systemctl" or "git push --force" tripped it.
#
# A heredoc whose delimiter is QUOTED (<<'EOF') undergoes no expansion: the
# shell hands the body to the receiver verbatim as stdin. If that receiver is a
# pure data sink, the body cannot execute anything and must not be scanned.
#
# ALLOWLIST, NEVER DENYLIST. An unrecognised receiver keeps its body scanned, so
# a gap here is a false positive (fail-safe), never a bypass (fail-open). This
# is why interpreters are absent: `python3 <<'PY'` executes its body.
# ---------------------------------------------------------------------------
# <phone>: verb-only receiver detection was itself a mention-vs-perform bug.
# `git commit -F - <<'MSG'` is a pure data sink (git cannot execute a commit
# message), but "git" is not in DATA_SINKS, so the body stayed scanned and this
# hook blocked the very commit that introduced it, on prose describing the rules.
# Subcommand-aware, matching the quoted-span allowlist below.
DATA_SINKS = {"cat", "tee"}
HEREDOC_SUB_SINKS = {"git": {"commit", "tag", "notes"},
                     "gh": {"pr", "issue", "release", "gist"}}
SEG_SPLIT = re.compile(r"\|\||&&|[|;&]")
HEREDOC = re.compile(r"<<-?\s*(['\"])([A-Za-z_][A-Za-z0-9_]*)\1")

def strip_inert_heredocs(text):
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = HEREDOC.search(line)
        if not m:
            i += 1
            continue
        delim = m.group(2)
        seg = SEG_SPLIT.split(line[:m.start()])[-1].strip()
        words = seg.split()
        wi = 0
        while wi < len(words) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[wi]):
            wi += 1
        recv = os.path.basename(words[wi]) if wi < len(words) else ""
        inert = recv in DATA_SINKS
        if recv in HEREDOC_SUB_SINKS:
            sub = ""
            for w in words[wi + 1:]:
                if not w.startswith("-"):
                    sub = w
                    break
            inert = sub in HEREDOC_SUB_SINKS[recv]
        j, body = i + 1, []
        while j < len(lines) and lines[j].strip() != delim:
            body.append(lines[j]); j += 1
        if not inert:
            out.extend(body)          # fail-safe: keep scanning
        if j < len(lines):
            out.append(lines[j])      # delimiter line
        i = j + 1
    return "\n".join(out)

# --- segment / verb structure ----------------------------------------------
CTRL = {"||", "&&", ";", ";;", "&", "|", "|&", "\n", "(", ")", "{", "}"}
PIPE = {"|", "|&"}
# The trailing &? is load-bearing (<phone>). The tokenizer emits `2>&1` as
# ONE operator `2>&` plus the word `1`. Without &? this pattern did not match
# `2>&`, so seg_parts never consumed the following word, `1` stayed in words,
# and cp/install/rsync/scp/ln (LAST_ARG_VERBS, destination = plain[-1]) took
# the fd number `1` as their destination instead of the real path. Net effect:
# appending `2>&1` to any such write into a guarded tree was a silent TOTAL
# bypass. Found by accident, not by probe: a routine
# `cp /tmp/src ~/.claude/hooks/x.sh 2>&1 | head` ran unguarded and only a
# missing source file stopped the write. Plain `cp a b` blocked because there
# was no trailing word to steal the destination slot.
REDIR_T = re.compile(r"^(&?>>?\|?|\d*>>?[&|]?)$")
# Input redirects are the same bug in the other direction (found <phone> by
# probing every operator shape, not by accident this time). REDIR_T covers `>`
# only, so `0<&3`, `3<&0` and `<<<x` left their trailing word in `words` and
# LAST_ARG_VERBS took the fd number / herestring body as the destination:
# `cp /tmp/x ~/.claude/hooks/z.sh 0<&3` ran unguarded, exactly the 2>&1 shape.
# These are reads, so the target is consumed but NEVER recorded as a write sink
# (recording it would resolve `3` against cwd and false-block reads from inside
# a guarded tree, which is the regression the &-duplication branch below exists
# to avoid).
#
# `<<-` WAS MISSED by that hand enumeration. The pattern was `^\d*<(&|<<?|>)?$`,
# a nesting that happens not to reach `<<-`, so the commit that closed six input
# shapes left the seventh open and `cp /tmp/x ~/.claude/hooks/z.sh <<- EOF` still
# ran unguarded. Caught by tests/risk-checkpoint-redir-property-test.sh on its
# first run, which is the entire argument for deriving the operator alphabet
# from OP_RE instead of listing shapes by hand: three bypasses in this family
# were all found by probe, none by the case list that was green throughout.
# Now an explicit mirror of OP_RE's own input alternatives, same order, so the
# two can be diffed by eye. Matches `<` `n<` `<&` `<<` `<<-` `<<<` `<>`.
REDIR_IN_T = re.compile(r"^\d*(<<<|<<-|<<|<&|<>|<)$")

# FOURTH instance of the destination steal, found <phone> by probing shapes
# the property test CANNOT reach by construction. `{v}>file` is bash/zsh fd-
# variable syntax: the shell allocates a descriptor and assigns it to $v. The
# tokenizer sees `{v}` as an ordinary WORD (it is not in OP_RE and never can be,
# OP_RE enumerates operators) followed by the operator `>`. So the fd sat in
# `words` exactly like the bare `2` of `2>&1`, and LAST_ARG_VERBS took it as the
# destination:
#   cp /tmp/src ~/.claude/hooks/z.sh {v}>tail     ran UNGUARDED
# Verified live in bash 5.3.9 and zsh: both consume `{v}>` as a redirect, cp
# receives two arguments, and the write into the guarded tree really happens.
# Same shape as the bare-fd pop below, so the fix is the same pop.
FD_VAR = re.compile(r"^\{[A-Za-z_][A-Za-z0-9_]*\}$")

def _is_fd_word(v):
    """Word occupying the fd slot immediately before a redirect operator: the
    bare `2` of `2>&1`, or the `{v}` of `{v}>file`. Only ever consulted AT a
    redirect token, so a literal argument named `{v}` with no following
    redirect keeps its place in words."""
    return v.isdigit() or bool(FD_VAR.match(v))

PREFIX_SKIP = {"env", "command", "sudo", "doas", "nohup", "setsid", "time",
               "builtin", "exec", "nice", "stdbuf", "xargs", "then", "do",
               "else", "elif", "if", "while", "until"}

def split_segments(toks):
    segs, cur = [], []
    for t in toks:
        if t["t"] == "o" and t["v"] in CTRL:
            segs.append({"toks": cur, "term": t["v"]}); cur = []
        else:
            cur.append(t)
    segs.append({"toks": cur, "term": ""})
    return segs

def seg_parts(seg):
    """-> (words, redirect_target_words). Redirect targets are removed from
    words so a verb's 'last argument' is not the fd of `2>/dev/null`."""
    words, redirs, i = [], [], 0
    toks = seg["toks"]
    while i < len(toks):
        t = toks[i]
        if t["t"] == "o":
            if REDIR_T.match(t["v"]):
                if words and _is_fd_word(words[-1]["v"]):
                    words.pop()          # fd left by `2` + `>`, or `{v}` + `>`
                if i + 1 < len(toks) and toks[i + 1]["t"] == "w":
                    tgt = toks[i + 1]
                    # fd duplication (`2>&1`, `>&2`, `2>&-`): operator ends in
                    # `&` and the target is a descriptor, not a path. Consume it
                    # so it cannot be stolen as a LAST_ARG_VERBS destination
                    # (the <phone> bypass above), but do NOT record it as a
                    # write sink: doing so resolved `1` against cwd and blocked
                    # every `2>&1` command run from inside a guarded tree.
                    # `&>file` keeps its trailing `>` and is still a real write.
                    if t["v"].endswith("&") and re.fullmatch(r"\d+|-", tgt["v"]):
                        i += 2; continue
                    redirs.append(tgt); i += 2; continue
            if REDIR_IN_T.match(t["v"]):
                if words and _is_fd_word(words[-1]["v"]):
                    words.pop()          # fd left by `0` + `<&`, or `{v}` + `<`
                if i + 1 < len(toks) and toks[i + 1]["t"] == "w":
                    i += 2; continue     # consumed, never a write sink
            i += 1; continue
        words.append(t); i += 1
    return words, redirs

def verb_of(words):
    k = 0
    while k < len(words):
        v = words[k]["v"]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", v):
            k += 1; continue
        b = os.path.basename(v.lstrip("\\"))
        if b in PREFIX_SKIP:
            k += 1; continue
        return b, words[k + 1:]
    return "", []

# ---------------------------------------------------------------------------
# Normalize step 2: blank quoted spans that are inert DATA arguments.
#
# WHY (<phone>): the same MENTION-vs-PERFORM confusion survived outside
# heredocs. `grep -n 'git push --force' hooks/x.sh` and feeding a test payload
# to this very hook both blocked, on text that no shell would ever execute.
#
# Conditions, all required, all fail-safe:
#   - the span is single-quoted, or double-quoted with no $( ) ` or ${ }
#   - the receiving verb is on a small allowlist of non-executors
#   - NO segment anywhere in the same pipeline is an interpreter. `echo 'rm -rf
#     ~' | bash` executes; stripping there would be fail-open, so the whole
#     pipeline keeps its quotes.
#   - the span is not a redirect target or a tee/sink argument. `printf 'x' >
#     '~/.claude/hooks/a.sh'` writes to a quoted path; blanking it would hide
#     the target.
# A local ./script.sh is NOT counted as an interpreter. Script bodies are
# already unscannable (`bash /tmp/x.sh` has always been opaque here), so
# treating one as an executor would block every test of this hook while closing
# nothing.
# ---------------------------------------------------------------------------
EXECUTORS = {"bash", "sh", "zsh", "ksh", "dash", "fish", "csh", "tcsh",
             "python", "python2", "python3", "node", "deno", "bun", "perl",
             "ruby", "php", "lua", "eval", "xargs", "sudo", "doas", "ssh",
             "env", "script", "osascript", "expect", "nc", "socat",
             "awk", "gawk", "mawk", "find", "parallel", "watch"}
STRIP_RECV = {"echo", "printf", "grep", "egrep", "fgrep", "rg", "ag", "jq",
              "yq", "wc", "diff", "comm", "sort", "uniq", "head", "tail",
              "cut", "tr", "column", "cat", "less", "more", "sed", "curl",
              "test", "["}
GIT_STRIP_SUB = {"commit", "tag", "notes"}
GH_STRIP_SUB = {"pr", "issue", "release", "gist"}
SINK_VERBS = {"tee"}

def blank_inert_quoted(text, segs):
    kill = []
    i = 0
    while i < len(segs):
        # gather one pipeline
        grp = [segs[i]]
        while segs[i]["term"] in PIPE and i + 1 < len(segs):
            i += 1; grp.append(segs[i])
        i += 1
        parsed = []
        exec_here = False
        for s in grp:
            words, redirs = seg_parts(s)
            verb, args = verb_of(words)
            if verb in EXECUTORS:
                exec_here = True
            parsed.append((verb, args, words, redirs))
        if exec_here:
            continue
        for verb, args, words, redirs in parsed:
            if verb not in STRIP_RECV and verb not in ("git", "gh"):
                continue
            sub = ""
            for a in args:
                if not a["v"].startswith("-"):
                    sub = a["v"]; break
            if verb == "git" and sub not in GIT_STRIP_SUB:
                continue
            if verb == "gh" and sub not in GH_STRIP_SUB:
                continue
            protect = {id(w) for w in redirs}
            if verb in SINK_VERBS or verb in ("cat",):
                protect |= {id(w) for w in args}
            for w in args:
                if id(w) in protect:
                    continue
                for sp in w["spans"]:
                    if not sp["sub"]:
                        kill.append((sp["a0"], sp["a1"]))
    if not kill:
        return text
    buf = list(text)
    for a0, a1 in kill:
        for k in range(a0, min(a1, len(buf))):
            buf[k] = " "
    return "".join(buf)

# ---------------------------------------------------------------------------
# Write-target extraction. Position matters per verb:
#   cp/install/rsync/scp/ln -> LAST non-flag arg only. `cp hooks/x.sh
#     /tmp/bak` reads a hook; `cp /tmp/x hooks/x.sh` overwrites one. An
#     argument-anywhere match would block every backup, which is most of what
#     touching this directory legitimately looks like. These verbs all LEAVE
#     THE SOURCE IN PLACE, which is what makes source position safe to ignore.
#   rm/unlink/shred/truncate/chmod/chown/chflags/mv -> ALL args. chmod -x on a
#     hook disarms it as surely as rewriting it; deleting one disarms it more.
#     mv belongs here and NOT with cp: `mv hooks/risk-checkpoint.sh /tmp/`
#     removes the guard as completely as `rm` does, and a destination-only
#     check never sees it. Any mv touching a guarded path is either a write in
#     or a removal out, so both positions are worth an audit line.
#     `rsync --remove-source-files` is the remaining source-removing case and
#     is a known residual gap.
#   sed -i / perl -i / ed -> all args except the quoted, nonexistent one (the
#     script). A quoted arg that IS an existing file is treated as a target.
#   dd -> of=
#   git checkout/restore -> pathspecs. Refs resolve outside the guarded dirs.
#   any verb -> its > >> &> tee targets.
#
# Relative paths resolve against the payload cwd, updated by `cd` earlier in
# the SAME command, which is how `cd ~/.claude/hooks && cp /tmp/x rc.sh` is
# caught. A `cd` from a PREVIOUS Bash call is not visible in the payload and is
# a known residual gap, as is any write performed inside a script this hook
# cannot read.
# ---------------------------------------------------------------------------
LAST_ARG_VERBS = {"cp", "install", "rsync", "scp", "ln"}
ALL_ARG_VERBS = {"rm", "unlink", "shred", "truncate", "chmod", "chown",
                 "chgrp", "chflags", "mv"}
INPLACE_VERBS = {"sed", "gsed", "perl", "ed", "ex"}
GIT_WRITE_SUB = {"checkout", "restore"}

def _expand(a):
    a = a.replace("${HOME}", HOME).replace("$HOME", HOME)
    if a == "~" or a.startswith("~/"):
        a = HOME + a[1:]
    return a

def resolve(arg, cwd):
    a = _expand(str(arg))
    if not a:
        return ""
    if not os.path.isabs(a):
        a = os.path.join(cwd, a)
    a = os.path.normpath(a)
    d, b = os.path.split(a)
    try:
        d = os.path.realpath(d)
    except Exception:
        pass
    return os.path.join(d, b) if b else d

def classify(p):
    if not p:
        return None
    if p in SETTINGS_FILES:
        return R_SETTINGS
    if p == HOOKS_DIR.rstrip(os.sep) or p.startswith(HOOKS_DIR):
        return R_HOOK
    return None

# <phone>: classify() answers "is this path guarded?", which misses the
# wholesale disarm: `mv ~/.claude /tmp/` and `rm -rf ~` carry hooks/ AND
# settings.json out together while naming neither, so every rule above returns
# None and the command is allowed. Found by probe after the mv fix. Same
# family of bug (the check looked at the path named, not at what containing it
# implies), and strictly larger, since it disarms every rule at once.
#
# Kept OUT of classify() on purpose. classify() is called on destination
# positions too, where an ancestor is not a disarm at all: `cp /tmp/a ~/` and
# `mv /tmp/x ~/` write INTO the container and must stay allowed. Only the
# caller still knows verb and argument position, so only the caller may ask
# this question. See write_targets.
def classify_container(p):
    """R_* if p strictly CONTAINS the guarded tree (i.e. removing p removes it).

    Trailing-separator compare so ~/.claudex does not match ~/.claude. p == "/"
    normalises to "/" and still matches, which is correct: `rm -rf /` disarms
    everything here too.
    """
    if not p:
        return None
    anc = p if p.endswith(os.sep) else p + os.sep
    if HOOKS_DIR.startswith(anc):
        return R_HOOK
    if any(s.startswith(anc) for s in SETTINGS_FILES):
        return R_SETTINGS
    return None

# Filled by write_targets / the tool branch: which resolved path produced which
# rule. The bypass needs this to be PATH SCOPED, so a grant for one hook cannot
# be spent on a different hook.
TARGET_PATHS = []

def write_targets(segs, cwd0):
    hits, cur = [], cwd0
    for s in segs:
        words, redirs = seg_parts(s)
        verb, args = verb_of(words)
        cands, plain, term = list(redirs), [], False
        for a in args:
            v = a["v"]
            if not term and v == "--":
                term = True; continue
            if not term and v.startswith("-") and len(v) > 1:
                continue
            plain.append(a)
        if verb in LAST_ARG_VERBS:
            if plain:
                cands.append(plain[-1])
        elif verb in ALL_ARG_VERBS or verb in SINK_VERBS:
            cands += plain
        elif verb in INPLACE_VERBS:
            if any(re.match(r"^-[A-Za-z]*i", a["v"]) for a in args):
                for a in plain:
                    if a["q"] and not os.path.exists(resolve(a["v"], cur)):
                        continue
                    cands.append(a)
        elif verb == "dd":
            for a in args:
                if a["v"].startswith("of="):
                    cands.append({"v": a["v"][3:], "q": False, "spans": []})
        elif verb == "git":
            if plain and plain[0]["v"] in GIT_WRITE_SUB:
                cands += plain[1:]
        # Container removals. classify_container asks "does removing this path
        # remove the guarded tree?", which is only meaningful in a REMOVAL
        # position, hence not folded into the cands loop below, which also
        # carries destinations. cp/install/rsync/scp/ln and redirect sinks are
        # excluded entirely: they write INTO a path and leave it in place. For
        # mv the last arg is the destination (`mv /tmp/x ~/` writes in and must
        # stay allowed), so only plain[:-1] are sources; every other all-arg
        # verb destroys each path it names. A lone arg is treated as a removal.
        if verb in ALL_ARG_VERBS:
            removals = plain[:-1] if (verb == "mv" and len(plain) > 1) else plain
            for a in removals:
                p = resolve(a["v"], cur)
                r = classify_container(p)
                if r:
                    if r not in hits:
                        hits.append(r)
                    if (r, p) not in TARGET_PATHS:
                        TARGET_PATHS.append((r, p))
        for a in cands:
            p = resolve(a["v"], cur)
            r = classify(p)
            if r:
                if r not in hits:
                    hits.append(r)
                if (r, p) not in TARGET_PATHS:
                    TARGET_PATHS.append((r, p))
        if verb == "cd" and plain:
            cur = resolve(plain[0]["v"], cur)
    return hits

SAFE = re.compile(r"(/tmp/|/var/tmp/|/private/tmp/|node_modules|\.next|dist/|build/|\.cache|__pycache__|\.pytest_cache|\.ruff_cache|\.mypy_cache|\.egg-info|/Caches/)")
RM = re.compile(r"\brm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|-rf|-fr)\b", re.I)

RULES = [
    ("destructive delete", lambda c: bool(RM.search(c)) and not SAFE.search(c)),
    ("git history rewrite", lambda c: bool(re.search(r"git\s+reset\s+--hard|git\s+clean\s+-[a-z]*f[a-z]*d|git\s+clean\s+-[a-z]*d[a-z]*f", c))),
    # The .* used to span the ENTIRE command string, so it crossed ; && || and
    # newlines. Measured <phone>: `git push -q origin main; pgrep -f x` was
    # blocked as a force push, because the -f belonged to pgrep two commands
    # later. A guard that fires on an ordinary push teaches the operator to arm
    # the bypass by reflex, which is worse than not having the guard at all.
    # Confined to the same command now.
    ("force push", lambda c: bool(re.search(r"git\s+push\b[^;&|\n]*(--force\b|--force-with-lease|\s-f\b)", c))),
    # crontab: block WRITES but NOT the read-only `crontab -l`. The old
    # `(-r|-)` matched the dash in `-l` and false-blocked listing every session.
    ("system daemon (launchd/cron)", lambda c: bool(re.search(r"\blaunchctl\s+(bootstrap|bootout|load|unload|enable|disable|kickstart)\b|\bcrontab\s+(?!-l\b)|\bsystemctl\b", c))),
    ("immutable flag", lambda c: bool(re.search(r"\bchflags\s+\w*(schg|uchg|simmutable)|\bchattr\s+[+-]i\b", c))),
    ("destructive SQL", lambda c: bool(re.search(r"\b(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)\b|\bdropdb\b", c, re.I))),
    ("repo visibility / delete", lambda c: bool(re.search(r"gh\s+repo\s+(delete|archive)\b|gh\s+repo\s+edit\b.*--visibility|gh\s+api\b.*visibility", c))),
    # Settings-write by text is kept alongside the tokenizer as belt-and-braces:
    # the redirect target must directly follow the operator, so `2>/dev/null` on
    # a read-only grep does not fire while `>> ~/.claude/settings.json` does.
    (R_SETTINGS, lambda c: (
        bool(re.search(r"(>>?|tee\s+(-a\s+)?)\s*['\"]?[^\s|&;>]*\.claude/(settings(\.local)?\.json|\.claude\.json)\b", c))
        or bool(re.search(r"\b(sed\s+-i|cp|mv)\b[^|&;]*\.claude/(settings(\.local)?\.json|\.claude\.json)\b", c))
        or bool(re.search(r"\bdefaults\s+write\b", c))
    )),
    # find's OWN action flags. The tokenizer models redirects and sed/cp/mv, and the
    # text rules above want the mutator and the path in one statement, so
    # `find ~/.claude/hooks -name '*.sh' -exec sed -i '' s/a/b/ {} +` reached disk with
    # no block, no bypass and no audit line. Found <phone> while fixing the
    # guarded-var false positive, and confirmed a PRE-EXISTING gap by replaying the same
    # command against the pre-patch copy of this file, which also allowed it.
    # The exec'd verb must itself mutate: `-exec grep` and `-exec wc` stay allowed,
    # because a guard that blocks read-only traversal of this directory is the very
    # thing that trains `echo ALL`.
    (R_HOOK, lambda c: bool(re.search(r"\bfind\b[^|;&]*\.claude/hooks", c))
             and bool(re.search(r"-delete\b|-exec(?:dir)?\s+(?:sed\s+-i|rm|mv|cp|tee|truncate|chmod|chown|ln|install)\b", c))),
    (R_SETTINGS, lambda c: bool(re.search(r"\bfind\b[^|;&]*\.claude/(?:settings(?:\.local)?\.json|\.claude\.json)", c))
             and bool(re.search(r"-delete\b|-exec(?:dir)?\s+(?:sed\s+-i|rm|mv|cp|tee|truncate|chmod|chown|ln|install)\b", c))),
    ("disk/device write", lambda c: bool(re.search(r"\bdd\b.*\bof=/dev/|\bdiskutil\s+(erase|partition|reformat)|\bmkfs\b", c))),
    ("recursive force chmod/chown", lambda c: bool(re.search(r"\bch(mod|own)\s+-[a-z]*R[a-z]*\s+.*(/|~)", c)) and not SAFE.search(c)),
]

# ---------------------------------------------------------------------------
# Interpreters doing their own file I/O. <phone>, found by probe after the
# container fix. write_targets answers "which WORD is the target of a write
# VERB", and `python3 -c "open('~/.claude/hooks/x','w').write(...)"` has no
# write verb and no write operator: the verb is `python3`, `-c` is dropped as a
# flag, and the payload is one opaque plain arg. Every rule returned None and
# the disarm was ALLOWED. Same for perl -e, ruby -e, node -e, and `sh -c` with
# a redirect inside the quotes, which blank_inert_quoted deliberately leaves
# live but which no verb rule then reads. Eight shapes, all total bypasses.
#
# Scanned as TEXT over text1 (inert heredoc bodies already stripped, quoted
# spans NOT yet blanked): the only string where BOTH inline -c code and live
# heredoc bodies are visible. A heredoc body arrives as its own segments whose
# verbs are Python fragments, so the tokenizer cannot reach it at all.
#
# Gated on THREE things at once, because any one alone false-blocks:
#   1. an interpreter invoked with INLINE CODE or a heredoc, not the bare
#      word python3, or `grep python3 file` would block
#   2. a MUTATION token, or read-only diagnostics would block, and reading
#      settings.json through python3 is routine and legitimate here
#   3. a LITERAL guarded path
#
# WHAT THIS CANNOT DO. It reads only what is written literally. A constructed
# path ("/".join([...]), a variable, base64, os.environ["HOME"]+"/.claude")
# defeats it, as it defeats every text rule in this file. It cannot see inside
# a SCRIPT FILE: `python3 /tmp/x.py` is opaque, so writing the payload
# elsewhere and running it stays open, and closing that needs execution, not
# parsing. This catches the plain-text mistake and the naive rewrite. The
# tokenizer rules above remain the load-bearing ones.
INTERP_INLINE = re.compile(r"""(?x)
    \b(?:python[0-9.]*|perl|ruby|node|deno|bun|php|lua|osascript|awk|gawk
        |sh|bash|zsh|ksh|dash|fish)\b
    [^\n|;&]*?
    (?:\s-(?:c|e|E)\b|\s--eval\b|<<-?\s*['"]?\w+)
""")

# Mutation vocabulary. Still broad, but QUALIFIED where the bare word is not
# actually a filesystem verb. A false BLOCK costs one scoped bypass, a false
# ALLOW costs the guard -- and that asymmetry was used to justify matching bare
# words, which turned out to cost the guard anyway, by a longer route.
#
# <phone>, measured. Three read-only diagnostics of stop-justify.sh blocked,
# and the third is the one that matters: `python3 /tmp/s2diag.py` names no hook
# at all, and was blocked on the contents of the script it was handed. The
# vocabulary, not the distance, was wrong:
#
#   errors="replace"      -> \breplace\b   the standard safe-read idiom.
#   t.replace("a","b")    -> \breplace\b   a pure string op.
#   rules.append(x)       -> \bappend\w*   a list method.
#   lst.remove(x)         -> \bremove\b    a list method.
#   copy.deepcopy(d)      -> \bcopy\w*     not the filesystem.
#
# None of these mutate anything. Python's file-append is open(p,'a'), never
# .append(); its file-replace is os.replace, never str.replace. So the verbs
# that are ambiguous between a filesystem call and an ordinary method now
# require a filesystem RECEIVER, while the verbs that are unambiguous in every
# language we care about (unlink, rmtree, symlink, chmod...) stay bare.
#
# WHY NOT MASK STRING LITERALS, which is the obvious fix for errors="replace":
# the payload arrives still wrapped in the shell's own quotes, e.g.
# python3 -c '...'. A masker cannot tell that outer quote from an inner one, so
# it blanks the whole body and every rule below silently matches nothing. That
# is a fail-open with no symptom. Qualification gets the same cases with no
# such cliff, so the quotes are left alone.
#
# NOT a proximity rule. A mutation anywhere plus a guarded path anywhere still
# blocks; see the KNOWN FALSE POSITIVE note on interp_hits for what that still
# costs and why the targeting fix that would close it was reverted.
#
# open(...,'w') and perl's three-arg open(F,'>',...) are spelled out. A bare >
# counts only when a .claude path follows it, so `python3 -c "...read()" >
# /tmp/out` stays allowed.
MUTATE = re.compile(r"""(?xi)
    # WRITE, QUALIFIED (<phone>). Was a bare \bwrite\w* under (?xi), so the
    # WORD write matched as DATA and blocked work that writes nothing. Measured,
    # not supposed: `python3 - <<PY ... print(open(h).read().count("write")) PY`
    # blocked, a command whose only file operation is .read(). The region rule
    # could not save it, and that is the whole point: `h` IS a guarded var and
    # the literal DOES sit in its statement, so the targeting was right and the
    # VOCABULARY was wrong. Same finding as the <phone> pass that qualified
    # replace/append/copy/remove by demanding a filesystem RECEIVER; write was
    # left bare and is the same ambiguity, only worse, because it is an ordinary
    # English noun AND this repo's own hooks print it ("a SHELL WRITE was
    # recorded here"), so any read-only diagnostic of one near a guarded path
    # blocked. A false BLOCK costs a bypass, and bypasses spent on read-only
    # work are how `echo ALL` becomes a habit; that is the real cost here.
    #
    # MASKING STRING LITERALS IS NOT THE FIX and is rejected 30 lines up: the
    # payload still carries the shell's own quotes, a masker cannot tell the
    # outer quote from an inner one, blanks the body, and every rule below then
    # matches nothing. Fail-open with no symptom. Qualification has no cliff.
    #
    # STILL CAUGHT: f.write(x), fs.writeFileSync, Path(p).write_text(s),
    # File.write, os.write, csv.writer, and bare destructured writeFile/
    # writeSync. open(p,'w') and >/>> into a guarded path are separate
    # alternatives below and are untouched.
    # NEWLY ALLOWED: write as data, as a comment word, or as an argument.
    # RESIDUAL: \s* after the dot keeps chained `fs\n  .writeFileSync(...)`
    # caught, so prose ending a sentence immediately before a line starting
    # with "write" still matches. Narrower than the word alone by a wide
    # margin, and it fails toward blocking, which is the safe direction.
    \.\s*write\w*
  | \bwrite(?:File|Text|Bytes|Sync|_text|_bytes)\w*
  | \bappend(?:File|Text|Bytes)\w*
  | \b(?:unlink|rmtree|symlink|truncate|chmod|chown|mkdir|rmdir|rename)\b
  | \b(?:os|shutil|pathlib|Path|fs|fsPromises|FileUtils|File|Dir|IO)
      \s*\.\s*(?:replace|remove|move|copy\w*|append\w*|delete\w*|rm\w*)\b
  | \b(?:shutil|fileutils)\b
  | \b(?:system|popen|subprocess|spawn|exec\w*)\b
  | \bopen\s*\([^)]*['"][awx+bt]+['"]
  | ['"]\s*>>?\s*['"]
  | >>?\s*['"]?[^\s|&;'"]*\.claude/
""")

GUARDED_TEXT = re.compile(
    r"\.claude/(hooks(?:/|\b)|settings\.json|settings\.local\.json|\.claude\.json)")

# ---------------------------------------------------------------------------
# PROXIMITY. A mutation token must sit near the guarded path it supposedly
# mutates. <phone>, the owner: "fix false positive".
#
# Both scans below used to ask two UNRELATED questions of the whole text --
# "is there a mutation word anywhere" and "is there a guarded path anywhere" --
# and AND them together. Ordinary Python that merely READS a hook satisfies
# both, so reading this directory required a bypass. Three real blocks, all on
# one read-only diagnostic of stop-justify.sh:
#   errors="replace"    -> \breplace\b    the standard safe-read idiom. Line 788
#                                         below uses it, so the guard flagged
#                                         its own source.
#   rules.append(...)   -> \bappend\w*    a list append.
#   open("/tmp/x","w")  -> open(...,'w')  a write to /tmp naming no hook at all.
#
# None of the three named a guarded path as a write target. The third is the
# clearest: the command `python3 /tmp/s2diag.py` mentions no hook path
# whatsoever, and was blocked on the contents of the script it was handed.
#
# This is the expensive kind of false positive, and this file already documents
# why: lines 866-879 record that 15 of 16 BLANKET uses were single-rule ops.
# Every needless block trains the bigger hammer, and a guard you must disarm in
# order to READ is a guard that ends up disarmed with `echo ALL`.
#
# A LINE WINDOW WAS THE FIRST ATTEMPT AND WAS STILL TOO BLUNT. With +/-3 lines,
# a script that READ a hook and wrote an unrelated /tmp file kept blocking,
# because the two sat three lines apart:
#     h = os.path.expanduser("~/.claude/hooks/stop-justify.sh")
#     t = open(h).read()
#     open("/tmp/out.txt", "w").write(t)
# That is the single most common diagnostic shape there is, and it names no hook
# as a target. So the window is gone. The question is not "is a mutation NEAR a
# guarded path" but "does the mutation's own call TARGET one":
#
#   region = the mutation's own line, extended FORWARD over balanced parens so a
#            wrapped call keeps its later arguments. Bounded at REGION_MAX.
#   hit    = that region names a guarded path literally, OR names a variable
#            that was itself assigned a guarded path literal.
#
# Reading the line from its START is load-bearing. In
#     open(expanduser("~/.claude/hooks/x"), "w").write("")
# the MUTATE token that fires is `write`, and everything identifying the target
# sits BEHIND it; a forward-only region would read `write("")` and allow it.
#
# Variable tracking is what keeps the assign-then-write shape caught now that
# the window is gone, and it covers the shell form (H=~/.claude/hooks/x) too.
#
# NOT a new class of gap. Still text-only, still defeated by a CONSTRUCTED path
# ("/".join, os.environ, base64) -- that is gap #2, unchanged. The tokenizer
# rules above remain the load-bearing ones; this was only ever the backstop for
# interpreter payloads. What changes is that the backstop no longer fires on
# reads, which is what was driving `echo ALL`.
GUARDED_VAR = re.compile(
    r"(?m)^[^\S\n]*([A-Za-z_]\w*)\s*=\s*[^=\n]*"
    r"\.claude/(?:hooks(?:/|\b)|settings\.json|settings\.local\.json|\.claude\.json)")
REGION_MAX = 400

def _rule_of(s):
    m = GUARDED_TEXT.search(s)
    if not m:
        return None
    return R_HOOK if m.group(1).startswith("hooks") else R_SETTINGS

def _region(text, pos):
    """The mutation's own statement: its line, extended over balanced parens."""
    ls = text.rfind("\n", 0, pos) + 1
    end = min(len(text), pos + REGION_MAX)
    depth, seen, i = 0, False, pos
    while i < end:
        c = text[i]
        if c == "(":
            depth += 1
            seen = True
        elif c == ")":
            depth -= 1
            if seen and depth <= 0:
                return text[ls:i + 1]
        elif c == "\n" and depth <= 0:
            return text[ls:i]
        i += 1
    return text[ls:end]

def _mutating_guarded(text):
    """R_* for guarded paths that a mutation in this text actually targets."""
    gvars = {}
    for m in GUARDED_VAR.finditer(text):
        r = _rule_of(m.group(0))
        if r:
            gvars[m.group(1)] = r
    out = []
    for m in MUTATE.finditer(text):
        region = _region(text, m.start())
        r = _rule_of(region)
        if not r:
            for v, vr in gvars.items():
                # (?<![-\w]) not \b: a guarded var named `d` or `p` otherwise matches
                # the FLAG in `tr -d ' '`, `find -type d`, `head -n`. Measured
                # <phone> by delta debugging a read-only inventory command that
                # this rule blocked. Three innocent ingredients had to line up: the
                # English word "exec" inside a printf label (MUTATE `exec\w*`), a
                # one-letter python var assigned from a guarded path
                # (`d=json.load(open(SETTINGS))`), and `tr -d ' '` eight lines away.
                # Removing any one of the three flipped it to allow, which is the
                # signature of a coincidence rather than a targeted write.
                # Real payloads reference the var as `open(p,'w')`, `p.write_text(s)`
                # or `$p`, where the preceding char is a paren, a space or a dollar,
                # never a dash. Same lesson as the bare `write` vocabulary fix above:
                # a false BLOCK costs a bypass, and bypasses spent on read-only work
                # are what train `echo ALL`.
                if re.search(r"(?<![-\w])" + re.escape(v) + r"\b", region):
                    r = vr
                    break
        if r and r not in out:
            out.append(r)
    return out

def interp_hits(text):
    """R_* for guarded paths named inside interpreter inline code / heredocs."""
    if not INTERP_INLINE.search(text):
        return []
    return _mutating_guarded(text)

# ---------------------------------------------------------------------------
# Interpreter given a SCRIPT FILE. Closes KNOWN GAP #1, which was pinned as an
# expectation by 3b4432b and flipped deliberately on <phone> at the owner's
# request (the test said a flip "wants review, not a silent green": this is it).
#
# The gap was not theoretical. It was walked into by this very agent earlier the
# same day: write /tmp/rcpatch2.py, run it, and a guarded edit to this file
# landed with no block, no bypass consumed, and no audit record. Every text rule
# above reads the COMMAND, and `python3 /tmp/x.py` says nothing about what x.py
# touches. The accidental case is the common one, and it is the one that matters:
# nobody has to be evading the guard for the guard to miss.
#
# The old note said closing this "needs execution, not parsing". That is true in
# general and false for the case that actually occurs: we cannot know what a
# script DOES, but we can read what it plainly SAYS. So the file's own text gets
# the same two scans the command got.
#
# Reuses MUTATE and GUARDED_TEXT rather than a second matcher, so the mutation
# gate is identical: a script that merely READS settings.json, or mentions a
# hooks path in a comment with no mutation token, still passes. INTERP_INLINE is
# deliberately NOT required here, since being fed to an interpreter is already
# established by the verb.
#
# RULES are run over the body too, so `bash /tmp/x.sh` containing `rm -rf ~`
# blocks on the same regexes as an inline `rm -rf ~`.
#
# BOUNDED ON PURPOSE:
#   * existing regular files only, under SCRIPT_MAX, decode errors replaced
#   * FIRST plain argument only: later args are the script's argv, not code
#   * ONE level. A script that runs another script is not followed. Recursion
#     would need a cycle guard and a budget for a case not yet observed.
#   * no TARGET_PATHS entry, matching interp_hits: GUARDED_TEXT matches a
#     substring, not a resolvable path, and inventing one would let a grant be
#     path-scoped to a path never actually verified. A bare rule grant covers
#     these, which is what _suppressed already does for a path-less hit.
#
# SCOPED TO SCRATCH DIRECTORIES, and this is the whole reason it is safe to
# ship. The first cut scanned EVERY script file and was unusable: this repo's
# own tooling is shell scripts that name .claude/hooks paths next to mutation
# words, so `bash tests/risk-checkpoint-test.sh` and `bash hooks/session-collide.sh`
# both blocked instantly. It also self-blocked, since running this very hook is
# `bash <guarded path>`. A guard that cannot run the suite that proves it works
# is worse than the gap it closes.
#
# Scratch-only is not a consolation prize, it is the actual threat model.
# Writing a script INTO a guarded path is already blocked by the path rules
# above. The only way to land a payload and run it is to put it somewhere
# unguarded first, and that is exactly what happened here: /tmp/rcpatch2.py.
# Files under a repo are a different risk class: they arrive by Edit/Write,
# which this hook already judges, and they persist for review.
#
# STILL OPEN, deliberately and in order of how likely they are to bite:
#   1. A payload written OUTSIDE both a scratch dir and a guarded path
#      (~/x.py, ./scratch.py) and then run. Narrower than the gap it replaces,
#      not gone. Widening this means solving the false positives above first.
#   2. A script that CONSTRUCTS its target ("/".join, a variable, base64,
#      os.environ), which is gap #2 and defeats every text rule in this file.
#   3. TOCTOU: the bytes read here are not provably the bytes executed later.
SCRIPT_INTERP = re.compile(
    r"^(?:python[0-9.]*|perl|ruby|node|deno|bun|php|lua|osascript"
    r"|sh|bash|zsh|ksh|dash|fish|ts-node|tsx)$")
# /var/folders/ is macOS $TMPDIR. Anchored, and matched against the RESOLVED
# path, so `/tmp/..$HOME` cannot smuggle a non-scratch file through.
SCRATCH_SCRIPT = re.compile(r"^(?:/private)?(?:/tmp/|/var/tmp/|/var/folders/)")
SCRIPT_MAX = 512 * 1024

def script_file_hits(segs, cwd0):
    """R_* for guarded writes named inside a script FILE handed to an interpreter."""
    out, cur = [], cwd0
    for s in segs:
        words, redirs = seg_parts(s)
        verb, args = verb_of(words)
        if verb == "cd":
            plain0 = [a for a in args if not a["v"].startswith("-")]
            if plain0:
                cur = resolve(plain0[0]["v"], cur)
            continue
        if not verb or not SCRIPT_INTERP.match(os.path.basename(verb)):
            continue
        term = False
        for a in args:
            v = a["v"]
            if not term and v == "--":
                term = True; continue
            if not term and v.startswith("-") and len(v) > 1:
                continue
            try:
                p = resolve(v, cur)
                # Scratch-only. Checked against the RESOLVED path so
                # /tmp/..$HOME cannot smuggle a repo file in here, and
                # `break` not `continue` because the first plain arg is the
                # script -- a non-scratch script ends the scan, it does not
                # make us go looking at its argv for something to read.
                if not SCRATCH_SCRIPT.match(p):
                    break
                if not os.path.isfile(p) or os.path.getsize(p) > SCRIPT_MAX:
                    break
                with open(p, encoding="utf-8", errors="replace") as fh:
                    body = fh.read()
            except Exception:
                break
            for name, fn in RULES:
                if name not in out:
                    try:
                        if fn(body):
                            out.append(name)
                    except Exception:
                        pass
            for r in _mutating_guarded(body):
                if r not in out:
                    out.append(r)
            break   # first plain arg is the script; the rest is its argv
    return out

# ---------------------------------------------------------------------------
# SUBSTITUTION RECURSION (<phone>). Structural analysis walked only the TOP
# level of a command. Text rules (RM, force push, destructive SQL, ...) scan the
# whole string and so survived substitution, but write_targets and
# script_file_hits never looked inside `$( )`, backticks, `<( )` or `>( )`:
#     cat <(cp /tmp/src ~/.claude/hooks/z.sh)       ran UNGUARDED
#     echo "$(cp /tmp/src ~/.claude/hooks/z.sh)"    ran UNGUARDED
#     cat <(rm -rf ~/.claude/hooks)                 BLOCKED (RM is a text rule)
# That split IS the finding: text-level rules survive substitution, structural
# destination analysis did not. Same destination-steal family as `2>&1`,
# `0<&3`, `<<-` and `{v}>`, reached by a different road.
#
# Single-quoted regions are SKIPPED. No shell expands a substitution inside
# them, and scanning them would false-block `grep -n '$(cp x hooks/y)' f`,
# the MENTION-vs-PERFORM regression blank_inert_quoted already exists to
# prevent. Double quotes DO expand, so they are scanned.
#
# `${...}` is parameter expansion, not a command, and is deliberately NOT an
# opener. `$((...))` arithmetic is caught by the `$(` opener; its body reaches
# no write verb, so it costs one walk and yields nothing.
#
# Depth-capped, and quote-aware inside the paren scan so a `)` in a quoted
# argument cannot close the body early and hand the tokenizer a truncated
# command.
# ---------------------------------------------------------------------------
SUBST_CMD = re.compile(r"\$\(|<\(|>\(|`")

def _skip_quoted(text, i, n):
    """i sits on a quote char -> index just past the closing quote."""
    q = text[i]; j = i + 1
    while j < n:
        if text[j] == "\\" and q == '"':
            j += 2; continue
        if text[j] == q:
            return j + 1
        j += 1
    return n

def subst_bodies(text, depth=0):
    """Command bodies of every substitution in text, innermost included."""
    if depth > 6:
        return []
    out, i, n = [], 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "\\":
            i += 2; continue
        if ch == "'":
            i = _skip_quoted(text, i, n); continue
        m = SUBST_CMD.match(text, i)
        if not m:
            i += 1; continue
        if m.group(0) == "`":
            j = text.find("`", i + 1)
            if j == -1:
                break
            body, i = text[i + 1:j], j + 1
        else:
            open_at = m.end() - 1        # index of the opening paren
            k, lvl = open_at, 0
            while k < n:
                c = text[k]
                if c == "\\":
                    k += 2; continue
                if c in "'\"":
                    k = _skip_quoted(text, k, n); continue
                if c == "(":
                    lvl += 1
                elif c == ")":
                    lvl -= 1
                    if lvl == 0:
                        break
                k += 1
            if k >= n or lvl != 0:
                break
            body, i = text[open_at + 1:k], k + 1
        out.append(body)
        out.extend(subst_bodies(body, depth + 1))
    return out

if TOOL == "Bash":
    text1 = strip_inert_heredocs(cmd)
    segs = split_segments(tokenize(text1))
    text2 = blank_inert_quoted(text1, segs)
    hits = [name for name, fn in RULES if fn(text2)]
    for name in write_targets(segs, data.get("cwd") or os.getcwd()):
        if name not in hits:
            hits.append(name)
    # text1, not text2: blanking would erase the very payload this reads.
    for name in interp_hits(text1):
        if name not in hits:
            hits.append(name)
    for name in script_file_hits(segs, data.get("cwd") or os.getcwd()):
        if name not in hits:
            hits.append(name)
    # Recurse. text1, not text2: a substitution inside DOUBLE quotes is live
    # code and blank_inert_quoted may have emptied it as data.
    _cwd = data.get("cwd") or os.getcwd()
    for _body in subst_bodies(text1):
        _bsegs = split_segments(tokenize(_body))
        for name in write_targets(_bsegs, _cwd):
            if name not in hits:
                hits.append(name)
        for name in script_file_hits(_bsegs, _cwd):
            if name not in hits:
                hits.append(name)
    SUBJ_LABEL, SUBJECT = "Command", cmd
else:
    target = _norm(TI.get("file_path") or TI.get("notebook_path") or "")
    if not target:
        sys.exit(0)
    hits = [name for name, fn in PATH_RULES if fn(target)]
    for _h in hits:
        TARGET_PATHS.append((_h, target))
    SUBJ_LABEL, SUBJECT = "Target", target
if not hits:
    sys.exit(0)

# ---------------------------------------------------------------------------
# Bypass: scoped, one-shot, audited.
# Consumed ONLY when it actually suppresses a match (the old code deleted it on
# the next Bash command regardless, so it was routinely spent on the wrong one).
# ---------------------------------------------------------------------------
def audit(kind, rules, remaining):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "kind": kind,
                "bypassed": sorted(rules) if rules != "ALL" else "ALL",
                "still_blocked": remaining,
                "tool": TOOL,
                # Which sentinel was spent. Under RC_BYPASS this is a harness
                # scratch file, so a test run can never be mistaken in the log
                # for the operator bypassing a real guard.
                "sentinel": BP,
                "session": _sid or "SHARED",
                # Key kept as "command" for Bash log continuity; for write
                # tools it holds the target path.
                "command": SUBJECT[:300],
            }) + "\n")
    except Exception:
        pass

# TTL gate, evaluated BEFORE anything in the sentinel is honoured or even read
# as a grant. Fails CLOSED in both directions:
#   - unstattable  -> treated as stale. The only thing worse than refusing a
#     good bypass is honouring one whose age cannot be established.
#   - future mtime -> also stale. Bounding only the old side lets a skewed clock
#     or a hand-set timestamp mint a grant that never expires, which is the
#     exact failure this gate exists to remove, reintroduced through the back.
# Removal is audited as EXPIRED with the hits it did NOT wave through, so an
# expiry is legible in the log as an event rather than as an absence.
BP_EXPIRED = 0
_bp_live = os.path.exists(BP)
if _bp_live:
    try:
        _age = int(time.time() - os.stat(BP).st_mtime)
    except Exception:
        # Force expiry against the PAST bound explicitly. Was BP_TTL + 1, which
        # is the same number only because BP_TTL aliases BP_TTL_PAST; it read as
        # "just past the symmetric limit", and that limit no longer exists.
        _age = BP_TTL_PAST + 1
    if not (-BP_TTL_FUTURE <= _age <= BP_TTL_PAST):
        try: os.remove(BP)
        except Exception: pass
        audit("EXPIRED", [], hits)
        BP_EXPIRED = _age
        _bp_live = False
        # falls through and blocks; the message below explains the expiry and
        # says to re-arm, so a stale grant reads as "arm again", not as "broken"

if _bp_live:
    try:
        raw = open(BP, encoding="utf-8").read().strip()
    except Exception:
        raw = ""
    # <phone>: an EMPTY sentinel used to mean BLANKET, which made the unsafe
    # option the cheapest to type: `touch <sentinel>` versus writing out a rule
    # name for a scoped one. The log shows exactly that failure. Of 16 blanket
    # uses, 15 were the identical single-rule command
    # (`mv .../risk-checkpoint.sh /tmp/`), which needed only "hook script
    # write". Each of those disarmed EVERY rule for that call. Worse, writing
    # the word ALL did nothing at all, because it was compared against rule
    # names and never matched, so the documented-looking blanket form silently
    # failed while the undocumented empty one worked.
    #
    # Now both forms cost one echo, and blanket must name itself. An empty
    # sentinel is REJECTED rather than upgraded: it is ambiguous (a truncated
    # write, a failed heredoc, a stray touch), and resolving ambiguity toward
    # "skip every guard" is the wrong direction.
    # <phone>: entries are `rule[@path]`. Session scoping fixed WHO can spend
    # a sentinel but not WHAT it authorises: "hook script write" armed to edit
    # stop-justify.sh equally authorised a write to risk-checkpoint.sh itself,
    # i.e. to this guard. A hit that came FROM a path is now suppressed only
    # when the grant names that path.
    #   rule@/abs/path  that file, or that dir and everything under it
    #   rule@*          any path: the old breadth, but explicit and audited
    #   rule            command-level rules only (hit carries no path)
    _entries = sorted({e.strip() for e in re.split(r"[,\n]", raw) if e.strip()})
    grants = {}
    for _e in _entries:
        _n, _sep, _gp = _e.partition("@")
        _n = _n.strip().lower()
        if _n:
            grants.setdefault(_n, set()).add(_gp.strip())
    want = set(grants)

    def _covers(g, t):
        if g == "*":
            return True
        # resolve() realpaths the dirname only, matching how targets are built
        # for Bash. A symlinked leaf can therefore miss and BLOCK, never allow.
        g = resolve(g, HOME).rstrip(os.sep)
        return bool(g) and (t == g or t.startswith(g + os.sep))

    def _tgts(h):
        return [q for (r, q) in TARGET_PATHS if r == h]

    def _suppressed(h):
        gp = grants.get(h.lower())
        if gp is None:
            return False
        ts = _tgts(h)
        if not ts:
            return True      # command-level hit: no path to scope against
        paths = [g for g in gp if g]
        if not paths:
            return False     # bare name does not cover a path-bearing hit
        return all(any(_covers(g, t) for g in paths) for t in ts)

    if not want:
        try: os.remove(BP)
        except Exception: pass
        audit("REJECTED-EMPTY", [], hits)
        # falls through and blocks; msg below explains both valid forms
    elif "all" in want:
        try: os.remove(BP)
        except Exception: pass
        audit("BLANKET", "ALL", [])
        sys.exit(0)
    else:
        remaining = [h for h in hits if not _suppressed(h)]
        if len(remaining) < len(hits):
            # SINGLE-USE, EXCEPT FOR A PURELY PATH-SCOPED GRANT (<phone>).
            # Measured across the live tree: 728 risk-checkpoint blocks, and of
            # the 298 whose target could be parsed, 100 were a REPEAT block on a
            # path already armed in the same session. Editing one hook four
            # times cost four blocks, four arms and four retries, and this guard
            # was the largest single source of failed tool calls on the box.
            # the owner, <phone>: "u need to prevent the guards from actually
            # making things worse".
            #
            # What single-use was protecting, from the TTL comment above: an arm
            # that suppresses NOTHING is never spent, stays live, and later waves
            # through an unrelated op. That hazard is about BREADTH, not about
            # repetition. A grant naming an absolute path can only ever wave
            # through that path, so reusing it inside its window authorises
            # exactly what the operator already stated intent for.
            #
            # So: `ALL` and any grant carrying `*` or a bare rule stay strictly
            # single-use. A grant whose every entry names a real path survives
            # until the EXISTING 300s TTL retires it. The mtime is deliberately
            # not refreshed on use, so the window still runs from the arm, and a
            # long edit run re-states intent every five minutes rather than
            # never.
            _path_only = all(g and g != "*"
                             for gs in grants.values() for g in gs)
            if not _path_only:
                try: os.remove(BP)
                except Exception: pass
            audit("SCOPED" if not _path_only else "SCOPED-RETAINED",
                  _entries, remaining)
            if not remaining:
                sys.exit(0)
            hits = remaining   # other rules still fire

# Quote the sentinel actually in force, never a hardcoded path. Under a harness
# override the default would be wrong advice, and a REJECTED override has to say
# so out loud: silently printing instructions for a bypass that cannot work is
# how someone concludes the guard is broken and reaches for a bigger hammer.
BP_SHOW = BP or ("/tmp/" + BP_NAME)
BP_NOTE = ""
if not _sid and not _bp_env:
    BP_NOTE += ("NOTE: no session_id in hook input, so the SHARED sentinel is in "
                "use and another concurrent session can spend it before you "
                "re-run.\n")
if _bp_env and not BP:
    BP_NOTE = ("RC_BYPASS=" + _bp_env + " was IGNORED (basename must be "
               + BP_NAME + "), so no bypass is available.\n")
# Appended AFTER the RC_BYPASS clause, which assigns rather than appends: an
# expiry must not be the thing that gets clobbered out of the message. Says
# REMOVED UNSPENT explicitly, because the failure this guards against is a
# grant that was never used being mistaken for one that was.
if BP_EXPIRED:
    BP_NOTE += ("NOTE: a sentinel was found and REMOVED UNSPENT because "
                + ("its timestamp is in the future"
                   if BP_EXPIRED < 0 else
                   "it was armed " + str(BP_EXPIRED) + "s ago, past the "
                   + str(BP_TTL) + "s limit")
                + ". Nothing was bypassed by it. Arm again in the call before "
                "the retry.\n")

# Name the real target in the suggested command: if the scoped form is more
# work to derive than the blanket one, the blanket one is what gets used.
_ft = [q for (r, q) in TARGET_PATHS if r == hits[0]]
ARM = ",".join(hits[0] + "@" + t for t in _ft) if _ft else hits[0]

# Step 2 has to name the surface that was actually blocked. For Edit/Write there
# is no command to re-run, and advice that does not fit what you just did is
# advice that gets abandoned for the blanket form.
_REDO = ("re-run the command below, unchanged" if TOOL == "Bash"
         else "retry the " + TOOL + " on the target below")

# A force-push rewrites history for every other session sharing the remote, but
# this message used to explain how to arm the sentinel without ever saying WHO
# ELSE IS LIVE, so the call got made blind. <phone>: 21 commits were dropped
# off a shared remote and the roster was consulted only afterwards. It came back
# clean, which is precisely why nothing caught it -- a blind call that happens to
# win is indistinguishable from a checked one until the day it loses.
#
# session-collide.sh ALWAYS prints. Empty output therefore means the tool is
# BROKEN, never "nobody else is here": before --owner existed (<phone>) it
# silently exited 0 and manufactured false negatives. So silence is surfaced as
# loudly as a collision. Failing open into a quiet all-clear would rebuild the
# exact bug this block exists to prevent.
LEDGER_NOTE = ""
if "force push" in hits:
    import subprocess
    _cwd = data.get("cwd") or os.getcwd()
    _sc = os.path.join(HOME, ".claude", "hooks", "session-collide.sh")
    _out, _err = "", ""
    try:
        _repo = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=_cwd,
                               capture_output=True, text=True,
                               timeout=5).stdout.strip() or _cwd
    except Exception:
        _repo = _cwd
    if not os.path.exists(_sc):
        _err = "session-collide.sh not found at " + _sc
    else:
        try:
            # 30s, not 10s. Measured <phone>: --owner is 14.5s COLD (it finds
            # over transcripts) and instant warm, since it caches on COLLIDE_TTL
            # (session-collide.sh, default 60 but env-overridable, so do NOT read
            # the warm case as guaranteed: 30s must clear the COLD path alone,
            # and it does, with ~2x headroom).
            # A 10s bound lost the cold path EVERY time -- the first smoke test only
            # passed because a --owner run seconds earlier had warmed the cache.
            # That is worse than it sounds: the block still failed loud, so it never
            # faked an all-clear, but the roster never actually arrived and an
            # operator who sees UNAVAILABLE on every force-push stops reading it
            # inside a day. Waiting ~15s is the right trade here specifically
            # because this path is already blocking a rare, history-rewriting call.
            _p = subprocess.run(["bash", _sc, "--owner", _repo],
                                capture_output=True, text=True, timeout=30)
            _out = (_p.stdout or "").strip()
            if not _out:
                _err = ("it printed NOTHING (exit " + str(_p.returncode)
                        + "), and it always prints")
        except subprocess.TimeoutExpired:
            _err = "it timed out after 30s"
        except Exception as _e:
            _err = "it failed: " + str(_e)[:200]
    if _err:
        LEDGER_NOTE = (
            "⚠ LEDGER UNAVAILABLE: " + _err + ".\n"
            "Do NOT read this as 'no other session is live' -- that is the\n"
            "failure mode this check exists to stop. Resolve the roster by hand\n"
            "before rewriting shared history.\n")
    else:
        _lines = _out.splitlines()
        LEDGER_NOTE = (
            "LEDGER for " + _repo + " (consulted BEFORE the rewrite, not after):\n"
            + "\n".join("  " + _l for _l in _lines[:40])
            + ("\n  ... " + str(len(_lines) - 40) + " more line(s)"
               if len(_lines) > 40 else "")
            + "\nForce-push rewrites history under every session listed above.\n"
              "Resolve any commit you do not recognise BEFORE arming:\n"
              "  bash ~/.claude/hooks/guild-session.sh --who <sha>\n")

msg = (
    "⛔ RISK-CLASS op blocked by risk-checkpoint (CLAUDE.md rule #3): "
    + ", ".join(hits) + ".\n"
    + BP_NOTE
    + LEDGER_NOTE
    + "State first: TARGET · WHY · BLAST RADIUS · ROLLBACK.\n"
    + "Then proceed in TWO SEPARATE CALLS (scoped, preferred since it leaves\n"
      "other rules armed):\n"
    + "  call 1:  echo '" + ARM + "' > " + BP_SHOW + "\n"
    + "  call 2:  " + _REDO + "\n"
    + "Arming cannot share a call with the op it unblocks: this check runs BEFORE\n"
      "the call executes, so a sentinel written by that same call does not exist\n"
      "yet when it is read. `echo ... && <op>` blocks, and the echo never runs.\n"
    + ("Grant is PATH SCOPED: it covers the target(s) above and nothing else.\n"
       "Use '" + hits[0] + "@*' for any path, or name a directory to cover a tree.\n"
       if _ft else "")
    + "Blanket, skips ALL " + str(len(RULES) + len(PATH_RULES)) + "+ rules for this call, audited.\n"
    + "Same two calls, only call 1 differs:\n"
    + "  call 1:  echo ALL > " + BP_SHOW + "\n"
    + "An EMPTY sentinel is rejected, not treated as blanket.\n"
    + "Sentinel is PER-SESSION and PER-PATH: only this session can spend it, and\n"
    + "only against the path named in it.\n"
    + SUBJ_LABEL + ":\n  " + SUBJECT[:500]
)
print(msg, file=sys.stderr)
sys.exit(2)
PY
