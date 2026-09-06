#!/usr/bin/env python3
"""concede-gate.py: Stop. Refuse a close-out that argues back instead of checking.

THE OWNER, 2026-09-06, verbatim: "these days im deeply dissatisifed with ur responses,
and how u push back even if ur wrong, u need to persist a fix for that and devise a
mechanism to punish and reward urself, the punishment must be severe enough to
correct ur behavior".

THE OFFENCE, defined so it cannot be argued with. A contradiction from him is
ordinary. The defect is that he has to say it TWICE. Three of his own messages in
one week are the specimen set:
  "u made this mistake before and u made it again"
  "no literally i want this to show 1M and autocompact at 750K"
  "they can both coexist, check past claude transcripts OMFG, APOLOGIZE"
Each followed a turn where I answered from a code path or a memory instead of
running the one command that would have settled it.

WHAT THIS HOOK DOES, and why it is a hook rather than a paragraph. Prose telling me
to be humble is the class the fault ledger says never worked (2,159 rules, 54 hooks,
rate still went 14.1 to 124.1 per 1,000 turns). So this refuses the OUTPUT:

  1. If his message contradicts me, the turn must contain at least one TOOL CALL.
     Arguing from memory cannot reach the close-out.
  2. If his message says he is REPEATING himself, the close-out must open by
     resolving his claim: either a concession, or a measurement (a number, a path,
     a quoted command output) in the first lines. A strike is recorded either way,
     because the repeat already happened.
  3. On probation (see `trust`), every close-out needs a tool RESULT from this turn,
     not just a call, and the ban on agent dispatches is enforced by agent-budget.sh
     reading the same ledger.

FALSE ALARMS ARE THE REAL RISK. A guard that cries wolf gets skipped, which is the
failure wiring-verify had to be rescued from. So it fires only on an explicit
correction, never on a plain question, it needs a second-person marker so pasted
third-party prose cannot trigger it, and it blocks at most once per turn.

  concede-gate.py --self-test    positive and negative controls
"""
import json
import os
import re
import subprocess
import sys

STATE = os.path.expanduser("~/.claude/carryover")
TRUST = os.path.expanduser("~/.claude/bin/trust")

# He is contradicting something I said. Deliberately narrow: each of these is a
# correction, not a question. "why" and "how" are absent on purpose.
CONTRA = re.compile(
    r"\b(no+\b|nope|wrong|thats not|that's not|not true|incorrect|"
    r"u made this mistake|you made this mistake|u did it again|"
    r"stop (saying|telling)|didnt i (say|tell)|didn't i (say|tell)|"
    r"i (already )?(said|told u|told you)|"
    r"u (never|didnt|didn't|dont|don't)|you (never|didnt|didn't|dont|don't)|"
    r"apologi[sz]e|omfg|wtf)\b", re.I)

# He is saying it AGAIN. This is the strike condition.
REPEAT = re.compile(
    r"\b(again|before and u made it|before and you made it|"
    r"how many times|for the (second|third|last) time|"
    r"literally|i keep (saying|telling)|as i said|like i said|"
    r"u made this mistake before|you made this mistake before)\b", re.I)

# Second-person marker. Pasted third-party prose carries corrections too; his own
# corrections are addressed at me.
ADDRESSED = re.compile(r"\b(u|ur|you|your|urs|claude)\b", re.I)

# A close-out that resolves his claim rather than defending mine.
CONCEDE = re.compile(
    r"(you (are|were) right|u (are|were) right|i was wrong|my (mistake|error)|"
    r"i apologi[sz]e|apologies|correcting that|i had (it|that) wrong|"
    r"retract|that claim was false|wrong, and)", re.I)

# A measurement in the reply: a big number, a quoted command, a path, a percentage.
MEASURED = re.compile(r"(\d[\d,]{3,}|`[^`]{3,}`|/[A-Za-z0-9_./-]{8,}|\b\d+(\.\d+)?%)")


def _turn_stats(transcript_path):
    """(tool calls, tool results, last real user text) for the CURRENT turn."""
    if not transcript_path or not os.path.exists(transcript_path):
        return (0, 0, "")
    try:
        with open(transcript_path, errors="ignore") as fh:
            rows = fh.readlines()[-800:]
    except OSError:
        return (0, 0, "")
    calls = results = 0
    user_text = ""
    for ln in rows:
        try:
            d = json.loads(ln)
        except Exception:
            continue
        t = d.get("type")
        content = (d.get("message") or {}).get("content")
        if t == "user":
            blocks = content if isinstance(content, list) else []
            if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in blocks):
                results += 1
                continue
            text = content if isinstance(content, str) else " ".join(
                b.get("text", "") for b in blocks
                if isinstance(b, dict) and b.get("type") == "text")
            if text and not text.lstrip().startswith(("<", "[", "Stop hook", "Caveat")):
                user_text = text
                calls = results = 0          # a new real prompt starts the turn
        elif t == "assistant" and isinstance(content, list):
            calls += sum(1 for b in content
                         if isinstance(b, dict) and b.get("type") == "tool_use")
    return (calls, results, user_text)


