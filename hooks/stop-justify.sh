#!/usr/bin/env bash

# PROVENANCE, added <phone>. the 1,451-transcript refusal figures were measured 2026-08 against the then-live transcript tree.
# That tree is NOT the corpus any more: transcript-archive moved 3,638 of the
# 3,857 transcripts to ~/Archive/claude-transcripts on <phone>, so the live
# tree is about 6% of sessions. These numbers are HISTORICAL and are not
# reproducible as stated. Re-derive across BOTH trees before citing them; see
# ~/.claude/bin/claims-audit and hooks/lib/probe-dedupe-backtest.py for the shape.
# stop-justify.sh: Stop hook. Refuses a stop that leaves visible work on the floor.
#
# the owner, <phone>: "u need to justify it every time u stop, why did u stop at
# this point, why cant u continue further". The trigger was landing a working fix
# to cc_invoice_lib.py and moving on with it uncommitted.
#
# Contract: this hook blocks ONLY when there is an objective signal that work
# remains AND the assistant did not say why it is stopping anyway. It is not a
# vibe check: every signal below is something you can run yourself and see.
#
# To stop legitimately with work outstanding, put a line in the final message:
#     STOPPING: <reason>
# e.g. "STOPPING: needs the owner's call on which vendor" or "STOPPING: blocked on mom's QC".
# That is the justification. It is logged, so bad ones are auditable.
#
# NOT a valid reason: waiting on permission to push. the owner removed that gate
# (CLAUDE.md, <phone>: "no need permissions from me to push"). The old example
# here literally read "needs the owner's call on push", which taught every session
# reading this header to file exactly the excuse the rule forbids. Corrected
# <phone>. Routine push is not an owner decision; ship it.
#
# LOOP SAFETY: three independent guards, because a Stop hook that always blocks
# wedges the session and the only way out is killing the process:
#   1. stop_hook_active: set by Claude Code when it is already continuing
#      because of a Stop hook. Honour it unconditionally. This is the real loop
#      breaker: every block buys the next stop a free pass, so a block can never
#      immediately re-block.
#   2. CONSECUTIVE block cap (MAX_BLOCKS): a backstop under guard 1, counted in
#      a state file. Resets to zero on any allowed stop, and decays after
#      BLOCK_DECAY seconds of not blocking.
#   3. kill switch: touch /tmp/stop-justify-disabled
#
# <phone>, second pass: guard 2 used to be a LIFETIME per-session counter.
# the owner: "the stop hook didnt work, u keep stopping". Session 475710d4 hit the
# cap of 2 at 15:37 and then ran unguarded until 18:56, every stop for three
# hours exited at the cap check with no log line and no block. A cap that only
# ever counts up is not loop safety, it is a fuse: one long session burns it and
# the hook is off for good, silently, exactly when a long session needs it most.
# Consecutive-with-decay still terminates a runaway (two blocks with no allowed
# stop between them) but rearms the moment the session does anything legitimate.
#
# Disable:  touch /tmp/stop-justify-disabled
# Log:      ~/.claude/stop-justify.log

set -uo pipefail

[ -f /tmp/stop-justify-disabled ] && exit 0

MAX_BLOCKS=3            # consecutive blocks, not lifetime
# <phone>: 2 -> 3. the owner: "u rlly need to make the stop hook stricter so u
# dont stop so easily". Guard 1 (stop_hook_active) already hands every block a
# free pass on the very next stop, so a cap of 2 meant a determined stop reached
# open water after ONE nag. Three still terminates a runaway (the cap is
# consecutive, and any allowed stop resets it to zero) but costs a stop that is
# genuinely finished nothing, because a finished stop trips no signal at all.
BLOCK_DECAY=900         # s; this long without blocking rearms the guard
# Both overridable for the same reason auto-push.sh takes CLAUDE_AUTOPUSH_LOG:
# a gate you can only exercise by writing into live state is not tested, it is
# deployed. Defaults are the real paths, so nothing changes in normal operation.
STATE_DIR="${CLAUDE_STOPJUSTIFY_STATE_DIR:-$HOME/.claude/.stop-justify}"
LOG="${CLAUDE_STOPJUSTIFY_LOG:-$HOME/.claude/stop-justify.log}"
mkdir -p "$STATE_DIR" 2>/dev/null

INPUT="$(cat)"

# ---- guard 1: already continuing because of a Stop hook -----------------------
eval "$(printf '%s' "$INPUT" | python3 -c '
import json, sys, shlex
d = json.load(sys.stdin)          # any failure -> no output -> hook fails OPEN
def emit(k, v):
    print(f"{k}={shlex.quote(str(v))}")
emit("SID", d.get("session_id", ""))
emit("TRANSCRIPT", d.get("transcript_path", ""))
emit("HOOK_ACTIVE", "1" if d.get("stop_hook_active") else "0")
emit("HCWD", d.get("cwd", ""))
emit("PARSED", "1")
' 2>/dev/null)"

# FAIL OPEN. If the payload did not parse we know nothing about the session,
# not even which counter to charge, so we must never block. Getting this
# backwards jams every stop in every session with no obvious cause.
[ "${PARSED:-0}" = "1" ] || exit 0
[ -n "${SID:-}" ] || exit 0

TRANSCRIPT="${TRANSCRIPT:-}"
HOOK_ACTIVE="${HOOK_ACTIVE:-0}"
HCWD="${HCWD:-}"          # never fall back to $PWD: the hook's cwd is not the
                          # session's cwd, and guessing means checking a repo
                          # the session never touched.

[ "$HOOK_ACTIVE" = "1" ] && exit 0

# ---- guard 2: consecutive block cap ------------------------------------------
# State file is "<count> <epoch-of-last-block>". Old single-number files read as
# count with epoch 0, which decays immediately, so upgrading rearms every
# session that had already burned its old lifetime cap. That is the intent.
COUNT_FILE="$STATE_DIR/$SID.count"
NOW="$(date +%s)"
COUNT=0
LAST_BLOCK=0
if [ -f "$COUNT_FILE" ]; then
  read -r _c _t _rest < "$COUNT_FILE" 2>/dev/null || true
  case "${_c:-}" in ''|*[!0-9]*) _c=0 ;; esac
  case "${_t:-}" in ''|*[!0-9]*) _t=0 ;; esac
  COUNT="$_c"
  LAST_BLOCK="$_t"
fi

# Decay: a quiet stretch means whatever loop we were guarding against is over.
if [ "$((NOW - LAST_BLOCK))" -ge "$BLOCK_DECAY" ]; then
  COUNT=0
fi

# Reset the counter and allow the stop. Every allowed stop rearms the guard,
# that is what makes this a loop breaker rather than a one-shot fuse.
#
# <phone>: allow_stop used to exit silently, so ONLY blocks left a trace. That
# made the hook unauditable in the one direction that matters, a false NEGATIVE
# (a stop that should have been blocked and was not) wrote nothing at all, so the
# only way to find one was to already suspect it. The S2d miss fixed above sat
# invisible for exactly that reason. Every decision now writes one line, and the
# ALLOW line carries the tail of the final message so a miss can be diagnosed
# from the log instead of reconstructed from memory.
# ---- regex helpers: a broken pattern must never fail silently ----------------
# <phone> incident: S2d's bound was widened to {0,240}->{0,400}. /usr/bin/grep
# here is BSD grep 2.6.0-FreeBSD, whose RE_DUP_MAX is 255, so it did not match
# less, it refused to compile, printed "maximum repetition exceeds 255" to
# stderr, and exited 2. `if grep -q ...; then` treats rc=2 identically to rc=1,
# so the gate was not loosened, it was DISABLED, and the log recorded a bland
# "no-signals". The interactive shell hid it: there `grep` is ugrep 7.5.0, which
# accepts {0,400}, so the pattern tested green by hand and dead in the hook.
#
# rx returns the RAW grep status: 0 match, 1 no match, >=2 error (logged loudly).
# There is deliberately no blanket "fail closed" here, because the safe direction
# is not the same at every call site: the STOPPING: gate treats a match as
# "justified -> allow", so an error there must NOT count as a match, while the
# S2* signal gates treat a match as "work left -> block", so an error there MUST.
rx() {
  local _err _rc
  _err="$(printf '%s' "$1" | grep -qiE "$2" 2>&1)"; _rc=$?
  if [ "$_rc" -ge 2 ]; then
    printf '%s | %s | REGEX-ERROR | rc=%s %s | %s\n' "$(date '+%F %T')" "${SID:-?}" "$_rc" \
      "$(printf '%s' "$_err" | tr '\n' ' ' | cut -c1-120)" \
      "$(printf '%s' "$2" | cut -c1-140)" >> "$LOG" 2>/dev/null
  fi
  return "$_rc"
}

# hit: for SIGNAL gates only. True on a match OR on a broken regex, so a gate
# that cannot compile fails CLOSED (blocks and demands justification) instead of
# silently waving every stop through. Bounded by MAX_BLOCKS, so a broken pattern
# costs at most $MAX_BLOCKS blocks and announces itself in the log.
hit() { rx "$1" "$2"; [ $? -ne 1 ]; }

