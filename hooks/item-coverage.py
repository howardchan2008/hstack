#!$HOME/.venvs/agent-libs/bin/python
# item-coverage.py: Stop. Refuse a close-out that never mentions one of the items.
#
# THE FAILURE THIS FIXES, the owner 2026-08-26, verbatim: "u never fully execute my
# prompt, u force it into sessions and force me to adapt by only accepting only a
# small part is done".
#
# WHY THE EXISTING HOOKS DO NOT CATCH IT, measured before writing this. Four hooks
# already touch this area and not one of them checks COVERAGE:
#   prompt-items.py     splits the prompt into items and re-injects them. It proves
#                       the items were SHOWN. It cannot tell whether they were done.
#   carryover-queue.py  keeps interrupted work owed. Same blind spot.
#   closeout-shape.py   R1-R7 are shape: opens with DONE, no third section, no ask
#                       outside YOUR MOVE. A close-out can satisfy every one of
#                       them while silently dropping half the request.
#   stop-justify.sh     catches the CONFESSION ("still to do", "next steps"), which
#                       only fires when the model admits it. A dropped item is
#                       precisely the case where nothing is admitted.
# So the gap is exact: everything guards how the answer LOOKS and nothing guards
# what it COVERS.
#
# THE CHECK, and why it is term overlap rather than a line count. The obvious
# version compares item count against DONE lines. It is wrong in both directions:
# one line can honestly answer two items, and three lines can answer one. Instead,
# each item must leave a FINGERPRINT: at least one of its distinctive words has to
# appear somewhere in the close-out. An item about gbrain that produced work says
# "gbrain". One that was dropped says nothing at all, anywhere.
#
# FALSE ALARMS ARE THE REAL RISK, not misses. A checker whose noise outnumbers its
# signal trains the reader to skip it, which is the failure wiring-verify.sh had to
# be rescued from after it cried wolf on twelve known-good hooks every session. So
# this fires ONLY on an item with ZERO overlap, needs two distinctive terms before
# it will judge an item at all, and never fires on a single-item prompt.

import json
import os
import re
import sys

sys.path.insert(0, os.path.expanduser("~/.claude/hooks"))

MAX_BLOCKS = 1                       # one refusal per turn, then get out of the way
STATE = os.path.expanduser("~/.claude/carryover")

# Words that carry no identity. An item whose only shared word is "the" has not
# been covered, it has been coincided with.
STOP = set("""a an the and or but if then than that this these those to of in on at by for
with from into over under again further once here there all any both each few more most
other some such no nor not only own same so too very can will just should now do does did
doing done make made get got go goes went it its is are was were be been being have has had
i me my we our you your he him his she her they them their what which who whom when where
why how also want need like use using used run running ran also please lets let us thing
things stuff also still even really actually basically simply u ur im idk coz becoz smt
shd hv rn well yeah also whether anything everything something across
fix find identify compare check make sure""".split())
# NOTE on what is deliberately NOT a stopword. Generic VERBS belong above, because
# "fix" appears in both the request and any reply and would manufacture a false
# pass. Domain NOUNS must never go up there, however ordinary they look: an early
# draft had "restart" and "piled" in this list, which erased the fingerprint of
# "make sure everything needing a restart is piled in" and let a dropped item
# through. The self-test below is what caught it.

WORD = re.compile(r"[A-Za-z][A-Za-z0-9_.-]{2,}")


def terms(text):
    out = set()
    for w in WORD.findall(text.lower()):
        w = w.strip(".-_")
        if len(w) >= 3 and w not in STOP:
            out.add(w)
            # a dotted or hyphenated identifier also counts by its head, so
            # "the local proxy" in the item matches "the local proxy" in the reply
            head = re.split(r"[.\-_]", w)[0]
            if len(head) >= 4 and head not in STOP:
                out.add(head)
    return out


def load_items(session_id):
    """Reuse whatever prompt-items.py already stored for this session.

    Its real schema is {"last": {"items": [...]}, "n": N}, verified by reading the
    live store rather than assuming. A first draft looked for a top-level "items"
    key, found none, and silently returned [] on every turn, which is the exact
    shape of a guard that can never fire.
    """
    p = os.path.join(STATE, f"{session_id}.json")
    try:
        with open(p) as f:
            d = json.load(f)
    except Exception:
        return []
    items = ((d.get("last") or {}).get("items")
             or d.get("items") or [])
    return [str(x) for x in items if str(x).strip()]


