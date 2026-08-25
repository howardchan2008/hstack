#!/bin/bash
# context-save.sh: Stop hook. Snapshots where work left off so the next session
# can resume instead of cold-starting (cuts cache_create on session sprawl).
# Writes ~/.claude/last-context.md. Fast, read-only on the repo. Never blocks Stop.
#
# Disable: touch /tmp/context-save-disabled

set -uo pipefail
[ -f /tmp/context-save-disabled ] && exit 0

OUT="$HOME/.claude/last-context.md"
CWD="$(pwd)"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

{
  echo "# Last context: $NOW"
  echo ""
  echo "cwd: $CWD"
  if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BR="$(git -C "$CWD" branch --show-current 2>/dev/null)"
    echo "repo: $(basename "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)")  branch: $BR"
    echo ""
    echo "## uncommitted (git status -s, top 20)"
    git -C "$CWD" status -s 2>/dev/null | head -20
    echo ""
    echo "## last 5 commits"
    git -C "$CWD" log --oneline -5 2>/dev/null
    # Two different questions, and `@{u}..` alone answers only one of them badly.
    # It ERRORS on a branch with no upstream, and 2>/dev/null turns that error into
    # "0 unpushed" for commits that exist nowhere but this disk. `HEAD --not --remotes`
    # needs no upstream and no network, and catches exactly that case.
    UNBACKED="$(git -C "$CWD" rev-list --count HEAD --not --remotes 2>/dev/null)"
    case "${UNBACKED:-}" in ''|*[!0-9]*) UNBACKED=0 ;; esac
    if git -C "$CWD" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
      UNPUSHED="$(git -C "$CWD" rev-list --count '@{u}..HEAD' 2>/dev/null)"
      case "${UNPUSHED:-}" in ''|*[!0-9]*) UNPUSHED=0 ;; esac
    else
      UNPUSHED=$UNBACKED
    fi
    [ "$UNPUSHED" != "0" ] && echo "" && echo "⚠ $UNPUSHED unpushed commit(s) on $BR"
    [ "$UNBACKED" != "0" ] && echo "⚠ $UNBACKED commit(s) on NO remote at all (lost if this disk dies)"
  else
    echo "(not a git repo)"
  fi
} > "$OUT" 2>/dev/null

exit 0
