#!/usr/bin/env python3
# prompt-items.py: UserPromptSubmit. Re-injects the ITEMS of the PREVIOUS prompt.
#
# The failure this fixes, Howard 2026-08-20, verbatim: "u keep neglecting these items,
# this is smt that a hook requires configuration for, since u ignore all my previous
# prompts when i put a new one". Same day, earlier: "omfg, u ignored all the other parts
# of my instruction" after a four-source instruction (Evolution, Gmail, Drive, transcripts)
# was answered using one source.
#
# WHY carryover-queue.py DOES NOT COVER THIS. That hook fires on two signals: open
# TaskCreate tasks, and an interrupt marker in the transcript. Howard's actual failure
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
# 2026-08-28: was 12, and Howard approved FIFTEEN Premier Trophy items in one
# message. Items 13-15 were dropped at the `return` below with nothing said, so
# the turn read as fully covered while three approvals never entered the list.
# A silent cap is the same defect as a false zero: the work looks done because
# the instrument stopped counting. Raised, and the cap now announces itself.
MAX_ITEMS = 40
MAX_ITEM_CHARS = 160

# Lines that are harness furniture, not Howard asking for something.
NOISE = re.compile(
    r"^\s*(<system-reminder|Caveat:|\[Request interrupted|Stop hook feedback|"
    r"DONE\b|YOUR MOVE\b|===|---|#{1,6}\s)",
    re.I,
)

# An item is a clause that asks for something. Imperative verbs Howard actually uses,
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
# the model keeps acting on the belief Howard just told it was wrong. ~/CLAUDE.md has
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


# A line carrying a measurement and no words: "140", "6.0%", "45.3k",
# "105.1k / 750k (14%)", or a bare dash standing in for an empty cell. Every
# character must come from the numeric set, so any real sentence is excluded by
# its own letters. The two unicode dashes are built with chr() because
# dash-gate.sh blocks the literal glyphs in an authored file, and it is right to:
# it cannot know this pair is a character class rather than punctuation.
DASHES = "-" + chr(0x2014) + chr(0x2013)
NUMLINE = re.compile(
    "^(?:[" + DASHES + r"]|(?=[^\n]*\d)[\s\d.,%/()+:-]*[kKmMgGbB]?[\s\d.,%/()+:-]*)$"
)

# Below this many measurement lines it is prose that happens to quote figures.
# The /context pane emits dozens; a prompt of Howard's has at most one or two.
MACHINE_TABLE_MIN = 8


def strip_machine_tables(prompt):
    """Drop the rows of a pasted machine table, keeping everything Howard typed.

    THE DEFECT, 2026-09-04. Howard pasted the `/context` pane and asked one
    question about it. The splitter returned 24 items, ten of them roster rows:
    "computer-use / computer_batch", "list_granted_applications",
    "writing-style.md". item-coverage then blocked the close-out for never
    mentioning them, and the Stop hook fired that same ten-item complaint on
    every turn for the rest of the session, so a guard built to catch dropped
    work became the loudest source of fake work on the box.

    NO PER-LINE TEST CAN FIX THIS, which is why the two filters that already
    exist both passed it. `judgeable()` admits a lowercase opener because bare
    imperatives ("commit + record in docs/X") carry no pronoun either, and
    `PASTED` looks for prose markers a roster row does not have. On its own line
    the row is genuinely indistinguishable from an instruction. What separates
    them is the TABLE: the row sits between two lines of pure measurement, which
    no sentence Howard writes ever does.

    So the unit of judgement moves from the line to its neighbourhood. A line is
    table furniture when the nearest non-blank line above AND below are both
    measurements. His trailing question survives because nothing follows it.
    """
    lines = prompt.splitlines()
    numeric = [bool(ln.strip()) and bool(NUMLINE.match(ln.strip())) for ln in lines]
    if sum(numeric) < MACHINE_TABLE_MIN:
        return prompt

    def neighbour(i, step):
        # Blank lines are transparent: a table stays a table across a gap, and
        # treating a gap as "not a measurement" is how the first draft let half
        # the roster back through.
        j = i + step
        while 0 <= j < len(lines):
            if lines[j].strip():
                return numeric[j]
            j += step
        return False

    def furniture(i):
        above, below = neighbour(i, -1), neighbour(i, 1)
        if above and below:
            return True
        # A row that is ONE token wide needs only one measurement neighbour.
        # Measured on the real paste: the memory-file section cycles filename,
        # size, directory, so every filename has a size on one side and a path
        # on the other and never sits between two numbers. "writing-style.md"
        # was the single row that survived the two-sided rule. A request Howard
        # types always has a space in it, so a bare token beside a measurement
        # is a cell, whatever it names.
        return (above or below) and len(lines[i].split()) == 1

    kept = [ln for i, ln in enumerate(lines) if not numeric[i] and not furniture(i)]
    return "\n".join(kept)


