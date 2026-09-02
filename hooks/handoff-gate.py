#!$HOME/.venvs/agent-libs/bin/python
# handoff-gate.py: Stop. Refuse to hand back work that is mine to do.
#
# THE FAILURE THIS FIXES, measured rather than felt. Across every close-out
# since 2026-08-20: 1,520 items were handed to the owner under YOUR MOVE, and
# only 142 of them (9%) genuinely required him. The other 91% were requests for
# a decision I could make, permission for work already authorised, or an action
# with an API I can call. The owner, 2026-08-27: "u keep delegating me tasks to
# do, instead of doing it urself".
#
# CLAUDE.md has said DECIDE, DO NOT ASK since 2026-08-06, and closeout-shape.py
# already has an R6 against parking work behind approval. Both are prose about
# INTENT; neither reads the item and asks "could you have done this?". That is
# what this does.
#
# WHAT COUNTS AS GENUINELY HIS, and it is a short list on purpose:
#   - credentials: entering, rotating or revoking anything secret
#   - his hands: a physical device, an app restart, a click in a GUI I cannot drive
#   - his knowledge: a business fact, a preference, data only he holds
#   - his authority: spending money, sending something I invented to a real person
# Everything else is mine, including deciding between two options I generated.
#
# WHAT IT DOES NOT DO: it never blocks an empty handoff. "Nothing." is the
# target state and passes silently every time.

import json
import os
import re
import sys

STATE = os.path.expanduser("~/.claude/state")
MAX_BLOCKS = 1

# Phrasings that hand a DECISION back. Each of these appeared verbatim in the
# measured sample above.
ASKS = re.compile(
    r"\b(tell me which|tell me where|tell me what|let me know|say go|say the word|"
    r"if you want|whenever you want|want me to|shall i|should i|do you want|"
    r"confirm (?:and|then|whether|if)|decide\b|"   # bare "Decide X: a, or b" was the live shape
    r"your call|up to you|pick one|choose (?:which|between)|"
    r"and i(?:'ll| will) (?:then |go ahead and )?(?:do|run|expand|repair|build|fix|send|write))\b",
    re.I)

# An action whose verb maps to a tool I hold.
DOABLE = re.compile(
    r"^\s*(?:optional[,:]?\s*)?(?:please\s+)?"
    r"(add|create|delete|remove|strike|update|edit|rename|move|fix|repair|run|"
    r"rebuild|regenerate|commit|push|merge|deploy|configure|set|enable|disable|"
    r"install|clean|prune|archive|index|document|write)\b", re.I)

# The narrow set that really is his.
HIS = re.compile(
    r"\b(rotate|revoke|password|passphrase|2fa|mfa|sign in|log in|sign-in|"
    r"credential|api key|token\b|"
    r"restart the claude|quit and reopen|cmd\+q|relaunch|reboot|"
    r"your phone|by hand|physically|plug|unplug|"
    r"admin\.google|platform\.openai|github\.com/settings|"
    r"measurements|only you|business decision|prefer|budget|invoice|"
    r"approve the spend|pay|purchase|subscribe|"
    # "…yourself" is an explicit marker that the item needs his hands or his
    # data. The backtest caught this: "Set the three metric fields yourself"
    # is his (only he knows the revenue), and the verb alone read as doable.
    r"yourself|your own)\b", re.I)

EMPTY = re.compile(r"^\s*[-*]?\s*(nothing|none)\b", re.I)

# The PARKED rule ("I keep looking", "I'll continue digging": a promise to work
# later is work not done) lived here from 2026-08-31 to 2026-09-02. MOVED to
# closeout-shape.py R10. the owner: "why are there 3 stop hooks in a row isnt that
# redundant". Measured: R10 there missed all three of PARKED's positives and
# PARKED missed all of R10's, so two disjoint blacklists were enforcing one
# principle from two files with two banners. One rule, one place, with the
# DEFER_OK / DEFER_QUOTE exemptions this copy never had. This hook now does
# the one thing only it does: YOUR MOVE items that are mine to do.


