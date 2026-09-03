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

# Resolve the same session bucket as agent-budget.sh before selecting the
# cache. A shared cache would show one session another session's count.
INPUT=$(cat 2>/dev/null || echo "{}")
. "$(dirname "${BASH_SOURCE[0]}")/session-identity.sh"
if [ -n "${BURN_CONTEXT_SESSION:-}" ]; then
  SESSION="$BURN_CONTEXT_SESSION"
else
  guild_resolve_session_id <<<"$INPUT"
  SESSION="$SESSION_ID"
fi
[ -z "$SESSION" ] && SESSION="unknown"
SESSION_KEY=$(printf '%s' "$SESSION" | /usr/bin/sed 's/[^A-Za-z0-9_.-]/_/g')

CACHE="/tmp/burn-context-cache-${SESSION_KEY}.json"
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
        BURN_CONTEXT_SESSION="$SESSION" /bin/bash "$0" --recompute >/dev/null 2>&1
        /bin/rm -f "$LOCK" 2>/dev/null
      ) </dev/null >/dev/null 2>&1 &
      disown 2>/dev/null
    fi
  fi
  exit 0
fi

# ---------- slow path: actual recompute ----------
# Count dispatches by ledger timestamp (not file mtime, sessions stay open).
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
LEDGER="${AGENT_BUDGET_LEDGER:-$HOME/.claude/agent-dispatch.log}"
SESSION_DAILY=0
BOX_DAILY=0
WEEKLY=0
if [ -f "$LEDGER" ]; then
  COUNTS=$(/usr/bin/awk -F'\t' -v d="$DAY_AGO" -v w="$WEEK_AGO" -v s="$SESSION" \
    '{ if ($1+0 > w) wk++; if ($1+0 > d) { box++; if ($2 == s) dy++ } } \
     END { printf "%d %d %d", dy+0, box+0, wk+0 }' "$LEDGER" 2>/dev/null)
  SESSION_DAILY=$(printf '%s' "$COUNTS" | awk '{print $1}')
  BOX_DAILY=$(printf '%s' "$COUNTS" | awk '{print $2}')
  WEEKLY=$(printf '%s' "$COUNTS" | awk '{print $3}')
fi

SESSION_DAILY=${SESSION_DAILY:-0}
BOX_DAILY=${BOX_DAILY:-0}
WEEKLY=${WEEKLY:-0}

# Caps (must match agent-budget.sh defaults)
DAILY_CAP="${AGENT_BUDGET_DAILY:-8}"
BOX_DAILY_CAP="${AGENT_BUDGET_BOX_DAILY:-40}"
WEEKLY_CAP="${AGENT_BUDGET_7D:-200}"

if [ "$SESSION" = "unknown" ]; then
  DISPLAY_DAILY="$BOX_DAILY"
  DISPLAY_DAILY_CAP="$BOX_DAILY_CAP"
else
  DISPLAY_DAILY="$SESSION_DAILY"
  DISPLAY_DAILY_CAP="$DAILY_CAP"
fi

# Status indicator
STATUS="OK"
if [ "$SESSION" != "unknown" ] && [ "$SESSION_DAILY" -ge "$DAILY_CAP" ]; then
  STATUS="PER-SESSION-CAP-HIT"
elif [ "$BOX_DAILY" -ge "$BOX_DAILY_CAP" ]; then
  STATUS="BOX-CAP-HIT"
elif [ "$WEEKLY" -ge "$WEEKLY_CAP" ]; then
  STATUS="WEEKLY-CAP-HIT"
fi
# Yellow zone: 75% of cap
DAILY_WARN=$(( DAILY_CAP * 3 / 4 ))
BOX_DAILY_WARN=$(( BOX_DAILY_CAP * 3 / 4 ))
WEEKLY_WARN=$(( WEEKLY_CAP * 3 / 4 ))
if [ "$STATUS" = "OK" ]; then
  [ "$SESSION" != "unknown" ] && [ "$SESSION_DAILY" -ge "$DAILY_WARN" ] && STATUS="NEAR-PER-SESSION"
  [ "$BOX_DAILY" -ge "$BOX_DAILY_WARN" ] && STATUS="NEAR-BOX"
  [ "$WEEKLY" -ge "$WEEKLY_WARN" ] && STATUS="NEAR-WEEKLY"
fi

