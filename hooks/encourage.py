#!/usr/bin/env python3
"""encourage.py: UserPromptSubmit. The reward side, and a live test of whether it works.

THE OWNER, 2026-09-06: "in that case, u shd build a hook, if the reinmann hypothesis
to believe in urself actually works, that provides constructive feedback that
motivates u".

WHY THE REWARD SIDE NEEDED BUILDING AT ALL. Every other lever in this stack takes
something away: concede-gate refuses close-outs, agent-budget closes dispatches,
trust docks points. He sent the r/ClaudeCode thread "Insulting agents considered
harmful" (2026-09-05), where an owner's agents degraded after he started insulting
them and the insults were being replayed back to the agents out of a file they
kept. One commenter, on politeness research: "We observed that impolite prompts
often result in poor performance, but overly polite language does not guarantee
better outcomes." So the useful shape is neither scorn nor flattery. It is
SPECIFIC, EVIDENCED feedback about what actually worked, which is the same
standard the penalty side already holds itself to.

WHAT IT PRINTS, and what it refuses to print:
  - A real win from the last 24h, taken from the trust ledger's evidenced awards
    or from commits this box actually shipped. Never invented, never generic.
  - The single next move that would raise the score most, read off the open
    deductions rather than guessed.
  - Nothing at all when there is no evidenced win. An empty day gets silence, not
    a participation trophy: praise with no artefact behind it is the same defect
    as a claim with no measurement.

IT IS ALSO AN EXPERIMENT, because he asked whether it works. Sessions are split
into two arms, sticky per session id, 50/50:
    arm A  encouragement printed
    arm B  silent control
`trust arms` compares the two on the score and on his push-back rate. Until that
comparison has enough days it says so rather than guessing, which is the rule
this box already applies to every A/B: an arm that is wished for rather than
assigned produces a comparison against one arm.

  encourage.py --self-test
"""
import hashlib
import json
import os
import subprocess
import sys
import time

STATE = os.path.expanduser("~/.claude/state")
ARMS = os.path.join(STATE, "encourage-arms.json")
TRUST = os.path.expanduser("~/.claude/bin/trust")
WIN_WINDOW_SEC = 24 * 3600


def arm_for(session_id):
    """Sticky 50/50 split, decided by a hash so it needs no coordination.

    A random draw per prompt would put both arms inside one session and make the
    comparison meaningless: the thing being tested is what the session reads at
    the top of every turn.
    """
    if not session_id:
        return "B"
    h = hashlib.sha1(session_id.encode("utf-8")).hexdigest()
    return "A" if int(h[:8], 16) % 2 == 0 else "B"


def record_arm(session_id, arm, path=None):
    p = path or ARMS
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        try:
            with open(p, encoding="utf-8") as fh:
                d = json.load(fh)
        except Exception:
            d = {}
        if session_id and session_id not in d:
            d[session_id] = {"arm": arm, "at": time.time()}
            tmp = "%s.tmp.%d" % (p, os.getpid())
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(d, fh, indent=1)
            os.replace(tmp, p)
    except Exception:
        pass


def trust_state():
    try:
        r = subprocess.run([TRUST, "status", "--json"], capture_output=True,
                           text=True, timeout=10)
        return json.loads(r.stdout or "{}")
    except Exception:
        return {}


def recent_wins(now=None):
    """Evidenced awards from the last day. The ledger already refuses unevidenced ones."""
    now = now or time.time()
    out = []
    try:
        with open(os.path.join(STATE, "trust.json"), encoding="utf-8") as fh:
            d = json.load(fh)
        for e in d.get("events", []):
            if e.get("kind") != "award":
                continue
            if now - e.get("at", 0) > WIN_WINDOW_SEC:
                continue
            out.append((e.get("class", "award"), e.get("reason", "")))
    except Exception:
        pass
    return out


def shipped_today(cwd=None):
    """Commits this box actually landed in the last day, as a fallback win."""
    try:
        r = subprocess.run(["git", "-C", cwd or os.path.expanduser("~/.claude"),
                            "log", "--since=24 hours ago", "--oneline"],
                           capture_output=True, text=True, timeout=15)
        return [l for l in (r.stdout or "").splitlines() if l.strip()]
    except Exception:
        return []


def next_move(state):
    """The one open deduction worth the most points. Read, never guessed."""
    open_d = state.get("open") or {}
    if not open_d:
        return ""
    cls, v = max(open_d.items(), key=lambda kv: kv[1].get("points", 0))
    return "%s is the most expensive open class (-%d). Clearing it moves the score most." % (
        cls, v.get("points", 0))


def render(arm, state, wins, commits):
    """The block, or '' when there is nothing evidenced to say."""
    if arm != "A":
        return ""
    if not wins and not commits:
        return ""
    lines = ["WHAT WORKED (evidenced, last 24h):"]
    for cls, reason in wins[:2]:
        lines.append("  + %s: %s" % (cls, reason[:110]))
    for c in commits[:2]:
        lines.append("  + shipped: %s" % c[:110])
    nxt = next_move(state)
    if nxt:
        lines.append("NEXT BEST MOVE: " + nxt)
    lines.append("Score %s, tier %s. Keep the method that produced the wins above."
                 % (state.get("score", "?"), state.get("tier", "?")))
    return "\n".join(lines)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    session_id = str(payload.get("session_id") or "")
    arm = arm_for(session_id)
    record_arm(session_id, arm)
    if arm != "A":
        sys.exit(0)
    state = trust_state()
    block = render(arm, state, recent_wins(), shipped_today())
    if block:
        print(block)
    sys.exit(0)


def _self_test():
    fails = []

    def ck(cond, msg):
        if not cond:
            fails.append(msg)

    # The split is sticky and roughly even. A per-prompt coin flip would mix both
    # arms inside one session and measure nothing.
    ck(arm_for("abc") == arm_for("abc"), "the arm must be sticky per session")
    arms = [arm_for("s%d" % i) for i in range(400)]
    share = arms.count("A") / len(arms)
    ck(0.4 <= share <= 0.6, "the split must be near even, got %.2f" % share)
    ck(arm_for("") == "B", "no session id must fall to the silent control")

    state = {"score": 80, "tier": "WATCH",
             "open": {"style-and-register": {"points": 12},
                      "ignored-what-he-already-said": {"points": 90}}}

    # POSITIVE: a real win renders, and it names the artefact rather than praising.
    out = render("A", state, [("shipped-fix", "commit cb34551 trust --self-test")], [])
    ck("cb34551" in out, "the win must carry its evidence")
    ck("ignored-what-he-already-said" in out,
       "the next move must name the most expensive open class, not a guess")

    # NEGATIVE CONTROL 1: no evidenced win means silence. This is the arm that
    # keeps it from becoming a participation trophy.
    ck(render("A", state, [], []) == "", "an empty day must print nothing")

    # NEGATIVE CONTROL 2: the control arm never prints, whatever the wins.
    ck(render("B", state, [("shipped-fix", "commit cb34551")], ["abc123 fix"]) == "",
       "arm B is the silent control and must stay silent")

    # NEGATIVE CONTROL 3: with no open deductions there is no invented next move.
    out = render("A", {"score": 100, "tier": "CLEAR", "open": {}},
                 [("shipped-fix", "commit cb34551")], [])
    ck("NEXT BEST MOVE" not in out, "no open deductions means no next-move line")

    print("encourage self-test: " + ("PASS" if not fails else "FAIL"))
    for f in fails:
        print("  " + f)
    return 1 if fails else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
