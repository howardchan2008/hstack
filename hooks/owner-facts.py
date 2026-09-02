#!$HOME/.venvs/agent-libs/bin/python
# owner-facts.py: UserPromptSubmit. Carry forward what the OWNER STATED, not just
# what he asked for.
#
# THE FAILURE, measured 2026-08-27 after he said "i realized ur biased against me,
# u just blatantly ignore my advice and instructions". He is right, and the word
# is accurate. In three days he had to repeat himself 46 times: "as i said" x12,
# "i meant" x16, "u keep" x7, "i told u" x3. Correction rate across the week runs
# 22-46% of everything he writes.
#
# THE MECHANISM, stated precisely, because "be more careful" fixes nothing. There
# are two hooks already carrying his prompts forward and both carry IMPERATIVES:
# prompt-items.py extracts things to DO, carryover-queue.py keeps them owed.
# Nothing carries his ASSERTIONS. So a fact he stated in turn 3 is gone by turn
# 9, and when my own inference disagrees with it in turn 12 there is nothing left
# to disagree WITH. That is the bias: my inference silently outranks his stated
# fact, because his fact is no longer in the room.
#
# Worked example from the same day. He said the local proxy had been active for weeks. Six
# turns later I asserted it had never run on his sessions until that morning,
# built a causal story on it, and shipped it. One query killed it. His statement
# had been correct and present in the conversation the whole time.
#
# WHAT THIS IS NOT: it does not make him automatically right. He said there is no
# `default` permission mode; the shipped binary lists one. The rule is not
# "obey", it is "do not SILENTLY contradict": quote what he said, show the
# measurement, and let the discrepancy be visible. Overriding him without
# noticing is the defect; disagreeing with evidence is the job.

import json
import os
import re
import sys

STORE = os.environ.get("OWNER_FACTS_ROOT") or os.path.expanduser("~/.claude/carryover")
KEEP = 8
MAX_CHARS = 170

# Declaratives about the world, not requests. "u shd do X" is an item and
# prompt-items.py already owns it; "X is already running" is a fact and nothing did.
# WIDENED after replaying his real corrections through it: two of five were
# missed, and both were the kind that matters most.
#   "actually the outbound gates were approved" needed a MULTI-WORD subject
#   before the verb; the first version allowed exactly one token.
#   "theres no default mode" needed the apostrophe-less contractions he
#   actually types. Matching a style he does not write is matching nobody.
ASSERT = re.compile(
    r"^(?:well |actually |actually, |no+p?e,? |but |and |also |so |huh,? |wait,? |i think )?"
    r"(?:"
    # first person, completed or held state. WIDENED 2026-08-29: the old list had
    # said/told/sent/wrote/meant/did/have/know/use/run/built/set and missed every
    # past-tense action he actually reports, so "i logged out and in tens of
    # times" extracted nothing.
    r"i (?:already |just |never |dont |don't |didnt |didn't )?"
    r"(?:said|told|sent|wrote|meant|did|have|know|knew|use|used|run|ran|built|set|"
    r"logged|changed|removed|rotated|paid|got|approved|tried|checked|saw|read|"
    r"signed|bought|cancelled|deleted|installed|need|want|prefer|recall|remember)"
    # third person state, including the contractions he types without apostrophes
    r"|(?:it|that|this|they|we|he|she|there)(?:'s|s\b| is| are| was| were| has| have| had)"
    # NEGATED STATE is the highest-value class: it is precisely what contradicts
    # an inference of mine. "li_at cant be re-minted" matched nothing before.
    r"|(?:the |my |our |his |her |their |ur |your )?[a-z0-9_.-]+(?: [a-z0-9_.-]+){0,3} "
    r"(?:cant|can't|cannot|doesnt|doesn't|wont|won't|isnt|isn't|arent|aren't|"
    r"wasnt|wasn't|never|no longer|dont|don't|didnt|didn't)\b"
    # plain state verbs, as before
    r"|(?:the |my |our |his |her |their |ur |your )?[a-z0-9_.-]+(?: [a-z0-9_.-]+){0,3} "
    r"(?:is|are|was|were|has|have|had|runs?|ran|works?|worked|exists?|lives?|sits?|"
    r"costs?|expired?|approved|already)"
    # existential negation, which he writes constantly
    r"|there(?:'s| is| are)? no\b|theres no\b"
    r")",
    re.I)