allow_stop() {
  rm -f "$COUNT_FILE" 2>/dev/null
  printf '%s | %s | %s | %s\n' "$(date '+%F %T')" "$SID" "${1:-ALLOW}" \
    "$(printf '%s' "${2:-}" | tr '\n' ' ' | cut -c1-240)" >> "$LOG" 2>/dev/null
  exit 0
}

[ "$COUNT" -ge "$MAX_BLOCKS" ] && \
  allow_stop CAP "$COUNT consecutive blocks, passing this stop through"

# ---- did the assistant justify the stop? -------------------------------------
# Read the last assistant text block out of the transcript.
# The SAME pass also collects the directories this session actually edited, into
# $DIRS_FILE. One read, not two: this transcript can be tens of MB and the whole
# hook runs under timeout 10. See the S1 header for why cwd was the wrong place.
DIRS_FILE="$STATE_DIR/$SID.dirs"
: > "$DIRS_FILE" 2>/dev/null
# The same pass also collects the FILES edited, basenames only, for the
# named-not-done gate below: it has to answer "is this a file you already
# touched?", which is the whole difference between typing and a follow-up.
FILES_FILE="$STATE_DIR/$SID.files"
: > "$FILES_FILE" 2>/dev/null

LAST_TEXT=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # FLUSH RACE (<phone>). The final assistant message is not always on disk
  # when this hook reads the transcript. Observed 20:16:36 this session: the
  # close-out opened with DONE and was on disk by 12:16:36.135Z, but LAST_TEXT
  # resolved to the PREVIOUS message -- mid-task narration -- so the shape gate
  # blocked a message that complied, quoting text that was never a close-out.
  # Every gate reading LAST_TEXT (STOPPING, named-not-done, S2, shape) inherits
  # that staleness, so this is not cosmetic to the shape check alone.
  # Bounded and cheap against the 10s hook timeout: worst case costs 0.5s.
  sleep 0.5
  LAST_TEXT="$(python3 -c '
import json, os, re, sys
path, dirs_path, files_path = sys.argv[1], sys.argv[2], sys.argv[3]
last = ""
dirs = []          # insertion ordered, deduped as we go
files = []         # basenames of files written/edited, deduped

def note(p):
    if not p or not p.startswith("/"):
        return
    d = p if os.path.isdir(p) else os.path.dirname(p)
    if d and d not in dirs:
        dirs.append(d)

# `cd` deliberately does NOT appear here. It used to confer ownership as a
# "medium signal". Measured <phone> across 91 transcripts, filtered to real
# git worktrees: 31 directories were claimed by `cd` alone with no write, and
# 19 of those were dirty at measurement time, i.e. 19 live sources of a block
# for work the session never touched. Against 38 write-backed claims. Session
# be14c63a `cd`-ed into code/whatsapp-mcp 26 times without writing a byte and
# would have been told it owned the dirt in that repo.
#
# The cost is real and accepted: a session that mutates only through the shell
# (`cd repo && sed -i ...`) is no longer attributed by this harvest. REPO_ROOTS
# still falls back to the hook cwd, so the common single-repo case keeps
# coverage; the uncovered case is shell-only edits in a repo that is not cwd.
# One quiet miss beats 19 confident false accusations.

# Only these tools establish that this session OWNS work in a directory. Read,
# Grep and Glob carry file_path/path too, and counting a read as ownership is
# how a conversation-only session ends up being told it owns another repo dirt.
# Full incident in the harvest note below.
MUTATORS = ("Write", "Edit", "MultiEdit", "NotebookEdit", "NotebookWrite")

try:
    with open(path, errors="replace") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            content = d.get("message", {}).get("content", [])
            parts = [
                b.get("text", "")
                for b in content
                if isinstance(b, dict) and b.get("type") == "text"
            ]
            if parts:
                last = "\n".join(parts)
            for b in content:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                inp = b.get("input") or {}
                if not isinstance(inp, dict):
                    continue
                # Strong signal: a file was WRITTEN at this path. Gated on
                # MUTATORS because Read, Grep and Glob carry file_path too, and
                # a read is not ownership: investigating a complaint must not
                # manufacture the ownership that complaint asserts.
                #
                # <phone> CORRECTION, kept because the wrong version shipped
                # in 5db6e65. That commit justified this gate by claiming
                # session be14c63a was BN(O) paperwork with no code in it, which
                # merely Read manifest.json and got locked onto automation-hub.
                # Its transcript disproves that: it has a Write into
                # automation-hub/jobs and 18 `cd ~/automation-hub`. It owned that
                # work and the complaint was accurate. The gate is still correct
                # on principle, but the incident cited for it was invented and
                # not checked against the transcript before being written down.
                # If you are about to justify a gate with a war story, read the
                # transcript first.
                if b.get("name") in MUTATORS:
                    for k in ("file_path", "notebook_path", "path"):
                        v = inp.get(k)
                        if isinstance(v, str):
                            note(v)
                            _b = os.path.basename(v)
                            if _b and _b not in files:
                                files.append(_b)
                # Bash commands are not harvested at all. See the `cd` note
                # above: navigating somewhere is not owning what is there.
except Exception:
    pass

# Most recent first, capped: the tail of the session is the work being stopped
# on, and every entry costs a `git -C` call below.
try:
    with open(dirs_path, "w") as fh:
        # Trailing newline on EVERY line, including the last. `join` alone left
        # the file unterminated, so the `printf %s\n "$HCWD"` that follows the
        # `cat` downstream got glued onto the final path, yielding one garbage
        # path that failed `[ -d ]`. Net effect: REPO_ROOTS empty AND the cwd
        # fallback destroyed, i.e. the hook silently checked nothing at all.
        fh.write("".join(d + "\n" for d in reversed(dirs[-40:])))
except Exception:
    pass
try:
    with open(files_path, "w") as fh:
        fh.write("".join(b + "\n" for b in files[-60:]))
except Exception:
    pass
sys.stdout.write(last[:8000])
' "$TRANSCRIPT" "$DIRS_FILE" "$FILES_FILE" 2>/dev/null)"
fi

# Explicit justification present -> allow the stop, but log it for audit.
# Uses rx, not hit: a match here means "justified -> allow the stop", so a broken
# regex must not read as a match. rx returns 2 on error, `if` treats that as
# false, and we fall through to the signal gates. Conservative in this direction.
# NAMED-NOT-DONE PARK (<phone>, the owner: "configure the stop hook such that
# [the three items I named] are completed").
#
# Until now STOPPING: exited HERE, before SIGNALS was computed, so the gate at
# the bottom -- "the final message names work that is still outstanding, then
# stops" -- could never fire on a justified stop. Net effect: "I noticed Y and
# left it named" was unconditionally sufficient, including for a one-line fix in
# a file this session already had open. The block text below has said since
# <phone> that such an edit is typing, not a follow-up. It was advice printed
# on OTHER blocks; this makes it load-bearing.
#
# Scope is deliberately narrow, because the unbounded version wedges: it fires
# only when the message names an outstanding item AND mentions the basename of a
# file THIS session edited. Work discovered anywhere else still parks freely on
# STOPPING alone, which is what keeps "name it in one line and stop" true.
#
# Fails OPEN. rx returns 2 on an uncompilable pattern and every call below reads
# non-zero as "not detected", so a broken regex loses this gate instead of
# jamming every stop on the box. That is the opposite of `hit`, and deliberate:
# `hit` guards work that is already visible, this guards a judgement call.
NND_MARKER_RX='(named,?[[:space:]]+not[[:space:]]+done|left[[:space:]]+it[[:space:]]+named|still[[:space:]]+to[[:space:]]+scope|needs[[:space:]]+the[[:space:]]+same[[:space:]]+guard)'
NND_HIT=""
named_not_done() {
  [ -s "$FILES_FILE" ] || return 1
  rx "$LAST_TEXT" "$NND_MARKER_RX" || return 1
  local _b
  while IFS= read -r _b; do
    # Plain basenames only: anything else may carry regex metacharacters, and a
    # metacharacter here would match text that is not a filename at all.
    case "$_b" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
    rx "$LAST_TEXT" "$_b" || continue
    NND_HIT="$_b"; return 0
  done < "$FILES_FILE"
  return 1
}

if rx "$LAST_TEXT" '^[[:space:]]*(\*\*)?STOPPING:'; then
  # Deferring stays legal. It just has to name which of the four legitimate
  # classes it is, instead of resolving to "I would rather not right now".
  if named_not_done && \
     ! rx "$LAST_TEXT" '^[[:space:]]*(\*\*)?NOT-TYPING:[[:space:]]*(owner-decision|destructive|expensive|not-mine)'; then
    NND_PARK="$NND_HIT"
  else
    allow_stop JUSTIFIED \
      "$(printf '%s' "$LAST_TEXT" | grep -iE '^[[:space:]]*(\*\*)?STOPPING:' | head -1)"
  fi
fi

# ---- objective unfinished-work signals ---------------------------------------
SIGNALS=""

