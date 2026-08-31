#!/bin/bash
# burn-context.sh: UserPromptSubmit hook.
# Injects current burn stats into Claude's context so the model SEES the cost
# before deciding to dispatch Agents.
#
# Output: additionalContext line prepended to user prompt.
#
# Cost profile (measured 2026-07-23): the recompute greps every *.jsonl under
# ~/.claude/projects modified in the last 8 days, several GB. Cold cost was
# 14.2s wall / 13.4s CPU, and it ran on a 15s TTL, i.e. on essentially every
# prompt, in the blocking path before the model saw anything.
#
# Fixed by:
#   1. TTL 15s -> 300s (dispatch counts do not move faster than that).
#   2. One grep pass instead of two (daily + weekly counted in a single awk).
#   3. Stale-while-revalidate: a stale cache is served INSTANTLY and the
#      recompute happens in the background. The prompt path never blocks.
#
# Disable: touch /tmp/burn-context-disabled

set -uo pipefail

[ -f /tmp/burn-context-disabled ] && exit 0

CACHE=/tmp/burn-context-cache.json
LOCK=/tmp/burn-context-refresh.lock
TTL=300          # seconds: cache considered fresh
LOCK_STALE=600   # seconds: abandoned refresh lock is ignored

RECOMPUTE_ONLY=0
[ "${1:-}" = "--recompute" ] && RECOMPUTE_ONLY=1

now() { /bin/date +%s; }
age_of() { echo $(( $(now) - $(/usr/bin/stat -f %m "$1" 2>/dev/null || echo 0) )); }

# ---------- fast path: serve cache, refresh in background if stale ----------
if [ "$RECOMPUTE_ONLY" -eq 0 ] && [ -f "$CACHE" ]; then
  /bin/cat "$CACHE"

  if [ "$(age_of "$CACHE")" -ge "$TTL" ]; then
    STALE_LOCK=0
    if [ -f "$LOCK" ] && [ "$(age_of "$LOCK")" -ge "$LOCK_STALE" ]; then
      /bin/rm -f "$LOCK" 2>/dev/null
      STALE_LOCK=1
    fi
    if [ ! -f "$LOCK" ] || [ "$STALE_LOCK" -eq 1 ]; then
      (
        /usr/bin/touch "$LOCK" 2>/dev/null
        /bin/bash "$0" --recompute >/dev/null 2>&1
        /bin/rm -f "$LOCK" 2>/dev/null
      ) </dev/null >/dev/null 2>&1 &
      disown 2>/dev/null
    fi
  fi
  exit 0
fi

# ---------- slow path: actual recompute ----------
# Count dispatches by JSONL line timestamp (not file mtime, sessions stay open)
NOW_EPOCH=$(now)
DAY_AGO=$(( NOW_EPOCH - 86400 ))
WEEK_AGO=$(( NOW_EPOCH - 7 * 86400 ))
# Count ALLOWED dispatches from the ledger agent-budget.sh actually enforces on.
# 2026-07-26: this used to grep every *.jsonl under ~/.claude/projects for Agent
# tool_use blocks. That counts ATTEMPTED dispatches, including every denial
# (184 in the audit log), so the banner read 52 for the 7d window while the
# ledger, which records only dispatches that RAN, held 10. Combined with a stale
# cap default of 50 here vs 80 in agent-budget.sh, the banner announced
# WEEKLY-CAP-HIT and "Agent tool is BLOCKED" while the enforcer was allowing
# every dispatch. Read the same file the enforcer writes. One source of truth.
# Bonus: O(1) ledger read replaces the multi-GB scan described in the header.
LEDGER="$HOME/.claude/agent-dispatch.log"
DAILY=0
WEEKLY=0
if [ -f "$LEDGER" ]; then
  COUNTS=$(/usr/bin/awk -F'\t' -v d="$DAY_AGO" -v w="$WEEK_AGO" \
    '{ if ($1+0 > w) wk++; if ($1+0 > d) dy++ } END { printf "%d %d", dy+0, wk+0 }' "$LEDGER" 2>/dev/null)
  DAILY=${COUNTS%% *}
  WEEKLY=${COUNTS##* }
fi

DAILY=${DAILY:-0}
WEEKLY=${WEEKLY:-0}

# Caps (must match agent-budget.sh defaults)
DAILY_CAP="${AGENT_BUDGET_DAILY:-8}"
WEEKLY_CAP="${AGENT_BUDGET_7D:-80}"

# Status indicator
STATUS="OK"
[ "$DAILY" -ge "$DAILY_CAP" ] && STATUS="DAILY-CAP-HIT"
[ "$WEEKLY" -ge "$WEEKLY_CAP" ] && STATUS="WEEKLY-CAP-HIT"
# Yellow zone: 75% of cap
DAILY_WARN=$(( DAILY_CAP * 3 / 4 ))
WEEKLY_WARN=$(( WEEKLY_CAP * 3 / 4 ))
if [ "$STATUS" = "OK" ]; then
  [ "$DAILY" -ge "$DAILY_WARN" ] && STATUS="NEAR-DAILY"
  [ "$WEEKLY" -ge "$WEEKLY_WARN" ] && STATUS="NEAR-WEEKLY"
fi

# Compose message
MSG="[BURN-BUDGET] Agent dispatches: ${DAILY}/${DAILY_CAP} today, ${WEEKLY}/${WEEKLY_CAP} last 7d. Status: ${STATUS}."
case "$STATUS" in
  "DAILY-CAP-HIT"|"WEEKLY-CAP-HIT")
    MSG="${MSG} Agent tool is BLOCKED by agent-budget.sh. Use bash/grep/Read/WebSearch/~/bin/codex-review/~/bin/ai-do instead. Override once: touch /tmp/agent-budget-bypass."
    ;;
  "NEAR-DAILY"|"NEAR-WEEKLY")
    MSG="${MSG} Approaching cap: prefer bash + WebSearch + codex-review over Agent dispatch this turn."
    ;;
