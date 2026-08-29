#!$HOME/.venvs/agent-libs/bin/python
# person-claim-balance.py: Stop. Refuse a one-directional reading of a person.
#
# THE INCIDENT, 2026-08-27, and it is the worst thing in this configuration's
# history. A session analysed the owner's relationships from message logs and
# generated thirteen claims about his character: relationship duration, zero
# apologies, no brokerage, capped intensity, never the student, disclosure
# collapse, a compliment gap, five deficits, a thread ending, who went first, an
# outstanding promise, thirty-four hours, a neighbour reading.
#
# ALL THIRTEEN WERE RETRACTED. Every one was a DEFICIT claim. Every one died in
# his favour. Zero died the other way. He supplied the counter-evidence himself,
# usually inside one message, without the corpus in front of him.
#
# Random error does not produce a 13-0 split. A generator whose errors are 100%
# one-directional is not erring, it is expressing a prior: it asked a bounded
# corpus what was MISSING and never what was PRESENT, and every absence turned
# out to be an artifact of the source's coverage.
#
# WHY A HOOK AND NOT A NOTE. The note already exists. `feedback-absence-from-
# incomplete-source.md` documents four instances of this in a single week, and
# records that instance 4 was committed INSIDE the document describing instances
# 1 to 3. Its own words: "Writing the lesson down did not install it." This was
# the fifth, and the subject was a person rather than a file.
#
# THE CHECK: when a report makes several evaluative claims about a PERSON, the
# balance is the signal. Deficit-only is not a finding about them, it is a
# finding about the question that was asked. An absence claim also has to state
# the source's COVERAGE, because a partial corpus answers every question and a
# short answer is indistinguishable from a true negative.

import json
import os
import re
import sys

STATE = os.path.expanduser("~/.claude/state")

# A claim ABOUT A PERSON: second person, or a capitalised given name as subject.
# CASE TRAP: every pattern here uses re.I, which makes [A-Z] match lowercase
# too, so the "capitalised name" branch silently matched ANY word. That is how
# "never apologised" scored as a CREDIT in an all-deficit text and made a
# six-nil report look balanced. Negators are excluded explicitly rather than
# relying on capitalisation that re.I throws away.
NEG = r"(?:not|never|no|nothing|hardly|rarely|seldom|without|failed|refused)"
SUBJ = rf"(?!{NEG}\b)(?:you|your|he|she|his|her|they|their|[A-Za-z][a-z]{{2,14}}(?:'s)?)"

DEFICIT = re.compile(
    rf"\b{SUBJ}\s+(?:never|rarely|hardly|seldom|did not|didn't|does not|doesn't|"
    rf"has not|hasn't|have not|haven't|failed to|refused to|avoided|withheld|"
    rf"lacks?|lacked|is missing|are missing|shows? no|showed no|offers? no|"
    rf"gave no|made no|zero\b)", re.I)
DEFICIT2 = re.compile(
    rf"\b(?:no|zero|absence of|lack of|gap in|deficit|shortfall|asymmetry|"
    rf"imbalance|one-sided|unreciprocated)\s+\w{{0,12}}\s*(?:from|by|in|on)\s+{SUBJ}\b", re.I)

# NEGATION MUST NOT COUNT AS CREDIT. The first version matched "You did" inside
# "You did NOT broker introductions" and scored it positive, so replaying the
# real incident produced a balanced verdict for a text that was six-nil against
# him. A credit counter that counts deficits is worse than no counter: it makes
# a one-directional report look even-handed.
CREDIT = re.compile(
    rf"\b{SUBJ}\s+(?!not\b|never\b|no\b|nothing\b)(?:did|does|has|have|showed|"
    rf"shows|offered|offers|gave|gives|made|makes|initiated|reciprocated|"
    rf"apologised|apologized|supported|defended|helped|went first|reached out|"
    rf"followed up|was right|were right)(?!n't|\s+not\b)",
    re.I)

# An absence asserted without saying how complete the source is.
ABSENCE = re.compile(
    r"\b(?:never (?:said|sent|wrote|apologi[sz]ed|mentioned|offered|asked)|"
    r"no record of|nothing in the (?:log|thread|export|corpus)|"
    r"does not appear|no evidence (?:of|that)|zero instances)\b", re.I)
COVERAGE = re.compile(
    r"\b(?:coverage|complete through|export ends|cutoff|only covers|"
    r"partial|bounded|messages? back to|from \d{4}-\d{2}-\d{2}|"
    r"coverage unverified|not found in)\b", re.I)

MIN_DEFICITS = 3