# Carried down from the STOPPING gate. Kept as a SIGNAL rather than an immediate
# block so it prints next to the dirty files and unpushed commits, and so
# MAX_BLOCKS bounds it exactly like every other signal.
if [ -n "${NND_PARK:-}" ]; then
  SIGNALS="${SIGNALS}
  - the final message parks a named-not-done item, and names ${NND_PARK}, a file THIS session edited. You know the file and the change, so what is left is typing. Do it now, or classify the deferral:
        NOT-TYPING: <owner-decision|destructive|expensive|not-mine>: <item>"
fi

# ---- close-out shape (CLAUDE.md 'Session close-out format is fixed', added <phone>, the owner directive) --
# The close-out format was written <phone> and then obeyed in 0 of 49
# sessions measured <phone>. the owner: "i dont think u ever obey my
# instructions". Text in CLAUDE.md is not enforcement. This is.
#
# Carried as a SIGNAL rather than an immediate block, for the same reason given
# at the NND_PARK block above: MAX_BLOCKS and stop_hook_active then bound it
# exactly like every other signal, so a wrong shape can never wedge a session.
#
# Fails OPEN. A missing checker, missing python3, or any error leaves SHAPE_OUT
# empty and loses this gate rather than jamming every stop on the box. The
# checker itself only fires on turns that used a tool, so conversation and
# mid-task narration are exempt; the target is the work summary the owner reads.
SHAPE_CHECKER="$HOME/.claude/hooks/closeout-shape.py"
if [ -f "$SHAPE_CHECKER" ] && [ -n "$LAST_TEXT" ]; then
  SHAPE_OUT="$(python3 "$SHAPE_CHECKER" "$TRANSCRIPT" "$LAST_TEXT" 2>/dev/null || true)"
  if [ -n "$SHAPE_OUT" ]; then
    SIGNALS="${SIGNALS}
  - the close-out does not match the fixed shape (CLAUDE.md 'Session close-out format is fixed'):
${SHAPE_OUT}
    Reshape the message you already have: DONE first, then YOUR MOVE. There is
    no third section. Requests for the owner go under YOUR MOVE and nowhere else.
    This is a rewrite, not new work, so it is not a reason to stop."
  fi
fi

# WHICH REPOS TO CHECK (rewritten <phone>, the owner: "fix the stop hook").
#
# Until now this was exactly one repo, resolved from the session's cwd. That is
# wrong whenever the session edits anywhere else, which on this box is the
# normal case: cwd sits in ~/repos/a venture while the F1-F6 work happens in six
# ~/repos/a venture/site-wt-* worktrees. The failure was not subtle in either
# direction on <phone>:
#   FALSE NEGATIVE: F4 messaging sat with 6 modified files and, later, a commit
#                   that had never been pushed. Every stop logged "no-signals".
#   FALSE POSITIVE: it blocked twice on 4 dirty a venture files belonging to
#                   another session, which this one never touched.
# A gate that nags about other people's dirt while ignoring yours is worse than
# no gate, because it trains you to type STOPPING: to get past it.
#
# So: check the repos this session actually EDITED (collected from the
# transcript above), falling back to cwd only when that list is empty, e.g. a
# conversation-only session. Deduped by toplevel, so several worktrees of one
# repo stay several entries (separate trees, separate indexes) while two paths
# inside one tree collapse to one.
REPO_ROOTS="$(
  {
    # cwd is a FALLBACK, not an addition. Appending it unconditionally is what
    # produced the false positive this rewrite exists to kill: a session working
    # in a worktree got nagged about 11 dirty a venture files it never touched.
    # That is the failure mode that trains you to type STOPPING: to get past the
    # gate, which costs more than the gate ever earns.
    if [ -s "$DIRS_FILE" ]; then
      cat "$DIRS_FILE"
    else
      printf '%s\n' "$HCWD"
    fi
  } 2>/dev/null |
  while IFS= read -r _d; do
    [ -n "$_d" ] && [ -d "$_d" ] || continue
    git -C "$_d" rev-parse --show-toplevel 2>/dev/null
  done | awk 'NF && !seen[$0]++' | head -12
)"

