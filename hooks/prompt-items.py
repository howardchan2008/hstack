#!/usr/bin/env python3
# prompt-items.py: UserPromptSubmit. Re-injects the ITEMS of the PREVIOUS prompt.
#
# The failure this fixes, the owner 2026-08-20, verbatim: "u keep neglecting these items,
# this is smt that a hook requires configuration for, since u ignore all my previous
# prompts when i put a new one". Same day, earlier: "omfg, u ignored all the other parts
# of my instruction" after a four-source instruction (Evolution, Gmail, Drive, transcripts)
# was answered using one source.
#
# WHY carryover-queue.py DOES NOT COVER THIS. That hook fires on two signals: open
# TaskCreate tasks, and an interrupt marker in the transcript. the owner's actual failure
# mode is neither. He sends ONE prompt carrying four imperatives, the model answers the
# first, and there is no interrupt and no task file, so nothing fires and the other three
# vanish silently. The hole is exactly where the complaint lives. TaskCreate is also not
# always available (the tool disconnected mid-session on 2026-08-20), so signal A can be
# structurally empty for a whole session.
#
# WHAT THIS DOES. Splits every incoming prompt into imperative items, persists them, and
# on the NEXT prompt injects the previous prompt's items back into context. The model
# cannot then claim not to know what was asked; it can only choose to skip, which is a
# visible act rather than an invisible one. Prose alone was measured at ~40% failure at
# changing behaviour (memory: "named, not fixed" is not an accepted close-out), so this
# carries the actual item text rather than a reminder to go look.
#
# Fails open, always. A reminder is never worth blocking a prompt over.

import json
import os
import re
import sys

STORE = os.environ.get("PROMPT_ITEMS_ROOT") or os.path.expanduser("~/.claude/carryover")
MAX_ITEMS = 12
MAX_ITEM_CHARS = 160

# Lines that are harness furniture, not the owner asking for something.
NOISE = re.compile(
    r"^\s*(<system-reminder|Caveat:|\[Request interrupted|Stop hook feedback|"
    r"DONE\b|YOUR MOVE\b|===|---|#{1,6}\s)",
    re.I,
)

# An item is a clause that asks for something. Imperative verbs the owner actually uses,
# plus question forms, plus explicit "i want/need".
ASKS = re.compile(
    r"\b(gener(ate|ating)|creat(e|ing)|writ(e|ing)|draft|review|check|verify|measure|"
    r"sync|rotate|fix|build|make|give|send|use|read|find|search|assess|analy[sz]e|"
    r"compare|list|add|remove|delete|update|install|run|test|deploy|push|commit|"
    r"handoff|profile|advice|advise|recommend|figure out|look into|go through|"
    r"i want|i need|can u|can you|could u|could you|pls|please|shd|should i|"
    r"how (do|should|can)|what (do|should|is|are)|why|which)\b",
    re.I,
)

# A CORRECTION is an item, and until 2026-08-24 none of them were. Measured against the
# real nine-item prompt of that morning ("remove If you would rather we closed your
# application ... no one has been interviewed ... by the progress i meant ..."), ASKS
# alone found 4 of 9. The five it dropped were every clause that corrects a wrong belief
# rather than ordering new work, which is the half that costs most when it vanishes:
# the model keeps acting on the belief the owner just told it was wrong. ~/CLAUDE.md has
# said "a correction is an item" since 2026-08-11; the splitter never implemented it.
CORRECTS = re.compile(
    r"(\b(no one|nobody|nothing|never|none of)\b|"
    r"\b(isn'?t|aren'?t|wasn'?t|weren'?t|don'?t|dont|do not|doesn'?t|didn'?t|"
    r"can'?t|cannot|won'?t|shouldn'?t|shd ?n'?t|shdnt)\b|"
    r"\b(wrong|incorrect|mistaken|misinterpret\w*|misread|misunderstood|"
    r"i meant|u meant|you meant|actually|instead|rather than|nope|nah|afaik|"
    r"unacceptable|omfg|wtf)\b|"
    r"(?:^|[,;]\s*)no\b|\bno$)",
    re.I,
)

