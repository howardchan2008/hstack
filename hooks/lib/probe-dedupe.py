#!/usr/bin/env python3
"""probe-dedupe: stop the same read-only question being re-asked all session.

WHY THIS EXISTS
  Measured 2026-08-23 against the FULL corpus, every transcript on the box:
  3,857 sessions (219 live plus 3,638 archived), of which 1,157 used Bash at all,
  101,987 Bash calls.

      repeat-probe rate  15.7%   (15,998 calls: 7,753 warn + 8,245 block)
      would block         8.1%   (8,245 calls, the 4th+ look at one subject)
      skipped as work     52.3%  (53,332 mutations, redirects and watch loops)

  Recent work is worse than historical: the 219 live sessions block at 10.0%
  against 6.3% for the archive, so this is growing, not decaying.

  AN EARLIER VERSION OF THIS COMMENT SAID 24%. That figure came from 39 sessions
  in a 7-day live-only window and overstated the real rate by 1.5x, which is the
  same denominator mistake that put "7855 close-outs" into closeout-shape.py.
  the owner caught both. Scan live AND archive, or say which one you scanned.

  Only 5 of one session's 406 calls were byte-identical, so exact-hash dedupe
  finds essentially nothing. The repeats are one question re-asked with different
  wording: 71 CPU probes, 54 an antivirus daemon, 47 mediaanalysisd, 47 ollama, 31 git
  status, all in a single session.

  Reproduce with hooks/lib/probe-dedupe-backtest.py, which imports the matchers
  below so the measurement can never drift from the guard.

  It matters because every tool call re-sends the whole conversation. Over the
  same window cache_read was 3.62 BILLION tokens against roughly 13M tokens of
  unique content, a 278x re-read amplification, and cost-weighted input is 91.4%
  of the bill. So a redundant probe is not "one cheap command", it is one more
  full re-read of everything said so far.

DESIGN, and why it is not stricter
  ADVISORY first, BLOCK only at the 4th look. R2 in closeout-shape.py is the
  cautionary tale: a hard cap that fires constantly gets worked around and makes
  output worse. Two or three looks at a subject is normal work. Four is a habit.

  MUTATIONS ARE NEVER DEDUPED. A command that writes, commits, installs or
  restarts something is not a probe, and re-running it is often the whole point.

  EXPLICIT WATCHES ARE NEVER DEDUPED. A command containing sleep or a loop is
  deliberately sampling over time. That is the correct shape, and it costs ONE
  call instead of six, so the guard rewards it by never counting it.

  Escape hatch is PROBE_DEDUPE_OFF=1, and the block message names it.
"""
import json
import os
import re
import sys
import time

STATE_DIR = os.path.expanduser("~/.claude/state/probe-dedupe")
BLOCK_AT = 4          # 1st free, 2nd and 3rd warn, 4th blocks
STALE_SEC = 6 * 3600  # a session file older than this starts clean

# Changing the world, not measuring it.
MUTATION = re.compile(
    r"(?<![\w-])(commit|push|pull|merge|rebase|checkout|clone|init|rm|mv|cp|"
    r"mkdir|touch|chmod|chown|ln|install|uninstall|brew|npm|pip|cargo|"
    r"launchctl|systemctl|kill|killall|renice|taskpolicy|"
    r"tee|dd|truncate|deploy|restart|bootstrap|bootout|sign)(?![\w-])"
)
# Any redirection that creates or appends to a file is a mutation too.
REDIRECT = re.compile(r"(?<![0-9<>&])>{1,2}\s*[^&\s]")
# Deliberate sampling over time. One call, many readings.
WATCH = re.compile(r"(?<![\w-])(sleep|while|until|watch)(?![\w-])|for\s+\w+\s+in")

