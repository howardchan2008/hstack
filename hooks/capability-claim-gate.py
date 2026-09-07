#!$HOME/.venvs/agent-libs/bin/python
# capability-claim-gate.py: Stop. Refuse "X is dead" unless X was actually tried.
#
# THE FAILURE THIS FIXES, and it is the most-repeated one on this box.
# CLAUDE.md has carried a VERIFY-CAPABILITY rule since 2026-06-29: never assert a
# tool, API or lane CANNOT do something from a comment, a memory or one failed
# probe. It is prose, and prose lost. Measured instances, all wrong, all shipped
# to the owner as fact:
#   "Azure image generation is dead"   -> credit had expired; the lane returned
#                                         HTTP 200 and a real image.
#   "aiplatform is disabled"           -> the probe ran as a service account that
#                                         cannot list services. As the user: enabled.
#   "Vertex image models not granted"  -> wrong REGION. A working caller for the
#                                         right one sat in the owner's own repo.
#   "telemetry is off"                 -> the env var was absent; the OTLP default
#                                         already pointed at the live collector.
#   "the CLI update will land"         -> npm had it; the desktop bundles its own.
# Every one cost a round trip and two sent the owner to fix something unbroken.
#
# WHAT IT CHECKS, deliberately narrow so it cannot become noise.
# A close-out that declares a NAMED CAPABILITY dead must, in the same turn,
# either (a) show a tool call that actually exercised that capability, or
# (b) hedge honestly ("could not verify", "unverified", "have not tested").
# Absent both, the claim is an assumption wearing a finding's clothes and the
# turn is refused with the specific missing step.
#
# WHAT IT DOES NOT TOUCH: ordinary negative facts. "the file is not there",
# "no rows matched", "nothing else writes to it" are conclusions from a check
# that just ran, not capability verdicts, and they carry no capability noun.

import json
import os
import re
import sys

STATE = os.path.expanduser("~/.claude/state")
MAX_BLOCKS = 1

# A capability, not a file or a number. The claim has to be ABOUT one of these.
CAPABILITY = (r"(?:api|apis|lane|endpoint|model|models|service|integration|"
              r"tool|cli|mcp|server|key|token|credential|proxy|daemon|hook|"
              r"pipeline|generation|search|browser|extension|account|quota)")

# Assertive death verbs. "may be", "might be", "looks" are excluded on purpose:
# a hedged guess is exactly what this wants people to write instead.
DEATH = (r"(?:is|are|was|were|'s|has been|have been)\s+"
         r"(?:completely\s+|totally\s+|now\s+|effectively\s+)?"
         r"(?:dead|broken|disabled|unavailable|down|gone|revoked|expired|"
         r"not\s+available|not\s+working|no\s+longer\s+(?:works?|available)|"
         r"unsupported|not\s+supported|not\s+granted|not\s+enabled)")

# BLAMING AN ACTOR IS THE SAME CLAIM WEARING A VERB. Added 2026-09-04 after the
# gate sat armed through a whole session of this exact error and matched nothing.
# Measured against the sentences actually shipped that day: "LinkedIn is refusing
# this account's outbound invites", "LinkedIn is refusing automation". Both are
# capability verdicts about an external system, both were WRONG (the real cause was
# an ordinary weekly invitation limit, which the owner had to paste from his own
# screen), and neither matched DEATH because none of those words is a state
# adjective. "X is dead" was covered; "X is refusing me" was not, and the second
# shape is the more seductive one because it reads as an observation rather than a
# verdict. Same evidence bar: exercise it, or hedge, or quote what it actually said.
BLAME = (r"(?:is|are|was|were|'s|has been|have been|keeps|kept)\s+"
         r"(?:actively\s+|silently\s+|deliberately\s+|now\s+)?"
         r"(?:refusing|rejecting|blocking|throttling|rate[- ]limiting|"
         r"restricting|banning|denying|ignoring|dropping|filtering)")

