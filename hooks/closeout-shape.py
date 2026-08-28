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

    # ---- R8, from the real 2026-08-27 incident -------------------------------
    # He wrote "he literally provided the numbers here" after pasting the MC525
    # dimension block, and the close-out still asked him to confirm the sizes.
    his = ("MC525 15*20cm (A5); 18*23cm; 20*25cm; 23*30cm (A4); 25*35cm\n"
           "i gave u the photos still")
    r8_hit = check("DONE\n- x\n\nYOUR MOVE\n- Tell me the MC525 sizes and I will run it.",
                   supplied=his)
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
    blocking = [p for p in problems if p.startswith(("R1 ", "R5 ", "R6 ", "R8 "))]
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

    print("\n".join("  - " + p for p in blocking))
    return 1


if __name__ == "__main__":
    sys.exit(main())
