#!/usr/bin/env python3
"""hookpaste: strip pasted HOOK OUTPUT out of a prompt before mining it for items or facts.

WHY THIS EXISTS (2026-09-02). the owner pasted three stop-hook banners (about 2,600 words
of the harness talking to itself) followed by one line of his own: "why are there 3 stop
hooks in a row isnt that redundant". prompt-items split the paste into 37 items and
announced "THIS PROMPT CARRIES 37 ITEMS"; owner-facts carried eight "facts he stated"
that were closeout-shape's own wording; carryover-queue queued the lot. Three injectors,
one blind spot, and the noise landed in front of him on the next turn.

A paragraph that carries a hook's own banner phrase is the harness quoting itself, not
the owner asking for something. Hook output arrives as ONE contiguous block, so everything
between the first and the last marker paragraph is the paste, and only the text before
and after it is his. The markers are the hooks' own banner strings, which keeps the list
bounded by what the hooks print rather than by guesses about how he phrases things.

Used by: prompt-items.py, owner-facts.py, carryover-queue.py. Each call site is wrapped
so a missing or broken lib degrades to "no stripping", never to a silent hook.
"""
import re
import sys

MARKERS = (
    # Stop chain banners
    "YOU PROMISED THE WORK",
    "Stop refused:",
    "work is still on the floor",
    "CLOSE-OUT SHAPE:",
    "STOPPING: <reason>",
    "Answer both, then act",
    "HANDING BACK WORK THAT IS YOURS",
    "ITEM COVERAGE",
    "ONE-DIRECTIONAL READING",
    "close-out must open with DONE",
    "BEFORE BLAMING ANOTHER SESSION",
    "AND CHECK THE CONSTRAINT IS REAL",
    "REVERSIBLE OPTIONS ARE NOT A DECISION",
    "FINISHING MEANS FINISHING",
    "A NAMED EDIT IN A FILE YOU ALREADY TOUCHED",
    "NOT-TYPING:",
    "stop-justify.log",
    # harness framing lines around hook output
    "Stop hook feedback",
    "Stop hook blocking error",
    "hook error: [",
    "hook additional context",
    "UserPromptSubmit hook",
    "SessionStart hook",
    "PreToolUse:",
    "PostToolUse:",
    # UserPromptSubmit injectors quoting themselves
    "[BURN-BUDGET]",
    "STATE-VERIFY:",
    "OWNER-STATED FACTS",
    "ITEMS FROM the owner",
    "THIS PROMPT CARRIES",
    "SOURCES THAT MATCH THIS PROMPT",
    "<claim-guard>",
    "CAVEMAN MODE ACTIVE",
    "LAST TURN FAILED THIS",
    "YOUR LAST CLOSE-OUT FAILED",
    "[GUILD-SESSION]",
    "[SESSION-COLLIDE]",
    "wiring-verify:",
)

_PARA = re.compile(r"\n\s*\n")


def _is_marker(par):
    return any(m in par for m in MARKERS)


def strip_hook_paste(text):
    """Return the prompt with the pasted hook block removed.

    Paragraphs (blank-line separated) from the FIRST marker paragraph to the LAST one are
    dropped as one span. Text before the span and after it is kept verbatim. A prompt with
    no marker is returned unchanged, same object, so callers pay nothing for the common
    case."""
    if not text or not any(m in text for m in MARKERS):
        return text
    paras = _PARA.split(text)
    idx = [i for i, p in enumerate(paras) if _is_marker(p)]
    if not idx:
        return text
    lo, hi = idx[0], idx[-1]
    kept = paras[:lo] + paras[hi + 1:]
    return "\n\n".join(p for p in kept if p.strip()).strip()


def _self_test():
    bad = 0

    def ck(cond, msg):
        nonlocal bad
        if not cond:
            bad += 1
            print("FAIL " + msg)

    paste = (
        "YOU PROMISED THE WORK INSTEAD OF DOING IT. These lines defer work the owner asked "
        "for to a later turn:\n  - \"Next in the sweep per your directive would be...\"\n\n"
        "The turn does not have to end for you to keep going.\n\n"
        "CLOSE-OUT SHAPE: 2 blocking finding(s).\n  - R1 close-out must open with DONE\n\n"
        "Stop refused: work is still on the floor:\n\n"
        "If it is none of those, continue the work instead of reporting on it. Committing "
        "finished code is not a separate task needing permission.\n\n"
        "If stopping really is right, say so on its own line:\n  STOPPING: <reason>\n"
        "(Logged to ~/.claude/stop-justify.log and auditable.)\n\n"
        "why are there 3 stop hooks in a row isnt that redundant"
    )
    out = strip_hook_paste(paste)
    ck(out == "why are there 3 stop hooks in a row isnt that redundant",
       "the 2026-09-02 paste must reduce to the owner's one question, got %r" % out[:80])

    plain = "fix the footer link and push, then check the ads script"
    ck(strip_hook_paste(plain) is plain, "a plain prompt must come back untouched (same object)")

    both = ("first, rotate the key.\n\n"
            "Stop hook feedback:\nStop refused: work is still on the floor\n\n"
            "second, why did that fire")
    ck(strip_hook_paste(both) == "first, rotate the key.\n\nsecond, why did that fire",
       "text before AND after the paste must both survive")

    ck(strip_hook_paste("") == "", "empty stays empty")

    quoted = "the close-out said DONE then YOUR MOVE and I want both kept"
    ck(strip_hook_paste(quoted) is quoted, "DONE / YOUR MOVE alone are not hook markers")

    print("hookpaste self-test: " + ("PASS" if not bad else "FAIL (%d)" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    sys.stdout.write(strip_hook_paste(sys.stdin.read()))
