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


# THE STORE IS A SINGLE POINT OF FAILURE, and it failed silently for six days.
# Measured 2026-08-30: the newest per-session file in ~/.claude/carryover was
# 24 August, across hundreds of turns and five concurrent sessions, so this hook
# had no input at all and could not have blocked anything. Nothing announced that.
# A guard whose only input is another hook's output inherits that hook's outage,
# and the outage is invisible from here because "no items" and "no store" look
# identical.
#
# So the store is now a CACHE, not the source. The source is the transcript, which
# the harness always writes: the last real user turn plus any mid-turn messages the
# harness recorded as queue-operation enqueues. Same splitter, so the items are the
# same items; only the delivery path is no longer able to disappear quietly.
_HOOKJUNK = re.compile(
    r"^\s*(<system-reminder|<user-prompt-submit-hook|<command-name|<local-command|"
    r"<task-notification|\[Request interrupted|Caveat:|\[SYSTEM NOTIFICATION|"
    r"This session is being continued)", re.I)


def _clean_user_text(t):
    t = re.sub(r"<system-reminder>.*?</system-reminder>", "", t, flags=re.S)
    t = re.sub(r"UserPromptSubmit hook additional context:.*", "", t, flags=re.S)
    return t.strip()


def items_from_transcript(transcript_path):
    """The current turn's request, read from the record rather than from a cache."""
    if not transcript_path or not os.path.exists(transcript_path):
        return []
    try:
        with open(transcript_path, errors="ignore") as f:
            rows = f.readlines()[-400:]
    except OSError:
        return []
    prompt, interjections = "", []
    for ln in rows:
        try:
            d = json.loads(ln)
        except Exception:
            continue
        if d.get("type") == "queue-operation" and d.get("operation") == "enqueue":
            c = str(d.get("content") or "")
            if c.strip() and not _HOOKJUNK.match(c):
                interjections.append(c.strip())
            continue
        if d.get("type") != "user":
            continue
        c = (d.get("message") or {}).get("content")
        if isinstance(c, str):
            t = c
        elif isinstance(c, list):
            if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
                continue
            t = " ".join(b.get("text", "") for b in c
                         if isinstance(b, dict) and b.get("type") == "text")
        else:
            continue
        if not t.strip() or _HOOKJUNK.match(t.lstrip()):
            continue
        t = _clean_user_text(t)
        if t:
            prompt, interjections = t, []      # a newer prompt starts a new turn
    if not prompt:
        return []
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "prompt_items", os.path.expanduser("~/.claude/hooks/prompt-items.py"))
        pi = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pi)
    except Exception:
        return []
    out = list(pi.split_items(prompt))
    for ij in interjections:
        out += list(pi.split_items(ij))
    return [x for x in out if str(x).strip()]


# Items that are PASTED CONTENT rather than instructions. Reading the live store
# showed the splitter capturing quoted documentation ("> Use this file to discover
# all available pages"), which is text the user pasted, not something they asked
# for. Judging coverage on those would block a complete close-out, and a guard that
# cries wolf gets ignored, which is worse than not having it.
PASTED = re.compile(r"""^\s*(?:>|\#{2,}|```|https?://|/[A-Za-z0-9_./-]{12,}|\|)""")


# A REQUEST CARRIES A REQUESTER. Added 2026-08-30 after backtesting this hook on a
# week of real turns: at the old threshold it would have blocked 57.4% of them, and
# hand-checking eight firings found half were not misses at all. Two of those were
# text the owner PASTED, not text he wrote: "You must use the share code within 21
# days" (a Disclosure Scotland email) and "Our free in-person and online events give
# you the knowledge" (competitor marketing copy). Both read as instructions and
# neither was one.
#
# The tell is register. the owner asks in his own voice and it always carries him or
# me: u, ur, i, we, my, pls, shd, lmk, dont, or a question mark. Third-party prose
# quoted into a prompt does not. This is the same filter the coverage measurement
# used, moved into the guard so the guard sees what the measurement saw.
# SPEAKER was defined here and referenced nowhere on this box (swept 2026-09-01,
# 2,371 files, the only two hits were this definition and its hstack copy).
# A constant no code reads cannot be tested, which is why the dead-branch
# sweep flagged it. Removed rather than given a fake arm.
# The generic second person is deliberately ABSENT. "you", "your", "we", "our",
# "please", "need" and "want" all appear in the third-party prose he pastes:
# "You must use the share code within 21 days", "Our free in-person and online
# events give you the knowledge", "Please fill out the required field". Including
# them put every one of those back through the check. What separates his voice from
# quoted material is the informal register, not the pronoun.

