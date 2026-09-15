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
# HIS SURFACES LIVE IN DATA, NOT IN THIS FILE.
#
# They were a literal list here until 2026-09-14, and the public mirror scrubs
# venture names to a placeholder. Inside a REGEX that is fatal: nine distinct
# patterns all collapsed to "a venture|another venture|..." so every prompt
# matched the last one, and the published self-test failed. Codex job 965 caught
# it. A list of pairs survived having its LABELS rewritten and its PATTERNS still
# did not.
#
# So the venture list is now data the mirror never sees, and this file ships a
# generic default that is coherent on its own. Mechanism public, roster private.
SURFACES_FILE = os.path.expanduser("~/.claude/state/surfaces.json")
DEFAULT_SURFACES = [
    ("product", r"\bproduct\b|catalogue|catalog|storefront|sku"),
    ("site", r"\bsite\b|landing page|homepage|sitemap|\bseo\b"),
    ("outreach", r"outreach|linkedin|cold |warm lane|investor|icp"),
    ("commerce", r"customer|order|invoice|revenue|ad(s|words)?\b|campaign|conversion"),
]


def _load_surfaces():
    try:
        with open(SURFACES_FILE, encoding="utf-8") as fh:
            rows = json.load(fh)
        out = [(r["label"], r["pattern"]) for r in rows if r.get("pattern")]
        if out:
            return out
    except Exception:
        pass
    return DEFAULT_SURFACES


SURFACES = _load_surfaces()
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
    """Exercise the MECHANISM against the built-in default roster.

    The cases used to name his real ventures, which meant the public mirror
    scrubbed the inputs AND the expected values to the same placeholder, so the
    shipped self-test failed while the private one passed. A test whose fixtures
    are private data cannot survive publication. These use the default roster,
    which is the same in both copies.
    """
    ok = True
    cases = [
        ("the storefront catalogue is broken", {"product"}, False),
        ("fix the stop hook then", set(), True),
        ("why are my sessions autocompacting at 97%", set(), True),
        ("chase the customer invoice", {"commerce"}, False),
        ("the landing page sitemap is stale", {"site"}, False),
        ("migrate everything", set(), False),
    ]
    saved = globals()["SURFACES"]
    globals()["SURFACES"] = DEFAULT_SURFACES
    try:
        for text, want_s, want_p in cases:
            got_s, got_p = surfaces(text), is_plumbing(text)
            if got_s != want_s or got_p != want_p:
                print("FAIL %r surfaces=%s want=%s plumbing=%s want=%s"
                      % (text, got_s, want_s, got_p, want_p))
                ok = False
    finally:
        globals()["SURFACES"] = saved
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
    # HANDBACK, measured 2026-09-15 over 2,909 close-outs: 92 per cent of August
    # and 76 per cent of September put something in YOUR MOVE, where the format's
    # declared target state is "Nothing". Printed here, before the reply is
    # written, because a Stop-time block would cost a second message and he
    # banned double texting. One line, no new hook.
    print("BEFORE YOUR MOVE: 76% of Sept close-outs handed work back. For each line "
          "you are about to put there, ask whether YOU could do it. If yes, do it "
          "instead. It belongs to him only if it needs his decision, his account, "
          "his hands, or his money.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