# ATTRIBUTION FILTER. <phone>, the owner: "the stop hook and the session collide
# hook shd be resolving this in session" -- said after S1 blocked THIS session on
# hooks/session-collide.sh while another live session was mid-edit in it.
#
# S1 counted every dirty tracked file as this session's unfinished work. With 3
# other sessions live in the same tree that is just false, and it fails in the
# worst direction: the model is told to go commit bytes it does not own, and
# `git add` takes the whole file, not its half, so the other session's
# half-finished work lands under this one's name. The ledger that knows better
# already existed -- session-collide.sh --owner -- and this hook merely PRINTED
# ADVICE telling the model to consult it, while never consulting it itself. That
# left the resolution manual: a human had to notice and say so. So call it.
#
# FAIL-CLOSED, ALWAYS. unknown, UNATTRIBUTED, timeout, missing tool and parse
# failure all resolve to "yours". The failure this gate exists to prevent is
# work left on the floor, so attribution may only ever REMOVE a path from the
# list when it positively names a different session. Silence never subtracts.
#
# COST, AND WHY THERE IS NO LONGER A CAP (<phone>). This used to call
# --owner once PER PATH and cap the count at 6, because each call cost seconds.
# It cost seconds for a bug reason, not a fundamental one: --owner could not
# tell "rg found nothing" from "rg is not installed", so every unattributed
# path fell through to a full BSD-grep corpus sweep. Fixed in session-collide.sh
# earlier this session. Measured after that fix, one --owner call against a REPO
# ROOT attributes every dirty path in the tree in a single corpus pass:
#     8 dirty -> 0.65s     30 dirty -> 1.96s     80 dirty -> 5.00s
# versus 17.6s for 80 one-at-a-time calls. So ask once per repo, not once per
# path, and attribute all of them.
#
# The cap was never a safety feature, it was a latency guard that traded away
# the exact signal this gate exists for. Above it the check was SKIPPED, and a
# skipped check is not a passed check: a venture routinely sat at 77 dirty
# paths, so ownership was never checked there at all. Deleting the cap is what
# makes the <phone> miss detectable in the trees where it actually happens.
COLLIDE="$HOME/.claude/hooks/session-collide.sh"
# _OWNER_MAP holds "<relpath>\t<sid8>" lines, one per attributed path, possibly
# several per path. _OWNER_MAP_OK distinguishes "asked and got an answer" from
# "could not ask", which the caller MUST fail closed on. Same empty-is-an-answer
# trap that caused the bug above: an empty map is a legitimate answer, meaning
# nothing here is owned by anyone else.
_OWNER_MAP=""
_OWNER_MAP_OK=0
_load_owner_map() {
  local root="$1" out
  _OWNER_MAP=""; _OWNER_MAP_OK=0
  [ -x "$COLLIDE" ] || return 0
  command -v timeout >/dev/null 2>&1 || return 0
  # 20s against a measured 5.0s worst case. A timeout here is a real failure and
  # falls through to fail-closed, so headroom is cheap and a stall is not.
  out="$(printf '{"session_id":"%s"}' "$SID" \
         | timeout 20 bash "$COLLIDE" --owner "$root" 2>/dev/null)" || return 0
  _OWNER_MAP="$(mktemp "${TMPDIR:-/tmp}/sj-owner-XXXXXX")" || { _OWNER_MAP=""; return 0; }
  # Only the block AFTER this marker attributes DIRTY bytes. The header above it
  # names whoever made the last COMMIT, which is a different question, and
  # reading it here would call a file yours because you committed it an hour ago.
  #
  # A path line is 3 spaces then a status word ("   M f.txt   modified ..."); a
  # session line is indented 4, so the leading-space count alone separates them.
  printf '%s\n' "$out" | awk '
    /^uncommitted edits:/ { inb = 1; next }
    /^verdict/            { inb = 0 }
    inb {
      if (match($0, /^   [^ ]+ /)) {
        l = $0
        sub(/^   [^ ]+ /, "", l)
        sub(/   modified .*$/, "", l)
        sub(/   \(deleted.*$/, "", l)
        cur = l
        next
      }
      if (cur != "" && match($0, /session [0-9a-f]{8}/)) {
        print cur "\t" substr($0, RSTART + 8, 8)
      }
    }' > "$_OWNER_MAP"
  _OWNER_MAP_OK=1
}
_owner_of() {
  local rel="$1" sids
  [ "$_OWNER_MAP_OK" = 1 ] && [ -f "$_OWNER_MAP" ] || { echo mine; return; }
  sids="$(awk -F'\t' -v r="$rel" '$1 == r { print $2 }' "$_OWNER_MAP" | sort -u)"
  # NO RECORDED OWNER IS NOT "MINE". Fixed <phone>, the owner: the reprompt "is
  # firing too commonly even when no code or session collide is present".
  #
  # This line used to return `mine`, so any dirty file that no session was
  # recorded as editing got blamed on whoever stopped next. The owner map is
  # built from HOOKED Edit and Write calls, and a file changed through Bash (a
  # heredoc, `sed -i`, a python one-liner) leaves no such record at all. I made
  # exactly that mistake tonight: six hook files got PROVENANCE banners through a
  # python heredoc at 23:09, and at 23:12 and 23:13 two other sessions were
  # blocked and told to justify "2 tracked file(s) modified but not committed in
  # .claude" that were mine. Both correctly answered that the files were not
  # theirs, which is a round trip each, spent on my mess.
  #
  # `unknown` is now its own bucket: still listed, never blocking. The <phone>
  # miss argues the other way, but that was about SILENCE, a tool exiting 0 with
  # no output so foreign edits got swept into a commit. Naming the files loudly
  # while declining to accuse keeps the information and drops the false charge.
  [ -n "$sids" ] || { echo unknown; return; }
  printf '%s\n' "$sids" | grep -qx "$(printf '%s' "$SID" | cut -c1-8)" && { echo mine; return; }
  echo "other:$(printf '%s\n' "$sids" | head -1)"
}

# CWD-SCOPED REPO SKIP (<phone>, the owner: "since we're doing a venture work,
# u need to adjust the stop hook ... to make them stop [surfacing a venture],
# permanently ... patch the upstream issues").
# A repo listed SKIP_UNLESS_CWD in the ignore conf is reported ONLY while the
# session is actually working inside it. This session edited a venture early,
# then moved to a venture/another venture for the rest of its life; the gate went on
# surfacing a venture' daily-refresh churn and one unattributed unpushed commit
# at EVERY stop. That is noise the session cannot act on, and noise the session
# cannot act on is what trains typing STOPPING: to get past the gate, which
# costs more than the gate earns.
#
# A FUNCTION, CALLED BY EVERY SIGNAL LOOP, and not an inline block in one of
# them. First cut guarded only the dirty-files loop, and the very next stop
# still surfaced a venture -- via the "N commit(s) ahead" loop further down,
# which iterates the same repo list and never saw the guard. Two loops, one
# rule: a scope that holds for one signal and not its twin is not a scope.
#
# SCOPED, NOT DELETED: cd into a venture and the gate behaves exactly as it
# always has. This suppresses irrelevance, not accountability.
# Fail-safe direction: if HCWD is missing, _cwd_repo is empty, the equality
# fails and the listed repo is skipped. Losing a signal on a repo the user
# explicitly de-scoped beats resurrecting the nag this exists to kill.
# Returns 0 = skip this repo, 1 = report it normally.
skip_unless_cwd() {
  _repo="$1"
  _conf="${CLAUDE_STOPJUSTIFY_IGNORE:-$HOME/.claude/stop-justify-ignore.conf}"
  [ -f "$_conf" ] || return 1
  awk -v r="$_repo" \
    '$1 == "SKIP_UNLESS_CWD" && $2 == r { found = 1 } END { exit !found }' \
    "$_conf" 2>/dev/null || return 1
  _cwd_repo="$(git -C "$HCWD" rev-parse --show-toplevel 2>/dev/null)"
  [ "$_repo" = "$_cwd_repo" ] && return 1
  return 0
}

# S1: tracked files modified but not committed. This is the exact miss that
# prompted the rule. Untracked files are ignored on purpose: this tree carries
# 100+ untracked audit artefacts by design and always would.
#
# `while read <<<` and NOT `printf | while read`: a pipeline puts the loop body
# in a subshell, so every SIGNALS append inside it would be discarded at `done`
# and the gate would silently never fire again.
while IFS= read -r REPO_ROOT; do
  [ -n "$REPO_ROOT" ] || continue
  skip_unless_cwd "$REPO_ROOT" && continue
  # <phone>: `head -10` used to run BEFORE the count, and N was computed from
  # the truncated list, so any tree with >10 dirty files reported exactly
  # "10 tracked file(s)" forever. Count the full list, truncate only for display.
  # REFRESH THE STAT CACHE FIRST. Added <phone>, the owner: the reprompt "is
  # firing too commonly even when no code or session collide is present".
  #
  # `git status --porcelain` reports a file modified when its mtime moved, even
  # if the bytes are identical, until something refreshes the index. Two things
  # on this box rewrite files with identical content on a schedule: the
  # pxpipe-repatch SessionStart hook re-applies all eleven patches every session,
  # and sync-sot-gbrain.sh rewrites its exports several times a day. So a session
  # that touched nothing gets blocked and told to justify work it never did.
  # Measured in this hook's own log: 100 of 971 blocks (10%) were dirty-file
  # blocks in the shared ~/.claude tree, across 35 distinct sessions. One session
  # tonight proved the mechanism by hand: `git diff` on both named files was
  # EMPTY, and after `git update-index --refresh` all eight went clean.
  #
  # HONESTY ABOUT THIS FIX: I could NOT reproduce phantom-dirty on demand.
  # Touching a tracked file, with and without holding .git/index.lock, left
  # `git status --porcelain` reporting clean on git 2.54.0, because status falls
  # back to a content compare when the stat entry mismatches. So the mechanism
  # above is the other session's observation plus the obvious remedy, not
  # something I demonstrated. What IS established: this file had zero refresh
  # calls, the other session saw eight files go clean under `update-index
  # --refresh` with `git diff` empty, and 100 of 971 logged blocks were dirty-file
  # blocks in the shared tree. The refresh only updates stat information, never
  # content, so it cannot lose work, and failure is ignored so a contended
  # index.lock cannot break the stop hook. If the reprompt keeps firing on clean
  # trees, this was not the cause and the next suspect is the FOREIGN accounting
  # below, not the stat cache.
  git -C "$REPO_ROOT" update-index -q --refresh >/dev/null 2>&1 || true
  DIRTY_ALL="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)"
  FOREIGN=0
  UNKNOWN=0
  UNATTRIB=0
  IGNORED=0
  # GENERATED-ARTIFACT FILTER (<phone>, the owner: "this session is
  # a venture, why do u keep calling another venture ... investigate and patch").
  # Pipeline output regenerated by a daily job is not session work. a venture
  # carries 75 refreshed web/data files that a cron rewrites; before this they
  # (a) nagged on EVERY stop no matter which project the session was on, and
  # worse (b) pushed NRAW to 77, far past the old 6-path attribution cap, so the
  # ownership check below was SKIPPED entirely and the report said "ownership
  # NOT checked" every single time.
  #
  # (b) died on <phone> when the cap was deleted; all 77 would be attributed
  # now. (a) did not, and the filter still earns its keep for a reason the cap
  # was masking: no session wrote those files, a cron did, so --owner returns
  # them UNATTRIBUTED and they fail closed to "yours". That is the right default
  # -- failing open is how another session's work gets swept into your commit --
  # but it means cron output would nag forever as 75 files you must account for.
  # A daily job is not a session, so drop it before attribution rather than
  # teaching the attributor to guess about it.
  # Deliberately NOT a hardcoded path list: config lives in
  # ~/.claude/stop-justify-ignore.conf as "<repo-toplevel> <glob> [glob...]",
  # so this stays a general mechanism and the hook still works on a box with no
  # such file. Globs are matched by `case`, where * spans / as well.
  IGNORE_CONF="${CLAUDE_STOPJUSTIFY_IGNORE:-$HOME/.claude/stop-justify-ignore.conf}"
  if [ -n "$DIRTY_ALL" ] && [ -f "$IGNORE_CONF" ]; then
    PATS="$(awk -v r="$REPO_ROOT" \
      '$0 !~ /^[[:space:]]*#/ && NF >= 2 && $1 == r { for (i = 2; i <= NF; i++) print $i }' \
      "$IGNORE_CONF" 2>/dev/null)"
    if [ -n "$PATS" ]; then
      IKEPT=""
      while IFS= read -r dl; do
        [ -n "$dl" ] || continue
        irel="${dl:3}"
        case "$irel" in *" -> "*) irel="${irel##* -> }" ;; esac
        irel="${irel#\"}"; irel="${irel%\"}"
        iskip=0
        while IFS= read -r pat; do
          [ -n "$pat" ] || continue
          case "$irel" in $pat) iskip=1; break ;; esac
        done <<< "$PATS"
        if [ "$iskip" -eq 1 ]; then
          IGNORED=$((IGNORED + 1))
        else
          IKEPT="${IKEPT}${dl}
"
        fi
      done <<< "$DIRTY_ALL"
      DIRTY_ALL="$IKEPT"
    fi
  fi
  if [ -n "$DIRTY_ALL" ]; then
    NRAW="$(printf '%s\n' "$DIRTY_ALL" | grep -c . )"
    # ONE call for the whole repo, then a pure lookup per path.
    _load_owner_map "$REPO_ROOT"
    if [ "$_OWNER_MAP_OK" != 1 ]; then
      # Could not ask: tool missing, no timeout(1), or the call failed or timed
      # out. A SKIPPED check is not a PASSED check, so subtract nothing and say
      # so. Asserting "all N are yours" here is the exact shape of the
      # <phone> miss: another session's uncommitted edits read as this
      # agent's work on the floor and got swept into its commit.
      UNATTRIB=1
    else
      KEPT=""
      while IFS= read -r dl; do
        [ -n "$dl" ] || continue
        rel="${dl:3}"
        # rename: "R  old -> new". The new name is the one on disk to commit.
        case "$rel" in *" -> "*) rel="${rel##* -> }" ;; esac
        rel="${rel#\"}"; rel="${rel%\"}"
        case "$(_owner_of "$rel")" in
          other:*) FOREIGN=$((FOREIGN + 1)) ;;
          unknown) UNKNOWN=$((UNKNOWN + 1)) ;;
          *)       KEPT="${KEPT}${dl}