esac

# Statusline cache: short string read by caveman-statusline.sh (fast, no recompute).
printf 'A:%s/%s W:%s/%s' "$DAILY" "$DAILY_CAP" "$WEEKLY" "$WEEKLY_CAP" > "$HOME/.claude/.burn-statusline-cache" 2>/dev/null

IDLE_HIT=0
# Idle-burn guard: overnight (local 00:00 to 08:00) + no commit across ~/repos in last 3h
# = a session left running with no work. Nudge to end it.
HOUR=$(/bin/date +%H)
if [ "$HOUR" -ge 0 ] && [ "$HOUR" -le 8 ]; then
  RECENT_COMMIT=$(find ~/repos -maxdepth 2 -name '*.git' -prune -o -type d -name .git -print 2>/dev/null | head -40 | while read -r g; do
    r="${g%/.git}"; git -C "$r" log --since="3 hours ago" --oneline 2>/dev/null | head -1; done | head -1)
  if [ -z "$RECENT_COMMIT" ]; then
    MSG="${MSG} [IDLE-BURN] Overnight + no commit across ~/repos in 3h, if this session's task is done, END it (don't idle-burn tokens). Marathon sessions inflate cache_read; see feedback_session_hygiene_compaction."
    IDLE_HIT=1
  fi
fi

# 2026-07-26: when the budget is green AND there is no idle-burn nudge, there is
# nothing actionable to say, so say nothing rather than spending ~90 tokens per
# turn restating it. The statusline cache is written above regardless, so the
# numbers stay visible; this only drops the in-context line. An EMPTY cache file
# is the mechanism, the fast path does a bare `cat "$CACHE"`, so empty == silent
# with no change to cache semantics.
if [ "$STATUS" = "OK" ] && [ "$IDLE_HIT" -eq 0 ]; then
  TMP="${CACHE}.$$"
  : > "$TMP" 2>/dev/null && /bin/mv -f "$TMP" "$CACHE" 2>/dev/null
  exit 0
fi

# JSON escape (very simple: content has no quotes/backslashes here)
JSON_MSG=$(echo "$MSG" | /usr/bin/sed 's/"/\\"/g')

OUTPUT="{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"${JSON_MSG}\"}}"

# Write cache atomically so a concurrent reader never sees a half-written file.
TMP="${CACHE}.$$"
printf '%s\n' "$OUTPUT" > "$TMP" 2>/dev/null && /bin/mv -f "$TMP" "$CACHE" 2>/dev/null

# In --recompute mode the caller is a background refresh: stay silent.
[ "$RECOMPUTE_ONLY" -eq 1 ] && exit 0

printf '%s\n' "$OUTPUT"
exit 0