# A negated pleasantry is not a correction. Negative-controlled the clause above against
# chit-chat and two got through: "no worries" and "i dont think that was needed but ok".
# Both are agreement wearing a negation. A false item costs more than a missed one here,
# because noise is what teaches the reader to skip the whole block (see the comment in
# split_items). Only CORRECTS matches are tested against this; an explicit ask stays an
# item whatever tail it carries.
SOFTENED = re.compile(
    r"^(no (worries|problem|rush|biggie|stress|thanks|need)|np|nvm|never mind|"
    r"don'?t worry\w*|no\b[^.]{0,12}\b(worries|problem))\b|"
    r"\b(but|though|anyway)\s+(ok|okay|fine|alright|all good|sure|np|no worries)\b[.! ]*$",
    re.I,
)


MARKER = re.compile(r"(?:(?<=^)|(?<=[\s.;:]))(\d{1,2})[.)]?\s+(?=[A-Za-z])")


def split_enumerated(line):
    """Return the clauses of a hand-numbered line, or None if it is not one.

    Requires three or more markers running 1,2,3... in order. Two is too easy to
    hit by accident ("send 2 files to 3 people"), and a run that does not ascend
    from 1 is a quantity, not a list.
    """
    all_hits = [(m.start(), m.end(), int(m.group(1))) for m in MARKER.finditer(line)]
    # Longest run that ascends 1,2,3 with no gaps. A stray number before the list
    # ("send 5 files. 1 do x. 2 do y. 3 do z") must not shift or break the run,
    # which a position-based index check did on the first draft.
    hits, run = [], []
    for h in all_hits:
        run = run + [h] if run and h[2] == run[-1][2] + 1 else ([h] if h[2] == 1 else [])
        if len(run) > len(hits):
            hits = run
    if len(hits) < 3:
        return None
    parts = []
    if hits[0][0] > 0:
        parts.append(line[: hits[0][0]])
    for i, (_, end, _n) in enumerate(hits):
        stop = hits[i + 1][0] if i + 1 < len(hits) else len(line)
        parts.append(line[end:stop])
    return parts


def split_items(prompt):
    """Break a prompt into the things it actually asks for."""
    items = []
    for raw_line in prompt.splitlines():
        line = raw_line.strip()
        if not line or NOISE.match(line):
            continue
        # An enumeration the owner typed himself beats any guess this splitter makes.
        # Added 2026-08-24 after watching this hook shred the one prompt it was
        # built from: it carried "1 remove the line. 2 nobody interviewed. ..."
        # inline, the comma rule below cut across the numbers, and three garbage
        # fragments came back with two real items lost. When a line holds three or
        # more ascending inline markers, split on THOSE and skip the guessing.
        parts = split_enumerated(line)
        if parts is None:
            # the owner writes long run-ons joined by commas and "and". Split on the joins
            # that reliably separate two asks, not on every comma.
            parts = re.split(r"(?:,\s+(?:and\s+)?(?=\w)|;\s*|\.\s+(?=[A-Za-z])|\band then\b)", line)
        for p in parts:
            p = p.strip(" ,.;-")
            if len(p) < 8:
                continue
            if not ASKS.search(p):
                if not CORRECTS.search(p) or SOFTENED.search(p):
                    continue
            items.append(p[:MAX_ITEM_CHARS])
            if len(items) >= MAX_ITEMS:
                return items
    return items