" ;;
        esac
      done <<< "$DIRTY_ALL"
      DIRTY_ALL="$KEPT"
    fi
    [ -n "$_OWNER_MAP" ] && rm -f "$_OWNER_MAP"
    _OWNER_MAP=""; _OWNER_MAP_OK=0
  fi
  if [ -n "$DIRTY_ALL" ]; then
    N="$(printf '%s\n' "$DIRTY_ALL" | grep -c . )"
    DIRTY="$(printf '%s\n' "$DIRTY_ALL" | head -10)"
    if [ "$N" -gt 10 ]; then
      DIRTY="$(printf '%s\n... and %s more\n' "$DIRTY" "$((N - 10))")"
    fi
    FNOTE=""
    [ "$FOREIGN" -gt 0 ] && FNOTE=" (+${FOREIGN} dirty here owned by another live session, not yours to commit)"
    # UNKNOWN is listed, never blocking. A file no hooked Edit or Write touched
    # was almost certainly changed through Bash by some session, and guessing
    # which one is how innocent sessions got refused. Say it and move on.
    [ "$UNKNOWN" -gt 0 ] && FNOTE="${FNOTE} (+${UNKNOWN} dirty here with NO recorded owner, changed through Bash or by hand, so not attributed to you and not blocking)"
    [ "$UNATTRIB" -eq 1 ] && FNOTE=" (ownership NOT checked: the attribution query failed or timed out on these ${NRAW} dirty paths, so an unknown number of them belong to another session. Ask the ledger before committing any of them; do not treat this list as yours)"
    SIGNALS="${SIGNALS}
  - ${N} tracked file(s) modified but not committed in $(basename "$REPO_ROOT")${FNOTE}:
$(printf '%s\n' "$DIRTY" | sed 's/^/      /')"
  fi
done <<< "$REPO_ROOTS"

# Are the unpushed commits in this repo THIS session's to push?
#
# WHY THIS EXISTS, <phone>. S3 counted unpushed commits with no ownership
# check at all, so it reported another session's branch as work on MY floor. I
# then "cleared" it by pushing two branches I did not write, in two repos I was
# never asked to touch. The owning session's own words afterwards: "Fixed forward
# in 5757b39 rather than rewriting, since you had already published it." That is
# the harm, exactly. Publishing someone's branch is not additive from where they
# stand: it converts a local amend or rebase into a force-push and takes the
# choice away. the owner: "u literally commited what session collide sh is built to
# prevent". A guard that PRESSURES the violation it exists to prevent is worse
# than no guard.
#
# The commit ledger behind `guild-session.sh --who` cannot decide this: checked
# on this session's own three most recent commits and all three came back
# "unattributed", so trusting it would mark my own work foreign and leave real
# unbacked commits sitting on this laptop, which is the worse failure.
# `session-collide.sh --owner` reads a ledger that DOES resolve, naming the
# session that made HEAD and counting the other live sessions in the repo.
#
# Conservative by design: anything not positively mine is a NOTE, never a
# blocking SIGNAL. A wrong "not yours" costs a line the owner reads. A wrong "yours"
# costs another session their history.
_commits_are_mine() {
  local repo="$1" out me
  me="$(printf '%s' "$SID" | cut -c1-8)"
  out="$(bash "$HOME/.claude/hooks/session-collide.sh" --owner "$repo" 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1          # silence is never the answer; treat as foreign
  # HEAD attributed to another session settles it.
  if printf '%s' "$out" | grep -q 'made by claude session'; then
    printf '%s' "$out" | grep 'made by claude session' | grep -q "$me" && return 0
    return 1
  fi
  # Unattributed HEAD: mine only if no other session is live in this repo.
  # grep -i, because the verdict prints "NO other live session in this repo" and
  # a case-sensitive match reported my OWN repo as foreign on the first try.
  printf '%s' "$out" | grep -qi 'no other live session' && return 0
  return 1
}

# S3: commits that exist but were never pushed.
#
# <phone>, the owner: "from now on, no need permissions from me to push". That
# makes pushing part of finishing in exactly the way committing already was, so
# commits sitting ahead of a configured upstream are work left on the floor, not
# a decision waiting on his call. Without this the hook had a hole big enough to
# drive the whole session through: it would block on one dirty file while waving
# through 19 finished commits that never left the machine.
#
# <phone>, the owner: "didnt i tell u to always push". The original "no upstream
# -> stay silent" guard below was wrong, and wrong in the worst direction. It
# conflated two situations that could not be less alike:
#
#   a repo with no remotes at all -> genuinely local-only, nothing to push to.
#   a repo WITH a remote whose branch tracks nothing -> a whole branch of work
#                                    that exists on no machine but this one.
#
# The second is the highest-risk state in the whole check, and it was the one
# case guaranteed to pass silently: every ahead/behind count is computed against
# @{upstream}, which ERRORS on a branch that has none, so the counts never exist
# and the branch reads as clean. That is exactly how finished commits on a fresh
# integration/ branch left this session unflagged -- strictly worse than the "19
# commits never pushed" hole this block was added to close, because there the
# counts at least existed to be compared.
#
# So: no upstream is quiet ONLY when there is no remote. Otherwise count commits
# reachable from HEAD but from no remote ref at all (--not --remotes), which is
# upstream-independent and still needs no network.
#
# Remaining guard, still deliberate:
#   behind > 0   -> the branch has diverged. A push would be rejected, and the
#                   right move is a human look at the divergence, not a demand
#                   to push. Same invariant auto-push.sh holds: never force past
#                   a remote that moved.
#
# No network call here, on purpose. A Stop hook must not fetch: it would add
# latency to every single stop and fail differently when offline. This reads the
# local tracking ref, which can be stale. Stale means quiet, and quiet is the
# safe direction for a gate whose failure mode is blocking the session.
while IFS= read -r REPO_ROOT; do
  [ -n "$REPO_ROOT" ] || continue
  skip_unless_cwd "$REPO_ROOT" && continue
  UPSTREAM="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"
  if [ -n "$UPSTREAM" ]; then
    AHEAD="$(git -C "$REPO_ROOT" rev-list --count "$UPSTREAM..HEAD" 2>/dev/null)"
    BEHIND="$(git -C "$REPO_ROOT" rev-list --count "HEAD..$UPSTREAM" 2>/dev/null)"
    case "${AHEAD:-}"  in ''|*[!0-9]*) AHEAD=0  ;; esac
    case "${BEHIND:-}" in ''|*[!0-9]*) BEHIND=0 ;; esac
    if [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -eq 0 ]; then
      if _commits_are_mine "$REPO_ROOT" "${UPSTREAM}..HEAD"; then
        SIGNALS="${SIGNALS}
  - ${AHEAD} commit(s) ahead of ${UPSTREAM} in $(basename "$REPO_ROOT"), committed but never pushed"
      else
        NOTES="${NOTES}
  - ${AHEAD} unpushed commit(s) in $(basename "$REPO_ROOT") are NOT yours. Leave them.
    Publishing another session's branch is not a favour: it takes away their
    option to amend or rebase, and forces a fix-forward instead."
      fi
    fi
  elif [ -n "$(git -C "$REPO_ROOT" remote 2>/dev/null)" ]; then
    # Remote exists but this branch tracks nothing: the branch lives only here.
    # --not --remotes needs no upstream and no network, just local remote refs.
    ORPHAN="$(git -C "$REPO_ROOT" rev-list --count HEAD --not --remotes 2>/dev/null)"
    case "${ORPHAN:-}" in ''|*[!0-9]*) ORPHAN=0 ;; esac
    if [ "$ORPHAN" -gt 0 ]; then
      BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
      if _commits_are_mine "$REPO_ROOT" "HEAD --not --remotes"; then
        SIGNALS="${SIGNALS}
  - ${ORPHAN} commit(s) on ${BRANCH} in $(basename "$REPO_ROOT") exist on no remote: branch has no upstream and was never pushed"
      else
        NOTES="${NOTES}
  - ${ORPHAN} commit(s) on ${BRANCH} in $(basename "$REPO_ROOT") exist on no remote and are
    NOT yours. Tell the owning session; do not push their branch for them."
      fi
    fi
  fi
done <<< "$REPO_ROOTS"

# S2a: STRUCTURED declaration of remaining work, a "Next steps:" header, a
# "TODO:" line, a bullet of leftovers. Anchored to start-of-line, so ordinary
# prose containing "next" or "remaining" does not trip it.
S2_HIT=""