def analyse(text):
    d = len(DEFICIT.findall(text)) + len(DEFICIT2.findall(text))
    c = len(CREDIT.findall(text))
    absent = bool(ABSENCE.search(text))
    covered = bool(COVERAGE.search(text))
    problems = []
    # RATIO, not a hard zero. The real incident scored 5 deficits against 1
    # stray credit, and a `c == 0` test let it through: one incidental positive
    # sentence is not balance, and requiring literal zero is a gate that the
    # worst case walks past. Thirteen-to-nothing was the shape; four-to-one is
    # the same generator with a rounding error.
    if d >= MIN_DEFICITS and c <= d // 3:
        problems.append(
            f"{d} deficit claims about a person against {c} in the other direction. "
            "A 13-0 split is what produced the worst incident here; random error "
            "does not do that. Ask what is PRESENT with the same effort, or say "
            "plainly that you only looked for what was missing.")
    if absent and not covered:
        problems.append(
            "an absence is asserted with no statement of the source's COVERAGE. "
            "A partial corpus answers every question, and a short answer is "
            "indistinguishable from a true negative. State coverage, or write "
            "'not found in <source>, coverage unverified'.")
    return problems


def last_text(tp):
    try:
        with open(tp, errors="ignore") as fh:
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


def main():
    try:
        p = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if p.get("stop_hook_active"):
        sys.exit(0)
    tp = p.get("transcript_path")
    if not tp or not os.path.exists(tp):
        sys.exit(0)
    text = last_text(tp)
    if len(text) < 200:
        sys.exit(0)
    probs = analyse(text)
    if not probs:
        sys.exit(0)
    sid = (p.get("session_id") or "x")[:36]
    stamp = os.path.join(STATE, f"pcb-{sid}")
    try:
        n = int(open(stamp).read().strip() or 0)
    except Exception:
        n = 0
    if n >= 1:
        sys.exit(0)
    try:
        os.makedirs(STATE, exist_ok=True)
        open(stamp, "w").write(str(n + 1))
    except Exception:
        pass
    listed = "\n".join(f"  - {x}" for x in probs)
    print(json.dumps({"decision": "block", "reason":
        f"ONE-DIRECTIONAL READING OF A PERSON:\n{listed}\n\n"
        "Thirteen character claims were generated this way and all thirteen were "
        "retracted, every one in his favour. He supplied the counter-evidence "
        "himself, from memory, without the corpus. Before this goes out: run the "
        "symmetric query, state the coverage, and drop any claim that only exists "
        "because the source stops early."}))
    sys.exit(0)


def _self_test():
    bad = 0
    def ck(c, m):
        nonlocal bad
        if not c:
            bad += 1
            print(f"FAIL {m}")

    oneway = ("You never apologised in the thread. You did not go first. "
              "You showed no reciprocity. There is no record of an offer.")
    ck(analyse(oneway), "an all-deficit reading of a person must fire")

    # The two rules are independent and the first draft of this test conflated
    # them: the "balanced" text below still asserts an absence with no coverage,
    # so it SHOULD trip the coverage rule. Assert each separately or the test
    # teaches the wrong thing.
    balanced = ("You never apologised in that thread. You did not go first there. "
                "You showed no reciprocity in August. You defended him in July, "
                "you reached out twice, and you gave him the introduction.")
    ck(not [x for x in analyse(balanced) if "deficit claims" in x],
       "a BALANCED reading must not trip the one-directional rule")
    ck([x for x in analyse(balanced) if "COVERAGE" in x],
       "but an uncovered absence in it must still trip the coverage rule")

    covered = ("You never apologised in the export, which only covers messages "
               "back to 2026-08-04, so coverage is partial.")
    ck(not [x for x in analyse(covered) if "COVERAGE" in x],
       "an absence WITH coverage stated must not fire on the coverage rule")

    ck(not analyse("The build failed. The test did not run. The hook does not fire."),
       "faults in SYSTEMS are not claims about a person")
    ck(not analyse("short"), "short text ignored")

    # --- DEAD-BRANCH ARMS 2026-08-29. DEFICIT and DEFICIT2 are summed, so either
    # could be corrupted to never match and the other kept the count above the
    # threshold. One arm per branch, each unreachable by the other.
    ck(analyse("You never replied to me. You did not call back. "
               "You have not written since, and I am recording that."),
       "DEFICIT: subject-verb absences alone must reach the threshold")
    # NO REAL NAMES IN A FIXTURE. This arm first read "no reply from <a real
    # first name>", which passed here and FAILED in the public build: the
    # publication scrubber redacts names, and the redacted token no longer
    # satisfied the subject pattern, so the shipped copy carried a red test.
    # A fixture has to survive scrubbing, which means pronouns, not people.
    ck(analyse("There was no reply from him. Absence of updates from him all week. "
               "Lack of contact from him after that, on the record."),
       "DEFICIT2: nominalised absences alone must reach the threshold")
    print("SELF-TEST PASS" if not bad else f"SELF-TEST FAILED ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
