#!/bin/bash
# context-restore.sh: SessionStart hook. If a fresh (<24h) last-context.md exists,
# surface a short "where you left off" so the session resumes without re-explaining.
# Outputs SessionStart additionalContext JSON. Silent if stale/absent.
#
# Disable: touch /tmp/context-restore-disabled

set -uo pipefail
[ -f /tmp/context-restore-disabled ] && exit 0

SRC="$HOME/.claude/last-context.md"
[ -f "$SRC" ] || exit 0
[ -L "$SRC" ] && exit 0

# Freshness: < 24h
AGE=$(( $(date +%s) - $(stat -f %m "$SRC" 2>/dev/null || echo 0) ))
[ "$AGE" -gt 86400 ] && exit 0

# Read, cap, strip control bytes + quotes/backslashes for safe JSON embedding.
BODY=$(head -c 1200 "$SRC" 2>/dev/null | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')
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