CLAIM = re.compile(rf"\b([A-Za-z0-9][\w.+-]{{2,30}})\s+{CAPABILITY}?\s*(?:{DEATH}|{BLAME})", re.I)
# EVIDENCE DOES NOT SUPPORT is not a capability claim. Added 2026-09-04, the same day
# the BLAME arm went in and caught its own author: "the within-month contrast does not
# support the hook doing the work" is a statistical statement about a measurement that
# WAS run and pasted, and blocking it teaches the opposite of what this gate is for. It
# would push a session to drop an honest negative result rather than report it.
# The capability sense keeps firing: "the API does not support streaming".
_EVIDENTIAL = re.compile(
    r"\b(data|evidence|contrast|result|results|finding|findings|numbers|sample|"
    r"measurement|control|correlation|comparison|analysis|test|breakdown)\b", re.I)

CLAIM2 = re.compile(rf"\b([A-Za-z0-9][\w.+-]{{2,30}})\s+(?:cannot|can't|cant|"
                    rf"does\s+not|doesn't)\s+(?:do|send|read|write|run|reach|"
                    rf"access|generate|create|list|support)\b", re.I)

HEDGED = re.compile(
    r"could\s+not\s+verify|couldn't\s+verify|unverified|have\s+not\s+tested|"
    r"haven't\s+tested|did\s+not\s+test|didn't\s+test|not\s+confirmed|"
    r"i\s+have\s+not\s+checked|assuming|hypothesis|unknown", re.I)

# Words too generic to be the SUBJECT of a capability verdict; a match on these
# is almost always ordinary prose ("the file is gone").
GENERIC = {"it", "this", "that", "there", "which", "what", "the", "a", "an",
           "file", "files", "dir", "directory", "row", "rows", "line", "lines",
           "entry", "value", "path", "commit", "branch", "test", "job", "run",
           "one", "none", "nothing", "everything", "work", "issue", "problem"}


def turn_text(transcript, limit=60):
    """The assistant's final text plus the tool calls made in this turn."""
    last_text, tools = "", []
    try:
        with open(transcript, errors="ignore") as fh:
            lines = fh.readlines()[-400:]
    except Exception:
        return "", []
    for ln in reversed(lines):
        try:
            d = json.loads(ln)
        except Exception:
            continue
        t = d.get("type")
        if t == "user" and isinstance((d.get("message") or {}).get("content"), str):
            break                       # reached the prompt that opened this turn
        if t == "assistant":
            for b in (d.get("message") or {}).get("content") or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and not last_text:
                    last_text = b.get("text", "")
                elif b.get("type") == "tool_use":
                    tools.append(json.dumps(b.get("input") or {})[:600])
        if len(tools) > limit:
            break
    return last_text, tools


def offenders(text, tools):
    """Capability-death claims with neither a test nor a hedge."""
    if HEDGED.search(text):
        return []
    blob = " ".join(tools).lower()
    out = []
    for rx in (CLAIM, CLAIM2):
        for m in rx.finditer(text):
            subj = m.group(1)
            if subj.lower() in GENERIC or subj.lower().endswith(("ing",)):
                continue
            # An EVIDENTIAL subject is reporting a measurement, not a capability.
            # "the within-month contrast does not support the hook" was blocked on
            # 2026-09-04 although the test had just been run and its table pasted,
            # which would teach a session to drop an honest negative result rather
            # than report it. "the API does not support streaming" still fires.
            if _EVIDENTIAL.fullmatch(subj):
                continue
            # Did any tool call in this turn actually mention the subject? That
            # is the cheapest possible proxy for "you tried it", and it is the
            # one the failures above would all have failed.
            stem = re.split(r"[.\-_]", subj.lower())[0]
            if len(stem) >= 3 and stem in blob:
                continue
            out.append(m.group(0).strip()[:110])
    return out[:4]


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
    text, tools = turn_text(tp)
    if not text.strip():
        sys.exit(0)
    bad = offenders(text, tools)
    if not bad:
        sys.exit(0)

    sid = (payload.get("session_id") or "x")[:36]
    stamp = os.path.join(STATE, f"capclaim-{sid}")
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
        "CAPABILITY CLAIM WITHOUT A TEST. This close-out declares something "
        f"unavailable and nothing in the turn exercised it:\n{listed}\n\n"
        "Every past instance of this shape was WRONG: a credit had expired while "
        "the lane worked, a probe ran as the wrong identity, a model was called "
        "in the wrong region, an env var was absent while the default already "
        "pointed at the live service. Before saying it again, do one of:\n"
        "  1. Call the thing and paste what it returned.\n"
        "  2. grep the repos for a WORKING caller and read how it differs.\n"
        "  3. Say 'I could not verify' and name what you did not test.\n"
        "An error from a dependency is a claim about YOUR call until the call "
        "itself has been checked."}))
    sys.exit(0)