# SUBJECT verbs only. What is being asked ABOUT.
#
# The filter half of a pipeline is deliberately NOT here. First version keyed on
# every executable in the command, so `ps ... | head`, `ps ... | grep kavd` and a
# bare `ps -o pcpu=` produced three different keys and the fourth look at the same
# subject registered as look #2. The pipeline tail is how a question is phrased;
# the subject verb is what it asks. Keying on phrasing is exact-hash dedupe with
# extra steps, and exact-hash already fails: 5 hits where subject matching finds
# 4,306.
VERBS = re.compile(
    r"(?<![\w/.-])(ps|top|uptime|vm_stat|sysctl|memory_pressure|git|ollama|lsof|pgrep|"
    r"launchctl|curl|du|df|stat|defaults|plutil|diskutil|networksetup|softwareupdate|"
    r"brew|docker|gh)(?![\w-])"
)
PATHY = re.compile(r"[~/][\w./*@+-]{3,}")
# Files named WITHOUT a leading ~ or /, the normal shape after `cd dir &&`. PATHY
# never saw them, so `cd .../wa && fold 04_Amer.txt` and `cd .../wa && fold
# 05_Joel.txt` both keyed on the cd target `wa`, and five distinct first reads of
# five files registered as looks #4 to #8 at one subject (2026-09-02). A file
# token needs a known extension so prose and numbers do not become subjects.
RELFILE = re.compile(
    r"(?<![\w/.~-])((?:[\w.@+*-]+/)*[\w@+*-]+\.(?:txt|md|py|sh|zsh|json|jsonl|csv|tsv|"
    r"log|ya?ml|toml|html?|js|ts|tsx|sql|db|pdf|png|jpe?g|parquet|plist))(?![\w./-])"
)
# The `cd` target is where the files live, never what is being read.
CD_TARGET = re.compile(r"(?<![\w-])cd\s+([~/][\w./*@+-]+|[\w.@+-]+)")
NOISE = {"dev", "null", "tmp", "usr", "bin", "etc", "var", "Users", "<github-user>"}


def _slice_suffix(cmd):
    """Return a stable identity for an explicit line or byte slice, if any."""
    sed = re.search(
        r"\bsed\b[^|;&]*?\s-n\s+(['\"])(\d+)(?:\s*,\s*(\d+))?p\1",
        cmd,
    ) or re.search(
        r"\bsed\b[^|;&]*?\s-n\s+(\d+)(?:\s*,\s*(\d+))?p\b",
        cmd,
    )
    if sed:
        groups = sed.groups()
        start = groups[-2] if len(groups) == 3 else groups[0]
        end = groups[-1] if len(groups) == 3 else groups[1]
        return "slice:%s-%s" % (start, end or start)

    stream = re.search(
        r"\b(head|tail)\s+(?:-n\s+([+]?[0-9]+)|-c\s+([0-9]+)|-([+]?[0-9]+))\b",
        cmd,
    )
    if stream:
        command, lines, bytes_, shorthand = stream.groups()
        kind, value = ("c", bytes_) if bytes_ else ("n", lines or shorthand)
        return "slice:%s-%s-%s" % (command, kind, value)

    if re.search(r"\bawk\b", cmd):
        numbers = re.findall(
            r"(?:NR\s*(?:>=|<=|==|>|<)\s*(\d+)|"
            r"(\d+)\s*(?:>=|<=|==|>|<)\s*NR)",
            cmd,
        )
        values = sorted({value for pair in numbers for value in pair if value})
        if values:
            return "slice:%s" % "-".join(values)
    return None


# A CONTAINER IS NOT A SUBJECT. Added 2026-08-24 after this guard blocked its own
# author twice on genuinely different questions. `grep` is deliberately not a
# subject verb, so `cd ~/.claude && grep X reference/` yields no verb at all and
# the only surviving leaf is `.claude`, which every command on this box mentions.
# The key collapses to the home of the whole config tree, and four unrelated reads
# register as four looks at one subject. Measured the same day: 28 of 111 failed
# Bash calls were this guard, the single largest cause, and it was added hours
# earlier, so it made the tool-failure rate WORSE while claiming to reduce work.
# Keys built only from these fall through to the raw-command fallback instead.
CONTAINERS = {
    ".claude", "claude", "repos", "projects", "hooks", "lib", "reference",
    "Downloads", "Documents", "home", "src", "scripts", "state", "automation-hub",
}


