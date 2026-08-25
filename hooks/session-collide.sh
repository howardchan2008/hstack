#!/usr/bin/env bash

# PROVENANCE, added <phone>. the corpus sizes and the named example transcripts were measured 2026-07 against the then-live transcript tree.
# That tree is NOT the corpus any more: transcript-archive moved 3,638 of the
# 3,857 transcripts to ~/Archive/claude-transcripts on <phone>, so the live
# tree is about 6% of sessions. These numbers are HISTORICAL and are not
# reproducible as stated. Re-derive across BOTH trees before citing them; see
# ~/.claude/bin/claims-audit and hooks/lib/probe-dedupe-backtest.py for the shape.
# session-collide.sh: detect concurrent-session / worktree work overlap in the
# current git repo, and tell Claude to register the claim via guild.
#
# WHY THIS EXISTS
#   guild is a voluntary quest/lore registry. It has no visibility into git
#   state, worktrees, or running processes, so it cannot *detect* duplication.
#   Detection has to happen at the git/process layer. guild is the *response*:
#   once real overlap is found, the claim gets posted so other agents see it.
#
# TWO INDEPENDENT DETECTORS
#   A. cross-worktree content overlap: same path, different bytes, >1 tree.
#   B. same-tree HEAD drift: HEAD moved between two runs of MY session, i.e.
#      another writer committed into the one tree I am working in.
#   B exists because A is structurally blind at TREE_COUNT=1. See <phone>.
#
# FALSE-POSITIVE GUARDS  (learned the hard way, <phone>)
#   1. gitignored paths force-added into a worktree index are NOT a collision.
#      a venture bootstraps SOT.md + docs/ into every worktree index; both
#      worktrees showed 59-68 "staged" files that were pure noise.
#   2. Same path in two worktrees with an IDENTICAL blob hash is NOT a
#      collision. Same bytes cannot conflict.
#   Only "same path, different content, >1 tree" counts.
#   3. Your OWN commit must never read as drift. Refresh mode absorbs it.
#
# MODES
#   default            warn, exit 0, never blocks
#   COLLIDE_BLOCK=1    exit 2 on real collision (blocks the tool call)
#   COLLIDE_DEBUG=1    show why things were filtered out
#   COLLIDE_REFRESH=1  re-stamp HEAD, print nothing, exit 0
#   COLLIDE_SESSION=x  override session identity (tests)
#
# Wired at SessionStart, PreToolUse(Write|Edit), and PostToolUse(Bash) in
# refresh mode. Result cached briefly so it does not re-scan on every
# keystroke-level edit. Drift is exempt from that cache.

set -uo pipefail

# ---- --owner <path>: ownership query (read-only, never silent) -------------
# WHY THIS IS A REAL SUBCOMMAND NOW (<phone>).
#   stop-justify.sh told every session to test "is someone else working here"
#   with `session-collide.sh --owner <path>`. No such flag existed. This file
#   is a hook and took no arguments at all, so the flag fell through, the
#   is-inside-work-tree guard below exited 0 against whatever cwd the caller
#   happened to have, and the caller got EMPTY OUTPUT AND SUCCESS. That reads
#   as "nobody else is here", which is the single most dangerous answer to
#   that question: it is the green light to revert a co-worker's commit.
#
#   Three invariants matter more than the feature:
#     1. ALWAYS print. Silence is never a valid answer to an ownership query.
#     2. Resolve the repo from the ARGUMENT, never from cwd. The caller that
#        exposed this ran from $HOME, which is not a repo at all.
#     3. Strictly read-only. A query that touched the drift stamps would mask
#        the very event it was asked to explain.
#   Liveness uses GUILD_SESSION_STALE and the same sess-* roster that
#   guild-session.sh writes, so the two tools cannot disagree about who is live.
#   Unrecognised arguments get the same treatment. All three wired call sites
#   pass zero arguments (COLLIDE_REFRESH=1 is env, not a flag), so any argument
#   at all is a human or agent typing at this script, and falling through to
#   detection would reproduce the original silent-exit-0 bug for every typo.
case "${1:-}" in
  ""|--owner) ;;
  --*)
    echo "session-collide.sh: unknown flag: $1"
    echo "usage: session-collide.sh --owner <path>"
    echo "  (hook invocations take no arguments; refresh mode is COLLIDE_REFRESH=1)"
    exit 0 ;;
  *)
    echo "session-collide.sh: unexpected argument: $1"
    echo "usage: session-collide.sh --owner <path>"
    exit 0 ;;
esac