def _self_test():
    bad = 0
    def ck(c, m):
        nonlocal bad
        if not c:
            bad += 1
            print(f"FAIL {m}")

    # the real failures this exists to stop
    ck(offenders("Azure image generation is dead, the credit expired.", []),
       "azure death claim must fire")
    ck(offenders("aiplatform is disabled on that project.", []),
       "disabled claim must fire")
    ck(offenders("Vertex models are not granted for this account.", []),
       "not-granted claim must fire")
    ck(offenders("The apollo api is dead.", []), "api death must fire")

    # ...and must NOT fire once the thing was actually tried
    ck(not offenders("Azure image generation is dead, the credit expired.",
                     ['{"command":"curl https://azure.../images/generations"}']),
       "must not fire when a tool call exercised azure")
    # ...nor when honestly hedged
    ck(not offenders("Azure may be dead but I could not verify it.", []),
       "hedged claim must not fire")
    # ...nor on ordinary negative facts
    ck(not offenders("The file is gone and the row is not there.", []),
       "ordinary negative fact must not fire")
    ck(not offenders("Nothing else writes to it.", []), "generic subject must not fire")
    ck(not offenders("The test is broken and I fixed it.", []),
       "'test' is too generic to be a capability verdict")

    # --- DEAD-BRANCH ARMS 2026-08-29. CLAIM2 and HEDGED could each be corrupted
    # to never match and this self-test stayed green, so neither was enforcing.
    ck(offenders("vertex_image.py cannot generate images on this box.", []),
       "CLAIM2: the verb-second 'X cannot <verb>' form must fire")
    ck(not offenders("I have not tested it, but vertex_image.py cannot generate images.", []),
       "HEDGED: a claim carrying its own hedge is allowed")
    # --- BLAME ARM 2026-09-04. The gate was armed all session and matched nothing
    # while the owner was told twice that LinkedIn was refusing his account. These
    # are the sentences that actually shipped, kept verbatim so the arm cannot rot.
    ck(offenders("LinkedIn is refusing this account's outbound invites.", []),
       "BLAME: 'X is refusing <us>' is a capability verdict and must fire")
    # EVIDENTIAL ARM 2026-09-04. The BLAME arm added the same day blocked its own
    # author's honest negative result, which is the opposite of what this gate is for.
    ck(not offenders("The within-month contrast does not support the hook doing the "
                     "work.", []),
       "a measurement reporting a null result is not a capability claim")
    ck(not offenders("The data does not support that conclusion.", []),
       "evidential 'does not support' must not fire")
    ck(offenders("The API does not support streaming.", []),
       "the capability sense of 'does not support' still fires")
    ck(offenders("The invite endpoint is rejecting our calls.", []),
       "BLAME: rejecting must fire")
    ck(offenders("Hunter is throttling the lane.", []), "BLAME: throttling must fire")
    # The sentence that SHOULD have been written instead: it quotes what the service
    # said rather than diagnosing it, so it must stay allowed or the gate teaches
    # people to hide the evidence.
    ck(not offenders("LinkedIn said: you have reached the weekly limit for "
                     "connection invitations.", []),
       "quoting the service's own words is evidence, not a verdict")
    ck(not offenders("He is ignoring my last message.", []),
       "a person is not a capability")
    print("SELF-TEST PASS" if not bad else f"SELF-TEST FAILED ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