def fingerprint(cmd):
    """The SUBJECT of a command, insensitive to how it was phrased.

    Verbs plus the distinctive tail of any path mentioned. Two commands reading
    the same thing through different pipelines collapse to one key, which is the
    point: byte-identical matching found 5 repeats where this finds 4,306.
    """
    verbs = sorted(set(VERBS.findall(cmd)))
    leaves = []
    for p in PATHY.findall(cmd):
        leaf = p.rstrip("/").split("/")[-1]
        leaf = re.sub(r"[0-9]{4,}", "N", leaf)  # dated files are the same subject
        if leaf and leaf not in NOISE and not leaf.startswith("-"):
            leaves.append(leaf)
    relfiles = [re.sub(r"[0-9]{4,}", "N", f.split("/")[-1]) for f in RELFILE.findall(cmd)]
    if relfiles:
        cd_leaves = {t.rstrip("/").split("/")[-1] for t in CD_TARGET.findall(cmd)}
        leaves = [l for l in leaves if l not in cd_leaves] + relfiles
    specific = [l for l in set(leaves) if l not in CONTAINERS]
    # No subject verb AND nothing but container directories means this command
    # has not told us what it is about. Fall back to the raw text, which dedupes
    # only genuine repeats rather than everything living under one folder.
    if not verbs and not specific:
        return re.sub(r"\s+", " ", cmd.strip())[:48]
    key = "|".join(verbs + sorted(specific or set(leaves))[:3])
    key = key or re.sub(r"\s+", " ", cmd.strip())[:48]
    suffix = _slice_suffix(cmd)
    return "%s|%s" % (key, suffix) if suffix else key


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except Exception:
        return {}
    if time.time() - d.get("_born", 0) > STALE_SEC:
        return {}
    return d


# --- second check: transcript scans that silently read 6% of the corpus --------
#
# THREE WRONG NUMBERS IN ONE WEEK, all the same defect, all caught by the owner:
#   "53.5% of 7855 close-outs"  real: 1,130 and 31.3%
#   "24% repeat-probe rate"     real: 15.7%
#   "913 zsh glob failures"     real: 2,006
# Every one came from globbing ~/.claude/projects and reporting the result as a
# total. On 2026-08-18 transcript-archive moved 3,638 of the 3,857 transcripts to
# ~/Archive/claude-transcripts as .jsonl.gz, so the live tree is now about 6% of
# the sessions and nothing about the glob says so. The reading is not wrong, the
# LABEL is, and a slice presented as a total is how it gets cited.
#
# Advisory, never a block: scanning only the live tree is legitimate when the
# question really is "recent sessions". The check exists so that choice is made
# out loud rather than by accident.
LIVE_SCAN = re.compile(r"\.claude/projects\b")
ARCHIVE_SCAN = re.compile(r"Archive/claude-transcripts|jsonl\.gz")
LIVE_DIR = os.path.expanduser("~/.claude/projects")
ARCHIVE_DIR = os.path.expanduser("~/Archive/claude-transcripts")


def corpus_slice_warning(cmd):
    """Warn when a command reads the live transcript tree and not the archive."""
    if not LIVE_SCAN.search(cmd) or ARCHIVE_SCAN.search(cmd):
        return None
    # Only bother when the command looks like a SWEEP, not a single-file read.
    if not re.search(r"\*|glob|find |rglob|walk|-r\b|recursive", cmd):
        return None

    def count(root, suffix):
        n = 0
        for _, _, files in os.walk(root):
            n += sum(1 for f in files if f.endswith(suffix))
        return n

    try:
        live = count(LIVE_DIR, ".jsonl")
        arch = count(ARCHIVE_DIR, ".jsonl.gz")
    except Exception:
        return None
    total = live + arch
    if arch == 0 or total == 0:
        return None
    return ("corpus-slice: live tree is %d of %d transcripts (%.0f%%); rest in "
            "~/Archive/claude-transcripts. Scan both, or name the slice.\n"
            % (live, total, 100.0 * live / total))