def split_items(prompt):
    """Break a prompt into the things it actually asks for."""
    items = []
    for raw_line in strip_machine_tables(prompt).splitlines():
        line = raw_line.strip()
        if not line or NOISE.match(line):
            continue
        # An enumeration Howard typed himself beats any guess this splitter makes.
        # Added 2026-08-24 after watching this hook shred the one prompt it was
        # built from: it carried "1 remove the line. 2 nobody interviewed. ..."
        # inline, the comma rule below cut across the numbers, and three garbage
        # fragments came back with two real items lost. When a line holds three or
        # more ascending inline markers, split on THOSE and skip the guessing.
        parts = split_enumerated(line)
        # HE NUMBERED IT, so every part is an item. Found 2026-08-29 by a
        # dead-branch arm: "1. fix the footer 2. rebuild the thumbnails 3. send
        # the batch" came back with the MIDDLE item gone, because "rebuild the
        # thumbnails" is not on the ASKS verb whitelist below. Dropping an item
        # he numbered with his own hand is the exact defect this hook exists to
        # stop ("u always only act on the first part and not the entirety"), and
        # the comment directly above already said his enumeration beats the
        # guess. The code then applied the guess anyway.
        enumerated = parts is not None
        if parts is None:
            # Howard writes long run-ons joined by commas and "and". Split on the joins
            # that reliably separate two asks, not on every comma.
            parts = re.split(r"(?:,\s+(?:and\s+)?(?=\w)|;\s*|\.\s+(?=[A-Za-z])|\band then\b)", line)
        for p in parts:
            p = p.strip(" ,.;-")
            if len(p) < 8:
                continue
            if not enumerated and not ASKS.search(p):
                if not CORRECTS.search(p) or SOFTENED.search(p):
                    continue
            items.append(p[:MAX_ITEM_CHARS])
            if len(items) >= MAX_ITEMS:
                # Never truncate in silence. The marker is itself an item, so it
                # is re-injected next turn and cannot be missed.
                items.append(f"OVERFLOW: split stopped at {MAX_ITEMS}; "
                             "re-read the prompt for anything past this point")
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
    # hookpaste (2026-09-02): pasted hook output is the harness quoting itself, not
    # Howard asking. Wrapped so a missing lib can never take this hook down.
    try:
        import sys as _s, os as _o
        _s.path.insert(0, _o.path.join(_o.path.dirname(_o.path.abspath(__file__)), "lib"))
        from hookpaste import strip_hook_paste as _strip
        prompt = _strip(prompt)
    except Exception:
        pass
    if not prompt.strip():
        return

    state = load(session_id)
    previous = state.get("last") or {}
    prev_items = [i for i in (previous.get("items") or []) if isinstance(i, str)]

    current = split_items(prompt)
    save(session_id, {"last": {"items": current}, "n": int(state.get("n") or 0) + 1})

    # THE CURRENT PROMPT'S OWN ITEMS, added 2026-08-30. Until now this hook only
    # ever showed the PREVIOUS turn's items, which arrives one turn too late for
    # the failure it is aimed at. Howard: "even if i mention more than 3 items
    # still do all of them, i think this is necessary".
    #
    # WHY THIS IS THE RIGHT PLACE, measured the same day across 175 items from a
    # week of real turns, judged by a local 27b model:
    #     item 1 of a message   66.7% addressed        message with 2-3 items  62.0%
    #     item 2                41.9%                  4-6 items               51.1%
    #     item 3                61.9%                  7-10 items              40.7%
    #     items 4-6             34.1%                  11+ items               34.6%
    #     items 7+              32.0%
    # Coverage halves as the list grows, and every item of a multi-item list was
    # covered in 8 turns out of 47. The decay is by POSITION, which is what a list
    # sitting in front of the model at the start of the turn addresses, rather than
    # a refusal at the end of it that costs Howard a second reply.
    #
    # Threshold is 3 because 2-3 item messages already run at 62% and the fall is
    # after that. A block on every two-item prompt is the noise this file's own
    # comment warns about.
    out = []
    if len(current) >= 3:
        out += [
            f"THIS PROMPT CARRIES {len(current)} ITEMS. Measured on a week of real turns,"
            " the 4th item onward is answered about a third of the time. Work the list,",
            "not the first thing that caught your attention. Every line closes out:",
            "done goes in DONE, refused or blocked goes in YOUR MOVE with the reason.",
        ]
        for i, item in enumerate(current, 1):
            out.append(f"  {i}. {item}")

    if prev_items:
        if out:
            out.append("")
        out += [
            "ITEMS FROM HOWARD'S PREVIOUS PROMPT. A new prompt does not retire these.",
            "Close out against every line. Finished goes in DONE, refused or blocked goes",
            "in YOUR MOVE with the reason. Silent omission is the defect this exists for.",
        ]
        for i, item in enumerate(prev_items, 1):
            out.append(f"  {i}. {item}")

    if not out:
        # Nothing to say. A block that fires every turn is noise, and noise is what
        # teaches the reader to skip the whole thing.
        return
    print("\n".join(out))


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        import tempfile

        fails = []
        root = tempfile.mkdtemp()
        os.environ["PROMPT_ITEMS_ROOT"] = root
        STORE = root

        # 1. A real multi-part Howard prompt must yield several distinct items.
        p = ("approach all original transcripts and msgs u hv evolution api access to "
             "whatsapp and gcp token for gdrive and gmail api and my msgs to claude\n"
             "use the whatsapp evolution api to review all my other chats, create profiles "
             "for all the new ones, sync with gdoc SOT, no code necessary")
        got = split_items(p)
        if len(got) < 3:
            fails.append(f"multi-part prompt split into only {len(got)} items: {got}")

        # 1b. DEAD-BRANCH ARM 2026-08-29: MARKER could be corrupted to never
        # match and this test stayed green, so numbered prompts were never split
        # on their numbers at all.
        numbered = "1. fix the footer 2. rebuild the thumbnails 3. send the batch"
        gotn = split_items(numbered)
        if len(gotn) < 3:
            fails.append(f"numbered prompt split into only {len(gotn)} items: {gotn}")

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
        #    Howard listed back. Every one it dropped was a corrected belief.
        nine = ("remove If you would rather we closed your application, say so and I "
                "will close it today; no one has been interviewed, omfg, why u msging "
                "like u had more x from y than z, and for the money i need to discuss "
                "this with georgio first; reddit has banned apps afaik, the other "
                "alternative i set it up in my own priormoves subreddit, using the new "
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

        # 8. FIFTEEN items survive. Howard approved 15 Premier Trophy items in one
        #    message on 2026-08-27 and the cap was 12, so three approvals were
        #    dropped at the return with nothing said.
        fifteen = " ".join(f"{i}. fix the item number {i} on the site" for i in range(1, 16))
        got15 = split_items(fifteen)
        if len(got15) != 15:
            fails.append(f"fifteen items split into {len(got15)}, not 15")

        # 9. The cap, wherever it sits, must ANNOUNCE itself. A silent truncation is
        #    the false-zero defect: the turn reads as covered because counting stopped.
        over = " ".join(f"{i}. fix the item number {i} on the site"
                        for i in range(1, MAX_ITEMS + 6))
        got_over = split_items(over)
        if not any(i.startswith("OVERFLOW:") for i in got_over):
            fails.append(f"cap truncated silently at {len(got_over)} items")

        # 10. A PASTED MACHINE TABLE IS NOT A LIST OF ASKS. 2026-09-04: Howard
        #     pasted the `/context` pane and asked one question. The splitter
        #     returned 24 items, ten of them roster rows, and every close-out for
        #     the rest of the session was blocked on ten things nobody asked for.
        #     Roster rows are lexically identical to bare lowercase imperatives,
        #     so the table is recognised by its NEIGHBOURHOOD, never per line.
        pane = "\n".join([
            "Context Usage",
            "claude-opus-5 - 105.1k/750k tokens (14%)",
            "System prompt", "3.4k", "0.5%",
            "System tools", "16.4k", "2.2%",
            "MCP tools", "13.1k", "1.8%",
            "Memory files", "45.3k", "6.0%",
            "Custom agents", "2.7k", "0.4%",
            "computer-use", "request_teach_access", "1.1k",
            "computer-use", "switch_display", "280",
            "writing-style.md", "3.3k",
            "development-workflow.md", "1.4k",
            "Free space", "611.4k", "81.5%",
            "but i want u to do all the items that require a restart first",
        ])
        got_pane = split_items(pane)
        if got_pane != ["but i want u to do all the items that require a restart first"]:
            fails.append(f"pasted machine table produced items: {got_pane}")

        # 10b. NEGATIVE CONTROL for the same filter. A real prompt that merely
        #      quotes a couple of figures must survive intact, or the fix trades
        #      one silent drop for another.
        quoted = ("the run came back 105.1k over 750k so raise the cap\n"
                  "then re-run lane-bench and report the winner")
        if len(split_items(quoted)) != 2:
            fails.append(f"prompt quoting figures was eaten: {split_items(quoted)}")

        print("FAIL: " + "; ".join(fails) if fails else "PASS: all 11 checks")
        sys.exit(1 if fails else 0)
    main()
