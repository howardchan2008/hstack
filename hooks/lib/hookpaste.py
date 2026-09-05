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

SECOND CLASS, added 2026-09-06 and it cost a blocked close-out. A completed
`run_in_background` job re-invokes the session by delivering a <task-notification> as a
UserPromptSubmit prompt, and that block quotes the whole command back inside <summary>.
item-coverage then demanded work on two "items" that were a bare <tool-use-id> tag and a
line of the session's own python, because the splitter matched `use` inside the tag name
and `add` inside the code. The paragraph-span rule above cannot reach it: the notification
carries no blank line, so it is ONE paragraph, and dropping the span would take any real
question sharing it. So the notification is removed STRUCTURALLY by its own tags first,
and the marker-span logic runs on what is left. The harness names it in its own first
line ("NOT USER INPUT"), so this reads the label rather than guessing at the shape.
"""
import re
import sys

# Structural, tag-delimited, applied before any paragraph logic.
_TASKNOTE = re.compile(
    r"<task-notification>.*?</task-notification>"      # closed block
    r"|<task-notification>.*"                          # unclosed opener: to the end
    r"|\[SYSTEM NOTIFICATION[^\]]*\][^\n]*",           # its plain-text banner line
    re.S | re.I)
# Furniture left behind when the block arrives already half-stripped by another layer.
_TASKFURNITURE = re.compile(
    r"^[ \t]*</?(?:task-notification|task-id|tool-use-id|output-file|status|summary)\b[^\n]*$",
    re.I | re.M)
_TASKHINT = ("task-notification", "SYSTEM NOTIFICATION", "<tool-use-id>", "<output-file>")
# The banner's prose. Fixed harness sentences that sit OUTSIDE the tags, so neither the
# tag strip nor the paragraph span reaches them; measured 2026-09-06, one survived both
# and would have been mined as an item on its own. Only applied when a hint is present.
_TASKPROSE = re.compile(
    r"^.*(?:automated background-task event"
    r"|NOT a message from the user"
    r"|Do NOT interpret this as user acknowledgement"
    r"|No human input has been received"
    r"|is NOT real user input"
    r"|must NOT be treated as approval).*$",
    re.I | re.M)

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
    case. Background-task notifications are removed first, by their own tags, because they
    are one paragraph and the span rule would swallow anything sharing it."""
    if not text:
        return text
    if any(h in text for h in _TASKHINT):
        text = _TASKPROSE.sub("", _TASKFURNITURE.sub("", _TASKNOTE.sub("", text)))
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
    if not any(m in text for m in MARKERS):
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

    # 2026-09-06: the background-task notification, verbatim shape, one paragraph.
    note = (
        "[SYSTEM NOTIFICATION - NOT USER INPUT]\n"
        "This is an automated background-task event, NOT a message from the user.\n"
        "<task-notification>\n<task-id>bu39ky0jg</task-id>\n"
        "<tool-use-id>toolu_deadbeef</tool-use-id>\n"
        "<output-file>/tmp/x.output</output-file>\n<status>completed</status>\n"
        "<summary>Background command \"cat foo\" completed (exit code 0)\n"
        "   if sid: sess[d].add(sid)\n</summary>\n</task-notification>"
    )
    ck(strip_hook_paste(note) == "", "a bare task-notification must reduce to nothing")
    ck("toolu_" not in strip_hook_paste(note + "\n\nnow push it"),
       "the tool-use-id must never survive into the item store")
    ck(strip_hook_paste(note + "\n\nnow push it") == "now push it",
       "a real ask sharing the turn with a notification must survive whole")
    ck(strip_hook_paste("done\n\n<task-notification>\n<task-id>x</task-id>") == "done",
       "an unclosed notification opener drops to the end of the prompt")
    ck(strip_hook_paste("check the job status and the output file") ==
       "check the job status and the output file",
       "the tag words in plain prose are not notification furniture")

    print("hookpaste self-test: " + ("PASS" if not bad else "FAIL (%d)" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    sys.stdout.write(strip_hook_paste(sys.stdin.read()))