# --- third check: output with no size bound -----------------------------------
#
# THE LARGEST LEAK MEASURED, and it is not duplication. Across 159,018 tool
# results in all 3,857 transcripts (210.7M chars, about 52.7M tokens):
#     results over  5,000 chars:  4.75% of results carry 42.7% of ALL bytes
#     results over 20,000 chars:  0.60% of results carry 15.2%
# Byte-identical repeats, by contrast, are only 1.1% of bytes, so de-duplicating
# was never going to be the win. Volume is.
#
# It compounds. A result is not paid for once: it sits in context and is re-sent
# on every later call in that session. One 20k-char result in a turn with fifty
# more calls to go is fifty re-reads of the same 5k tokens.
#
# Of Bash results over 5,000 chars, 29% came from a command with NO output bound,
# carrying 11.1M chars. Bare `cat` alone is 33.7% of those bytes, python3 20.5%.
# The other 71% were bounded and still large, so this catches under a third of
# the problem and is advisory for that reason: the judgement about how much
# output is worth keeping cannot be made by a regex.
UNBOUNDED_SRC = re.compile(
    r"(?<![\w/.-])(cat|find|git\s+log|git\s+diff|rg|grep|ls\s|du|env|jq|python3)(?![\w-])")
HAS_BOUND = re.compile(          # bounds the number of LINES
    r"\|\s*(head|tail)\b|\bhead\s+-|\btail\s+-|\|\s*wc\b|"
    r"\bsed\s+-n\s+.[0-9]+,[0-9]+p|--max-count|\s-m\s*[0-9]+|-n\s*[0-9]+|"
    r"\bLIMIT\b|\|\s*sort\b.*\|\s*uniq\s+-c|>\s*/dev/null", re.I)
WIDTH_BOUND = re.compile(        # bounds the width of each line
    r"\bcut\s+-c|\bhead\s+-c|\bfold\b|\bcolrm\b|\|\s*wc\b|>\s*/dev/null", re.I)


def unbounded_output_warning(cmd):
    """Two axes. A line bound does nothing when a line is 343 chars wide.

    Measured over 2,770 bounded-but-oversized Bash results: median 80 lines at
    91 chars, p90 185 lines at 343. 27.9% were too many lines, 19.3% were few
    but far too wide, and only 9.4% of commands capped bytes at all. Line bounds
    are near-universal, width bounds are almost never used, so WIDTH is the
    missing half. The remaining 52.7% are moderately over on both axes and no
    regex can judge those: that part is a call-by-call decision about whether
    the output is being read or merely collected.
    """
    if not UNBOUNDED_SRC.search(cmd):
        return None
    has_lines = bool(HAS_BOUND.search(cmd))
    has_width = bool(WIDTH_BOUND.search(cmd))
    if has_lines and has_width:
        return None
    if has_lines:
        return "cap width too: add `| cut -c1-200`. Lines run 343 wide at p90.\n"
    if has_width:
        return "cap lines too: add `| head -40`.\n"
    return "no output bound: add `| head -40 | cut -c1-200`, or ignore if you need it all.\n"


READ_BLOCK_AT = 3   # 1st free, 2nd warns, 3rd blocks. Tighter than Bash: a file
                    # read twice with no edit between is already the whole point.


def _state_path(payload):
    sid = str(payload.get("session_id") or "unknown")[:36]
    os.makedirs(STATE_DIR, exist_ok=True)
    return os.path.join(STATE_DIR, sid + ".reads.json")


def clear_read_counter(payload, path):
    """An Edit or Write to a path makes the next read of it legitimate."""
    if not path:
        return
    p = _state_path(payload)
    st = load(p)
    if st.pop(os.path.abspath(os.path.expanduser(path)), None) is not None:
        st.setdefault("_born", time.time())
        try:
            with open(p, "w", encoding="utf-8") as f:
                json.dump(st, f)
        except Exception:
            pass


