#!/bin/bash
# context-restore.sh: SessionStart hook. If a fresh (<24h) last-context.md exists,
# surface a short "where you left off" so the session resumes without re-explaining.
# Outputs SessionStart additionalContext JSON. Silent if stale/absent.
#
# Disable: touch /tmp/context-restore-disabled

set -uo pipefail
[ -f /tmp/context-restore-disabled ] && exit 0

# PREFER THIS REPO'S OWN SNAPSHOT, added 2026-08-30. The global file is written
# by whichever session stopped last, and with five to ten concurrent sessions
# across different repos that is almost never this one. A premier-trophy session
# was restoring hstack's git log and reading it as its own memory, which is
# worse than restoring nothing: it is another repo's state presented as context.
REPO_SLUG="$(basename "$(pwd)" 2>/dev/null | tr -c 'A-Za-z0-9._-' '-' | tr -d '\n')"
SRC="$HOME/.claude/context/${REPO_SLUG}.md"
if [ ! -f "$SRC" ]; then
  # THE FALLBACK REOPENED THE HOLE. Written an hour earlier the same day, it
  # sent any repo with no snapshot of its own to the global file, and the
  # global file is whatever repo stopped last. A negative control caught it
  # immediately: a fresh directory restored premier-trophy's memory as its own.
  #
  # So the global copy is now read ONLY when there is no repo identity to
  # mismatch, i.e. the session is not inside a git work tree. Inside a repo
  # with no snapshot the correct output is silence.
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0
  fi
  SRC="$HOME/.claude/last-context.md"
fi
[ -f "$SRC" ] || exit 0
[ -L "$SRC" ] && exit 0

# Freshness: < 24h
AGE=$(( $(date +%s) - $(stat -f %m "$SRC" 2>/dev/null || echo 0) ))
# 7 DAYS, widened 2026-08-30. The 24h cap made sense when this file was GLOBAL:
# a day-old snapshot from whichever repo stopped last is noise. Now that it is
# per-repo, the opposite is true. A Friday session's state is exactly what the
# Monday session in that repo needs, and the block prints its own age so a stale
# one is visible rather than silently authoritative.
[ "$AGE" -gt 604800 ] && exit 0

# Read, cap, strip control bytes + quotes/backslashes for safe JSON embedding.
# 3000, raised from 1200 on the same day the file started carrying his last ask
# and the last close-out. At 1200 the git log filled the budget and the two
# useful sections were cut off, which would have shipped the fix and kept the
# symptom.
BODY=$(head -c 3000 "$SRC" 2>/dev/null | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')
[ -z "$BODY" ] && exit 0

HRS=$(( AGE / 3600 ))

# The saved cwd is where the LAST session's shell ended up, not where this one starts.
# Sessions launched at $HOME would otherwise inherit a repo/branch/status banner for a
# directory they are not in. Say so explicitly rather than letting it read as current.
SAVED_CWD=$(sed -n 's/^cwd: //p' "$SRC" 2>/dev/null | head -1)
HERE="$(pwd)"
if [ -n "$SAVED_CWD" ] && [ "$SAVED_CWD" != "$HERE" ]; then
  WARN="NOTE: this session's cwd is ${HERE}, NOT the ${SAVED_CWD} recorded below. The repo/branch/git-status lines describe the PREVIOUS session's directory. cd deliberately before acting on them. "
else
  WARN=""
fi
WARN=$(printf '%s' "$WARN" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')

MSG="[RESUME] Prior session context (${HRS}h ago), use to continue, don't re-explore: ${WARN}${BODY}"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$MSG"
exit 0