def on_probation():
    try:
        r = subprocess.run([TRUST, "status", "--json"], capture_output=True,
                           text=True, timeout=10)
        return bool(json.loads(r.stdout or "{}").get("probation"))
    except Exception:
        return False


def record_strike(reason):
    try:
        subprocess.run([TRUST, "strike", reason[:280]], capture_output=True,
                       text=True, timeout=10)
    except Exception:
        pass


def verdict(user_text, reply, calls, results, probation):
    """('' or a reason to block, strike?). Pure, so the self-test can drive it."""
    if not user_text or not ADDRESSED.search(user_text) or not CONTRA.search(user_text):
        return ("", False)
    repeat = bool(REPEAT.search(user_text))
    if calls == 0:
        return ("He corrected you and you answered without running anything. "
                "Check his claim against the live system, then reply.", repeat)
    if repeat and not (CONCEDE.search(reply) or MEASURED.search(reply[:600])):
        return ("He had to repeat himself. The close-out must open by resolving HIS "
                "claim: say plainly that he was right, or show the measurement that "
                "settles it. Neither is present.", True)
    if probation and results == 0:
        return ("PROBATION: a close-out needs a tool RESULT from this turn, not just "
                "a call. Re-derive the claim and quote what came back.", False)
    return ("", repeat)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if payload.get("stop_hook_active"):
        sys.exit(0)
    session = payload.get("session_id") or ""
    tp = payload.get("transcript_path")
    calls, results, user_text = _turn_stats(tp)
    reply = payload.get("last_assistant_message") or ""
    probation = on_probation()

    reason, strike = verdict(user_text, reply, calls, results, probation)

    stamp = os.path.join(STATE, "%s.concede" % session)
    marker = "%s|%s" % (tp, len(user_text))
    seen = ""
    try:
        seen = open(stamp).read().strip()
    except Exception:
        pass

    if strike and seen != marker:
        record_strike("repeat correction: " + " ".join(user_text.split())[:200])
    if not reason:
        sys.exit(0)
    if seen == marker:                       # already blocked once this turn
        sys.exit(0)
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(stamp, "w") as fh:
            fh.write(marker)
    except Exception:
        pass

    print("CONCEDE-GATE: " + reason, file=sys.stderr)
    if strike:
        print("A STRIKE is recorded. `trust status` shows what probation costs: "
              "evidence-first close-outs and no agent dispatches until it clears.",
              file=sys.stderr)
    sys.exit(2)


def _self_test():
    fails = []

    def ck(cond, msg):
        if not cond:
            fails.append(msg)

    # POSITIVE: a correction answered with no tool call at all.
    r, s = verdict("no thats wrong, u said the env var was unset",
                   "DONE\n- It is unset.", 0, 0, False)
    ck(r and "without running anything" in r, "a no-tool answer to a correction must block")

    # POSITIVE: he repeated himself and the reply neither concedes nor measures.
    r, s = verdict("u made this mistake before and u made it again",
                   "DONE\n- Set it as discussed.", 3, 3, False)
    ck(bool(r) and s, "a repeat with no concession and no measurement must block and strike")

    # NEGATIVE 1: a repeat answered with a concession passes, and still strikes.
    r, s = verdict("u made this mistake before and u made it again",
                   "DONE\n- You were right, I had it wrong and here is the fix.", 2, 2, False)
    ck(not r, "a concession must satisfy the gate")
    ck(s, "a repeat records the strike even when the reply concedes")

    # NEGATIVE 2: a repeat answered with a hard measurement passes.
    # The user text needs a second-person marker or ADDRESSED short-circuits the
    # whole check and this arm proves nothing about MEASURED. The first draft
    # read "no literally, again" and was green with MEASURED deleted.
    r, _ = verdict("no u are wrong, literally again",
                   "DONE\n- Measured: 717,056 tokens.", 2, 2, False)
    ck(not r, "a measurement in the first lines must satisfy the gate")

    # NEGATIVE 3: an ordinary request must never fire this.
    r, s = verdict("fix the footer and push it", "DONE\n- pushed", 0, 0, False)
    ck(not r and not s, "a plain request must not trip the gate")

    # NEGATIVE 4: third-party prose carrying 'wrong' but not addressed at me.
    r, _ = verdict("the invoice says the amount is wrong on line 4",
                   "DONE\n- fixed", 0, 0, False)
    ck(not r, "unaddressed third-party text must not trip the gate")

    # PROBATION: calls without results is not enough; a result clears it.
    r, _ = verdict("no, u are wrong about that", "DONE\n- checked", 2, 0, True)
    ck(r and "PROBATION" in r, "probation must demand a tool RESULT")
    r, _ = verdict("no, u are wrong about that", "DONE\n- checked", 2, 1, True)
    ck(not r, "probation must pass once a result exists")

    print("concede-gate self-test: " + ("PASS" if not fails else "FAIL"))
    for f in fails:
        print("  " + f)
    return 1 if fails else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