def check_read(payload, inp):
    path = str(inp.get("file_path", ""))
    if not path:
        return 0
    # A different byte range is a different question, so it gets its own counter.
    key = os.path.abspath(os.path.expanduser(path))
    span = (inp.get("offset"), inp.get("limit"))
    if span != (None, None):
        key = "%s#%s-%s" % (key, span[0], span[1])

    p = _state_path(payload)
    st = load(p)
    st.setdefault("_born", time.time())
    n = int(st.get(key) or 0) + 1
    st[key] = n
    try:
        with open(p, "w", encoding="utf-8") as f:
            json.dump(st, f)
    except Exception:
        pass

    if n < 2:
        return 0
    short = key.replace(os.path.expanduser("~"), "~")
    if n < READ_BLOCK_AT:
        sys.stderr.write("probe-dedupe: read #%d of %s, unchanged since. Already "
                         "in context.\n" % (n, short))
        return 0
    sys.stderr.write("probe-dedupe: BLOCKED, read #%d of %s, unchanged. It is in "
                     "context verbatim. Different part: pass offset/limit. Changed "
                     "underneath you: PROBE_DEDUPE_OFF=1.\n" % (n, short))
    return 2


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    tool = payload.get("tool_name")
    inp = payload.get("tool_input") or {}

    # --- Edit and Write only RESET state, they never trip anything -------------
    # Re-reading a file you just changed is legitimate. Clearing the counter here
    # is what separates "I need to see the new bytes" from "I forgot I read this".
    if tool in ("Edit", "Write", "NotebookEdit"):
        clear_read_counter(payload, str(inp.get("file_path", "")))
        return 0

    # --- Read: 31% of all Read calls re-read a file already read this session --
    # Measured 2026-08-23 over all 3,857 transcripts: 15,106 Read calls, 4,630 of
    # them (31%) repeat a path already read in that same session, carrying about
    # 11.4M tokens of duplicate file content back into context. Live sessions run
    # 40% against the archive's 28%, so this is growing, exactly like the Bash
    # probe repeats. Reproduce with hooks/lib/probe-dedupe-backtest.py.
    #
    # The harness already says not to re-read a file just edited to verify. This
    # is the same rule with a counter behind it, and Edit/Write above make it
    # safe: a genuine re-read after a change never trips.
    if tool == "Read":
        return check_read(payload, inp)

    if tool != "Bash":
        return 0
    cmd = str(inp.get("command", ""))
    if not cmd.strip():
        return 0

    # THE ESCAPE HATCH MUST BE READ FROM THE COMMAND TEXT, NOT THE ENVIRONMENT.
    # First version checked os.environ only, and the block message told the reader
    # to run `PROBE_DEDUPE_OFF=1 <cmd>`. That cannot work: the hook is a separate
    # process and never sees an assignment made in the command it is judging. The
    # guard blocked its own author twice with a documented override that was inert.
    # Tested now by the escape-hatch control, which the first round of controls
    # never covered: I proved it BLOCKS and proved it stays SILENT, and never
    # proved it could be turned off.
    if os.environ.get("PROBE_DEDUPE_OFF") or re.search(
            r"(?:^|[;&|(]|\s)PROBE_DEDUPE_OFF=(?!0\b|\s|$)", cmd):
        return 0

    warn = corpus_slice_warning(cmd)
    if warn:
        sys.stderr.write(warn)

    warn = unbounded_output_warning(cmd)
    if warn:
        sys.stderr.write(warn)

    # Never dedupe work, only measurement.
    if MUTATION.search(cmd) or REDIRECT.search(cmd) or WATCH.search(cmd):
        return 0

    sid = str(payload.get("session_id") or "unknown")[:36]
    os.makedirs(STATE_DIR, exist_ok=True)
    path = os.path.join(STATE_DIR, sid + ".json")
    state = load(path)
    state.setdefault("_born", time.time())

    key = fingerprint(cmd)
    rec = state.get(key) or {"n": 0, "first": "", "last_at": 0}
    rec["n"] += 1
    if not rec["first"]:
        rec["first"] = re.sub(r"\s+", " ", cmd.strip())[:110]
    ago = int(time.time() - rec["last_at"]) if rec["last_at"] else 0
    rec["last_at"] = time.time()
    state[key] = rec
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(state, f)
    except Exception:
        pass

    n = rec["n"]
    if n < 2:
        return 0

    where = "%ds ago" % ago if ago else "earlier"
    head = "probe-dedupe: look #%d at `%s` this session (last %s)." % (n, key, where)
    firstline = "  first was: %s" % rec["first"]

    if n < BLOCK_AT:
        sys.stderr.write(head + "\n" + firstline +
                         "\n  Re-probe only if something could have changed it.\n")
        return 0

    sys.stderr.write(head + "\n" + firstline +
                     "\n  BLOCKED at look #%d. Use the answer in context, or watch it "
                     "in ONE call: for i in 1 2 3; do <probe>; sleep 5; done. "
                     "Override: PROBE_DEDUPE_OFF=1\n" % n)
    return 2