# Before matching, remove text that is being QUOTED rather than asserted:
# fenced code blocks, inline `code spans`, and "double-quoted strings".
#
# This exists because the hook fired on its own documentation. Explaining what
# trips the gate necessarily involves writing the trigger phrases down, and the
# gate cannot tell the difference between declaring leftover work and quoting an
# example of someone declaring leftover work. Anything I quote is by definition
# not a statement about my own outstanding work, so quoted spans are excluded.
# Negated forms ("nothing left to do") are stripped here too, they assert the
# opposite and must not count.
S2_TEXT="$(printf '%s' "$LAST_TEXT" | python3 -c '
import re, sys
t = sys.stdin.read()
t = re.sub(r"```.*?```", " ", t, flags=re.S)      # fenced code blocks
t = re.sub(r"`[^`\n]*`", " ", t)                  # inline code spans
t = re.sub(r"\"[^\"\n]*\"", " ", t)               # "straight quotes"
t = re.sub("“[^”\n]*”", " ", t)    # curly quotes
t = re.sub(r"[Nn]o(thing| items| work| SKUs)? (left to do|still need[s]? to|yet to (run|do|verify|commit|check))", " ", t)
sys.stdout.write(t)
' 2>/dev/null)"
# If that filter failed for any reason, fall back to the raw text rather than
# silently matching against an empty string (which would disable S2 entirely).
[ -n "$S2_TEXT" ] || S2_TEXT="$LAST_TEXT"

# Ordered-list markers added <phone>. Latent hole, found while diagnosing the
# S2f miss and verified separately: "- Next steps" was caught, "1. Next steps"
# was not, though numbered lists are the more common way to write a plan. This
# did NOT cause that miss and is not credited with it.
if hit "$S2_TEXT" '^[[:space:]]*(([-*+]|[0-9]{1,2}[.)])[[:space:]]*)?(\*\*)?(next( up| step)?s?\b|still (need|to do|outstanding|open)|remaining\b|todo\b|not yet (done|run|checked)|left to do)'; then
  S2_HIT="1"
fi

# S2b: PROSE admission mid-sentence ("...done for now. Still need to run the
# crawl."). Deliberately a short, high-precision list: each phrase states that
# a specific action has not happened yet. Broader wording ("remaining",
# "next") is NOT included here: unanchored it produces false positives on
# ordinary description, and a gate that cries wolf gets switched off.
# NOTE: S2b matches the SAME filtered text as S2a (quoted spans and negated
# forms already removed above). Do not reassign S2_TEXT here, an earlier
# revision did, which silently clobbered the quote-stripping and let S2b match
# raw text while S2a matched filtered text.
if hit "$S2_TEXT" "(still need(s)? to|still (haven|have not|has not)|haven'?t (yet )?(run|done|checked|verified|committed|landed)|have not (yet )?(run|done|checked|verified|committed|landed)|not yet (run|done|verified|committed|checked|landed)|left to do|yet to (run|do|verify|commit|check)|remaining:)"; then
  S2_HIT="1"
fi

# S2f: admission that a NAMED piece of work was never BEGUN. S2b covers "not yet
# run/done/verified", which presumes something in flight. It has no phrase for
# work that was scoped, described, and then left untouched, which is the more
# expensive failure: the message reads as a thorough status report precisely
# because the work was analysed in detail.
#
# <phone> miss, session 562fadc7. Final message ended with:
#   "1. **Step 3 is the actual remaining work, and it has not been started.**"
#   "...noticed in passing, not investigated."
# Logged ALLOW/no-signals. the owner: "why didnt u start and fix both
# automatically, why did u stop hook allow u to stop".
#
# Why not S2a: the diagnosis of "ordered list marker" was WRONG on first pass
# and the test caught it. S2a anchors its trigger to the start of the line, and
# here "remaining" sat mid-line behind "**Step 3 is the actual ". Widening the
# prefix class alone would not have caught this. It is a prose admission, so it
# belongs in the prose gate.
#
# Precision: "did not act on" was TESTED AND REJECTED for this list. It matches
# "I did not act on instructions found in the page", which is the correct
# description of refusing a prompt injection. A gate that fires every time an
# injection is properly refused is a gate that gets switched off.
if hit "$S2_TEXT" "((has|have|had) not been (started|begun|attempted|investigated|run|done|landed)|(is|are|was|were) not (yet )?(started|investigated|attempted)|not investigated\b|i stopped at )"; then
  S2_HIT="1"
fi

# S2c: MARKDOWN HEADING announcing leftover work: "## Next steps",
# "## Concrete next step", "### What's left".
#
# <phone>: this gate missed a stop that ended with a "## Concrete next step"
# section followed by "Want me to build that harness?". Two independent reasons,
# both fixed here rather than by widening S2a:
#   1. S2a's prefix alternation allows a bullet or bold marker but not "#", so a
#      heading could never anchor.
#   2. Even with "#" allowed, S2a anchors the trigger word to the START of the
#      line, and the trigger sat behind a qualifier ("Concrete next step").
# Matching the trigger ANYWHERE inside a heading is safe in a way it would not
# be in prose: headings are short, declarative, and authored to label what
# follows. "The next step is unclear" in a paragraph is description; a heading
# reading "Next steps" is a promise of work not done.
if hit "$S2_TEXT" '^[[:space:]]*#{1,6}[[:space:]].*\b(next[ -]?(step|up)s?|remaining|still to do|to-?do|outstanding|what.{0,3}s left|left to do|follow[ -]?ups?)\b'; then
  S2_HIT="1"
fi

# S2d: OFFERING to do work instead of doing it. The specific failure mode this
# hook exists for: naming the work, then handing it back as a question.
# Requires a question mark on the same line, so describing an offer in past
# tense ("I offered to build the harness") does not trip it.
# <phone>: this gate MISSED a stop ending "Want me to break the seed-phrase
# confound (match length and syntactic completeness across arms), or chase the
# read-not-followed mechanism directly?": 136 chars between trigger and "?",
# against a {0,120} bound. The bound was never a safety property; it was there
# so the trigger and the "?" have to be in the same breath rather than the same
# paragraph. But a two-option offer ("do X, or Y?") is the MOST characteristic
# form of this failure and is always long. Note the offer that escaped was mine,
# and a tighter bound rewards verbosity: the wordier the hand-back, the likelier
# it slips the gate.
#
# HARD CEILING 255: DO NOT RAISE. First fix widened this to {0,400}, which
# made the gate strictly WORSE than the bug it fixed. This hook runs under
# /usr/bin/grep (BSD grep 2.6.0-FreeBSD), whose RE_DUP_MAX is 255:
#     $ grep -qE 'a[^?]{0,400}\?'  ->  "maximum repetition exceeds 255", rc=2
# rc=2 is not "no match", it is a compile error, but `if ... ; then` treats any
# nonzero identically, so S2d silently never fired at all, and the log said
# "no-signals" rather than reporting an error, because stderr was discarded.
# The interactive shell hides this: there `grep` is ugrep 7.5.0, which accepts
# {0,400} happily, so the pattern tests green by hand and dead in the hook.
# 240 covers the 136-char miss above with headroom and stays under the cap.
# If a longer bound is ever genuinely needed, use [^?]* with a different
# anchor: do not reach for a bigger number.
if hit "$S2_TEXT" '(want me to|shall i|should i|would you like me to|do you want me to)[^?]{0,240}\?'; then
  S2_HIT="1"
fi

# S2e: DECLARATIVE hand-back: "say the word and I'll ...". Same failure mode
# as S2d (name the work, hand it back) but phrased as a STATEMENT, so it ends in
# a period and S2d's mandatory "?" could never match it. It sat inside S2d's
# alternation as dead weight until <phone>, when the log showed two
# consecutive ALLOW/no-signals stops that both named outstanding work:
#   08:50:48 "...say the word and I'll start on either."
#   08:52:07 "Say the word and I'll fix it while the research runs."
# No {0,N} bound here on purpose: nothing to bound, and every bound in this
# file is one BSD-grep RE_DUP_MAX incident waiting to happen. The phrase is
# idiomatic enough to carry its own precision; it does not occur in ordinary
# description of past work the way "want me to" can.
if hit "$S2_TEXT" "(say the word and i)"; then
  S2_HIT="1"
fi

