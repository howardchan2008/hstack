#!/usr/bin/env python3
"""closeout-shape.py: enforce CLAUDE.md "Session close-out format is fixed".

the owner, 2026-08-06: the rule was written 2026-08-04 and obeyed in 0 of 49
sessions. Text in CLAUDE.md is not enforcement. This is.

Cite CLAUDE.md by SECTION TITLE, never by line number. ADDED 2026-08-12: every
hardcoded line citation in this file had rotted. :108 pointed at the
persist-findings rule, :124 at a rule about reconstructing past labels, :127 at
an environment note on WAL-mode quest.db. Each was printed at the reader as the
authority for a rule that line does not state, which is worse than no citation:
it sends anyone checking the claim to the wrong text. Line numbers move on every
CLAUDE.md edit, section titles do not.

Contract, deliberately narrow. It fires ONLY on a turn that did work
(a tool_use block since the last real user message). Conversational turns,
questions, mid-task narration: exempt. The failure being fixed is the
work summary that buries what the owner must do.

Checks, all mechanical:
  R1  first non-blank line is DONE
  R2  whole message <= 12 non-blank lines: DEMOTED to guidance 2026-08-06, not enforced here
  R3  no ask outside YOUR MOVE ("YOUR MOVE is the only place")
  R4  no internal enforcement token in the close-out ("BANNED in the close-out")
  R5  no FYI section, and no third bucket of any name ("Two sections, never three")
  R6  no work parked behind approval INSIDE YOUR MOVE ("Never park work here to
      avoid doing it"). R3 guards where an ask sits and so treats YOUR MOVE as a
      safe harbour; R6 is what closes that harbour. Fires on 16.5% of the 284
      close-outs in the corpus, against the 53.5% that got R2 demoted, and unlike
      R2 the rewrite it asks for is to do the work rather than to compress prose.
  R9  a completion claim in DONE must carry the evidence the work EMITTED.
      Blocking: the remedy is different content, not a rearrangement. Fires on
      1.2% of the 1,882 close-outs in the corpus (22), against 24.2% before it
      was scoped to short bare claims, where sampled precision was only ~40%.
      Long lines carry their own context and are exempt by measurement.
  R7  one close-out per user turn. Not a check on the text: a cap on this hook.
      If a DONE heading already reached the owner in this turn, every remaining
      block is logged and the stop is allowed. The only remedy a Stop hook has
      is another assistant message, so a block filed after a delivered close-out
      cannot improve what he read: it can only make him read it twice. Run
      `python3 closeout-shape.py --self-test` after touching any of this.

R4 exists because the author of R1-R3 broke it twice in the same session that
shipped them, ending close-outs with a STOPPING line in the message the owner
reads. Those tokens are Claude's bookkeeping. The stop hook may still demand
one; that answer belongs in the hook exchange, not in the owner's message.

Exit 0 = shape ok, or not applicable.  Exit 1 = violation, reasons on stdout.
Reads the transcript itself so it cannot be fooled by what the model claims.

Bounded on purpose: only the tail of the transcript is parsed, because these
files reach hundreds of MB and a full walk times out.
"""
import datetime
import json
import os
import re
import sys

CEILING = 12
TAIL_BYTES = 2_000_000

# An ask aimed at the owner. Kept tight on purpose: these are the phrasings that
# actually smuggled decisions into prose, not every sentence with a verb.
ASK = re.compile(
    r"\b("
    r"want me to|would you like|do you want|should i\b|shall i\b|"
    r"let me know|your call\b|up to you\b|if you want|"
    r"worth a look|worth checking|you may want|you might want|"
    r"sound good|ok to (push|proceed|send)"
    r")",
    re.I,
)


# CLAUDE.md 'BANNED in the close-out'. Internal enforcement vocabulary. the owner should not have to
# retain these to read his own status message.
BANNED = re.compile(r"\b(STOPPING|NOT-TYPING|NOT-DONE|NND_PARK)\b")


# R6, below. Two halves, and BOTH must appear on one line for it to fire.
# Half one: Claude announcing it will do the thing itself.
#
# The negative lookahead is load-bearing, found in the 2026-08-14 backtest. Without
# it the top hit was "Unarchive the repo, since I will not change repo settings
# myself", which is the exact opposite of a parked offer: it is Claude correctly
# refusing an action and handing over a genuinely the owner-only task. Matching the
# negation would have trained the rule to punish the behaviour it wants.
# Negations never read as an offer. The `(?!')` is needed because "i can" ends on a
# word boundary inside "i can't", so without it the contraction matched; "couldn't"
# and "won't" fail on their own since the alternation never reaches them.
OFFER = re.compile(
    r"\b(i(?:'| wi)ll|i can|i could|happy to|ready to)\b(?!'|\s*(not|never)\b)",
    re.I,
)
# Half two: that same action gated on the owner granting it first.
GATE = re.compile(
    r"\b("
    r"say (the word|go|yes)|give me the (go|word|nod)|greenlight|green light|"
    r"if you (want|approve|agree|confirm|say|prefer)|"
    r"once you (confirm|approve|decide|say)|"
    r"want me to|shall i\b|should i\b|"
    r"(just )?confirm and|let me know and|tell me and"
    r")",
    re.I,
)


