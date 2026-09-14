#!/usr/bin/env python3
"""Name the surface the owner's last message is about, for the close-out contract.

His complaint, 2026-09-14, verbatim: "most of ur closeout isnt even fucking
relevant to me either, why the fuck do u keep telling me technical items" and
"u fucking use so many proxies".

WHY THIS IS NOT ANOTHER TEXT RULE. closeout-shape.py already carries four rules
(R3, R6, R10, R12) that scan my wording for work handed back. They have fired
3,979 times and its own comment concedes "a blacklist cannot win the race". The
rule that actually changed behaviour is stop-justify.sh, which reads repo STATE.
So this reads state too: which surface did he name, and which surface do my
close-out items name. It never inspects phrasing.

It prints BEFORE the close-out is written, on UserPromptSubmit, so a mismatch
costs zero extra messages. A Stop-time block would force a second reply, and he
banned double texting on 2026-09-04.
"""
import json
import os
import re
import sys

# His surfaces, as a LIST of pairs and not a dict.
#
# This was a dict keyed by venture name until 2026-09-14. The public mirror in
# hstack scrubs venture names to a generic placeholder, and six keys all became
# the same string, so Python silently collapsed them and the published hook
# matched one venture instead of nine. A dict literal cannot survive having its
# keys rewritten; a list of pairs can. Duplicate labels after scrubbing are
# harmless here because only the pattern decides a match.
SURFACES = [
    ("a venture", r"another venture|premier[- ]?trophy|獎盃|trophy|plaque|flag"),
    ("a venture", r"crystal ?century|another venture|卓越"),
    ("example.com", r"example.com|the owner-me|spring ?week|writing/"),
    ("a venture", r"another venture|prior ?moves|13F|filing|market literacy"),
    ("a venture", r"another venture|parent|student|tutor"),
    ("a venture", r"another venture|elevate ?os|oxbridge"),
    ("outreach", r"outreach|linkedin|cold |warm lane|investor|icp"),
    ("a venture", r"another venture|play console|another venture"),
    ("sites", r"a venture|another venture|another venture|another venture|another venture|another venture"),
    ("commerce", r"customer|order|invoice|revenue|ad(s|words)?\b|campaign|conversion|sku"),
]
# My surfaces: the machinery. Real work, but not what he bought.
PLUMBING = (
    r"hook|settings\.json|launchd|launchagent|weekend-run|weekend-refill|codex-bg"
    r"|subagent|token|context window|autocompact|auto-compact|compaction"
    r"|\.claude/|pgrep|pipefail|stop hook|transcript|jobq|state file|tsv"
    r"|close-out|closeout|git add|rev-list|pushed|commit [0-9a-f]{7}|pytest|lint"
)


def surfaces(text):
    t = (text or "").lower()
    return {name for name, pat in SURFACES if re.search(pat, t)}


def is_plumbing(text):
    t = (text or "").lower()
    return bool(re.search(PLUMBING, t)) and not surfaces(t)


def last_user_text(path):
    """His most recent authored turn. Tool results and notifications excluded."""
    last = ""
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for ln in fh:
                try:
                    d = json.loads(ln)
                except Exception:
                    continue
                if d.get("type") != "user":
                    continue
                c = (d.get("message") or {}).get("content")
                if isinstance(c, str):
                    t = c
                elif isinstance(c, list):
                    t = " ".join(b.get("text", "") for b in c
                                 if isinstance(b, dict) and b.get("type") == "text")
                else:
                    continue
                if "tool_result" in t or t.startswith("[SYSTEM NOTIFICATION"):
                    continue
                if t.strip():
                    last = t
    except OSError:
        return ""
    return last


def _self_test():
    ok = True
    cases = [
        ("the a venture css is gone", {"another venture"}, False),
        ("fix the stop hook then", set(), True),
        ("why are my sessions autocompacting at 97%", set(), True),
        ("push the a venture order sheet", {"another venture", "commerce"}, False),
        ("migrate everything to codex", set(), False),
    ]
    for text, want_s, want_p in cases:
        got_s, got_p = surfaces(text), is_plumbing(text)
        if got_s != want_s or got_p != want_p:
            print("FAIL %r surfaces=%s want=%s plumbing=%s want=%s"
                  % (text, got_s, want_s, got_p, want_p))
            ok = False
    print("RESULT: ALL PASS" if ok else "RESULT: FAIL")
    return 0 if ok else 1


def main():
    if "--self-test" in sys.argv:
        return _self_test()
    path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TRANSCRIPT", "")
    if not path or not os.path.exists(path):
        return 0
    ask = last_user_text(path)
    if not ask:
        return 0
    s = surfaces(ask)
    if s:
        print("HE ASKED ABOUT: %s. Every DONE item names that surface and what changed on it."
              % ", ".join(sorted(s)))
        print("  Plumbing items (hooks, tokens, launchd, commits, context window) do not go in")
        print("  DONE unless he asked for them. They are how the work got done, not the work.")
    elif not is_plumbing(ask):
        print("HE NAMED NO VENTURE. Answer the thing he asked, in his words, not in file paths.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