# S2g: CONDITIONAL hand-back: work is named, then made contingent on the owner
# asking for it. Same failure as S2d (question form) and S2e ("say the word"),
# in the one phrasing that escapes both: there is no "?" for S2d to anchor on
# and no fixed idiom for S2e to match. Found by auditing the ALLOW/no-signals
# stops in this log (125 of them against 284 blocks):
#   <phone>:06:22  "...live provider state won. If you want, I"
#   <phone>:02:15  "...no history behind it. Still think that's worth fixing, and sti"
#   <phone>:46:07  "...and the allow-list version of the stop hook. If you want the literal"
# Each named real outstanding work and stopped on it. Each logged no-signals.
#
# No {0,N} bound anywhere in this gate, for the reason spelled out at S2d:
# every bound in this file is one BSD-grep RE_DUP_MAX incident waiting to happen.
#
# Precision, and why "worth" is not matched bare: "worth fixing" is an offer,
# but "worth 3 hours", "worth it in the end" and above all "that WAS worth
# fixing" (a description of work already finished) are not. BSD grep has no
# lookbehind, so the exclusion is positive: the gerund must sit behind an
# explicit present-tense marker.
#
# The first version of this gate wrote that marker as (it|that|this).{0,3}s,
# meaning to cover the apostrophe in "that's". The test below caught it firing
# on "That was worth fixing, and I fixed it.": .{0,3} spans " wa" quite happily,
# so "that was" matched the exact case the comment claimed to exclude. A
# wildcard standing in for one specific character will also stand in for the
# thing you were trying to exclude. The apostrophe is now literal, and
# is|are|still carry a \b so "analysis worth doing" cannot match the "is" inside
# "analysis".
# Shared verb list for the "worth <gerund>" forms in S2g and S2h. It started as
# the literal three verbs S2g was born with (fixing|doing|chasing), which is
# exactly as wide as the three log lines that prompted S2g and no wider. The
# <phone> miss was "Worth ADDING the mirror pushes": a verb nobody had
# thought of yet, in a gate whose whole job is catching work handed back. Naming
# the list once means the next missing verb is a one-word fix in one place
# instead of a divergence between two gates that drift apart silently.
S2_ACTION="adding|automating|building|chasing|checking|cleaning|deleting|doing|fixing|hardening|implementing|migrating|parking|patching|refactoring|removing|revisiting|running|scripting|testing|updating|wiring"

if hit "$S2_TEXT" "(if you want|if you.d like|((it|that|this)['’]s|\b(is|are|still)) worth (${S2_ACTION}))"; then
  S2_HIT="1"
fi

# S2h: DEFERRED IMPROVEMENT. Work is named, correctly diagnosed, sized, and then
# filed as advice for a future pass instead of being done. Added <phone>,
# the owner: "from next time, the stop hook shd implement [these] instead of
# waiting for the next pass".
#
# The stop that prompted it ended:
#   "Two things worth your attention, neither blocking:
#      - deploy.sh only pushes origin. That's the root cause of a 458-commit
#        drift on codeberg ... Worth adding the mirror pushes ...
#      - The propagation lag ... If you want deploy verification to be
#        trustworthy, it needs a settle delay or a cache-bypass fetch"
#
# That stop DID trip S2g, but only on the incidental "If you want" in the SECOND
# bullet. Delete four words and the whole thing sails through: "Worth adding X"
# matched nothing, "worth your attention" matched nothing, "neither blocking"
# matched nothing. The gate caught it by luck rather than by design, and a gate
# that works by luck logs a false negative the first time the phrasing shifts.
# This closes the forms S2d/S2e/S2g were never shaped for: no question mark for
# S2d to anchor on, no "say the word" idiom for S2e, and no present-tense marker
# in front of "worth" for S2g.
#
# Why "neither blocking" is a trigger and not a mitigation: declaring the work
# non-blocking is the MECHANISM of the deferral, not an excuse for it. The two
# items above were one mirror-push line and one settle delay. Both were smaller
# than the paragraph written to explain postponing them.
#
# "non-blocking" is deliberately NOT matched: it is ordinary vocabulary for
# async I/O and would fire on any technical discussion of it. Only the
# self-referential "neither/nothing/none of them ... blocking" forms count.
#
# No {0,N} bound anywhere in this gate, for the reason spelled out at S2d: every
# bound in this file is one BSD-grep RE_DUP_MAX incident waiting to happen.
#
# Anchoring on (a): sentence-initial or bullet-initial only, because that is
# where a deferral announces itself. Bare mid-sentence "worth adding" is left to
# S2g, which demands an explicit present-tense marker and so will not fire on
# "that was worth adding", a description of finished work. BSD grep has no
# lookbehind, so the exclusion has to be positional.
if hit "$S2_TEXT" "(^|[.!?][[:space:]])[[:space:]]*(\*\*)?worth (${S2_ACTION})\b"; then
  S2_HIT="1"
fi
if hit "$S2_TEXT" "worth (your (attention|time)|a look|another look)"; then
  S2_HIT="1"
fi
if hit "$S2_TEXT" "(neither|nothing|none of (them|these|which)) blocking\b"; then
  S2_HIT="1"
fi
if hit "$S2_TEXT" "((for|in|on) (the )?next (pass|session|round|go)\b|future work\b|down the line\b|at some point\b|when you get a chance\b)"; then
  S2_HIT="1"
fi

# S2i: BARE LEFTOVER LIST. Added <phone>, the owner: "the stop hook shd flag both
# items as smt u can do without my approval ... make the stop hook stricter so u
# dont stop so easily".
#
# Every gate above keys on an IDIOM of deferral: "worth adding", "if you want",
# "next pass", "neither blocking". The stop that prompted this one used none of
# them. It shipped a working dedupe guard for the enrich lane and then closed with
# a plain inventory:
#   "Remaining: apply the same guard to run_draft.sh, and scope CODEX_HOME per lane."
# No hedge, no idiom, nothing for S2d-S2h to anchor on. Just a heading and two
# named edits, in two files already open, that took nine minutes to do the
# following turn. A gate that only recognises apologetic deferral will always miss
# the confident kind, and the confident kind is the common kind.
#
# Anchored to line/sentence/bullet start or a colon, because that is where an
# inventory heading lives. Mid-sentence "the remaining rows were merged" is prose
# about finished work and must not fire.
if hit "$S2_TEXT" "(^|[.!?][[:space:]])[[:space:]]*(\*\*|- |[0-9]+\. )?(remaining|outstanding|still to do|left to do|next steps?|follow-?ups?|open items?|todo)\b"; then
  S2_HIT="1"
fi
if hit "$S2_TEXT" "\b(follow-?ups?|next steps?|still to do|left to do|open items?|not yet done)[[:space:]]*:"; then
  S2_HIT="1"
fi

# S2j: THE SIBLING FIX. The sharpest form of the same miss, and worth its own gate
# because it is self-refuting: to write the sentence you must already know the
# file, the change, and that they match. Diagnosis IS the work here; what is left
# is retyping a known edit into a named path. If you can say "run_draft.sh needs
# the same guard", you are strictly closer to having applied it than to having
# explained why you did not.
#
# The <phone> draft-lane case also shows why deferring this is not neutral: the
# guard as written would have dropped 28/28 draft targets, because a draft target
# is already present in out/enr* by construction. Left as a follow-up it reads as a
# tidy copy-paste; done in the same session it surfaces as a scoping bug that
# silently produces zero output. Handing the sibling fix back defers the DISCOVERY,
# not just the typing.
# Two arms, both requiring a DEFERRAL, added <phone> after this clause blocked a
# compliant close-out on the sentence "Same guard had a real gap: find -exec sed -i
# edited every hook." That is a report of work FINISHED, and the bare noun phrase
# could not tell it apart from work handed onward. Describing a fix in terms of the
# guard it duplicates is the normal way to write a DONE line, so the old pattern taxed
# accurate reporting and pushed the next writer toward vaguer prose.
# Arm 1: a transfer verb before the noun ("apply the same guard to run_draft.sh").
# Arm 2: the deferral after it ("the same fix elsewhere", "belongs in", "needs to be").
# 16-case probe incl. the two real <phone> deferrals this clause was written for:
# tests/stop-justify-test.sh, cases s2j-*.
if hit "$S2_TEXT" "(^|[^[:alpha:]])(appl|port|cop|extend|replicat|mirror|repeat|reus|us|need|require|want|deserve|belong|wire|add|giv|scope)[a-z]*[^.!?]{0,40}same +(fix|guard|change|patch|treatment|approach|edit|scoping|reasoning)"; then
  S2_HIT="1"
fi
if hit "$S2_TEXT" "same +(fix|guard|change|patch|treatment|approach|edit|scoping|reasoning)[^.!?]{0,60}(elsewhere|everywhere|as well|too|later|pending|outstanding|unapplied|to do\b|to go\b|next (pass|session|round)|the (other|others|rest|remaining)|belongs? (in|on|to)|wants? (appl|port|do|copy)|needs? (appl|port|do|copy|to be)|(should|could|ought to|would) (also )?(be|go|get)|has yet to|remains to)"; then
  S2_HIT="1"
fi
# No third arm for a marker BEFORE the noun ("TODO: same guard for X", "Left to
# do: the same guard on X"). One was written <phone> and deleted the same
# hour: a mutant with it removed still blocked all four of its own test cases,
# because the S2a next-steps clause and arm 2's "the rest" already had them. It
# would have been an arm that could never be shown to fire, which is the exact
# decoration this file's own README warns about. The tests stay, the arm does not.
# Bare "left" and bare "still" are the reason such an arm is also risky: "Left
# the tests green and the same guard verified" is a report of finished work.
if hit "$S2_TEXT" "(needs|need|requires|require|wants) the same\b"; then
  S2_HIT="1"
fi
if hit "$S2_TEXT" "(should|could|can|ought to) also be (applied|added|scoped|done|fixed|wired|patched)\b"; then
  S2_HIT="1"