if [ "${1:-}" = "--owner" ]; then
  QPATH="${2:-}"
  if [ -z "$QPATH" ]; then
    echo "usage: session-collide.sh --owner <path>"
    echo "  Reports which claude sessions are live in the repo containing <path>,"
    echo "  and which session last committed <path> itself."
    echo "  For a single commit, use: guild-session.sh --who <sha>"
    exit 0
  fi
  command -v git >/dev/null 2>&1 || { echo "$QPATH: git unavailable, ownership unresolvable"; exit 0; }
  [ -e "$QPATH" ] || { echo "$QPATH: no such file or directory, ownership unresolvable"; exit 0; }

  if [ -d "$QPATH" ]; then QDIR="$QPATH"; else QDIR="$(dirname "$QPATH")"; fi
  QROOT="$(git -C "$QDIR" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$QROOT" ]; then
    echo "$QPATH: not inside a git repository, so there is no session ownership data"
    exit 0
  fi

  QKEY="$(printf '%s' "$QROOT" | shasum | awk '{print $1}')"
  QROSTER="${GUILD_HOME:-$HOME/.guild}/sessions/$QKEY"
  QLEDGER="$QROSTER/commits.log"
  QSTALE="${GUILD_SESSION_STALE:-7200}"
  # --owner exits before the stdin parse further down, so the env-only lookup left
  # ME empty under a real hook invocation: the self-exclusion at "fid = ME" below
  # never fired and this session was counted and printed as a foreign one. The
  # error ran toward false positives (alone in a repo still reported "1 other
  # live session"), which is the direction that teaches you to ignore the verdict.
  . "${BASH_SOURCE[0]%/*}/session-identity.sh"
  guild_resolve_session_id
  ME="$SESSION_ID"
  # CALLER IDENTITY IS A SEPARATE AXIS FROM OWNER IDENTITY (<phone>).
  # The <phone> fix taught this tool that an unknown OWNER is not "nobody".
  # It never learned the mirror case: an unknown CALLER is not "everyone else".
  # With ME empty the "$fid" = "$ME" test below cannot match, so every live
  # session counts as foreign, and this session's own commits print without the
  # THIS-session marker, and the ABSENCE of that marker is what reads as
  # "someone else's". Measured on this very file: identified prints "3 other
  # live session(s)", the same run unidentified prints "4", and the 4th is the
  # caller. Same shape as guild-session.sh --who calling your own commit
  # concurrent work. Silence about who is asking is not permission to assume
  # it is not you.
  ME_KNOWN=1; [ -z "$ME" ] && ME_KNOWN=0
  NOW="$(date +%s)"

  echo "repo: $QROOT"

  OTHER_LIVE=0
  SELF_LIVE=0
  COLD=0
  for f in "$QROSTER"/sess-*; do
    [ -f "$f" ] || continue
    fid="$(sed -n 's/^sid=//p' "$f" 2>/dev/null | head -1)"
    [ -n "$fid" ] || continue
    seen="$(sed -n 's/^last_seen=//p' "$f" 2>/dev/null | head -1)"
    fcwd="$(sed -n 's/^cwd=//p' "$f" 2>/dev/null | head -1)"
    [ -n "$seen" ] || seen=0
    age=$(( NOW - seen ))
    if [ "$age" -ge "$QSTALE" ]; then COLD=$(( COLD + 1 )); continue; fi
    if [ "$fid" = "$ME" ]; then
      SELF_LIVE=1
      printf '  LIVE  session %s  %sm ago  cwd %s   <- THIS session\n' \
        "$(printf '%s' "$fid" | cut -c1-8)" "$(( age / 60 ))" "${fcwd:-?}"
    else
      OTHER_LIVE=$(( OTHER_LIVE + 1 ))
      printf '  LIVE  session %s  %sm ago  cwd %s\n' \
        "$(printf '%s' "$fid" | cut -c1-8)" "$(( age / 60 ))" "${fcwd:-?}"
    fi
  done
  [ "$COLD" -gt 0 ] && echo "  ($COLD cold roster entr(y/ies) older than ${QSTALE}s, not counted)"
  [ "$OTHER_LIVE" -eq 0 ] && [ "$SELF_LIVE" -eq 0 ] && \
    echo "  (no roster entries: no hooked session has run in this repo yet)"

  # Who last committed the path itself. Repo root asks about HEAD instead.
  if [ -d "$QPATH" ] && [ "$(cd "$QDIR" 2>/dev/null && pwd)" = "$QROOT" ]; then
    SCOPE="HEAD of repo"
    LASTLINE="$(git -C "$QROOT" log -1 --format='%H%x09%s' 2>/dev/null)"
  else
    SCOPE="last commit touching $QPATH"
    LASTLINE="$(git -C "$QROOT" log -1 --format='%H%x09%s' -- "$QPATH" 2>/dev/null)"
  fi
  if [ -n "$LASTLINE" ]; then
    lsha="$(printf '%s' "$LASTLINE" | cut -f1)"
    lsubj="$(printf '%s' "$LASTLINE" | cut -f2-)"
    lown="$(grep -m1 "^$lsha" "$QLEDGER" 2>/dev/null | cut -f2)"
    echo "$SCOPE:"
    echo "  $(printf '%s' "$lsha" | cut -c1-8)  $lsubj"
    if [ -n "$lown" ]; then
      if [ "$ME_KNOWN" -eq 0 ]; then
        # Never let a MISSING marker carry the meaning "not yours". Without an
        # id the two cases are indistinguishable, so say that instead of
        # picking the one that reads as an accusation.
        echo "  made by claude session $(printf '%s' "$lown" | cut -c1-8)"
        echo "  owner UNRESOLVED relative to you: no CLAUDE_SESSION_ID /"
        echo "  COLLIDE_SESSION in env and no hook payload on stdin, so this"
        echo "  cannot tell whether that session is you. If it is, this is YOUR"
        echo "  commit and the hands-off rule below does not apply to it."
        echo "  Re-run identified before concluding otherwise:"
        echo "    COLLIDE_SESSION=<your-sid> session-collide.sh --owner <path>"
      elif [ "$lown" = "$ME" ]; then
        echo "  made by claude session $(printf '%s' "$lown" | cut -c1-8)   <- THIS session"
      else
        echo "  made by claude session $(printf '%s' "$lown" | cut -c1-8)"
      fi
    else
      echo "  UNATTRIBUTED: no hooked session recorded this commit. the owner by hand,"
      echo "  or a session running without these hooks. Still not yours to rewrite."
    fi
  else
    echo "$SCOPE: no commits found"
  fi

  # ---- uncommitted edits: attribute the dirty working tree ------------------
  # git attributes only what is committed. A path edited but not yet committed
  # has no sha, so the verdict below used to fall back on a guess: "most likely
  # YOURS". That guess is exactly how one session sweeps another's in-flight
  # work into its own commit.
  #
  # Transcripts are the only durable record of who touched a file BEFORE it was
  # committed: every Edit/Write/MultiEdit tool call carries an absolute
  # file_path. Two rules keep the attribution honest:
  #   Reads are excluded. A session that merely read the file is not an editor.
  #   An earlier attempt matched any "file_path" and counted readers as authors.
  #   Failed edits are excluded, by dropping tool_use ids whose tool_result came
  #   back is_error. An edit that errored did not change the file.
  # Do NOT regex the JSON for this. Key order inside "input" is not stable
  # ("replace_all" can precede "file_path"), so a positional pattern silently
  # misses real edits. Narrow with grep, then decide with a real JSON parse.
  #
  # Blind spot, declared rather than hidden: a write made by a shell heredoc,
  # by sed, or by an unhooked session leaves no tool_use record and reports
  # UNATTRIBUTED. That means unknown. It never means "nobody, so take it".
  DIRTY="$(git -C "$QROOT" status --porcelain --untracked-files=all -- "$QPATH" 2>/dev/null)"
  if [ -z "$DIRTY" ]; then
    echo "uncommitted edits: none, working tree is clean for this path"
  elif ! command -v python3 >/dev/null 2>&1; then
    echo "uncommitted edits: PRESENT, but python3 is unavailable so they cannot be"
    echo "  attributed here. Do not read that absence as \"they are mine\"."
  else
    echo "uncommitted edits:"
    # SINGLE-PASS TRANSCRIPT MAP (<phone>). The find+grep below used to run
    # once PER DIRTY FILE, re-reading the whole transcript corpus every time:
    # O(dirty files x corpus). Profiled here, 8 dirty files x 5.3s = 45s, which
    # blew risk-checkpoint's 30s ledger budget, so every force-push printed
    # LEDGER UNAVAILABLE and the roster never arrived. No timeout value fixes
    # that: the cost scales with how dirty the tree is, so a bigger number only
    # moves the cliff.
    #
    # MEASURED, NOT ASSUMED, and the obvious fix is the WRONG one, which is
    # exactly why it is written down here. Replacing the N per-file greps with
    # ONE grep over the union of all patterns is SLOWER. BSD grep -F does not
    # fold N fixed patterns into a single automaton; its cost scales with the
    # pattern count. On this corpus (47 files, 586 MB, 2-day window):
    #       2 patterns  ->   5.3s
    #      36 patterns  ->  44.4s
    # so the union pass costs more than all the passes it replaces. It was
    # tried and measured end to end at 57s, worse than the 45s it was meant to
    # fix. Do not retry it. Prefiltering on the repo root fails for a different
    # reason: 39 of 47 transcripts mention this repo, so it drops 5% of the
    # bytes and buys nothing.
    #
    # ripgrep DOES fold the patterns (Aho-Corasick, parallel): the same sweep
    # is 0.04s, and one pass emits the whole transcript->path map, so the loop
    # below becomes a lookup and reads the corpus ZERO further times.
    #
    # rg is a brew package, not a guarantee. If it is absent we fall back to
    # the original per-file grep: slow, but correct. Correctness must not
    # depend on the fast path being installed.
    OWNER_SCAN_DAYS="${OWNER_SCAN_DAYS:-2}"
    COLLIDE_PROJECTS_DIR="${COLLIDE_PROJECTS_DIR:-$HOME/.claude/projects}"
    # EMPTY IS AN ANSWER, NOT A FAILURE (<phone>). The branch below used to
    # be selected by [ -n "$COLLIDE_MAP" ], which cannot distinguish "rg ran and
    # found no transcript touching this path" from "rg never ran". Those need
    # OPPOSITE handling: the first is the final answer (this path is genuinely
    # UNATTRIBUTED), the second needs the slow grep. Conflating them meant every
    # unattributed path paid a full BSD-grep corpus sweep to rediscover the
    # nothing that rg had already established. Profiled on this box: 5.63s of a
    # 5.83s --owner call was that fallback, with rg having already run and
    # correctly returned empty, and rg itself measured 0.05s at 4, 16 or 64
    # patterns. That single conflation is why attribution looked expensive
    # enough to need a per-path cap in stop-justify.sh.
    #
    # So track whether the fast path RAN, not whether it MATCHED. If rg is
    # present but broken, this now reports UNATTRIBUTED instead of scanning,
    # which is the degrade direction this file already commits to everywhere
    # else: unknown is acceptable, a false "this is yours" is not.
    COLLIDE_MAP=""
    COLLIDE_MAP_READY=0
    if command -v rg >/dev/null 2>&1; then
      RGARGS=()
      while IFS= read -r uline; do
        [ -n "$uline" ] || continue
        urel="${uline:3}"; urel="${urel##* -> }"
        urel="${urel%\"}"; urel="${urel#\"}"
        uabs="$QROOT/$urel"
        # Same both-spellings rule as GARGS below; see the PATH SPELLING note.
        case "$uabs" in
          /private/*)           ualt="${uabs#/private}" ;;
          /tmp/*|/var/*|/etc/*) ualt="/private$uabs" ;;
          *)                    ualt="" ;;
        esac
        RGARGS+=(-e "\"file_path\":\"$uabs\"" -e "\"notebook_path\":\"$uabs\"")
        [ -n "$ualt" ] && RGARGS+=(-e "\"file_path\":\"$ualt\"" -e "\"notebook_path\":\"$ualt\"")
      done <<UNIONEOF
$DIRTY
UNIONEOF
      # Guard BOTH empties. `xargs -0 rg` with no file arguments does not
      # no-op, it runs rg against stdin and the hook hangs until its timeout.
      CORPUS="$(find "$COLLIDE_PROJECTS_DIR" -maxdepth 2 -name '*.jsonl' -type f \
                     -mtime -"$OWNER_SCAN_DAYS" -print 2>/dev/null || true)"
      if [ -n "$CORPUS" ] && [ ${#RGARGS[@]} -gt 0 ]; then
        COLLIDE_MAP="$(printf '%s\n' "$CORPUS" | tr '\n' '\0' \
                       | xargs -0 rg -F -o -H -N --no-heading "${RGARGS[@]}" 2>/dev/null \
                       | sort -u || true)"
      fi
      # rg was available and the corpus was enumerated, so the map is
      # authoritative even when it is empty. An empty CORPUS is also an answer:
      # no transcript exists inside the window, so no candidate can exist, and
      # falling through would run xargs with zero files -- the documented hang
      # guarded against just above.
      COLLIDE_MAP_READY=1
    fi
    while IFS= read -r dline; do
      [ -n "$dline" ] || continue
      dst="${dline:0:2}"
      drel="${dline:3}"
      drel="${drel##* -> }"
      drel="${drel%\"}"; drel="${drel#\"}"
      dabs="$QROOT/$drel"
      if [ ! -e "$dabs" ]; then
        printf '  %s %s   (deleted from working tree)\n' "$dst" "$drel"
        continue
      fi
      printf '  %s %s   modified %s\n' "$dst" "$drel" \
        "$(stat -f '%Sm' -t '%H:%M:%S' "$dabs" 2>/dev/null || echo '?')"
      # Only transcripts touched inside the scan window can explain a dirty
      # file, and the full corpus is thousands of files / gigabytes. This
      # prefilter is what keeps the query interactive.
      #
      # PATH SPELLING. git reports the realpath'd root (/private/tmp/x) while a
      # tool call records the path as it was typed (/tmp/x). On macOS /tmp and
      # /var are symlinks into /private, so grepping one literal spelling finds
      # nothing and prints UNATTRIBUTED, which reads as "nobody edited this"
      # when it actually means "I looked under the wrong name". So: grep every
      # plausible spelling to find candidates, then let python decide by
      # realpath, which is spelling-independent.
      case "$dabs" in
        /private/*)           dalt="${dabs#/private}" ;;
        /tmp/*|/var/*|/etc/*) dalt="/private$dabs" ;;
        *)                    dalt="" ;;
      esac
      GARGS=(-e "\"file_path\":\"$dabs\"" -e "\"notebook_path\":\"$dabs\"")
      [ -n "$dalt" ] && GARGS+=(-e "\"file_path\":\"$dalt\"" -e "\"notebook_path\":\"$dalt\"")
      # SCAN WINDOW. Measured <phone>: grep is the entire cost of this query.
      # The 7-day corpus is 1325 files / 1.6 GB and takes 15s; the 2-day corpus
      # is 26 files / 262 MB and takes 2.4s. The find traversal itself is 0.03s
      # and the JSON parse of the surviving candidates is 0.03s, so neither is
      # worth optimising and the window is the only lever that matters.
      #
      # Two days is the right default because a DIRTY file is by definition
      # in-flight work. Narrowing degrades toward UNATTRIBUTED, never toward a
      # false "this is yours", so the failure direction stays conservative.
      # But the UNATTRIBUTED message below must then name the window, or an
      # edit that is merely OLD reads identically to one made by hand.
      OWNER_SCAN_DAYS="${OWNER_SCAN_DAYS:-2}"
      # COLLIDE_PROJECTS_DIR: tests only, same role as COLLIDE_SESSION above.
      # The harness must be able to plant a transcript somewhere private; the
      # alternative is writing fake sessions into the real ~/.claude/projects,
      # where they would be picked up by every OTHER live session's --owner scan
      # and have to be cleaned up correctly on every failure path.
      COLLIDE_PROJECTS_DIR="${COLLIDE_PROJECTS_DIR:-$HOME/.claude/projects}"
      # LOOKUP, not a corpus read. The single rg pass above already recorded
      # which transcripts mention this path, under either spelling, so reuse
      # GARGS unchanged and strip the ":<matched pattern>" suffix rg appends to
      # each line to recover the transcript path.
      if [ "$COLLIDE_MAP_READY" = 1 ]; then
        CANDS="$(printf '%s\n' "$COLLIDE_MAP" | grep -F "${GARGS[@]}" 2>/dev/null \
                 | sed -E 's/:"(file_path|notebook_path)":".*$//' \
                 | sort -u || true)"
      else
        # rg absent. Original behaviour: one full corpus pass per dirty file.
        CANDS="$(find "$COLLIDE_PROJECTS_DIR" -maxdepth 2 -name '*.jsonl' -type f \
                   -mtime -"$OWNER_SCAN_DAYS" -print0 2>/dev/null \
                 | xargs -0 grep -l -F "${GARGS[@]}" 2>/dev/null || true)"
      fi
      # COMMITTED EDITS ARE NOT IN FLIGHT. Without this cutoff the query names
      # every session that touched the path inside the window, including ones
      # whose work is already in HEAD, so a file with any history reads as
      # contended and the warning gets ignored. Found <phone> on this very
      # file: two sessions were reported as holding it while their edits were
      # committed. The dirty bytes can only have been written after the last
      # commit that touched the path, so that commit's time is the floor.
      # Untracked file -> no such commit -> 0 -> keep everything.
      #
      # CONTENT BEATS CLOCK, because the clock alone is WRONG here. That floor
      # is a time proxy for "this edit is already committed", and the proxy
      # breaks in exactly the case this tool exists for: a CONCURRENT session
      # commits this same path for an unrelated reason, its timestamp becomes
      # the floor, and every other session's still-dirty edit sinks below it.
      # Measured <phone> on this very file. Session a4949e8b committed
      # 6481fc6 at 17:31:39 touching tests/risk-checkpoint-test.sh; session
      # e0d86b2a's 17:29:49 edit introduced RC_HOOK_UNDER_TEST, a string that
      # commit does not contain anywhere. That edit was live, uncommitted, and
      # 110 seconds too early, so the query answered "unknown, not nobody"
      # about bytes it could have named. That is silence, and this file's
      # policy is to degrade toward naming too many, never toward silence.
      #
      # So pass the HEAD blob and let python settle it by content: is this
      # edit's own inserted text in HEAD, or only in the worktree? That is
      # immune to who else committed the path and when. The clock stays as the
      # fallback for edits whose text cannot be recovered.
      CUT="$(git -C "$(dirname "$dabs")" log -1 --format=%ct -- "$dabs" 2>/dev/null || true)"
      [ -n "$CUT" ] || CUT=0
      HEADBLOB="$(mktemp "${TMPDIR:-/tmp}/collide-head-XXXXXX")"
      git -C "$QROOT" show "HEAD:$drel" > "$HEADBLOB" 2>/dev/null || : > "$HEADBLOB"
      # SHELL-WRITE LEDGER (<phone>). Effect-recorded writers for this path,
      # most recent first, deduped. Consulted by the python below ONLY when the
      # transcript scan produced no rows, so tool-call evidence keeps priority
      # and this can never override a named writer.
      SHELL_WRITERS=""
      _WLOG="${GUILD_HOME:-$HOME/.guild}/sessions/$QKEY/writes.log"
      if [ -f "$_WLOG" ]; then
        SHELL_WRITERS="$(awk -F'\t' -v r="$drel" '$1==r{print $2"|"$3}' "$_WLOG" \
          | sort -t'|' -k2,2nr | awk -F'|' '!seen[$1]++' | head -6 | tr '\n' ' ')"
      fi
      export SHELL_WRITERS
      # shellcheck disable=SC2086
      python3 - "$dabs" "$(stat -f %m "$dabs" 2>/dev/null || echo 0)" "$ME" "$OWNER_SCAN_DAYS" "$CUT" "$HEADBLOB" $CANDS <<'ATTR'
import json,sys,os,datetime,re
target=sys.argv[1]; mtime=float(sys.argv[2]); me=sys.argv[3]
days=sys.argv[4]; cut=float(sys.argv[5] or 0); headblob=sys.argv[6]; cands=sys.argv[7:]
def _slurp(p):
    try:
        with open(p,errors="replace") as fh: return fh.read()
    except OSError:
        return ""
HEADTXT=_slurp(headblob); WTTXT=_slurp(target)
EDIT={"Edit","Write","MultiEdit","NotebookEdit"}
# Shortest inserted fragment trusted as a fingerprint. Below this a string like
# "}" or "return" occurs everywhere, would match HEAD by coincidence, and would
# mark a live edit committed. Too short to judge falls through to the clock.
MINFRAG=12
def _texts(i):
    # Only text this edit INSERTED. old_string is worthless for this question:
    # it is in HEAD either way, so it cannot separate committed from dirty.
    out=[]
    for k in ("new_string","content","new_source"):
        v=i.get(k)
        if isinstance(v,str): out.append(v)
    e=i.get("edits")
    if isinstance(e,list):
        for d in e[:20]:
            if isinstance(d,dict) and isinstance(d.get("new_string"),str):
                out.append(d["new_string"])
    return out
def _frags(strs):
    # Per LINE, never the whole new_string as one substring.
    #
    # Caught <phone> by tests/session-collide-test.sh case 1, against the
    # first version of this very content test. An Edit inserting
    #     "line1\nZZQQ_MARKER"
    # no longer appears verbatim in a worktree that reads
    #     "line1\nunrelated-concurrent-work\nZZQQ_MARKER"
    # because the concurrent commit landed a line BETWEEN the anchor and the
    # inserted text. The blob match failed, the "all of it is in HEAD" match
    # failed too, and the edit fell through to the commit-clock fallback --
    # which is the precise bug this content test was written to remove. The
    # test passed only while nothing else touched the file, i.e. only in the
    # case that was never in dispute.
    #
    # A single inserted line is the right fingerprint: it survives arbitrary
    # edits ELSEWHERE in the file, which is exactly the interference we are
    # trying to be immune to. Stripped, so a reindent does not read as a
    # different line; length-filtered by MINFRAG, so "}" cannot match HEAD by
    # coincidence and retire a live edit.
    out=[]
    for s in strs:
        if not isinstance(s,str): continue
        for ln in s.splitlines():
            ln=ln.strip()
            if len(ln)>=MINFRAG: out.append(ln)
    return out
# Compare by realpath, never by string: the same file is spelled /tmp/x by the
# tool call and /private/tmp/x by git. basename first, because realpath() is a
# syscall and the basename check rejects almost everything for free.
RP=os.path.realpath(target); BN=os.path.basename(target)
def ep(ts):
    try:
        return datetime.datetime.strptime(ts[:19],"%Y-%m-%dT%H:%M:%S").replace(
            tzinfo=datetime.timezone.utc).timestamp()
    except Exception:
        return 0.0
TSRE=re.compile(r'"timestamp":"([^"]+)"')
rows=[]; stale=[]
# RESUMED TRANSCRIPTS INHERIT THEIR PARENT'S RECORDS VERBATIM, and the copy is
# not marked as a copy: sessionId is REWRITTEN to the heir, so one edit reads as
# several sessions' work. Measured <phone> on handoff/culver/READING-LIST.md.
# One Write, tool_use toolu_01CNVX72jUuWfcaULAxisJZE, stamped 05:38:32.808Z,
# present in transcripts 85565659, 339ecd2d and 32105b48 with each file's OWN
# sessionId written onto it. --owner reported three sessions holding the path,
# the owner was asked to arbitrate a collision that never happened, and the
# deliverable sat uncommitted for nine hours waiting on that non-question.
#
# Two things survive the copy and still identify the original:
#   tool_use id:  byte-identical in every heir, so it is a dedupe key
#   timestamp:    the ORIGINAL edit time, never rewritten to the resume time
# and an heir's own first record is stamped when the RESUME happened, which is
# necessarily after any work it inherited. So an edit stamped before this
# transcript's own first record cannot be this session's.
#
# Timestamps are NOT monotonic inside a resumed file: the resume meta lands
# first, then history replays carrying original stamps. 339ecd2d opens at
# 05:43:57 and then contains a 05:38:32 record. That is why this compares
# against the FIRST RECORD rather than assuming the file is ordered.
FILES=[]
for tf in cands:
    hits=[]; errids=set(); own_start=None
    try: fh=open(tf,errors="replace")
    except OSError: continue
    with fh:
        for line in fh:
            if own_start is None:
                # Cheap: the first stamp in the file is this session's start.
                # Avoids json-parsing every line of a large transcript.
                m=TSRE.search(line)
                if m: own_start=ep(m.group(1))
            if '"tool_use"' not in line and '"tool_result"' not in line: continue
            try: o=json.loads(line)
            except Exception: continue
            c=(o.get("message") or {}).get("content")
            if not isinstance(c,list): continue
            ts=o.get("timestamp","")
            for b in c:
                if not isinstance(b,dict): continue
                if b.get("type")=="tool_use" and b.get("name") in EDIT:
                    i=b.get("input") or {}
                    fp=i.get("file_path") or i.get("notebook_path")
                    if fp and os.path.basename(fp)==BN and os.path.realpath(fp)==RP:
                        hits.append((b.get("id"),ts,_texts(i)))
                elif b.get("type")=="tool_result" and b.get("is_error"):
                    errids.add(b.get("tool_use_id"))
    FILES.append((tf,own_start,hits,errids))

# One tool_use id belongs to exactly ONE session: the earliest-starting file
# carrying it, i.e. the one that did not inherit it. Ranking None as +inf keeps
# a file with no parseable stamp from claiming everything, while the "prev is
# None" arm guarantees every id still gets an owner even if EVERY file is
# unstamped. An id must never end up owned by nobody: that is silence, and
# silence is the one failure this file does not accept.
OWNER={}
for tf,own,hits,errids in FILES:
    rank=own if own else float("inf")
    for i,t,x in hits:
        if i is None: continue
        prev=OWNER.get(i)
        if prev is None or rank<prev[0]: OWNER[i]=(rank,tf)
DROPPED=0
for tf,own_start,hits,errids in FILES:
    kept=[]
    for i,t,x in hits:
        # Stamped before this transcript existed -> inherited, not its work.
        # 1s of slack absorbs same-second resume races.
        if own_start and ep(t) and ep(t)<own_start-1: DROPPED+=1; continue
        # Same edit already attributed to its originator.
        if i is not None and i in OWNER and OWNER[i][1]!=tf: DROPPED+=1; continue
        kept.append((i,t,x))
    hits=kept
    ok=[(t,x) for i,t,x in hits if i not in errids]
    # Is this edit still in flight? Ask the bytes, not the clock.
    #
    # An edit is LIVE when text it inserted is in the worktree and NOT in HEAD.
    # That is the definition of an uncommitted edit, stated directly instead of
    # inferred from a timestamp, and unlike the timestamp it does not care that
    # some other session committed this same path one minute ago.
    # Correspondingly it is COMMITTED when everything it inserted is already in
    # HEAD. Only when the edit's text cannot be recovered (no new_string, a
    # whole-file Write, a fragment too short to be distinctive) do we fall back
    # to the old commit-time floor.
    #
    # A timestamp that will not parse is still KEPT, and an edit we cannot
    # judge at all is still KEPT: the expensive failure here is telling the owner
    # nobody holds a path when somebody does, because that is how another
    # session's work gets committed under his name. Degrade toward naming too
    # many, never toward silence.
    live=[]; done=[]
    for t,strs in ok:
        u=_frags(strs)
        seen=[s for s in u if s in WTTXT and s not in HEADTXT]
        if seen: live.append(t); continue
        if u and all(s in HEADTXT for s in u): done.append(t); continue
        if ep(t)==0.0 or ep(t)>cut: live.append(t)
        else: done.append(t)
    if live:
        rows.append((max(live),os.path.basename(tf)[:-6],len(live),len(hits)-len(ok)))
    elif done:
        stale.append((max(done),os.path.basename(tf)[:-6]))
rows.sort(reverse=True); stale.sort(reverse=True)
if not rows:
    # Effect-recorded shell writes. CONSULTED IN BOTH no-row branches, and the
    # reason is a bug this very block was already caught missing (<phone>).
    # It first went into the `else` only -- the branch for a path with no edit
    # history at all -- so the motivating case still failed: a file that older
    # sessions HAD edited, then I shell-patched, has rows, they are all in HEAD,
    # and it lands in `stale` instead. That branch's own text names the answer
    # it is throwing away: "came from hand editing, a shell heredoc, or an
    # unhooked session: unknown, not nobody". When the ledger holds a record,
    # that is no longer unknown, so it must speak wherever the tool is about to
    # say it does not know. Verified against the real repo: this file, patched
    # by heredoc, was recorded correctly and printed nothing.
    sw=[x for x in os.environ.get("SHELL_WRITERS","").split() if x]
    if sw:
        print("    NO TOOL-CALL RECORD, but a SHELL WRITE was recorded here:")
        for item in sw:
            sid,_,ts=item.partition("|")
            try: when=datetime.datetime.fromtimestamp(float(ts)).strftime("%H:%M:%S")
            except Exception: when="?"
            m="   <- THIS session" if sid==me else ""
            print("      session %s  shell write %s%s" % (sid[:8],when,m))
        print("    Recorded by EFFECT, not by name: this path changed while that")
        print("    session ran a shell command (redirect, sed -i, heredoc), which")
        print("    writes no per-file record anywhere. WEAKER THAN A TOOL CALL: a")
        print("    concurrent write by another session inside the same window is")
        print("    misattributable here. Confirm before you act on it.")
    if stale:
        # Reached only when the file is dirty yet every recorded edit's text is
        # already in HEAD. Those two facts contradict, so do not present this
        # as a clean "nobody": name the sessions and let the owner adjudicate.
        print("    NOT IN FLIGHT: %d session(s) edited this path inside the last" % len(stale))
        print("    %s day(s), and every one of those edits appears in HEAD" % days)
        print("    already, so none of them explains the uncommitted bytes.")
        if not sw:
            print("    Those came from hand editing, a shell heredoc, or an")
            print("    unhooked session: unknown, not nobody. Last edit by each,")
            print("    in case the bytes are theirs after all:")
        if sw:
            print("    The shell write above is the better explanation for those")
            print("    bytes. Prior committed edits, for context only:")
        for ts,sid in stale[:6]:
            m="   <- THIS session" if sid==me else ""
            print("      %s  %s%s" % (datetime.datetime.fromtimestamp(ep(ts)).strftime("%H:%M:%S"),sid,m))
    else:
        if not sw:
            print("    UNATTRIBUTED: no hooked session recorded an Edit/Write to this")
            print("    path within the last %s day(s). Written by hand, by a shell" % days)
            print("    heredoc, by an unhooked session, or edited before that window.")
            print("    Widen with OWNER_SCAN_DAYS=<n>. This means unknown, not nobody.")
        # NO HOOKED WRITER IS NOT NO EVIDENCE. Unhooked writers (launchd jobs,
        # heredocs, hand edits) leave no per-write record anywhere, so the
        # transcript scan above can never attribute them, and OWNER_SCAN_DAYS
        # cannot either: widening only searches harder for a record that was
        # never written. The path's own commit history is the one source that
        # always exists. Print it as a LEAD, not a verdict: it deliberately
        # does NOT set an owner, because "last committer" is not "current
        # writer", and treating it as such is exactly the false positive this
        # tool exists to prevent.
        # Added <phone>: --owner returned a bare UNATTRIBUTED for all 85
        # dirty a venture paths, which is indistinguishable from a broken
        # tool and left the caller with nowhere to go next.
        # DO NOT print the git author here. Checked against the real repo
        # <phone>: every commit carries the owner's git identity no matter
        # which lane or agent wrote it, so an author column is constant, and
        # an "all one author => one lane" inference built on it is vacuous,
        # always true, and reads as evidence while carrying none. The lane
        # lives in the subject prefix before the colon ("data:", "plan:",
        # "checkpoint:"), which is what this repo actually commits under, so
        # that is what gets summarised, and only when the prefixes agree.
        try:
            import subprocess
            d=os.path.dirname(target) or "."
            h=subprocess.run(["git","-C",d,"log","-4","--format=%h|%s","--",target],
                             capture_output=True,text=True,timeout=5).stdout.strip().splitlines()
        except Exception:
            h=[]
        if h:
            print("    LEAD: last %d commit(s) touching this path (NOT an owner):" % len(h))
            lanes=[]
            for line in h:
                sha,_,s = line.partition("|")
                print("      %-10s %s" % (sha[:10], s[:64]))
                lanes.append(s.split(":",1)[0].strip().lower() if ":" in s else "")
            if lanes[0] and all(l==lanes[0] for l in lanes):
                print("    Every recent commit here is lane '%s:' => that lane" % lanes[0])
                print("    regenerates this path. Confirm before acting.")
            else:
                print("    Mixed or absent lane prefixes => no single regenerator.")
                print("    Read the subjects above and confirm before acting.")
    sys.exit(0)
for ts,sid,n,bad in rows:
    tag="  <- matches file mtime" if abs(ep(ts)-mtime)<=2 else ""
    mine="   <- THIS session" if sid==me else ""
    fail=f", {bad} failed" if bad else ""
    when=datetime.datetime.fromtimestamp(ep(ts)).strftime("%H:%M:%S")
    # FULL sid, not sid[:8]. Two reasons, both learned the hard way:
    # the stale printer above already prints it in full, so truncating here
    # made one fact render two ways depending on which branch you landed in;
    # and the id is meant to be pasted into `guild-session.sh --who`, which a
    # lopped-off prefix cannot be. Caught <phone> by case 1 of
    # tests/session-collide-test.sh, which greps for the id it planted.
    print(f"    session {sid}  {n} edit(s){fail}, last {when}{tag}{mine}")
ATTR
      rm -f "$HEADBLOB"
    done <<< "$DIRTY"
  fi

  if [ "$OTHER_LIVE" -eq 0 ]; then
    echo "verdict: NO other live session in this repo."
    echo "  \"another session has it in flight\" is NOT supported by the ledger."
    if [ "$ME_KNOWN" -eq 1 ]; then
      echo "  Any uncommitted edits above are attributed by session. If they name"
      echo "  only you, they are yours, possibly from hours ago."
    else
      # No id: "name only you" is a test this run cannot perform. Printing it
      # anyway is how a session talks itself into disowning its own edits.
      echo "  Uncommitted edits above are attributed by session, but this run has"
      echo "  no identity, so it CANNOT tell which of them are yours. Do not read"
      echo "  an unfamiliar sid as someone else's. Re-run identified to decide."
    fi
  else
    # "other" is a claim about identity, and line 136 can only make it when ME
    # is set: with no id nothing matches SELF, so the caller is counted here.
    # Call them live, not other, rather than assert what was never tested.
    if [ "$ME_KNOWN" -eq 1 ]; then
      echo "verdict: $OTHER_LIVE other live session(s) in this repo."
    else
      echo "verdict: $OTHER_LIVE live session(s) in this repo, one of which may be you."
    fi
    echo "  Concurrent commits are EXPECTED. Do NOT revert, amend, or force-push."
    echo "  Uncommitted edits above name the session that wrote them. Do NOT"
    echo "  commit a path attributed to another session: git add takes the file,"
    echo "  not your half of it, and their work lands under your name."
    if [ "$ME_KNOWN" -eq 0 ]; then
      echo "  CAUTION: this run has no identity. One of the sessions listed above"
      echo "  may BE you. Treat the hands-off rule as covering the others only"
      echo "  once you know which is which. Do not strand your own work on it."
    fi
    echo "  Resolve a specific sha with: guild-session.sh --who <sha>"
  fi
  exit 0
fi

CACHE_TTL="${COLLIDE_TTL:-60}"
STAMP_DIR="${TMPDIR:-/tmp}/claude-collide"
mkdir -p "$STAMP_DIR" 2>/dev/null || true

command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

PRIMARY="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$PRIMARY" ] || exit 0

KEY="$(printf '%s' "$PRIMARY" | shasum | awk '{print $1}')"
STAMP="$STAMP_DIR/$KEY"

# ---- session identity ------------------------------------------------------
# Needed to remember what HEAD looked like the last time THIS session ran. Env
# first (cheap, and what the tests drive); otherwise parse the hook's stdin
# payload, then a pid-anchored cache so a manual re-run from the Bash tool is
# still identified. An unidentified session simply skips the drift check:
# fail-safe means a missed warning, never a fabricated one.
. "${BASH_SOURCE[0]%/*}/session-identity.sh"
guild_resolve_session_id

# ---- detector B: same-tree HEAD drift --------------------------------------
# THE GAP THIS CLOSES (<phone>). Detector A's trigger is "same path,
# different content, in >1 worktree", which is UNSATISFIABLE when there is
# only one tree. That is precisely the topology that bit us: a second session
# committed a67c74d and 3b4432b into this very tree and pushed them, while
# this hook ran at SessionStart, printed nothing, and was correct by its own
# logic. Detection was never wrong; it was inapplicable.
#
# HEAD is the one piece of state that every session in a shared tree mutates
# and that all of them can observe. Remember it per session. If it moved
# between two of MY runs, some other writer advanced it.
#
# Self-commits do NOT trip this, because the hook is also wired at
# PostToolUse(Bash) in refresh mode, which fires immediately after a
# `git commit` and re-stamps before the next Write/Edit can compare. Without
# that wiring this check would fire on the utterly ordinary "commit, then keep
# editing" flow, and a detector that cries wolf on every commit is a detector
# that gets ignored. Same lesson as the process-count note further down.
HEAD_NOW="$(git -C "$PRIMARY" rev-parse HEAD 2>/dev/null || echo none)"
DRIFT=""
DRIFT_LOG=""
ALL_ATTRIBUTED=0
LEDGER="${GUILD_HOME:-$HOME/.guild}/sessions/$KEY/commits.log"
if [ -n "$SESSION_ID" ] && [ "$HEAD_NOW" != "none" ]; then
  SAFE_SID="$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_.-' '_')"
  HSTAMP="$STAMP_DIR/head-$KEY-$SAFE_SID"
  PREV=""
  [ -f "$HSTAMP" ] && PREV="$(cat "$HSTAMP" 2>/dev/null)"
  printf '%s' "$HEAD_NOW" > "$HSTAMP"
  if [ -n "$PREV" ] && [ "$PREV" != "$HEAD_NOW" ]; then
    if git -C "$PRIMARY" merge-base --is-ancestor "$PREV" "$HEAD_NOW" 2>/dev/null; then
      DRIFT="advanced"
      # NAME THE OWNER, do not merely report the movement (<phone>).
      # An anonymous sha is exactly what sends a session off investigating its
      # co-workers, and in the worst case reverting them. guild-session.sh
      # records sha -> session for every hooked session, so resolve it here and
      # let the report say "this is session X's work" instead of "something
      # happened". Unresolvable shas stay labelled UNATTRIBUTED: an honest
      # unknown is fine, a fabricated owner is not.
      DRIFT_LOG="$(git -C "$PRIMARY" log --format='%H %s' "$PREV..$HEAD_NOW" 2>/dev/null \
        | head -10 \
        | while read -r dsha dsubj; do
            downer="$(grep -m1 "^$dsha" "$LEDGER" 2>/dev/null | cut -f2)"
            if [ -n "$downer" ]; then
              printf '%s %s   [claude session %s]\n' \
                "$(printf '%s' "$dsha" | cut -c1-8)" "$dsubj" \
                "$(printf '%s' "$downer" | cut -c1-8)"
            else
              printf '%s %s   [UNATTRIBUTED]\n' \
                "$(printf '%s' "$dsha" | cut -c1-8)" "$dsubj"
            fi
          done)"
      if [ -n "$DRIFT_LOG" ] && ! printf '%s\n' "$DRIFT_LOG" | grep -q 'UNATTRIBUTED'; then
        ALL_ATTRIBUTED=1
      fi
    else
      # amend / rebase / reset landed under a live session. This is the variant
      # that actually destroys work rather than merely surprising you: the
      # commits you were building on may no longer exist.
      DRIFT="rewritten"
      DRIFT_LOG="  $PREV is no longer reachable from HEAD"
    fi
    [ -n "$DRIFT_LOG" ] || DRIFT_LOG="  (no commit range available)"
  fi
fi

# ---- shell-write ledger ----------------------------------------------------
# WHY THIS EXISTS (<phone>). Attribution reads transcripts for
# "file_path":"<abs>", a key only Edit/Write/MultiEdit/NotebookEdit record. A
# write made THROUGH Bash -- a > redirect, sed -i, cp, or a python heredoc
# calling open(p,"w") -- names its path nowhere the scan can see, so --owner
# returned UNATTRIBUTED for bytes a session demonstrably wrote. Caught on this
# very file: it was patched by a python heredoc, and --owner called the result
# unattributed while that patch was still sitting in the working tree.
#
# PARSING THE COMMAND STRING CANNOT FIX THIS, and it is worth being exact about
# why, because a redirect parser is the obvious wrong fix. The path that
# motivated this lived inside python source passed on stdin. It appears in no
# shell token at all. A parser good enough for `sed -i f` would still miss the
# case that produced the bug. So record the EFFECT, not the intent: after each
# Bash call, diff the repo's dirty tracked paths against a snapshot taken after
# this session's previous Bash call, and claim what changed.
#
# THIS IS A WEAKER EVIDENCE CLASS THAN A TOOL CALL and is labelled as such
# where it prints. A tool call NAMES its writer. This INFERS the writer from
# timing, so a concurrent write by another session inside the same window is
# misattributable. Two guards keep the inference honest: a session's first
# refresh only takes the snapshot and claims nothing (otherwise pre-existing
# dirt, possibly someone else's, is claimed wholesale at startup), and the read
# side consults this ledger ONLY when the transcript scan found nothing, so a
# real tool-call record always wins.
_record_shell_writes() {
  [ -n "${SESSION_ID:-}" ] || return 0
  [ -n "${PRIMARY:-}" ] || return 0
  [ -n "${KEY:-}" ] || return 0
  _wdir="${GUILD_HOME:-$HOME/.guild}/sessions/$KEY"
  mkdir -p "$_wdir" 2>/dev/null || return 0
  _snap="$_wdir/snap-$SESSION_ID"
  # Tracked-only: untracked churn is build output and scratch far more often
  # than authored work, and claiming it would bury the signal.
  _cur="$(git -C "$PRIMARY" status --porcelain --untracked-files=no 2>/dev/null \
    | while IFS= read -r _l; do
        _p="${_l:3}"; _p="${_p##* -> }"; _p="${_p#\"}"; _p="${_p%\"}"
        [ -n "$_p" ] || continue
        printf '%s\t%s\n' "$_p" "$(stat -f '%m:%z' "$PRIMARY/$_p" 2>/dev/null || echo 0:0)"
      done)"
  if [ -f "$_snap" ]; then
    _now="$(date +%s)"
    printf '%s\n' "$_cur" | while IFS= read -r _line; do
      [ -n "$_line" ] || continue
      grep -qxF "$_line" "$_snap" 2>/dev/null && continue
      _pp="$(printf '%s' "$_line" | cut -f1)"
      _fp="$(printf '%s' "$_line" | cut -f2)"
      # FIRST CLAIMER WINS. Without this the ledger is not merely imprecise,
      # it is systematically wrong, and it fails in exactly the topology this
      # tool exists for. A snapshot diff answers "changed since I last looked",
      # not "changed BY me". So every session whose snapshot predates a foreign
      # write claims that write on its next Bash call, and in a repo with three
      # live sessions attribution converges on everyone wrote everything.
      # Measured <phone> while verifying this very feature: g.txt was
      # shell-written once, by session aaaabbbb, and a later loop of unrelated
      # refreshes made deadbeef claim it too. Both names printed, one was false.
      #
      # The fingerprint (mtime:size) settles it, because ORDERING IS THE
      # EVIDENCE. The writer's own PostToolUse refresh fires milliseconds after
      # its write, in the same tool call. A foreign session cannot claim that
      # same content until its NEXT Bash call, which is strictly later. So the
      # first session to record a given path+fingerprint is the writer, and
      # every later observer of identical content is a bystander seeing the
      # same bytes. A residual race survives -- a foreign call ending inside
      # that millisecond gap -- and that is the honest width of this evidence
      # class, rather than the "everyone" it would otherwise report.
      if [ -f "$_wdir/writes.log" ] && awk -F'\t' -v p="$_pp" -v f="$_fp" \
           '$1==p && $4==f{hit=1} END{exit !hit}' "$_wdir/writes.log" 2>/dev/null; then
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' "$_pp" "$SESSION_ID" "$_now" "$_fp" \
        >> "$_wdir/writes.log"
    done
    # Bound it. Oldest entries are least useful: a dirty path stays dirty until
    # committed, so anything still live gets re-claimed by a newer entry.
    if [ "$(wc -l < "$_wdir/writes.log" 2>/dev/null || echo 0)" -gt 4000 ]; then
      tail -n 2000 "$_wdir/writes.log" > "$_wdir/writes.log.tmp" 2>/dev/null \
        && mv "$_wdir/writes.log.tmp" "$_wdir/writes.log" 2>/dev/null
    fi
  fi
  printf '%s\n' "$_cur" > "$_snap" 2>/dev/null
  return 0
}

# Refresh mode: absorb this session's own commit, say nothing, do not scan.
if [ -n "${COLLIDE_REFRESH:-}" ]; then
  # Runs BEFORE the exit: refresh fires on every PostToolUse Bash call, which
  # is exactly the event whose effect needs recording. Never fails the hook.
  _record_shell_writes || true
  exit 0
fi

# ---- cache -----------------------------------------------------------------
# Drift bypasses the cache deliberately. It is a one-shot edge, not a standing
# condition, so swallowing it for the rest of a TTL window loses the event
# outright rather than merely delaying it.
if [ -f "$STAMP" ] && [ -z "$DRIFT" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || echo 0) ))
  if [ "$AGE" -lt "$CACHE_TTL" ]; then
    # replay a previous positive finding; stay silent on a previous clean run
    [ -s "$STAMP" ] && cat "$STAMP"
    exit 0
  fi
fi
: > "$STAMP"

# ---- enumerate worktrees ---------------------------------------------------
TREES=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10)}')
TREE_COUNT=$(printf '%s\n' "$TREES" | grep -c . || true)

# ---- collect modified paths per tree, filtering ignored --------------------
# emit: <path>\t<blobhash>\t<tree>
WORK="$(mktemp)"; trap 'rm -f "$WORK" "$WORK.c" 2>/dev/null' EXIT

while IFS= read -r t; do
  [ -n "$t" ] || continue
  [ -d "$t" ] || continue
  git -C "$t" status --porcelain 2>/dev/null | while IFS= read -r line; do
    p="${line:3}"
    p="${p%% -> *}"                      # renames: keep destination side
    [ -n "$p" ] || continue
    # guard 1: ignored in the PRIMARY repo's rules -> bootstrap noise
    if git -C "$PRIMARY" check-ignore -q -- "$p" 2>/dev/null; then
      [ -n "${COLLIDE_DEBUG:-}" ] && echo "  filtered(ignored): $p [$t]" >&2
      continue
    fi
    # Hash the ACTUAL WORKING-TREE BYTES, not the index entry.
    #
    # Using `git ls-files -s` here was a real bug (caught in test, <phone>):
    # for an unstaged " M" file the index hash is still the HEAD blob, so two
    # worktrees branched from the SAME commit with different uncommitted edits
    # produce IDENTICAL hashes -> collision silently missed. That is the most
    # common concurrent-agent case (two agents spawned off main), i.e. the bug
    # would have blinded the detector exactly when it mattered most.
    if [ -f "$t/$p" ]; then
      h=$(shasum "$t/$p" 2>/dev/null | awk '{print $1}')
    else
      h="absent"   # deleted in this tree; still a claim on the path
    fi
    [ -n "$h" ] || h="unreadable"
    printf '%s\t%s\t%s\n' "$p" "$h" "$t"
  done
done <<< "$TREES" > "$WORK"

# ---- guard 2: same path must differ in content to count --------------------
COLLISIONS=$(
  awk -F'\t' '
    { seen[$1]=seen[$1] "\n" $2 "\t" $3; hash[$1"|"$2]=1; n[$1]++ }
    END {
      for (p in n) {
        c=0
        for (k in hash) { split(k,a,"|"); if (a[1]==p) c++ }
        if (n[p] > 1 && c > 1) print p
      }
    }
  ' "$WORK" | sort
)

# ---- other live claude processes rooted at this repo -----------------------
# COLLIDE_DEBUG gates the WHOLE sweep, not just the print. $OTHER is read in
# exactly one place (the debug line near the end of this file), and the note
# there explains why the count is deliberately not a trigger. Computing it
# unconditionally cost ~600ms per throttle window: one `lsof -a -p <pid> -d cwd`
# for every surviving pid (7 of 30 candidates here), every time the 60s cache
# expired, and then threw the answer away. Measured <phone>.
OTHER=0
if [ -n "${COLLIDE_DEBUG:-}" ] && command -v lsof >/dev/null 2>&1 && command -v pgrep >/dev/null 2>&1; then
  # Build the set of my own ancestors so the hook never counts itself.
  # `pgrep -f claude` matches any COMMAND LINE containing "claude", which
  # includes this very script (~/.claude/hooks/session-collide.sh) and every
  # bash/zsh subprocess it spawns. Without both guards below the hook reports
  # phantom "other sessions" on a completely idle repo.
  MINE=" "
  anc=$$
  for _ in <phone>; do
    [ -z "$anc" ] || [ "$anc" = "0" ] || [ "$anc" = "1" ] && break
    MINE="$MINE$anc "
    anc=$(ps -o ppid= -p "$anc" 2>/dev/null | tr -d ' ')
  done

  for pid in $(pgrep -f '[c]laude' 2>/dev/null | head -30); do
    case "$MINE" in *" $pid "*) continue ;; esac
    # require the real executable to be claude, not merely a path mentioning it
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | awk -F/ '{print $NF}')
    case "$comm" in
      claude|claude-code|node) ;;
      *) continue ;;
    esac
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/{print substr($0,2); exit}')
    [ "$cwd" = "$PRIMARY" ] && OTHER=$((OTHER+1))
  done
fi

# ---- report ----------------------------------------------------------------
HITS=$(printf '%s\n' "$COLLISIONS" | grep -c . || true)

# NOTE: process count is deliberately NOT a trigger, and is shown only under
# COLLIDE_DEBUG. A live `claude` process with its cwd here proves nothing about
# whether it is editing anything, and the desktop app's own bundled claude-code
# helper reliably matches, including this very session (the ancestor walk
# cannot see it; hooks spawn off a detached process tree). Reporting a phantom
# "1 other session" on every run is how a detector gets ignored. The worktree
# content check is evidence of WORK, which is the thing worth warning on.
if [ "$HITS" -eq 0 ] && [ -z "$DRIFT" ]; then
  if [ -n "${COLLIDE_DEBUG:-}" ]; then
    echo "[collide] clean, ${TREE_COUNT} worktree(s), no content-differing overlap" >&2
    [ -z "$SESSION_ID" ] && \
      echo "[collide] no session id resolved, HEAD-drift check skipped" >&2
  fi
  exit 0
fi

REPORT="$(mktemp)"
{
  echo "[SESSION-COLLIDE] concurrent work detected in $(basename "$PRIMARY")"
  if [ "$HITS" -gt 0 ]; then
    echo "  same path, DIFFERENT content, in >1 worktree:"
    printf '%s\n' "$COLLISIONS" | sed 's/^/    /'
  fi
  if [ "$DRIFT" = "advanced" ]; then
    echo "  HEAD MOVED since this session last looked. Another writer committed"
    echo "  into this shared tree:"
    printf '%s\n' "$DRIFT_LOG" | sed 's/^/    /'
    if [ "$ALL_ATTRIBUTED" = "1" ]; then
      echo "  Every commit above belongs to a known concurrent claude session."
      echo "  THIS IS EXPECTED WORK, NOT DAMAGE. Do not revert it, do not amend"
      echo "  it, do not reset, do not investigate it as a mystery. Rebase onto"
      echo "  it and continue your own task."
    else
      echo "  At least one commit above is UNATTRIBUTED: made by the owner by hand,"
      echo "  by an unhooked session, or recorded after this check ran. Still not"
      echo "  yours to rewrite. Identify it before building on it:"
      echo "    bash ~/.claude/hooks/guild-session.sh --who <sha>"
    fi
  elif [ "$DRIFT" = "rewritten" ]; then
    echo "  HEAD was REWRITTEN under this session (amend/rebase/reset by another"
    echo "  writer). Commits you were building on may be gone:"
    printf '%s\n' "$DRIFT_LOG" | sed 's/^/    /'
    echo "  Do NOT amend or force-push until you know whose rewrite this was."
  fi
  [ -n "${COLLIDE_DEBUG:-}" ] && [ "$OTHER" -gt 0 ] && \
    echo "  (debug only, NOT evidence: $OTHER claude proc(s) with cwd here)"
  echo
  echo "  ACTION: register the claim before editing these paths:"
  echo "    mcp__guild__guild_session_start(project=\"$(basename "$PRIMARY")\")"
  echo "    mcp__guild__quest_post(subject=\"<what you are about to change>\","
  echo "                           files=[<the paths above>])"
  echo "  guild is advisory, not a lock: agents that skip it will not see the"
  echo "  claim. If you need real exclusion, coordinate with the owner first."
} > "$REPORT"

cat "$REPORT"

# CACHE ONLY THE STANDING CONDITION.
# Detector A (content overlap) persists until someone resolves it, so replaying
# it inside the TTL window is correct. Detector B is a one-shot EDGE: HEAD moved,
# once. Caching that makes the next clean run replay a stale "HEAD MOVED" that
# refresh mode has already absorbed. That is exactly what broke tests C and E on
# the first cut of this change: C replayed B's report naming B's commit, long
# after the drift was resolved. Drift is reported, never cached.
if [ "$HITS" -gt 0 ]; then
  cat "$REPORT" > "$STAMP"
fi
rm -f "$REPORT"

if [ -n "${COLLIDE_BLOCK:-}" ]; then
  exit 2
fi
exit 0