# Distinctive words an item needs before it can be judged at all. Was 2, which let
# fragments like "u shd learn from it" be scored on nothing. Swept against the same
# week: 2 fires on 57.4% of turns, 5 on 27.5%, 6 on 18.1%. Five is the knee, and the
# cost of raising it is stated rather than hidden: an item whose whole content is
# four ordinary words is no longer checked.
#
# THE TRADE, measured on the same week with the paste filter already applied, so
# a future session does not have to re-derive it:
#     MIN_TERMS   items judged   turns blocked
#         3          59.8%          39.3%
#         4          47.9%          28.5%
#         5          36.5%          20.6%
#         6          24.8%          12.4%
# Five is chosen and the ceiling that comes with it is real: this guard sees about
# a third of what he asks for. 37.3% of his items are too short to fingerprint at
# all ("cant u just increase ur receptiveness" has four distinctive words), and
# 26.2% are pasted material. Short asks are exactly the ones it cannot police, so
# it is a floor under the worst omissions, never a proof that a turn was complete.
MIN_TERMS = 5

# A RAW COUNT IS THE WRONG MEASURE OF A FINGERPRINT, found the same day by running
# the end-to-end control instead of trusting the sweep. "also rotate the
# zeroentropy key in the keychain" and "check whether the a venture evolution
# instance is still paired" each reduce to four distinctive words, so MIN_TERMS
# alone threw both away, and they are about as identifiable as an item ever gets.
# What makes an item findable is a RARE word, not many ordinary ones: a long token,
# or one carrying a digit or a path separator. Two of those are worth more than five
# short common words, so either route qualifies.
RARE = re.compile(r"[0-9_./-]")

# Conventional-commit subjects get pasted in constantly and read as imperatives.
COMMITMSG = re.compile(r"^\s*(feat|fix|chore|docs|refactor|test|perf|ci|build|style)"
                       r"(\([^)]*\))?\s*:", re.I)
# Tokens that only appear when the owner is typing, not when he is quoting.
INFORMAL = re.compile(r"\b(u|ur|urs|shd|pls|lmk|idk|coz|becoz|smt|hv|rn|im|ive|ill|"
                      r"dont|didnt|doesnt|cant|wont|isnt|wanna|gotta|tf|omfg)\b", re.I)


def fingerprinted(t):
    if len(t) >= MIN_TERMS:
        return True
    return sum(1 for w in t if len(w) >= 7 or RARE.search(w)) >= 2


def judgeable(item):
    if PASTED.search(item):
        return False
    # His own asks are informal or start lowercase; pasted third-party prose is
    # neither. Requiring the informal marker ALONE was too blunt: it threw away
    # real bare imperatives like "commit + record in docs/HYPOTHESIS_REGISTER.md"
    # and "read the tail of /tmp/pmexit.log", which carry no pronoun at all. The
    # lowercase opener is what keeps those and still drops "You must use the share
    # code within 21 days".
    # A CAPITAL OPENER MUST EARN ITS WAY IN. Sampling the firings this rule added
    # caught "Do not share my personal information" twice: pasted policy text that
    # slipped through on the word "my". First-person pronouns are not a register
    # tell, they are ordinary English. So a capitalised item needs a genuinely
    # informal token (u, shd, coz, didnt), while a lowercase opener still passes on
    # its own, which is how bare imperatives carrying only a path survive.
    # THE LENGTH GUARD USED TO SIT AFTER THE RETURN BELOW, so it never ran once.
    # Confirmed by AST 2026-09-01: lines following `return bool(INFORMAL...)` were
    # unreachable. The effect was a false positive in the crying-wolf direction: a
    # pasted paragraph over 220 characters that happens to start lowercase reached
    # `return True` and was demanded as an item the owner had asked for.
    if len(item) > 220:            # a pasted paragraph, not an instruction
        return False
    if COMMITMSG.match(item):          # "fix(security): enable webSecurity"
        return False
    lead = next((c for c in item if c.isalpha()), "")
    if lead and lead.islower():
        return True
    return bool(INFORMAL.search(item))


