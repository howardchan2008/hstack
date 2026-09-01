#!/usr/bin/env bash
# closeout-preflight.sh: UserPromptSubmit. Inject the close-out contract BEFORE
# the reply is written.
#
# Why this exists, and why it is not another Stop rule. closeout-shape.py already
# detects the failure perfectly: R1s ("close-out does not open with DONE") fired
# on 4 of 6 close-outs on 2026-08-14 alone. It just cannot fix it. A Stop hook's
# only lever is to force ANOTHER assistant message, and the measured cost of that
# was the owner reading the same close-out twice with the preamble deleted, which is
# why R1s was demoted to advisory earlier the same day. Demoting it removed the
# nag and left the behaviour: every preamble since has sailed through and been
# logged rather than prevented.
#
# So move the intervention earlier. At UserPromptSubmit nothing has been written
# yet, so the correction costs zero extra messages. The escalation reads the
# advisory log the detector already writes: a rule that fired on the previous
# turn gets named outright, because a generic reminder that has already been
# ignored once is not worth repeating unchanged.
#
# Fails open. Any error here must never block a prompt.
#
# LAYER CHECK, added 2026-08-24. The generic contract below is ALREADY carried by
# two always-loaded files: ~/CLAUDE.md ("RESPONSE FORMAT IS MANDATORY") and
# ~/.claude/CLAUDE.md ("Session close-out format is fixed"). Printing it here made
# a third copy, paid per prompt instead of once per session. Measured before
# cutting it: close-out compliance (first line opens with DONE) ran 97.9% over
# 2026-08-17 to 2026-08-22, BEFORE this hook existed, against 98.4% since it was
# added on 2026-08-23. No detectable effect, at 517 bytes every turn.
# So the generic block now fires only as a fail-safe, when neither loaded file
# verifiably carries the rule (file moved, renamed heading, session started
# somewhere those files do not reach).
#
# The escalation below is NOT a duplicate and stays: it names a failure that
# actually happened, which no static file can know.
set -uo pipefail

LOG="$HOME/.claude/closeout-advisory.log"

# LIVE CHECK OF THE PREVIOUS CLOSE-OUT, added 2026-09-01. Everything below this
# block reads $LOG, and only the Stop chain ever wrote it. The Stop chain has
# not run on this box since 2026-08-24 23:18 (measured 2026-09-01: dozens of
# turns, zero bytes written by any Stop hook), so R10 and R12 were green,
# self-tested and completely inert, and a restart did not restore them. This
# runs the same rules from UserPromptSubmit, which demonstrably does fire.
# It reads its own copy of the payload and never blocks a prompt.
PAYLOAD="$(cat 2>/dev/null || true)"
if [ -n "$PAYLOAD" ]; then
  printf '%s' "$PAYLOAD" | /usr/bin/python3 "$HOME/.claude/hooks/closeout-shape.py" --advise 2>/dev/null || true
fi

if ! grep -q 'YOUR MOVE' "$HOME/CLAUDE.md" 2>/dev/null \
   && ! grep -q 'YOUR MOVE' "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  printf 'CLOSE-OUT CONTRACT, applies to the reply you are about to write:\n'
  printf '  First line is DONE. Not a preamble, not a status sentence, not "Here is where things stand".\n'
  printf '  Two sections only: DONE, then YOUR MOVE. No third section under any name.\n'
  printf '  Every ask aimed at the owner lives under YOUR MOVE. Nowhere else.\n'
  printf '  No STOPPING / NOT-TYPING / NOT-DONE tokens: those are hook bookkeeping.\n'
  printf '  Empty YOUR MOVE is the target state. Write "Nothing. Finished." and stop.\n'
fi

# Name what actually went wrong last time, rather than repeating the generic rule.
# FRESHNESS GATE, added 2026-08-24 with the cut above. There was none, so the last
# line of a 65-line log kept announcing "LAST TURN FAILED THIS" on every prompt for
# as long as it stayed last, including days later in unrelated sessions. An
# instrument that reports a stale failure as a current one is worse than silence.
if [ -f "$LOG" ]; then
  last="$(tail -1 "$LOG" 2>/dev/null || true)"
  ent_ts="$(printf '%s' "$last" | sed -n 's/^\([0-9-]\{10\} [0-9:]\{8\}\).*/\1/p')"
  if [ -n "$ent_ts" ]; then
    ent_epoch="$(/bin/date -j -f '%Y-%m-%d %H:%M:%S' "$ent_ts" '+%s' 2>/dev/null || echo 0)"
    now_epoch="$(/bin/date '+%s')"
    [ "$ent_epoch" -gt 0 ] && [ $(( now_epoch - ent_epoch )) -gt 1800 ] && last=""
  else
    last=""
  fi
  if [ -n "$last" ]; then
    rule="$(printf '%s' "$last" | sed -n 's/.*| \(R[0-9]s\{0,1\}\) .*/\1/p')"
    case "$rule" in
      R1s)
        printf 'LAST TURN FAILED THIS: the close-out opened with a preamble line and DONE came after it.\n'
        printf 'Delete the preamble. Whatever it said belongs inside a DONE bullet or nowhere.\n'
        ;;
      R3)
        printf 'LAST TURN FAILED THIS: an ask for the owner sat outside YOUR MOVE.\n'
        ;;
      R4)
        printf 'LAST TURN FAILED THIS: an internal enforcement token appeared in the message the owner reads.\n'
        ;;
    esac
  fi
fi

exit 0