# Compose message
if [ "$SESSION" = "unknown" ]; then
  MSG="[BURN-BUDGET] Agent dispatches: unknown session, ${BOX_DAILY}/${BOX_DAILY_CAP} box-wide in the last 24h, ${WEEKLY}/${WEEKLY_CAP} last 7d. Status: ${STATUS}."
else
  MSG="[BURN-BUDGET] Agent dispatches: ${SESSION_DAILY}/${DAILY_CAP} this session in the last 24h, ${BOX_DAILY}/${BOX_DAILY_CAP} box-wide in the last 24h, ${WEEKLY}/${WEEKLY_CAP} last 7d. Status: ${STATUS}."
fi
case "$STATUS" in
  "PER-SESSION-CAP-HIT"|"BOX-CAP-HIT"|"WEEKLY-CAP-HIT")
    MSG="${MSG} Agent tool is BLOCKED by agent-budget.sh. Use bash/grep/Read/WebSearch/~/bin/codex-review/~/bin/ai-do instead. Override once: touch /tmp/agent-budget-bypass."
    ;;
  "NEAR-PER-SESSION"|"NEAR-BOX"|"NEAR-WEEKLY")
    MSG="${MSG} Approaching cap: prefer bash + WebSearch + codex-review over Agent dispatch this turn."
    ;;
esac

# Statusline cache: short string read by caveman-statusline.sh (fast, no recompute).
printf 'A:%s/%s B:%s/%s W:%s/%s' "$DISPLAY_DAILY" "$DISPLAY_DAILY_CAP" "$BOX_DAILY" "$BOX_DAILY_CAP" "$WEEKLY" "$WEEKLY_CAP" > "$HOME/.claude/.burn-statusline-cache" 2>/dev/null

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
# 2026-09-02: Fable 5.1 fan-out is what empties the 5-hour window. Measured that day:
# 14 live sessions on claude-fable-5-1 at once, each call 1.8x an Opus 5 call at list
# price, and the window hit 100% in under 30 minutes where Opus 5 lasts the full 5h.
# Count the live Fable sessions (the launcher argv carries --model) and say so when
# more than two are open. Mechanically decidable, so it belongs here and not in prose.
FABLE_LIVE=$(/bin/ps -eo command 2>/dev/null | /usr/bin/grep -c -- '[-]-model claude-fable-5' 2>/dev/null || echo 0)  # [-] so grep's own argv is not counted
FABLE_HIT=0
if [ "${FABLE_LIVE:-0}" -gt 2 ]; then
  MSG="${MSG} [FABLE-FANOUT] ${FABLE_LIVE} Fable 5.1 sessions are live on this box. Fable is the scarce thinking budget: one session at a time, effort high, write the spec and hand execution to Codex (jobq). Everything parallel runs on Opus 5 (/model claude-opus-5)."
  FABLE_HIT=1
fi

# Is THIS session on Fable? Opus 5 became the settings default on 2026-09-03, so
# sitting on Fable is now a deliberate choice and the session should be told what
# the choice is for. Read the model out of the session's own transcript rather
# than the process list: a session that switched with /model keeps its launch argv,
# so argv answers the wrong question. tail keeps this to a fixed read.
SELF_FABLE=0
TRANSCRIPT=$(printf '%s' "$INPUT" | /usr/bin/sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | /usr/bin/head -1)
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  if /usr/bin/tail -c 400000 "$TRANSCRIPT" 2>/dev/null \
     | /usr/bin/grep -q '"model"[[:space:]]*:[[:space:]]*"claude-fable-5' 2>/dev/null; then
    SELF_FABLE=1
  fi
fi
if [ "$SELF_FABLE" -eq 1 ]; then
  MSG="${MSG} [FABLE-SESSION] This session is on Fable 5.1. Opus 5 is the default since 2026-09-03, so this is opt-in and it is for ONE hard problem: think, decide, write the spec, then hand execution to Codex (jobq add) or to an Opus session. Measured 2026-09-03 on the days both ran: a Fable call costs 1.6x an Opus call and 58.5% of its bill is cache WRITE, so every long tool result and every pasted block is charged at \$12.50/MTok here. the owner's own account is that Opus lets him work a full 5-hour window and Fable does not. Mechanical work belongs elsewhere: /model claude-opus-5."
  FABLE_HIT=1
fi

if [ "$STATUS" = "OK" ] && [ "$IDLE_HIT" -eq 0 ] && [ "$FABLE_HIT" -eq 0 ]; then
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