fi
if hit "$S2_TEXT" "(not yet|has not been|still needs to be|remains to be) (applied|wired|scoped|added|ported|copied)\b"; then
  S2_HIT="1"
fi

if [ -n "$S2_HIT" ]; then
  SIGNALS="${SIGNALS}
  - the final message names work that is still outstanding, then stops"
fi

# Nothing to answer for, a clean stop rearms the guard like any other allow.
# Log the TAIL of the final message, not the head: hand-backs live in the last
# line ("...directly?"), so a head-truncated line would hide the thing an audit
# is looking for.
# Foreign unpushed commits are reported, never blocked on. Printing to stderr on
# the ALLOW path keeps the information without turning someone else's branch into
# a reason to refuse this session's stop, which is how those branches got pushed
# in the first place. Silence was the alternative and silence is what let a
# foreign edit get swept into a commit on <phone>.
if [ -n "${NOTES:-}" ]; then
  printf 'stop-justify NOTE, not blocking:%s\n' "$NOTES" >&2
fi

[ -z "$SIGNALS" ] && allow_stop ALLOW \
  "no-signals | tail: $(printf '%s' "$LAST_TEXT" | tr '\n' ' ' | tail -c 200)"

# ---- guard 4: per-complaint lifetime cap (<phone>, derived from history) --
# Guard 2 counts CONSECUTIVE blocks and decays on every allowed stop, so the
# interleaved pattern block,block,allow,block,block,allow never reaches 3. The
# log shows the consequence: 26 CAP firings against 661 blocks, while a single
# complaint recurred up to 16 times in one session.
#
# Number chosen from the recurrence hazard over 533 per-complaint instances:
#   after 1 occurrence  P(recurs) = 0.26
#   after 2 occurrences P(recurs) = 0.55
#   after 3 occurrences P(recurs) = 0.81   <- and 0.85-0.90 thereafter, never falls
# A complaint that has been blocked three times has ~85% odds of simply being
# blocked again. Blocking a fourth time buys turns, not compliance.
#
# Behaviour at the cap: pass THIS complaint through and keep gating everything
# else. The counter is per signal hash and per session, and deliberately NOT
# cleared by allow_stop, which is exactly how it differs from guard 2.
PERSIST_MAX=3
SIGHASH="$(printf '%s' "$SIGNALS" | { md5 -q 2>/dev/null || md5sum 2>/dev/null | cut -d' ' -f1; })"
case "${SIGHASH:-}" in ''|*[!0-9a-f]*) SIGHASH='' ;; esac
if [ -n "$SIGHASH" ]; then
  SIG_FILE="$STATE_DIR/$SID.sig.$SIGHASH"
  _sn="$(cat "$SIG_FILE" 2>/dev/null)"
  case "${_sn:-}" in ''|*[!0-9]*) _sn=0 ;; esac
  if [ "$_sn" -ge "$PERSIST_MAX" ]; then
    allow_stop PERSIST-CAP "same complaint blocked $_sn times this session, passing through | $(printf '%s' "$SIGNALS" | tr '\n' ' ' | cut -c1-120)"
  fi
  printf '%s' "$((_sn + 1))" > "$SIG_FILE" 2>/dev/null || true
  find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
fi

# ---- block --------------------------------------------------------------------
printf '%s %s\n' "$((COUNT + 1))" "$NOW" > "$COUNT_FILE" 2>/dev/null
printf '%s | %s | BLOCKED |%s\n' "$(date '+%F %T')" "$SID" \
  "$(printf '%s' "$SIGNALS" | tr '\n' ' ' | cut -c1-300)" >> "$LOG" 2>/dev/null

# ---- standing guidance: deliver once, re-deliver after compaction ------------
# Measured across 1,451 transcripts: 1,089 refusals, 79% byte-identical, and the
# static tail below accounted for ~647,399 tokens of WITHIN-SESSION repeats
# (80% of its own bytes). It persists in context once delivered, so re-sending it
# carries no new information until a compaction drops it. Compaction is
# observable: paired system/compact_boundary + user/isCompactSummary records.
# The SIGNALS above are short and differ every time, so they always ship in full.
# Fail-safe: unreadable transcript or non-numeric count re-delivers the full text.
COACH_FULL="$(cat <<'COACHEOF'
Answer both, then act:
  1. Why stop HERE? Name what makes this a boundary and not just a pause.
  2. Why can you not continue? If the blocker is the owner's decision, an external
     dependency, or a genuinely ambiguous requirement, say which.

If it is none of those, continue the work instead of reporting on it. Committing
finished code is not a separate task needing permission: it is part of finishing,
and so is pushing it. the owner does not gate routine pushes (CLAUDE.md, AUTO-PUSH
IS THE DEFAULT), so "waiting for the go-ahead to push" is not a reason to stop.
Genuine prod hazards (unapplied migration, destructive DDL, secrets in the diff)
are still worth raising before the push. Routine permission asks are not.

A NAMED EDIT IN A FILE YOU ALREADY TOUCHED IS NOT A FOLLOW-UP. If you can write
"X needs the same guard" or "still to scope Y", you have already done the hard
part: you know the file, the change, and that it applies. What is left is typing.
Deferring it also defers DISCOVERY, which is the real cost: on <phone> the
sibling fix handed back as copy-paste turned out to drop 28 of 28 targets when
actually applied, a silent-zero-output bug that only surfaced by doing it. An
identical fix to a sibling file, a scoping change, a config default, a guard you
just wrote for one lane and not its twin: these are not the owner's decisions and
never needed his approval. Since <phone> this is enforced rather than
advised: a named-not-done item that mentions a file this session edited does not
pass on STOPPING alone. Type the fix, or classify it with a NOT-TYPING: line.

REVERSIBLE OPTIONS ARE NOT A DECISION TO HAND BACK. If the choice is between N
approaches and each one is cheap to undo (a file copy, a branch, a scratch dir),
building all N and measuring them beats describing them and waiting. the owner picks
between outcomes, not between guesses. Present a decision only when trying it is
expensive, destructive, or the criterion itself is his to set.

FINISHING MEANS FINISHING WHAT WAS ASKED. Everything above bounds HOW you finish
the task; none of it widens WHAT the task is. Work you discovered but were not
asked to do is not on the floor: name it in one line and stop. Cheap to undo is
not free -- the scarce resource is the owner's review attention and the diff noise
he has to read, not your effort, so an unrequested fix still spends something he
did not agree to spend. Bytes you did not write are not yours to finish either:
ask the ledger, and if an uncommitted edit is not attributable to you, leave it
alone and say whose it looks like rather than sweeping it into your commit.
"He asked X, I did X, I noticed Y and left it named" is a complete answer and a
legitimate STOPPING reason, not a lazy one.

BEFORE BLAMING ANOTHER SESSION, ASK THE LEDGER. "Not my work, another session
has it in flight" is a claim with a tool behind it. hooks/session-collide.sh
--owner <path> lists the sessions live in that path's repo and names who last
committed the path itself; it resolves the repo from the ARGUMENT, so it works
from any cwd. hooks/guild-session.sh --who <sha> resolves one commit, and
hooks/guild-session.sh list shows who is live. All three ALWAYS print: empty
output is never the answer, and if you get silence, treat the tool as broken
rather than reading it as "nobody else is here". --owner was implemented
<phone>; before that it silently exited 0 and manufactured false negatives.
<phone> miss: a STOPPING was filed on that reasoning when the ledger said no
other session was live in the repo at all, and the changes were this same
agent's, from 10h earlier.

AND CHECK THE CONSTRAINT IS REAL. Before optimising toward a number, grep for the
thing that enforces it. Same day: 3.9KB of memory entries were queued for deletion
to get under a 17510 byte cap that no hook, script, or config anywhere defines.

If stopping really is right, say so on its own line:
  STOPPING: <reason>
(Logged to ~/.claude/stop-justify.log and auditable. STOPPING is a real outcome,
not a confession. "He asked X, I did X, I noticed Y and left it named" is
exactly what the line is for, and filing it is finishing, not quitting. What the
log watches for is the other shape: a reason that names work you could simply
have done. Both get written down; only one of them is a miss.)
COACHEOF
)"
COACH_PTR="(Standing guidance omitted: delivered earlier this session and still in
context. It re-delivers after a compaction. Source: hooks/stop-justify.sh.)"
COACH="$COACH_FULL"
COACH_STATE="$STATE_DIR/$SID.coach"
if [ -n "${TRANSCRIPT:-}" ] && [ -r "${TRANSCRIPT:-}" ]; then
  _nc="$(grep -c '"subtype":"compact_boundary"' "$TRANSCRIPT" 2>/dev/null)"
  case "${_nc:-}" in ''|*[!0-9]*) _nc='' ;; esac
  if [ -n "$_nc" ]; then
    if [ "$(cat "$COACH_STATE" 2>/dev/null)" = "$_nc" ]; then
      COACH="$COACH_PTR"
    else
      printf '%s' "$_nc" > "$COACH_STATE" 2>/dev/null || true
    fi
  fi
fi

REASON="Stop refused: work is still on the floor:
${SIGNALS}

${COACH}"

python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
' "$REASON"

exit 0