def load(session_id):
    path = os.path.join(STORE, f"{session_id}.json")
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def save(session_id, data):
    try:
        os.makedirs(STORE, exist_ok=True)
        path = os.path.join(STORE, f"{session_id}.json")
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        pass


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return

    session_id = str(payload.get("session_id") or os.environ.get("CLAUDE_SESSION_ID") or "")
    # Reject a malformed id rather than scrubbing it: scrubbing "../../OTHER" yields a
    # real and DIFFERENT session, which would serve another conversation's items here.
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", session_id or ""):
        return
    prompt = str(payload.get("prompt") or "")
    if not prompt.strip():
        return

    state = load(session_id)
    previous = state.get("last") or {}
    prev_items = [i for i in (previous.get("items") or []) if isinstance(i, str)]

    current = split_items(prompt)
    save(session_id, {"last": {"items": current}, "n": int(state.get("n") or 0) + 1})

    if not prev_items:
        # Nothing to carry. Say nothing: a block that fires every turn is noise, and
        # noise is what teaches the reader to skip the whole thing.
        return

    out = [
        "ITEMS FROM the owner'S PREVIOUS PROMPT. A new prompt does not retire these.",
        "Close out against every line. Finished goes in DONE, refused or blocked goes",
        "in YOUR MOVE with the reason. Silent omission is the defect this exists for.",
    ]
    for i, item in enumerate(prev_items, 1):
        out.append(f"  {i}. {item}")
    print("\n".join(out))


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        import tempfile

        fails = []
        root = tempfile.mkdtemp()
        os.environ["PROMPT_ITEMS_ROOT"] = root
        STORE = root

        # 1. A real multi-part the owner prompt must yield several distinct items.
        p = ("read the failing test and tell me why it hangs\n"
     "then fix the timeout and push it\n"
     "also the readme still says twelve hooks, that is wrong")
        got = split_items(p)
        if len(got) < 3:
            fails.append(f"multi-part prompt split into only {len(got)} items: {got}")

        # 2. Harness furniture must never become an item.
        noise = ("<system-reminder>do the thing</system-reminder>\n"
                 "Stop hook feedback: check this\nDONE\nYOUR MOVE")
        if split_items(noise):
            fails.append(f"noise produced items: {split_items(noise)}")

        # 3. Chit-chat with no ask must produce nothing.
        if split_items("ok thanks that looks good"):
            fails.append("non-ask produced items")

        # 4. Traversal id must be refused, not scrubbed.
        if re.fullmatch(r"[A-Za-z0-9_-]{1,64}", "../../other-session"):
            fails.append("traversal session id was accepted")

        # 5. A CORRECTION is an item. This is the real 2026-08-24 prompt, and the
        #    version of this splitter that only looked for asks found 4 of the 9 things
        #    the owner listed back. Every one it dropped was a corrected belief.
        nine = ("remove If you would rather we closed your application, say so and I "
                "will close it today; no one has been interviewed, omfg, why u msging "
                "like u had more x from y than z, and for the money i need to discuss "
                "this with a contact first; reddit has banned apps afaik, the other "
                "alternative i set it up in my own a venture subreddit, using the new "
                "api path do not send the 62, the 8 questions are also important no, by "
                "the progress i meant the current level of correspondence between each "
                "of the tutors and myself")
        got9 = split_items(nine)
        if len(got9) < 8:
            fails.append(f"nine-item prompt split into only {len(got9)}: {got9}")
        if not any("interviewed" in i for i in got9):
            fails.append("dropped the correction 'no one has been interviewed'")

        # 6. A negated pleasantry is agreement, not a correction.
        for soft in ("no worries, that all makes sense to me now",
                     "nice, i dont think that was needed but ok"):
            if split_items(soft):
                fails.append(f"pleasantry produced items: {soft!r}")

        # 7. Round trip: items saved under one prompt come back on the next.
        save("testsess", {"last": {"items": ["rotate ascend pw", "give social advice"]}})
        back = load("testsess").get("last", {}).get("items")
        if back != ["rotate ascend pw", "give social advice"]:
            fails.append(f"round trip lost items: {back}")

        print("FAIL: " + "; ".join(fails) if fails else "PASS: all 7 checks")
        sys.exit(1 if fails else 0)
    main()