def self_test():
    """Guard the two directions at once. A dedupe key that is too coarse blocks
    real work (the 2026-08-24 container bug); one that is too fine dedupes
    nothing and the tool is dead weight. Neither failure is visible from the
    other side, so both get an assertion."""
    fails = []
    # TOO COARSE: four different reads under one config tree must not collide.
    keys = {fingerprint(c) for c in (
        "cd ~/.claude && grep -n 'hook' reference/inventory.md",
        "cd ~/.claude && grep -rn 'sonnet' projects/memory/*.md",
        "cd ~/.claude && sed -n '1,40p' bin/gen-sot-digest.sh",
        "cd ~/.claude && wc -c CLAUDE.md",
    )}
    if len(keys) < 4:
        fails.append(f"unrelated reads under ~/.claude collided: {keys}")
    # TOO FINE: the same subject asked three ways must still collapse to one.
    same = {fingerprint(c) for c in (
        "ps -o pcpu= -p 4242",
        "ps -o pcpu= -p 4242 | cut -c1-80",
        "ps -o pcpu=,rss= -p 4242 | awk '{print $1}'",
    )}
    if len(same) != 1:
        fails.append(f"one subject asked three ways split into {len(same)}: {same}")
    # Two reads of ONE file through different pipelines are one subject.
    if fingerprint("sed -n '1,40p' ~/.claude/bin/gen-sot-digest.sh") != \
       fingerprint("sed -n \"1,40p\" ~/.claude/bin/gen-sot-digest.sh | cut -c1-80"):
        fails.append("two reads of one file did not collapse")
    # Distinct files read after ONE `cd` are distinct subjects; the cd target is
    # only where they live. 2026-09-02: five first reads under one scratch dir
    # were blocked as looks #4 to #8 at the directory.
    per_file = {fingerprint(c) for c in (
        "cd /tmp/x/wa && fold -s -w 200 04_Amer.txt",
        "cd /tmp/x/wa && fold -s -w 200 05_Joel.txt",
        "cd /tmp/x/wa && cat 06_Devika.txt 08_Alessandro.txt",
    )}
    if len(per_file) != 3:
        fails.append(f"distinct files after one cd collapsed: {per_file}")
    if fingerprint("cd /tmp/x/wa && fold -s -w 200 04_Amer.txt") != \
       fingerprint("cd /tmp/x/wa && cat 04_Amer.txt | head"):
        fails.append("one bare file read two ways did not collapse")
    # Explicit slices are distinct subjects, while repeating one exact slice
    # remains a repeat.  This is the paging contract for long files.
    sliced = (
        "sed -n '100,137p' decisions/x.md | cut -c1-300",
        "sed -n '247,295p' decisions/x.md | cut -c1-300",
        "sed -n '113,175p' decisions/x.md | cut -c1-300",
        "sed -n '295,332p' decisions/x.md | cut -c1-300",
        "unzip -p \"$Z\" _chat.txt | sed -n '46,85p' | cut -c1-200",
    )
    if len({fingerprint(c) for c in sliced}) != 5:
        fails.append("distinct line slices collapsed")
    if fingerprint("sed -n '1,40p' f.md") != fingerprint("sed -n '1,40p' f.md"):
        fails.append("identical line slice did not repeat")
    if fingerprint("git status --short") != "git":
        fails.append("slice-free legacy key changed")
    slice_forms = (
        "sed -n \"1,40p\" f.md",
        "sed -n 1,40p f.md",
        "head -n 40 f.md",
        "head -40 f.md",
        "head -c 40 f.md",
        "tail -n 40 f.md",
        "tail -n +40 f.md",
        "tail -40 f.md",
        "awk 'NR>=1 && NR<=40' f.md",
    )
    if any(_slice_suffix(c) is None for c in slice_forms):
        fails.append("a supported slice syntax form was not recognised")
    # A mutation is never a probe, whatever it mentions. Same test the main
    # path uses, so this cannot pass while the live check drifts.
    if not MUTATION.search("git -C ~/.claude commit -m x"):
        fails.append("a commit was not recognised as a mutation")
    if MUTATION.search("git -C ~/.claude status -s"):
        fails.append("git status was misread as a mutation")
    for f in fails:
        print("  " + f)
    print("probe-dedupe self-test: %s" % ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(main())