# Items that are PASTED CONTENT rather than instructions. Reading the live store
# showed the splitter capturing quoted documentation ("> Use this file to discover
# all available pages"), which is text the user pasted, not something they asked
# for. Judging coverage on those would block a complete close-out, and a guard that
# cries wolf gets ignored, which is worse than not having it.
PASTED = re.compile(r"""^\s*(?:>|\#{2,}|```|https?://|/[A-Za-z0-9_./-]{12,}|\|)""")


def judgeable(item):
    if PASTED.search(item):
        return False
    if len(item) > 220:            # a pasted paragraph, not an instruction
        return False
    return True


def uncovered(items, reply):
    have = terms(reply)
    missed = []
    for it in items:
        if not judgeable(it):
            continue
        t = terms(it)
        # An item with fewer than two distinctive words cannot be judged fairly:
        # "also do that" has no fingerprint to look for.
        if len(t) < 2:
            continue
        if not (t & have):
            missed.append(it)
    return missed


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if payload.get("stop_hook_active"):
        sys.exit(0)
    session_id = payload.get("session_id") or ""
    if not session_id:
        sys.exit(0)

    items = load_items(session_id)
    if len(items) < 2:            # a single-item prompt cannot be partially done
        sys.exit(0)

    reply = payload.get("last_assistant_message") or ""
    if not reply:
        tp = payload.get("transcript_path")
        if tp and os.path.exists(tp):
            try:
                with open(tp, errors="ignore") as f:
                    lines = f.readlines()[-40:]
                for ln in reversed(lines):
                    d = json.loads(ln)
                    if d.get("type") == "assistant":
                        c = (d.get("message") or {}).get("content") or []
                        reply = " ".join(b.get("text", "") for b in c
                                         if isinstance(b, dict) and b.get("type") == "text")
                        if reply.strip():
                            break
            except Exception:
                sys.exit(0)
    if not reply.strip():
        sys.exit(0)

    missed = uncovered(items, reply)
    if not missed:
        sys.exit(0)

    # Never block more than once per turn.
    stamp = os.path.join(STATE, f"{session_id}.coverage")
    try:
        n = int(open(stamp).read().strip() or 0)
    except Exception:
        n = 0
    if n >= MAX_BLOCKS:
        sys.exit(0)
    try:
        os.makedirs(STATE, exist_ok=True)
        open(stamp, "w").write(str(n + 1))
    except Exception:
        pass

    listed = "\n".join(f"  - {m[:150]}" for m in missed[:6])
    print(json.dumps({
        "decision": "block",
        "reason": (
            "ITEM COVERAGE: the close-out never mentions "
            f"{len(missed)} item(s) from the request:\n{listed}\n\n"
            "Each of these was asked for and nothing in the reply refers to it. "
            "Do the work now, or, if it genuinely cannot be done, say which item "
            "and why under YOUR MOVE. Silence is not a valid exit for an item."
        )}))
    sys.exit(0)


def _self_test():
    bad = 0

    def ck(c, m):
        nonlocal bad
        if not c:
            bad += 1
            print(f"FAIL {m}")

    items = ["fix the gbrain prune job", "compare ox alpha against local models",
             "make sure everything needing a restart is piled in"]
    full = ("DONE\n- gbrain prune was already repaired.\n"
            "- ox alpha scored 6/7 against local models.\n"
            "- restart list complete, ten items piled in.")
    ck(uncovered(items, full) == [], "a covering reply must pass")

    partial = "DONE\n- gbrain prune was already repaired. Nothing else to report."
    miss = uncovered(items, partial)
    ck(len(miss) == 2, f"a reply dropping two items must flag both, got {len(miss)}")

    # must NOT fire on a vague item with no fingerprint
    ck(uncovered(["also do that"], "DONE\n- unrelated") == [],
       "an item with no distinctive words must not fire")
    # head matching: item says the local proxy, reply says the local proxy
    ck(uncovered(["run the local proxy and report", "check the holdout percentage"],
                 "DONE\n- the local proxy passes. holdout set to 10.") == [],
       "head-of-identifier matching must count as coverage")
    # stopwords alone are not coverage
    ck(len(uncovered(["measure the savings since day zero",
                      "wire the openrouter key"],
                     "DONE\n- the work is done and the thing was made.")) == 2,
       "stopword-only overlap must not count as coverage")
    # pasted content must never be judged: these appear in the live store
    ck(uncovered(["> Use this file to discover all available pages",
                  "## Documentation Index",
                  "https://example.com/some/long/path"],
                 "DONE\n- unrelated work.") == [],
       "pasted/quoted lines must not be judged as items")
    ck(uncovered(["x" * 260], "DONE\n- unrelated") == [],
       "an over-long pasted paragraph must not be judged")
    print("SELF-TEST PASS" if not bad else f"SELF-TEST FAILED ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