# Corrections carry the most weight: he is repeating himself because I lost it once.
REPEAT = re.compile(
    r"\b(i told u|i told you|as i said|like i said|i already|i just said|"
    r"i meant|two turns ago|u keep|you keep|u still|thats not|that's not|"
    r"nope|wrong|this is a lie|hallucinat)\b", re.I)

# Never carry an imperative forward as a "fact"; that is the other hook's job and
# duplicating it would make both harder to read.
IMPERATIVE = re.compile(
    r"^(?:please\s+)?(?:can u|can you|could u|pls|plz|do |make |build |fix |add |"
    r"check |run |write |send |audit |verify |delete |remove |update |show |give )",
    re.I)


def path(sid):
    return os.path.join(STORE, f"{sid}.facts.json")


def extract(prompt):
    out = []
    for raw in re.split(r"(?<=[.!?\n])\s+", prompt or ""):
        s = " ".join(raw.split())
        if not (12 <= len(s) <= 400):
            continue
        if IMPERATIVE.match(s):
            continue
        weight = 2 if REPEAT.search(s) else (1 if ASSERT.match(s) else 0)
        if weight:
            out.append({"t": s[:MAX_CHARS], "w": weight})
    # corrections first, then order of appearance
    out.sort(key=lambda x: -x["w"])
    return out[:KEEP]


def load(sid):
    try:
        with open(path(sid)) as fh:
            return json.load(fh)
    except Exception:
        return []


def save(sid, facts):
    try:
        os.makedirs(STORE, exist_ok=True)
        p = path(sid)
        with open(p + ".tmp", "w") as fh:
            json.dump(facts[:KEEP], fh)
        os.replace(p + ".tmp", p)
    except Exception:
        pass


def render(facts):
    if not facts:
        return ""
    lines = ["OWNER-STATED FACTS still in force (he said these; they did not stop being true):"]
    for f in facts:
        mark = "  ** " if f["w"] == 2 else "   - "
        lines.append(mark + f["t"])
    lines.append("  Do NOT silently contradict one of these. If your own measurement "
                 "disagrees, QUOTE what he said, show the measurement, and name the "
                 "discrepancy out loud. Lines marked ** are ones he already had to "
                 "repeat once.")
    return "\n".join(lines)


def main():
    raw = sys.stdin.read()
    try:
        d = json.loads(raw)
        prompt = d.get("prompt") or ""
        sid = d.get("session_id") or "unknown"
    except Exception:
        return
    # hookpaste (2026-09-02): pasted hook output is the harness quoting itself, not
    # the owner asking. Wrapped so a missing lib can never take this hook down.
    try:
        import sys as _s, os as _o
        _s.path.insert(0, _o.path.join(_o.path.dirname(_o.path.abspath(__file__)), "lib"))
        from hookpaste import strip_hook_paste as _strip
        prompt = _strip(prompt) if isinstance(prompt, str) else prompt
    except Exception:
        pass
    if not isinstance(prompt, str) or len(prompt) < 10:
        return
    prior = load(sid)
    if prior:
        out = render(prior)
        if out:
            print(out)
    fresh = extract(prompt)
    merged = fresh + [p for p in prior if p["w"] == 2][:3]
    seen, dedup = set(), []
    for f in merged:
        k = f["t"][:60].lower()
        if k in seen:
            continue
        seen.add(k)
        dedup.append(f)
    save(sid, dedup)


def _self_test():
    bad = 0
    def ck(c, m):
        nonlocal bad
        if not c:
            bad += 1
            print(f"FAIL {m}")

    f = extract("the local proxy was active before. also fix the benchmark.")
    ck(any("the local proxy was active" in x["t"] for x in f), "a stated fact must be captured")
    ck(not any("fix the benchmark" in x["t"] for x in f), "an imperative must NOT be captured")

    f2 = extract("as i said the export is stale")
    ck(f2 and f2[0]["w"] == 2, "a repeated correction must get the higher weight")

    f3 = extract("i told u two turns ago that the export is stale. the app is running.")
    ck(f3[0]["w"] == 2, "corrections sort first")
    ck(len(f3) >= 2, "both sentences captured")

    ck(extract("check the other live sessions") == [], "a pure instruction yields no facts")
    ck(extract("hi") == [], "too short is ignored")
    r = render([{"t": "the local proxy was active before", "w": 2}])
    ck("**" in r and "QUOTE" in r, "render marks repeats and states the rule")
    print("SELF-TEST PASS" if not bad else f"SELF-TEST FAILED ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