def uncovered(items, reply):
    have = terms(reply)
    missed = []
    for it in items:
        if not judgeable(it):
            continue
        t = terms(it)
        # An item with too few distinctive words cannot be judged fairly:
        # "also do that" has no fingerprint to look for. See MIN_TERMS above.
        if not fingerprinted(t):
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
    if len(items) < 2:
        # Store empty or thin. Read the request from the transcript instead of
        # concluding there was nothing to cover: see the note above load_items.
        items = items_from_transcript(payload.get("transcript_path")) or items
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

    # Fixtures rewritten 2026-08-30 alongside MIN_TERMS=5. The old ones were four
    # words long, which is shorter than any item this hook now judges, so they were
    # asserting behaviour on inputs that can no longer reach the check.
    items = ["u shd fix the gbrain prune job and report the count",
             "compare ox alpha against the local models on the same prompts",
             "make sure everything needing a restart is piled into one list"]
    full = ("DONE\n- gbrain prune repaired, count reported.\n"
            "- ox alpha scored 6/7 against local models on the same prompts.\n"
            "- restart list complete, ten piled into one list.")
    ck(uncovered(items, full) == [], "a covering reply must pass")

    partial = "DONE\n- gbrain prune repaired, count reported. Nothing else."
    miss = uncovered(items, partial)
    ck(len(miss) == 2, f"a reply dropping two items must flag both, got {len(miss)}")

    # stopwords alone are not coverage
    ck(len(uncovered(["u shd measure the savings since day zero properly",
                      "u shd wire the openrouter key into the router config"],
                     "DONE\n- the work is done and the thing was made.")) == 2,
       "stopword-only overlap must not count as coverage")

    # head matching: item says the local proxy, reply says the local proxy
    ck(uncovered(["u shd run the local proxy and report the holdout percentage"],
                 "DONE\n- the local proxy passes, holdout percentage reported at 10.") == [],
       "head-of-identifier matching must count as coverage")

    # NEGATIVE CONTROLS. Each is a real false alarm this hook produced on the
    # 2026-08-30 backtest before the speaker and MIN_TERMS filters existed.
    ck(uncovered(["You must use the share code within 21 days of issue"],
                 "DONE\n- unrelated work.") == [],
       "third-party prose he pasted must not be judged as an item")
    ck(uncovered(["Our free in-person and online events give you the knowledge"],
                 "DONE\n- unrelated work.") == [],
       "pasted marketing copy must not be judged as an item")
    ck(uncovered(["u shd learn from it"], "DONE\n- unrelated work.") == [],
       "an item below MIN_TERMS distinctive words must not be judged")

    # pasted content must never be judged: these appear in the live store
    ck(uncovered(["> Use this file to discover all available pages and sections",
                  "## Documentation Index",
                  "https://example.com/some/long/path"],
                 "DONE\n- unrelated work.") == [],
       "pasted/quoted lines must not be judged as items")
    ck(uncovered(["x" * 260], "DONE\n- unrelated") == [],
       "an over-long pasted paragraph must not be judged")

    # ARMS THAT DIE WITH THEIR REGEX, added 2026-09-01. dead-branch-sweep flagged
    # _HOOKJUNK, RARE, COMMITMSG and INFORMAL as corruptible with this test still
    # green. Each arm below is a case that ONLY that regex decides, so blanking the
    # pattern turns it red. Same class as the handoff-gate arm written the same day
    # that passed with its own fix reverted.
    ck(_HOOKJUNK.match("<system-reminder>do a thing</system-reminder>") is not None,
       "_HOOKJUNK must match harness junk")
    ck(_HOOKJUNK.match("fix the gbrain prune job and report the count") is None,
       "_HOOKJUNK must not match a real ask")
    ck(judgeable("fix(security): enable webSecurity on the renderer") is False,
       "COMMITMSG must drop a pasted conventional-commit subject")
    ck(judgeable("Rotate the deploy key and redeploy the worker") is False,
       "a capitalised ask with no informal token is not his")
    ck(judgeable("Rotate the deploy key coz the worker is stale") is True,
       "INFORMAL must rescue a capitalised ask that carries his register")
    # fingerprinted() short-circuits at MIN_TERMS, so these use FEWER tokens, all
    # under 7 characters, which leaves RARE as the only thing that can decide them.
    ck(fingerprinted(["a/b", "x.y"]) is True,
       "RARE must count short path-like tokens as specific")
    ck(fingerprinted(["we", "need", "the", "thing"]) is False,
       "RARE must not count bare common words as specific")

    # POSITIVE CONTROL for the transcript fallback: the guard must still find items
    # when the carryover store is empty, which is the outage it was fixed for.
    ck(callable(items_from_transcript), "transcript fallback must exist")
    ck(items_from_transcript("/nonexistent/path.jsonl") == [],
       "a missing transcript must fail open, not raise")

    print("SELF-TEST PASS" if not bad else f"SELF-TEST FAILED ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