def last_text(transcript):
    try:
        with open(transcript, errors="ignore") as fh:
            lines = fh.readlines()[-200:]
    except Exception:
        return ""
    for ln in reversed(lines):
        try:
            d = json.loads(ln)
        except Exception:
            continue
        if d.get("type") == "assistant":
            for b in (d.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip():
                    return b["text"]
    return ""


def offenders(text):
    # ANCHOR THE HEADING TO A LINE START, fixed 2026-09-01 on a false positive
    # this hook produced against a close-out whose YOUR MOVE said only
    # "Nothing. Finished." A DONE bullet read "Empty YOUR MOVE across every repo
    # by day: 0.0% until 3 Aug...", and an unanchored split on the first
    # occurrence took everything after that phrase as handed-back items, so a
    # sentence of MEASUREMENTS was reported as work parked on the owner.
    # closeout-shape.py already anchors the same heading; this was the sibling
    # that did not. A guard that cries wolf gets ignored, which is how the real
    # eight-day Stop outage stayed invisible.
    m = re.search(r"^\s*(?:\*\*|##\s*)?YOUR MOVE", text, re.M)
    if not m:
        return []
    tail = text[m.end():]
    out = []
    for raw in tail.splitlines():
        line = raw.strip().lstrip("-*• ").strip()
        if len(line) < 12 or EMPTY.match(line):
            continue
        if HIS.search(line):
            continue                     # genuinely his, leave it
        if ASKS.search(line) or DOABLE.match(line):
            out.append(line[:120])
    return out[:5]


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if payload.get("stop_hook_active"):
        sys.exit(0)
    tp = payload.get("transcript_path")
    if not tp or not os.path.exists(tp):
        sys.exit(0)
    text = last_text(tp)
    bad = offenders(text)
    if not bad:
        sys.exit(0)

    sid = (payload.get("session_id") or "x")[:36]
    stamp = os.path.join(STATE, f"handoff-{sid}")
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

    listed = "\n".join(f"  - \"{b}\"" for b in bad)
    print(json.dumps({"decision": "block", "reason":
        "HANDING BACK WORK THAT IS YOURS. These YOUR MOVE items ask the owner "
        f"for a decision or an action you can perform:\n{listed}\n\n"
        "Measured across every close-out since 2026-08-20: 1,520 items handed "
        "over, only 9% genuinely needed him. YOUR MOVE is for credentials, his "
        "hands, his knowledge, or his money. Deciding between two options YOU "
        "generated is not any of those.\n"
        "Go do it now, then report it in DONE. If it truly cannot be done, say "
        "which item and WHY in one line. An empty YOUR MOVE is the target."}))
    sys.exit(0)


def _self_test():
    bad = 0
    def ck(c, m):
        nonlocal bad
        if not c:
            bad += 1
            print(f"FAIL {m}")

    D = "DONE\n- did a thing\n\nYOUR MOVE\n"

    # The parked-promise arms moved to closeout-shape.py --self-test (R10) on
    # 2026-09-02 together with the rule they exercised.
    # real examples from the measured sample: all must fire
    ck(offenders(D + "- Optional, whenever you want: tell me where gbrain dumps "
                     "should live and I will repair transcript-prune."),
       "asking where + I-will-then must fire")
    ck(offenders(D + '- hstack "everything": say go and I\'ll expand the manifest.'),
       "say-go must fire")
    ck(offenders(D + "- Decide the local proxy routing: heavy-lanes-only, or force all."),
       "decide-between-my-options must fire")
    ck(offenders(D + "- Delete the three stale rows from the config."),
       "a doable action must fire")

    # genuinely his: must NOT fire
    ck(not offenders(D + "- Rotate the OpenAI key at platform.openai.com."),
       "credential rotation is his")
    ck(not offenders(D + "- Restart the Claude app (Cmd+Q, relaunch)."),
       "app restart is his")
    ck(not offenders(D + "- Send me the BB series measurements, or say where they live."),
       "data only he has is his")
    ck(not offenders(D + "- Nothing."), "empty handoff must never fire")
    ck(not offenders("DONE\n- did a thing"), "no YOUR MOVE section at all")

    # ANCHOR ARM, 2026-09-01. The real false positive: the phrase "YOUR MOVE"
    # inside a DONE bullet. With an unanchored split this fires on a close-out
    # that hands back nothing, and it dies if the ^ anchor is ever removed.
    # The bullet AFTER the inline phrase must be verb-initial, or this arm never
    # reaches the bug: with the old unanchored split the tail has to contain
    # something DOABLE matches, otherwise it passes either way and is a dead
    # branch. Checked by reverting the anchor and confirming this arm goes red.
    ck(not offenders(
        "DONE\n"
        "- Empty YOUR MOVE across every repo by day: 0.0% until 3 Aug, then 5.9%.\n"
        "- Delete the three stale rows from the config.\n"
        "\nYOUR MOVE\n- Nothing. Finished."),
       "a DONE bullet containing the words YOUR MOVE is not a handoff")

    # --- DEAD-BRANCH ARMS 2026-08-29. HIS and EMPTY could each be corrupted to
    # never match with this test still green: the existing "is his" arms pass
    # because ASKS misses them, not because HIS exempts them. These reach HIS.
    ck(not offenders(D + "- Set the new password on the wifi and tell me which one you used."),
       "HIS: a credential line trips DOABLE and only HIS may exempt it")
    ck(not offenders(D + "- Nothing here unless you want me to expand the list."),
       "EMPTY: a wordy empty handoff trips ASKS and only EMPTY may exempt it")
    print("SELF-TEST PASS" if not bad else f"SELF-TEST FAILED ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