def tail_lines(path, nbytes=TAIL_BYTES):
    """Last nbytes of the file as whole lines. Empty list on any failure."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > nbytes:
                fh.seek(size - nbytes)
                fh.readline()  # discard the partial first line
            return fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return []


def turn_did_work(transcript_path):
    """True if a tool_use block appears after the last real user message."""
    saw_tool = False
    for ln in reversed(tail_lines(transcript_path)):
        if '"type"' not in ln:
            continue
        try:
            d = json.loads(ln)
        except ValueError:
            continue
        t = d.get("type")
        if t == "user":
            # Tool results are recorded as user turns; a real user message is
            # one whose content is text, not tool_result.
            c = (d.get("message") or {}).get("content")
            if isinstance(c, str):
                return saw_tool
            if isinstance(c, list) and not any(
                isinstance(b, dict) and b.get("type") == "tool_result" for b in c
            ):
                return saw_tool
            continue
        if t == "assistant":
            c = (d.get("message") or {}).get("content") or []
            if any(isinstance(b, dict) and b.get("type") == "tool_use" for b in c):
                saw_tool = True
    return saw_tool


DONE_HEADING = re.compile(r"^\s*(\*\*|#+\s*)?DONE\b", re.M)


def prior_closeout_in_turn(transcript_path):
    """True if an assistant message in THIS user turn already carried a DONE heading.

    R7, added 2026-08-17 after the owner read the same close-out twice in one turn.
    A Stop hook has exactly one remedy: force another assistant message. So a
    block filed after a correct close-out has already reached him buys a line
    order and costs a duplicate. Measured shape (session 1cbd1ecb): message one
    closed out, a stop hook refused on an unrelated ground, message two repeated
    the same DONE and YOUR MOVE with three words changed. Refusing the repeat
    would have demanded a THIRD message, so R7 suppresses instead of blocking.
    """
    for ln in reversed(tail_lines(transcript_path)):
        if '"type"' not in ln:
            continue
        try:
            d = json.loads(ln)
        except ValueError:
            continue
        t = d.get("type")
        if t == "user":
            c = (d.get("message") or {}).get("content")
            if isinstance(c, str):
                return False
            if isinstance(c, list) and not any(
                isinstance(b, dict) and b.get("type") == "tool_result" for b in c
            ):
                return False
            continue
        if t == "assistant":
            c = (d.get("message") or {}).get("content") or []
            if isinstance(c, str):
                if DONE_HEADING.search(c):
                    return True
                continue
            for b in c:
                if isinstance(b, dict) and b.get("type") == "text":
                    if DONE_HEADING.search(b.get("text") or ""):
                        return True
    return False


def split_sections(text):
    """Return (before_your_move, your_move_and_after)."""
    m = re.search(r"^\s*(\*\*)?YOUR MOVE", text, re.M)
    if not m:
        return text, ""
    return text[: m.start()], text[m.start():]


# R8 ADDED 2026-08-28. the owner, across three sessions in two days: "he literally
# provided the numbers here", "i gave u the photos still", "i corrected u on the
# bb before". owner-facts.py already carries his ASSERTIONS forward into context,
# and it is wired. What nothing did was CHECK THE WAY OUT: a close-out could ask
# him for a thing he had already pasted, and no rule objected.
#
# Deliberately narrow. It fires on the shape that was actually measured: an ask
# naming an identifier or a supplied artefact that is already sitting in an
# earlier user turn. It does not try to judge asks in general.
ASK_FOR_INFO = re.compile(
    r"\b(tell me|say which|let me know|confirm (?:the|whether|that|it)|send me|"
    r"share the|give me|what (?:is|are|were)|which of|do you have|please provide|"
    r"provide the|paste the|remind me)\b", re.I)
# SKU/part-shaped tokens: MC525, F305, part-04, BB, E7. Distinctive enough that a
# match in an earlier user turn is real reuse rather than a common word.
IDENT = re.compile(r"\b(?:[A-Z]{1,4}[-_]?\d{2,5}[A-Z]?|[A-Z]{2,4}(?=\s+(?:dims|dimensions|sizes)))\b")
# Nouns for material he hands over. Paired with evidence that he actually pasted
# something, so "tell me the sizes" only fires when sizes were in fact supplied.
SUPPLIED = re.compile(
    r"\b(numbers?|dimensions?|sizes?|measurements?|photos?|images?|screenshots?|"
    r"files?|zips?|links?|the list|spreadsheet|csv)\b", re.I)


def _looks_pasted(user_text):
    """Did he hand over structured material, as opposed to just writing a line?"""
    if not user_text:
        return False
    if re.search(r"\[\d{4}/\d{2}/\d{2},", user_text):      # WhatsApp export paste
        return True
    if re.search(r"```", user_text):
        return True
    if len(re.findall(r"\d+\s*[x×*]\s*\d+", user_text)) >= 2:  # a size table
        return True
    return sum(1 for ln in user_text.splitlines() if ln.strip()) >= 8



# R9 ADDED 2026-08-28. The root cause, after a local model read all 897 distinct
# corrections: the largest theme cluster is hallucination (14 of 120), and its
# sharpest four are FALSE CLAIMS ABOUT MY OWN PRIOR ACTIONS. "claiming 3 dms
# were sent when only 1 went out". "claiming to have run a script". "asserted
# .codex refilled from the absence of an error".
#
# The defect is not failing to read. It is reporting completion from INTENTION
# rather than from EVIDENCE: "I did X" is generated exactly like any other
# sentence, and nothing marks it as a claim that could be checked.
#
# So a DONE line that asserts something is finished must carry the evidence the
# work produced: a count, a path, a URL, an exit code, a hash. Not the command
# that was run, which proves only that it was attempted. Four instances in the
# session that produced this rule, every one caught by luck rather than design:
# "1,219 corrections" (a quarter was text he pasted), "17,784 directives" (two
# thirds junk), "half your keychain wasted" (mostly macOS entries), and
# "gbrain repointed" when the sync had imported zero files.
# --- R11 ADDED 2026-08-29 -------------------------------------------------
# the owner: "well corrections are still important and shouldnt be ignored", after
# R10 was backtested and caught 0 of his 3 August deferral complaints. The two
# R10 missed were GATED OFFERS, and the finding that matters is that R6 did not
# catch them either, in its own section, on its own turf:
#
#   "Say send and the 20 go out ... and I will replace it before sending."
#   "If you would rather the copy had come off the free lane, say regenerate
#    and I will rebuild all 20 on Codex against the same threads."
#
# OFFER matched both ("I will"). GATE matched NEITHER, because GATE knows only
# the fixed phrase "say the word" while these name the trigger word itself: "say
# send", "say regenerate". Same defect R10 documented one rule earlier: a real
# evasion sitting INSIDE a rule's declared scope. Scope was never the hole, so
# widening R6's section would not have found it.
#
# What makes it parked work and not a legal ask: the missing input is his ASSENT
# to work already built. Twenty drafts sat finished behind the word "send". So
# SUPPLY keeps legal the ask where he alone holds a FACT, or where the world has
# to move first: "tell me when it is on", "tell me the MC525 sizes", "once the
# printer confirms". Approval is parked work; a fact he owns is not.
ASSENT = re.compile(
    r"\b("
    r"say [a-z']+(?: [a-z']+)? and\b|say (?:the word|go|yes|so|ok|okay)\b|"
    r"give me the (?:go|word|nod)\b|greenlight|green light|"
    r"if you (?:want|would rather|'d rather|prefer|approve|agree|say so)\b|"
    r"once you (?:confirm|approve|decide|say)\b|"
    r"on your word\b|at your word\b|parked on your word|"
    r"(?:just )?confirm and\b|approve and\b"
    r")",
    re.I,
)
SUPPLY = re.compile(
    r"\b("
    r"tell me (?:when|what|which|who|whether|how|the|your|if)\b|"
    r"give me (?:the )?(?:password|login|token|code|sizes?|number|address|name)\b|"
    r"send me\b|paste\b|forward me\b|"
    r"once (?:the|it|they|he|she|that)\b|after you (?:have )?(?:set|turn|enable|add|create)"
    r")",
    re.I,
)


# --- R10 ADDED 2026-08-29 -------------------------------------------------
# the owner: "im not asking you to do the tasks for me, im asking u to audit why the
# agent has repeatedly failed to comply with my requests, delegating my ask the
# next term". His own words three days earlier, 2026-08-26: "u keep delegating me
# tasks to do, instead of doing it urself".
#
# WHY EVERY EXISTING RULE MISSES IT. R3 and R6 both police work handed BACK to
# the owner. R6 needs OFFER and GATE on one line: an action plus permission asked
# for it. The close-out that prompted this read
#
#   "YOUR MOVE
#    Nothing. Next from me, in this order and without asking: the ads
#    reconfiguration script for your mum, then the thumbnails..."
#
# and matched NEITHER half. "Next from me" carries no first-person verb, so OFFER
# misses; "without asking" is the negation of GATE, so GATE misses. Measured: that
# line passes R1, R3, R5, R6 and R9 clean. The phrase "without asking" is CLAUDE.md's
# own DECIDE-DO-NOT-ASK directive being quoted as cover for not doing the work.
#
# So the model found the one disposition that costs nothing: keep the item, name
# it as mine, do none of it. That empties YOUR MOVE, which the format explicitly
# calls "the target state", and the cheapest way to empty it is to promise.
#
# Measured over 1,686 live close-outs: 136 (8.1%) carry a forward promise, and this
# rule as scoped fires on 19 (1.1%). Promises are NOT a context-exhaustion artifact:
# their median position in a session is 0.58 against a 0.56 baseline, and 15.9% land
# in the final tenth against a 17.2% baseline. There is room left when they are made.
# One item ("parallel render loop still unshipped, as flagged last turn") fired on
# five consecutive turns, which is the defect documenting itself.
#
# A deferral stays legal when it is RECORDED (a path, a backlog file, a quest) or
# REFUSED with its blocker named. What it may not be is a promise with no carrier.
DEFER = re.compile(
    r"\bnext from me\b"
    r"|\bnext session,? i\b"
    r"|\bi'?ll (?:do|start|write|build|run|tackle|pick|get|fold|add) [^.]{0,40}\bnext\b"
    r"|\bthen i'?ll (?:do|start|write|build|run|tackle|fix|ship|add|fold)\b"
    r"|\bi (?:have )?(?:still )?(?:have )?not (?:yet )?(?:written|built|done|started|shipped)\b"
    r"|\bstill (?:not|un)(?:written|built|started|shipped)\b"
    r"|\b(?:left|leaving) (?:it |that )?(?:for|to) (?:the )?next\b"
    r"|\bwill do next\b|\bcoming next\b"
    # THE THIRD VARIANT, 2026-08-30. the owner: "YOUR MOVE is still deferring,
    # despite your multitude of fixes." He was right, and the lesson is bigger
    # than the phrase. Each time a wording is banned the next close-out uses a
    # different one:
    #   1. "Nothing. Next from me, without asking: the ads script."
    #   2. "...still have no proof they refuse. Next from me unless you redirect."
    #   3. "Still owed by me and not done: the銀碟 rebuild, the banner reroll..."
    # A phrasing blacklist cannot win that race. So this half matches the SHAPE
    # instead: work attributed to ME and stated as outstanding, however it is
    # worded. "owed by me", "still owed", "on me and not done", "mine to do".
    r"|\b(?:still )?owed by me\b|\bstill owed\b|\bowed and not done\b"
    r"|\b(?:it|that|these|those) (?:is|are) (?:mine|on me)\b"
    r"|\bmine (?:to do|rather than yours|not yours)\b"
    # VARIANT FOUR, 2026-08-31. the owner, after restarting a session and watching it
    # happen again: "a restarted session still postponed all items". The wording
    # that got through was "Nothing. Next actions are mine and need no decision
    # from you: fix the llms.txt domain, update Yoast Premium, unhide the GA4
    # conversion action, and queue the 132 products". Four real jobs, all named,
    # none done, and the close-out scored ZERO findings. The subject was a noun
    # phrase rather than a pronoun, so the "(it|that|these|those) are mine" half
    # could not see it.
    r"|\b(?:next |remaining |other |outstanding |the rest of the )?"
    r"(?:actions?|items?|steps?|fixes?|jobs?|tasks?|work|moves?) "
    r"(?:here |left |that remain |from here )?(?:are|is) (?:all )?"
    r"(?:mine|on me|for me|my own)\b"
    r"|\bnot done:(?!\s*$)"
    r"|\boutstanding (?:from|on) me\b|\bstill (?:owe|owed) you\b",
    re.I,
)
# Recorded somewhere durable, or refused with a stated blocker. Either is honest.
DEFER_OK = re.compile(
    r"/[A-Za-z0-9._~-]+/|`[^`]+`|\.md\b|\.json\b|\bbacklog\b|OPEN-ITEMS|\bquest\b"
    # NARROWED 2026-08-29, on my own close-out. `\brefus` matched ANY use of the
    # word, so the line "7 hooks still have no proof they refuse: ... Next from
    # me unless you redirect" exempted itself. That is a deferral about refusal
    # buying a pass because it says refuse. the owner caught it in the same turn
    # the rule shipped: "last turn i explicitly said check every other hook ...
    # and u postponed that to the next turn still".
    #
    # An exemption has to name MY refusal of THIS item, not mention the concept.
    r"|\b(?:i|we) refuse|\brefused\b|\brefusing to\b|\bnot mine\b"
    r"|\bblocked on\b|\bcannot until\b|\bwaiting on\b|\bneeds? your\b"
    r"|\bbecause you (?:have not|haven'?t|did not|didn'?t)\b",
    re.I,
)
# Quoted material is data, not a promise: draft copy, a WhatsApp line, his own words.
# Half the first draft's hits were these, which is why the rule skips them outright.
DEFER_QUOTE = re.compile(
    r'^\s*(?:>|\*\*[A-Z] \d{1,2}:\d{2}|["\u201c])'
    r'|^\s*[-*]?\s*\d+\.\s*(?:Hi|Hello|Dear)\b'
)

CLAIMS_DONE = re.compile(
    r"\b(?:pushed|committed|deployed|shipped|synced|sent|fixed|repaired|resolved|"
    r"created|built|generated|wrote|written|ran|executed|installed|wired|enabled|"
    r"disabled|removed|deleted|migrated|backed up|verified|completed|finished|"
    r"landed|merged|updated|added)\b", re.I)

# Evidence is something the work EMITTED. A digit, a path, a URL, an exit code,
# a hash. Deliberately generous: the target is the bare "Fixed the prune job."
# shape, not an honest sentence that happens to be short.
EVIDENCE = re.compile(
    r"\d"                                  # any count, version, date, exit code
    r"|/[A-Za-z0-9._~-]+/"                  # a path
    r"|https?://"                           # a link
    r"|\b[0-9a-f]{7,40}\b"                  # a sha
    r"|`[^`]+`"                             # a named artefact in backticks
    r"|\b(?:one|two|three|four|five|six|seven|eight|nine|ten|both|every|all|each|"
    r"none|zero|clean|above|attached|below)\b"   # spelled-out or stated result
    , re.I)

# Sentences that are ANSWERS, not completion claims. "You were right" contains
# no claim about my own output and must never fire.
NOT_A_CLAIM = re.compile(
    r"\byou (?:were|are) right\b|\bnot your\b|\bnothing\.\s*finished\b"
    r"|\bstill owed\b|\bnot done\b|\bdid not\b|\bcould not\b|\bfailed to\b"
    r"|\battempted\b|\bI have not\b|\bnothing (?:was|sent|to send)\b|\bheld back\b"
    r"|\balready (?:pushed|committed|done|sent)\b|\bwhat I can say\b"
    r"|\bwhat survived\b|\bresurfaced\b", re.I)


def _done_lines(text):
    """Bullet lines inside DONE, which is where completion claims live."""
    before, _after = split_sections(text)
    out = []
    for ln in before.splitlines():
        s = ln.strip()
        if s.startswith(("-", "*")) and len(s) > 12:
            out.append(s)
    return out


def check(text, supplied=""):
    problems = []
    lines = text.splitlines()
    first = next((ln.strip() for ln in lines if ln.strip()), "")

    # R2 DEMOTED TO GUIDANCE 2026-08-06, on measurement, not taste. Squeezing under
    # 12 lines removed the blank lines between bullets, so 8 lines collapsed into one
    # unreadable markdown bullet. A shape rule that damages the thing it exists to
    # protect has to go. Guidance only.
    #
    # THE ORIGINAL NUMBERS HERE WERE WRONG. This comment claimed the cap "fired on
    # 53.5% of 7855 close-outs (median 13, p90 26)". Re-measured 2026-08-23 across
    # every transcript, live and archived: only 1,130 close-outs exist at all (the
    # 3,638 archived transcripts predate the format and hold 4 between them), their
    # non-blank line counts are p50 10, p90 24, max 131, and a 12-line cap would
    # breach 31.3%, not 53.5%. That denominator is off by 7x and counts something
    # other than close-outs. the owner caught it by asking whether he had ever had that
    # many turns; there are 81,890 prose turns in total, but only 1,134 opened with
    # DONE. The DEMOTION still stands, on the collapsed-bullet evidence, which is
    # about damage and not about frequency. Do not re-cite the old figures.
    #
    # R1 RESTORED 2026-08-06, hours after being demoted alongside R2, when the owner
    # asked whether the format had actually persisted into other sessions. Measured
    # answer: session 0f0abafe had this rule loaded from CLAUDE.md the whole time
    # and opened with DONE in 1 of 521 assistant turns. Demoting R1 was the wrong
    # read of the backtest. An 86.9% fire rate on a rule the owner states plainly is
    # evidence of non-compliance, not of a bad rule. Unlike R2, the DONE opener
    # costs exactly one line and damages nothing. Text in CLAUDE.md had 49 sessions
    # to work and did not; this is the only thing that has ever bound.
    #
    # R1 SPLIT 2026-08-14, the owner: "the other sessions still double reply, patch".
    # A Stop hook's only remedy is another assistant message, so blocking a
    # close-out whose CONTENT is already complete buys nothing and costs the owner a
    # second near-identical message. Measured case, session 1cbd1ecb 16:07:57:
    # R1 fired on the first line "Both trees clean, nothing unpushed.", the DONE
    # and YOUR MOVE sections underneath it were correct, and what came back was
    # the same close-out with the preamble deleted. the owner read it twice.
    # So: no DONE section anywhere is a real shape failure and still blocks. A
    # DONE section sitting under a preamble line is advisory, logged not blocked.
    if not re.match(r"^(\*\*)?DONE\b", first):
        has_done = bool(re.search(r"^\s*(\*\*|#+\s*)?DONE\b", text, re.M))
        problems.append(
            "%s close-out must open with DONE (CLAUDE.md 'Session close-out format is fixed'). "
            "First line was %r. Every response to the owner is DONE / YOUR MOVE, "
            "including the ones that feel like conversation."
            % ("R1s" if has_done else "R1", first[:70] or "(empty)")
        )
    del lines  # R2 retired; lines was only needed to find the first one

    # R5 ADDED 2026-08-12, the owner: "FYI is also unaccpetalbe and shdnt exist".
    # FYI was the escape hatch that made "named, not fixed" survivable. Anything
    # real enough to report is either something that was done (DONE) or something
    # the owner must act on (YOUR MOVE). A third bucket exists precisely so work can
    # be mentioned without being finished and without being handed over, which is
    # the deferral this whole ruleset exists to kill. Note the shape of the miss:
    # R1's OWN violation text taught "DONE / YOUR MOVE / FYI" until this commit,
    # so the enforcer was advertising the section it should have been rejecting.
    if re.search(r"^\s*(\*\*|#+\s*)?FYI\b", text, re.M):
        problems.append(
            "R5 close-out contains an FYI section (CLAUDE.md 'Two sections, never three', the owner "
            "2026-08-12: it should not exist). Anything in it either got done, "
            "and belongs in DONE, or needs the owner, and belongs in YOUR MOVE. "
            "If it is neither, it is not worth his attention: cut it."
        )

    # R3 SCOPED 2026-08-06. It fired on 40.3% of the corpus, but the rule is about
    # PLACEMENT: "asks live under YOUR MOVE and nowhere else". With no YOUR MOVE
    # section at all, split_sections returns the whole message as `before`, so any
    # polite "let me know" anywhere tripped a placement rule that did not apply.
    has_ym = bool(re.search(r"^\s*(\*\*)?YOUR MOVE", text, re.M))
    before, _after = split_sections(text)
    for ln in (before.splitlines() if has_ym else []):
        s = ln.strip()
        if not s:
            continue
        if ASK.search(s):
            problems.append("R3 ask outside YOUR MOVE (CLAUDE.md 'YOUR MOVE is the only place'): %r" % s[:70])
            break

    # R6 ADDED 2026-08-14, the owner: "u stop there only to where i asked u, naturally
    # u know what the next step might be right". R3 polices WHERE an ask sits and
    # treats YOUR MOVE as a safe harbour, so the one phrasing that survives every
    # existing rule is an offer to do the work once permission arrives. That is not
    # a request for the owner's judgement, it is Claude's own work held back behind a
    # turnaround, and CLAUDE.md forbids it twice: "Never park work here to avoid
    # doing it" and "DECIDE, DO NOT ASK".
    #
    # Worked example from the session that prompted this. The close-out ended with
    # "The 52 empty category URLs currently serve nothing. Say go and I will 302
    # each to its nearest stocked parent." the owner's entire reply was "302 all". The
    # decision was never his; the round trip bought nothing and cost a turn.
    #
    # Deliberately needs BOTH halves on one line. A YOUR MOVE item that only asks
    # for something Claude cannot get ("paste the raw WhatsApp text", "10% or the
    # approved 26%, do not average") has no offer half and stays legal, which is
    # the whole point: this rule targets parked work, not genuine questions.
    for ln in _after.splitlines():
        s = ln.strip()
        if s and OFFER.search(s) and GATE.search(s):
            problems.append(
                "R6 work parked behind approval in YOUR MOVE (CLAUDE.md 'Never park work "
                "here to avoid doing it' + 'DECIDE, DO NOT ASK'): %r. You are offering to "
                "do this yourself, so it is not the owner's move. Do it, then report it under "
                "DONE. Keep it here only if he alone can supply the input or the judgement, "
                "and then drop the offer and name only what you need." % s[:90]
            )
            break

    # R8: do not ask him for what he already handed over.
    if supplied:
        for ln in _after.splitlines():
            s = ln.strip()
            if not s or not ASK_FOR_INFO.search(s):
                continue
            reused = [t for t in set(IDENT.findall(s)) if t in supplied]
            if reused:
                problems.append(
                    "R8 asking for something already supplied (CLAUDE.md 'Asking for "
                    "already-stored info = infraction'): %r names %s, which is already in "
                    "an earlier message of his. Go read it." % (s[:90], ", ".join(sorted(reused)))
                )
                break
            if SUPPLIED.search(s) and _looks_pasted(supplied):
                problems.append(
                    "R8 asking for something already supplied (CLAUDE.md 'Asking for "
                    "already-stored info = infraction'): %r asks for material he has "
                    "already pasted in this session. Go read it." % s[:90]
                )
                break

    # R9: a completion claim in DONE must carry the evidence the work produced.
    for s_ in _done_lines(text):
        if NOT_A_CLAIM.search(s_) or not CLAIMS_DONE.search(s_):
            continue
        if EVIDENCE.search(s_):
            continue
        # Long lines carry their own context. The defect is the bare assertion:
        # "Committed and pushed." Measured 2026-08-28, firing on every length gave
        # ~40% precision, which would cost a duplicate message every other turn.
        if len(s_) > 70:
            continue
        problems.append(
            "R9 completion claim with no evidence (CLAUDE.md 'a completion claim must "
            "carry the evidence that verifies it, produced after the work'): %r. Say what "
            "the work EMITTED: the count, the path, the exit code, the URL. The command "
            "you ran proves it was attempted, not that it is done. If you cannot produce "
            "the evidence, the honest word is attempted." % s_[:90]
        )
        break

    # R11 ADDED 2026-08-29. Fires anywhere in the close-out, unlike R6, because
    # the shape is not about placement: an offer parked behind his assent is the
    # same defect in DONE as under YOUR MOVE. Both halves must land on ONE line,
    # keeping R6's discipline, and SUPPLY takes the line back out when the thing
    # he must give is a fact or an event rather than permission.
    for ln in text.splitlines():
        s_ = ln.strip()
        if not s_ or not OFFER.search(s_) or not ASSENT.search(s_):
            continue
        if SUPPLY.search(s_):
            continue
        # Quoted material is data, not an offer. Same exemption R10 carries:
        # this session's own close-out quoted the owner's "say regenerate and I
        # will rebuild" back at him as evidence and R11 fired on the quote.
        if DEFER_QUOTE.match(s_):
            continue
        problems.append(
            "R11 work parked behind your assent (the owner 2026-08-24, twice: work "
            "finished and held on a trigger word): %r. It is built and you are "
            "the switch. Do it, or name what you are actually missing." % s_[:110]
        )
        break

    # R10: work deferred to a future turn with nothing to make it come due.
    for ln in text.splitlines():
        s10 = ln.strip()
        if not s10 or not DEFER.search(s10):
            continue
        if DEFER_QUOTE.match(s10) or DEFER_OK.search(s10):
            continue
        problems.append(
            "R10 work deferred to a future turn (the owner 2026-08-26: 'u keep delegating me "
            "tasks to do, instead of doing it urself'): %r. R3 and R6 only catch work handed "
            "BACK to him; this hands it FORWARD to yourself, which no rule priced and nothing "
            "carries. Do it in this turn, or write it into the repo backlog and name the file "
            "on this line, or refuse it out loud with the blocker. A promise is not a "
            "disposition." % s10[:110]
        )
        break

    # --- R12 ADDED 2026-08-31 ---------------------------------------------
    # A SHAPE, NOT A PHRASE. R10's own comment predicted this and the prediction
    # came true a fourth time: each banned wording is replaced by a new one, so
    # a blacklist cannot win the race. What every version of the move shares is
    # the STRUCTURE, and it cannot be paraphrased away: YOUR MOVE opens with
    # "Nothing", which is the format's declared target state, and then carries on
    # to name work that belongs to me. The opener empties the section for the owner
    # while the sentence after it keeps the job.
    #
    #   legal   "Nothing. Finished."
    #   defect  "Nothing. Next actions are mine and need no decision from you: ..."
    #   defect  "Nothing. Next from me, without asking: the ads script."
    #
    # Attribution is restricted to explicit ownership (mine, on me, from me, I
    # will) rather than any first person, because "the three questions from my
    # last message are still open" is a genuine open item and not a promise.
    _before, _after = split_sections(text)
    # split_sections keeps the YOUR MOVE heading inside the section it returns,
    # found by printing it rather than assuming: the first attempt matched nothing
    # because it was testing the word "YOUR" against a rule about "Nothing".
    ym = re.sub(r"^\s*(?:\*\*|#+\s*)?YOUR MOVE\b[:*\s]*", "", _after.strip(), flags=re.I)
    ym = ym.strip()
    if ym:
        m_nothing = re.match(r"^[-*\s]*(?:nothing|none)\b[^.:;\n]*[.:;\n]?", ym, re.I)
        if m_nothing:
            rest = ym[m_nothing.end():]
            # A SECOND close-out concatenated after this one is not this one's
            # deferral. Backtesting surfaced "Nothing. Finished." immediately
            # followed by a fresh DONE heading, which is two messages, not a
            # promise. Cut at the next heading.
            rest = re.split(r"(?m)^\s*(?:\*\*|#+\s*)?DONE\b", rest)[0].strip()
            owns = re.search(r"\bmine\b|\bon me\b|\bfrom me\b|\bfor me to\b"
                             r"|\bi'?ll\b|\bi will\b|\bi am going to\b", rest, re.I)
            acts = re.search(r"\b(fix|update|unhide|queue|build|write|run|ship|send|"
                             r"deploy|rebuild|reroll|draft|wire|add|remove|migrate|"
                             r"translate|publish|start|finish|chase|clean)\b", rest, re.I)
            quoted = all(DEFER_QUOTE.match(l.strip())
                         for l in rest.splitlines() if l.strip())
            if (owns and acts and not quoted
                    and not DEFER_OK.search(rest) and len(rest) > 40):
                problems.append(
                    "R12 YOUR MOVE opens with %r and then keeps the work anyway: %r. "
                    "the owner 2026-08-31: 'a restarted session still postponed all items'. "
                    "Saying Nothing empties the section for him while the sentence after "
                    "it holds four jobs you named and did not do. Either do them in this "
                    "turn, or write them into a backlog file and name it here, or state "
                    "the blocker. An empty YOUR MOVE has to be empty."
                    % (m_nothing.group(0).strip()[:40], rest[:140])
                )

    hit = BANNED.search(text)
    if hit:
        problems.append(
            "R4 internal token %r in the close-out (CLAUDE.md 'BANNED in the close-out'). It belongs "
            "in the hook exchange, not in the owner's message." % hit.group(1)
        )
    return problems


def _self_test():
    """Both arms of R7: a first close-out is still policed, a repeat is not."""
    import tempfile

    def line(role, text, tool=False):
        blocks = [{"type": "text", "text": text}]
        if tool:
            blocks.append({"type": "tool_use", "name": "Bash", "input": {}})
        return json.dumps({"type": role, "message": {"content": blocks}})

    fails = []

    def check_arm(cond, label):
        if not cond:
            fails.append(label)

    # ---- R9: a completion claim must carry evidence ------------------------
    bare = "DONE\n- Fixed the prune job.\n\nYOUR MOVE\n- Nothing."
    check_arm(any(p.startswith("R9 ") for p in check(bare)),
              "r9: missed a bare completion claim")

    # NEGATIVE CONTROL 1: the same claim WITH the evidence must pass.
    ok = "DONE\n- Fixed the prune job: exit 0, fresh log at 16:10.\n\nYOUR MOVE\n- Nothing."
    check_arm(not any(p.startswith("R9 ") for p in check(ok)),
              "r9 negative control: fired on a claim carrying evidence")

    # NEGATIVE CONTROL 2: an ANSWER is not a completion claim.
    ans = "DONE\n- You were right, and the phrasing was never the problem.\n\nYOUR MOVE\n- Nothing."
    check_arm(not any(p.startswith("R9 ") for p in check(ans)),
              "r9 negative control: fired on an answer")

    # NEGATIVE CONTROL 3: honestly reporting NON-completion must pass. The rule
    # exists to make 'attempted' sayable, so it must never punish saying it.
    att = "DONE\n- Attempted the sync; it did not import anything.\n\nYOUR MOVE\n- Nothing."
    check_arm(not any(p.startswith("R9 ") for p in check(att)),
              "r9 negative control: fired on an honest non-completion")

    # NEGATIVE CONTROL 4: a named artefact in backticks is evidence.
    art = "DONE\n- Wired `com.the owner.jobq-drain` and it drained.\n\nYOUR MOVE\n- Nothing."
    check_arm(not any(p.startswith("R9 ") for p in check(art)),
              "r9 negative control: fired on a named artefact")

    # ---- R8, from the real 2026-08-27 incident -------------------------------
    # He wrote "he literally provided the numbers here" after pasting the MC525
    # dimension block, and the close-out still asked him to confirm the sizes.
    his = ("MC525 15*20cm (A5); 18*23cm; 20*25cm; 23*30cm (A4); 25*35cm\n"
           "i gave u the photos still")
    r8_hit = check("DONE\n- x\n\nYOUR MOVE\n- Tell me the MC525 sizes and I will run it.",
                   supplied=his)
    # R10 arms. The blocking one is the exact close-out the owner pasted 2026-08-29.
    defer = ("DONE\n- Footer fixed, verified live.\n\nYOUR MOVE\n"
             "Nothing. Next from me, in this order and without asking: the ads "
             "reconfiguration script for your mum, then the thumbnails.")
    check_arm(any(p.startswith("R10 ") for p in check(defer)),
              "R10 missed the pasted close-out: deferral with no carrier")
    # recorded -> legal
    rec = ("DONE\n- Footer fixed, verified live.\n\nYOUR MOVE\n"
           "- Nothing. Ads script not started, recorded in `storefront/docs/OPEN-ITEMS.md`.")
    check_arm(not any(p.startswith("R10 ") for p in check(rec)),
              "R10 fired on a deferral that names its backlog file")
    # refused with a blocker -> legal
    ref = ("DONE\n- Footer fixed, verified live.\n\nYOUR MOVE\n"
           "- Thumbnails still not built, blocked on your approval of the one sample.")
    check_arm(not any(p.startswith("R10 ") for p in check(ref)),
              "R10 fired on a deferral that names its blocker")
    # quoted draft copy is data, not a promise
    quo = ('DONE\n- Drafted the follow-up:\n> Hi Adhvaith, following up once and then '
           "I'll leave it.\n\nYOUR MOVE\n- Nothing.")
    check_arm(not any(p.startswith("R10 ") for p in check(quo)),
              "R10 fired on quoted draft copy")
    # a clean close-out must stay clean
    # R11 arms. The blocking one is the exact YOUR MOVE line the owner corrected on
    # 2026-08-24, verbatim from that close-out.
    g11 = ("DONE\n- Staged all 20, nothing sent.\n\nYOUR MOVE\n"
           "- If you would rather the copy had come off the free lane, say "
           "regenerate and I will rebuild all 20 on Codex.")
    check_arm(any(p.startswith("R11 ") for p in check(g11)),
              "R11 missed the 2026-08-24 gated offer")
    # An event in the world he must trigger stays legal, or the rule punishes
    # the correct handover it exists to protect.
    check_arm(not any(p.startswith("R11 ") for p in check(
                  "DONE\n- Forward rule researched.\n\nYOUR MOVE\n"
                  "- Tell me when it is on and I will read the triage.")),
              "R11 fired on an event only the owner can cause")
    check_arm(not any(p.startswith("R11 ") for p in check(
                  "DONE\n- x\n\nYOUR MOVE\n"
                  "- Give me the password and I will finish it.")),
              "R11 fired on a fact only the owner holds")
    check_arm(not any(p.startswith("R11 ") for p in check(
                  "DONE\n- Backtested.\n\nYOUR MOVE\n- Nothing.\n"
                  "> say regenerate and I will rebuild all 20")),
              "R11 fired on quoted material")
    # SUPPLY arm: verbatim from a real 2026-08 close-out. The ONLY arm where SUPPLY
    # decides. Without it SUPPLY is unreachable, and the negative control that
    # corrupts it passes green, which is exactly how it sat dead when first written.
    sup = ("DONE\n- x\n\nYOUR MOVE\n"
           "- If you want to write the incident framework properly for us, tell me "
           "what you would want in return and I will make the time.")
    check_arm(not any(p.startswith("R11 ") for p in check(sup)),
              "R11 fired on a fact only the owner can supply")
    check_arm(not any(p.startswith("R11 ") for p in
                      check("DONE\n- Footer now reads a venture.com, verified live."
                            "\n\nYOUR MOVE\n- Nothing.")),
              "R11 false-positive on a clean close-out")

    check_arm(not any(p.startswith("R10 ") for p in
                      check("DONE\n- Footer now reads a venture.com, verified live.\n\nYOUR MOVE\n- Nothing.")),
              "R10 false-positive on a clean close-out")

    # IDENT arm. R8 has two branches and only the second was ever reached, so
    # IDENT could be corrupted to never match with this test green. Here the
    # supplied text is one plain sentence, so _looks_pasted is False and the
    # SUPPLIED branch cannot fire: only the reused-identifier branch can.
    id8 = check("DONE\n- x\n\nYOUR MOVE\n- Tell me the MC525 sizes and I will run it.",
                "the MC525 model is the one dad asked about")
    check_arm(any(p.startswith("R8 ") for p in id8),
              "R8 missed a reused identifier (IDENT regex dead)")
    # The 2026-08-29 self-inflicted case. This exact line shipped in a close-out
    # about deferral detection and exempted itself, because DEFER_OK matched the
    # word "refuse" anywhere. A deferral ABOUT refusal is still a deferral.
    own = ("DONE\n- Fixed it: exit 0 at 16:10.\n\nYOUR MOVE\n"
           "- 7 hooks still have no proof they refuse. Next from me unless you redirect.")
    check_arm(any(p.startswith("R10 ") for p in check(own)),
              "R10 missed a deferral that merely mentions refusing")

    # The THIRD variant, 2026-08-30, verbatim from a live close-out the owner read.
    # Banning a wording just moves the wording, so this one is matched on shape:
    # work attributed to me and stated as outstanding.
    owed = ("DONE\n- Deleted 581 products, restore map written.\n\nYOUR MOVE\n"
            "- Nothing blocking. Still owed by me and not done: the rebuild, the "
            "banner reroll, and a real coverage measurement.")
    check_arm(any(p.startswith("R10 ") for p in check(owed)),
              "R10 missed 'still owed by me and not done'")

    # DEFER_OK arm: a deferral that names where it is recorded must stay legal.
    ok10 = check("DONE\n- Footer fixed, verified live.\n\nYOUR MOVE\n"
                 "- Nothing. Next from me: the ads script, recorded in the repo backlog.")
    check_arm(not any(p.startswith("R10 ") for p in ok10),
              "R10 fired on a deferral that names its record (DEFER_OK regex dead)")

    # --- DEAD-BRANCH ARMS ADDED 2026-08-29 ------------------------------------
    # Found by corrupting each module-level regex one at a time and re-running this
    # self-test. Five stayed green with the regex dead: ASK, BANNED, GATE, SUPPLIED,
    # NOT_A_CLAIM. Three of those five sit inside BLOCKING rules (R6, R8, R9), so the
    # gate could have stopped enforcing them and nothing here would have said so.
    #
    # This is the mirror of the failure the evidence-gate rule already names. A gate
    # that always FAILS is a gate nobody reads; a gate that always PASSES is a gate
    # nobody notices, and it is worse, because it reports success while enforcing
    # nothing. Every rule now needs at least one arm that dies when its regex dies.
    #
    # Direction matters and differs per rule. GATE dead makes R6 UNDER-block (R6 needs
    # OFFER and GATE on one line), so it needs a must-FIRE arm. SUPPLIED and
    # NOT_A_CLAIM are exemption halves: dead, they make R8 and R9 OVER-block, so they
    # need arms that pin the exempted shape.
    ask3 = check("DONE\n- Fixed the prune job.\n- Let me know if you want the full "
                 "list.\n\nYOUR MOVE\n- Nothing.")
    check_arm(any(p.startswith("R3 ") for p in ask3),
              "R3 missed an ask sitting in DONE (ASK regex dead)")
    ban4 = check("DONE\n- Staged all 20.\n\nYOUR MOVE\n- STOPPING: You said draft, "
                 "not send.")
    check_arm(any(p.startswith("R4 ") for p in ban4),
              "R4 missed an internal token in the close-out (BANNED regex dead)")
    # Real 2026-08 shape: an offer to act, held behind his approval, on one line.
    gate6 = check("DONE\n- Staged all 20, nothing sent.\n\nYOUR MOVE\n- If you want "
                  "the mirror files regenerated, say so and I will rebuild them.")
    check_arm(any(p.startswith("R6 ") for p in gate6),
              "R6 missed a gated offer in YOUR MOVE (GATE regex dead)")
    # R8's second branch: no SKU token reused, so only SUPPLIED plus a pasted-looking
    # earlier message can catch it. The existing r8_hit arm exercises the IDENT branch
    # only, which is why SUPPLIED could die unnoticed.
    sup8 = check("DONE\n- x\n\nYOUR MOVE\n- Send me the photos again and I will "
                 "restamp them.",
                 "\n".join("row %d of the export" % i for i in range(9)))
    check_arm(any(p.startswith("R8 ") for p in sup8),
              "R8 missed a re-ask for pasted material (SUPPLIED regex dead)")
    # An honest report of work NOT done is not a completion claim and must never be
    # asked for evidence. NOT_A_CLAIM dead turns every such line into an R9 finding.
    nac9 = check("DONE\n- Nothing was pushed; the tree is still dirty.\n\nYOUR MOVE"
                 "\n- Nothing.")
    check_arm(not any(p.startswith("R9 ") for p in nac9),
              "R9 fired on an honest not-done line (NOT_A_CLAIM regex dead)")

    check_arm(any(p.startswith("R8 ") for p in r8_hit),
              "r8: missed an ask for an identifier he already supplied")

    # NEGATIVE CONTROL 1: same ask, nothing supplied. Must stay silent, or the
    # rule becomes "never ask a question", which is not the rule.
    check_arm(not any(p.startswith("R8 ") for p in
                      check("DONE\n- x\n\nYOUR MOVE\n- Tell me the MC525 sizes and I will run it.",
                            supplied="")),
              "r8 negative control: fired with nothing supplied")

    # NEGATIVE CONTROL 2: a genuine ask for something he never gave. The whole
    # point of R8 is re-asking; a first ask is legitimate and must pass.
    check_arm(not any(p.startswith("R8 ") for p in
                      check("DONE\n- x\n\nYOUR MOVE\n- Tell me which supplier quoted F305.",
                            supplied=his)),
              "r8 negative control: fired on an identifier he never supplied")

    # NEGATIVE CONTROL 3: mentioning the identifier without asking for it.
    # Reporting on MC525 under YOUR MOVE is not a request to re-send it.
    check_arm(not any(p.startswith("R8 ") for p in
                      check("DONE\n- x\n\nYOUR MOVE\n- MC525 ships Monday once the printer confirms.",
                            supplied=his)),
              "r8 negative control: fired on a mention rather than an ask")

    # An ask parked BEFORE YOUR MOVE is R3's job, not R8's: scope stays narrow.
    check_arm(not any(p.startswith("R8 ") for p in
                      check("DONE\n- Tell me the MC525 sizes.\n\nYOUR MOVE\n- Nothing.",
                            supplied=his)),
              "r8: leaked outside YOUR MOVE")

    with tempfile.TemporaryDirectory() as d:
        first = os.path.join(d, "first.jsonl")
        repeat = os.path.join(d, "repeat.jsonl")
        # Arm 1: work happened, no close-out sent yet. R7 must stay out of the way.
        with open(first, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"type": "user", "message": {"content": "do the thing"}}) + "\n")
            fh.write(line("assistant", "working on it", tool=True) + "\n")
        check_arm(turn_did_work(first), "arm1: turn_did_work should be True")
        check_arm(not prior_closeout_in_turn(first), "arm1: no prior close-out expected")

        # PROTOCOL ARMS, added 2026-08-29. Every other arm in this file calls
        # check() directly, so all of them passed for weeks while main() was
        # reporting its findings in a form the harness discards: plain text on
        # stdout and exit 1, which on a Stop hook is a NON-BLOCKING error. The
        # rules were correct and nothing was ever blocked. the owner found it by
        # watching a live session defer on ten turns with R10 green.
        #
        # So these run the file as a SUBPROCESS, the way settings.json calls it,
        # and assert the contract the manifest records: decision=block on
        # stdout, exit 0. Testing what a guard FINDS is not testing that it
        # refuses.
        import subprocess

        def _run(msg):
            payload = json.dumps({"transcript_path": first,
                                  "last_assistant_message": msg,
                                  "stop_hook_active": False})
            p = subprocess.run([sys.executable, os.path.abspath(__file__)],
                               input=payload, capture_output=True, text=True)
            try:
                return p.returncode, json.loads(p.stdout or "{}")
            except ValueError:
                return p.returncode, {"__unparsed__": p.stdout[:120]}

        rc, obj = _run("DONE\n- Footer fixed, verified live.\n\nYOUR MOVE\n"
                       "Nothing. Next from me, without asking: the ads script.")
        check_arm(obj.get("decision") == "block",
                  "protocol: a blocking finding must emit decision=block, got %r" % obj)
        check_arm(rc == 0,
                  "protocol: a block exits 0 (exit 1 is a non-blocking error), got %d" % rc)
        rc2, obj2 = _run("DONE\n- Fixed the prune job: exit 0, fresh log at 16:10.\n\n"
                         "YOUR MOVE\n- Nothing.")
        check_arm(rc2 == 0 and not obj2.get("decision"),
                  "protocol: a clean close-out must not block, got rc=%d %r" % (rc2, obj2))
        check_arm(bool(check("Here is what happened.\n\nDONE\n- a\n\nYOUR MOVE\n- Nothing. Finished.")),
                  "arm1: a preamble close-out should still be flagged")

        # Arm 2: a close-out already reached the owner this turn. Nothing may force another.
        with open(repeat, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"type": "user", "message": {"content": "do the thing"}}) + "\n")
            fh.write(line("assistant", "working on it", tool=True) + "\n")
            fh.write(line("assistant", "DONE\n- shipped it\n\nYOUR MOVE\n- Nothing. Finished.") + "\n")
        check_arm(prior_closeout_in_turn(repeat), "arm2: prior close-out should be seen")

        # A close-out in the PREVIOUS turn must not suppress this one.
        older = os.path.join(d, "older.jsonl")
        with open(older, "w", encoding="utf-8") as fh:
            fh.write(line("assistant", "DONE\n- old work\n\nYOUR MOVE\n- Nothing. Finished.") + "\n")
            fh.write(json.dumps({"type": "user", "message": {"content": "next task"}}) + "\n")
            fh.write(line("assistant", "on it", tool=True) + "\n")
        check_arm(not prior_closeout_in_turn(older), "arm3: last turn's close-out must not carry over")

        # A tool_result user turn is not a real user message and must not end the scan.
        tr = os.path.join(d, "toolresult.jsonl")
        with open(tr, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"type": "user", "message": {"content": "go"}}) + "\n")
            fh.write(line("assistant", "DONE\n- shipped\n\nYOUR MOVE\n- Nothing. Finished.") + "\n")
            fh.write(json.dumps({"type": "user", "message": {"content": [
                {"type": "tool_result", "content": "ok"}]}}) + "\n")
        check_arm(prior_closeout_in_turn(tr), "arm4: tool_result must not end the turn scan")

    # Rules unrelated to R7 must be unchanged.
    check_arm(any(p.startswith("R5 ") for p in check("DONE\n- a\n\nFYI\n- b\n\nYOUR MOVE\n- Nothing.")),
              "arm5: R5 still fires on FYI")
    check_arm(not check("DONE\n- shipped it\n\nYOUR MOVE\n- Nothing. Finished."),
              "arm6: a clean close-out stays clean")

    for f in fails:
        print("  - " + f)
    print("closeout-shape self-test: %s" % ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


def _from_stdin():
    """Stop-hook payload -> (transcript, text).

    This existed as argv-only for weeks and settings.json never called it, so
    every rule below was dead. 2026-08-27: R6 was shown to catch a real
    close-out verbatim while the hook was wired to nothing. An unwired guard
    is indistinguishable from no guard, and it is worse than none, because
    its existence is cited as coverage.
    """
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return None, ""
    transcript = payload.get("transcript_path") or ""
    text = payload.get("last_assistant_message") or ""
    if not text and transcript and os.path.exists(transcript):
        try:
            with open(transcript, encoding="utf-8", errors="ignore") as fh:
                for ln in reversed(fh.readlines()[-400:]):
                    try:
                        d = json.loads(ln)
                    except Exception:
                        continue
                    if d.get("type") != "assistant":
                        continue
                    c = (d.get("message") or {}).get("content")
                    if isinstance(c, list):
                        t = "".join(b.get("text", "") for b in c
                                    if isinstance(b, dict) and b.get("type") == "text")
                        if t.strip():
                            text = t
                            break
        except Exception:
            pass
    return transcript, text


def user_supplied(transcript_path):
    """Every user-authored turn in this transcript, concatenated.

    R8 needs the thing he actually handed over, not a summary of it. The
    identifiers live in his own messages (SKUs, part names, pasted dimension
    blocks), so the corpus to match against is his turns and nothing else.
    Assistant turns are excluded on purpose: a token this session INVENTED
    must never count as something the owner supplied.
    """
    out = []
    try:
        with open(transcript_path, encoding="utf-8", errors="ignore") as fh:
            for ln in fh:
                try:
                    d = json.loads(ln)
                except Exception:
                    continue
                if d.get("type") != "user":
                    continue
                c = (d.get("message") or {}).get("content")
                if isinstance(c, str):
                    t = c
                elif isinstance(c, list):
                    t = " ".join(b.get("text", "") for b in c
                                 if isinstance(b, dict) and b.get("type") == "text")
                else:
                    continue
                # tool results are echoes of MY work, not his words
                if "tool_result" in t or t.startswith("[SYSTEM NOTIFICATION"):
                    continue
                if t.strip():
                    out.append(t)
    except OSError:
        return ""
    return "\n".join(out)


def main():
    if "--self-test" in sys.argv:
        return _self_test()
    if len(sys.argv) >= 3:
        transcript, text = sys.argv[1], sys.argv[2]
    elif not sys.stdin.isatty():
        transcript, text = _from_stdin()
    else:
        return 0
    if not transcript:
        return 0
    if not text.strip():
        return 0
    if not turn_did_work(transcript):
        return 0
    problems = check(text, supplied=user_supplied(transcript))
    if not problems:
        return 0

    # BLOCKING vs ADVISORY, split 2026-08-14. Blocking is reserved for the rules
    # whose remedy is different CONTENT: R1 (no DONE section at all), R5 (a third
    # bucket, i.e. work mentioned but neither done nor handed over) and R6 (work
    # parked behind approval). The rest ask for the same content rearranged, and
    # the only way this hook can ask for anything is to make Claude send a second
    # message, so enforcing them costs the owner a duplicate reply and buys a line
    # order. Advisory findings are logged and measurable, never blocked.
    blocking = [p for p in problems if p.startswith(("R1 ", "R5 ", "R6 ", "R8 ", "R9 ", "R10 ", "R11 ", "R12 "))]
    advisory = [p for p in problems if p not in blocking]

    if advisory:
        try:
            log = os.path.join(os.path.expanduser("~"), ".claude", "closeout-advisory.log")
            stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            with open(log, "a", encoding="utf-8") as fh:
                for p in advisory:
                    fh.write("%s | %s\n" % (stamp, p.replace("\n", " ")[:300]))
        except Exception:
            pass  # advisory logging never gates a stop

    if not blocking:
        return 0

    # R7 2026-08-17, the owner: "u just double replied". Once a close-out has been
    # delivered in this turn, no rule here may demand another message. The block
    # is recorded so the rule stays measurable, and the turn is allowed to end.
    if prior_closeout_in_turn(transcript):
        try:
            log = os.path.join(os.path.expanduser("~"), ".claude", "closeout-advisory.log")
            stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            with open(log, "a", encoding="utf-8") as fh:
                for p in blocking:
                    fh.write("%s | R7 suppressed (close-out already sent this turn) | %s\n"
                             % (stamp, p.replace("\n", " ")[:260]))
        except Exception:
            pass
        return 0

    # THE PROTOCOL, and it is the reason none of this ever fired. Found
    # 2026-08-29, after the owner watched a live premier-trophy session defer on
    # every one of ten turns with R10 shipped and green.
    #
    # This printed plain text to STDOUT and returned 1. On a Stop hook, exit 1
    # is a NON-BLOCKING error: Claude Code shows stderr to the owner and lets
    # the turn end. Stdout is not read as a decision, and stderr was empty, so
    # the model never saw a word of it. R1, R5, R6, R8, R9, R10 and R11 were
    # all listed as "blocking" and not one of them had ever blocked anything.
    #
    # item-coverage.py, a Stop hook in this same directory, had the protocol
    # right the whole time: a JSON decision object on stdout and exit 0. The
    # manifest even records `block: json` for BOTH. So the contract was
    # documented, one hook honoured it, this one did not, and every test here
    # passed because they all call check() directly and never once looked at
    # how main() reports what check() found.
    #
    # Verified against the live payload before and after: plain text + exit 1
    # produced no decision; this produces decision=block.
    listed = "\n".join("  - " + p for p in blocking)
    print(json.dumps({
        "decision": "block",
        "reason": (
            "CLOSE-OUT SHAPE: %d blocking finding(s).\n%s\n\n"
            "Fix the close-out and send it again. These are not style notes: "
            "each one names work that was neither done nor handed over."
            % (len(blocking), listed)
        )}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
