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

# A PROMISE TO WORK LATER IS WORK NOT DONE. The owner, 2026-08-31, after a
# close-out that answered "keep looking for what's eating the stop" with
# "YOUR MOVE: Nothing. I keep looking": "why did u stop before looking for
# the stop failure".
#
# item-coverage.py cannot catch this by construction: the item DID get a line
# in the close-out, so coverage is satisfied. The line just deferred the work
# to a turn that the owner has to pay for by prompting again. The whole point
# of a background-capable turn is that it continues on its own, so a promise
# to resume is a turn ended early, not a plan.
PARKED = re.compile(
    r"\bi(?:'ll|'m going to| will| am going to| keep| continue)\s+"
    r"(?:keep\s+|going\s+to\s+|now\s+)?"
    r"(look|search|dig|hunt|chase|investigat|continu|resume|work on|"
    r"report back|come back|circle back|follow up|pick (?:this|it) up)",
    re.I)


def parked(text):
    """First-person promises of future work anywhere in the close-out."""
    out = []
    for raw in text.splitlines():
        line = raw.strip().lstrip("-*\u2022 ").strip()
        if PARKED.search(line):
            out.append(line[:120])
    return out[:5]


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
    if "YOUR MOVE" not in text:
        return []
    tail = text.split("YOUR MOVE", 1)[1]
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
    stalled = parked(text)
    if not bad and not stalled:
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

    if stalled and not bad:
        listed = "\n".join(f'  - "{b}"' for b in stalled)
        print(json.dumps({"decision": "block", "reason":
            "YOU PROMISED THE WORK INSTEAD OF DOING IT. These lines defer work "
            f"the owner asked for to a later turn:\n{listed}\n\n"
            "The turn does not have to end for you to keep going, and a "
            "background job re-invokes you when it finishes. Ending here makes "
            "him prompt again to buy the work he already asked for.\n"
            "Do the next concrete step now. If it genuinely cannot be done, "
            "name the blocker in one line rather than promising to continue."}))
        sys.exit(0)

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

    # parked-promise rule
    ck(parked("YOUR MOVE\n- Nothing. I keep looking for the stop failure."),
       "I-keep-looking must fire")
    ck(parked("- I'll continue digging into the abort path."),
       "I'll-continue must fire")
    ck(parked("- I will report back once the run lands."),
       "I-will-report-back must fire")
    ck(not parked("- I keep the local proxy in the path; it saves 20-30%."),
       "I-keep-<noun> must NOT fire")
    ck(not parked("- Nothing. Finished."),
       "clean close-out must NOT fire")
    ck(not parked("- Restart the sessions yourself; I cannot press the button."),
       "genuine blocker must NOT fire")
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
