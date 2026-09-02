#!/bin/bash
# agent-budget.sh: PreToolUse hook on Agent dispatches.
# Blocks Agent invocations when the per-session, box-wide, or weekly dispatch
# count reaches its threshold, unless a bypass sentinel is present.
#
# Updated 2026-09-02. DAILY_CAP is per session, so one busy session cannot
# lock out the 5 to 7 other sessions commonly running on this box. A separate
# BOX_DAILY_CAP is a rolling-24h backstop across all sessions. Session id
# "unknown" uses only the box-wide numbers because it cannot have its own
# bucket. The incident prompting this change: on 2026-09-01 session ad751018
# made 8 dispatches between 09:24 and 10:15 UTC, then every other session was
# denied until 09:24 UTC the next day.
#
# Wired into PreToolUse with matcher "Agent".
#
# Threshold logic:
#   - DAILY:      default 8 dispatches for this session in last 24h
#   - BOX DAILY:  default 40 dispatches across all sessions in last 24h
#   - 7-day:      default 200 dispatches across all sessions in last 7d
#   - First breached threshold wins -> block.
#
# Counting: an append-only ledger (~/.claude/agent-dispatch.log), one line
# "EPOCH<TAB>SESSION" per ALLOWED Agent dispatch. O(1): replaces the old
# find+jq scan over the full ~875MB transcript corpus (5.5s/dispatch, fail-open
# under latency). Allowed dispatches are appended; denied ones are NOT, so the
# ledger stays an accurate count of what actually ran.
#
# Every decision is recorded in ~/.claude/agent-budget-audit.log so bypass
# overuse and leaks are visible (the old version's denials were only knowable
# by grepping transcripts).
#
# Bypass:
#   touch /tmp/agent-budget-bypass    # single-use, hook deletes after read
#   touch /tmp/agent-budget-disabled  # permanent, lasts until the owner rm's it
#
# Override via env: AGENT_BUDGET_DAILY=20 AGENT_BUDGET_BOX_DAILY=100
# AGENT_BUDGET_7D=300 AGENT_BUDGET_LEDGER=/tmp/ledger AGENT_BUDGET_AUDIT=/tmp/audit claude ...

set -uo pipefail

DAILY_CAP="${AGENT_BUDGET_DAILY:-8}"
BOX_DAILY_CAP="${AGENT_BUDGET_BOX_DAILY:-40}"
WEEKLY_CAP="${AGENT_BUDGET_7D:-200}"

LEDGER="${AGENT_BUDGET_LEDGER:-$HOME/.claude/agent-dispatch.log}"
AUDIT="${AGENT_BUDGET_AUDIT:-$HOME/.claude/agent-budget-audit.log}"

NOW_EPOCH=$(/bin/date +%s)
DAY_AGO=$(( NOW_EPOCH - 86400 ))
WEEK_AGO=$(( NOW_EPOCH - 7 * 86400 ))
KEEP_AGO=$(( NOW_EPOCH - 14 * 86400 ))

# Read hook input from stdin JSON. PreToolUse is already gated to "Agent" by the
# settings.json matcher; double-check defensively, and grab the session id.
INPUT=$(cat 2>/dev/null || echo "{}")
# WHITESPACE AFTER THE COLON, fixed 2026-08-29. This grep required `"tool_name":"Agent"`
# with no space, so a pretty-printed payload left TOOL empty and the very next
# line exited 0: the budget was not enforced at all on that shape. The comment
# thirty lines below already records this exact bug being found and fixed for
# the SESSION id, and the same defect was sitting here untouched, because
# nothing ever asserted that this hook refuses. Found by writing that assertion.
TOOL=$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try: print((json.load(sys.stdin) or {}).get("tool_name") or "")
except Exception: print("")' 2>/dev/null)
[ "$TOOL" != "Agent" ] && exit 0
# The old regex required no space after the colon, so a pretty-printed payload
# never matched and every session shared one "unknown" budget bucket. $INPUT
# already holds the payload, so hand it to tier 2 directly.
. "$(dirname "${BASH_SOURCE[0]}")/session-identity.sh"
guild_resolve_session_id <<<"$INPUT"
SESSION="$SESSION_ID"
[ -z "$SESSION" ] && SESSION="unknown"

# Don't charge automated / headless dispatches to the interactive ship-discipline
# budget. The cap measures the owner's hands-on Agent use; headless launchd jobs
# (r17-digest, startup-digest, etc.) and SDK runs run their own work and must not
# jam his interactive budget: that was the 2026-06 lockout mechanism. Exempt the
# known headless entrypoints: allow + record in audit, but do NOT count to ledger.
ENTRYPOINT="${CLAUDE_CODE_ENTRYPOINT:-}"
case "$ENTRYPOINT" in
  sdk-cli|sdk-ts|sdk-py|sdk|cron|headless|automation)
    echo "$(/bin/date -u +%Y-%m-%dT%H:%M:%S)	exempt-headless($ENTRYPOINT)	$SESSION" >> "$AUDIT" 2>/dev/null
    exit 0 ;;
esac

# Count existing allowed dispatches before bypass/headless handling so every
# audit decision reports the same current view of the ledger.
SESSION_DAILY=0
BOX_DAILY=0
WEEKLY=0
if [ -f "$LEDGER" ]; then
  read -r SESSION_DAILY BOX_DAILY WEEKLY < <(/usr/bin/awk -F'\t' \
    -v d="$DAY_AGO" -v w="$WEEK_AGO" -v s="$SESSION" \
    '{ if ($1+0 > w) wk++; if ($1+0 > d) { box++; if ($2 == s) dy++ } } \
     END { print dy+0, box+0, wk+0 }' "$LEDGER")
fi
SESSION_DAILY=${SESSION_DAILY:-0}; BOX_DAILY=${BOX_DAILY:-0}; WEEKLY=${WEEKLY:-0}

if [ "$SESSION" = "unknown" ]; then
  DISPLAY_DAILY="$BOX_DAILY"
  DISPLAY_DAILY_CAP="$BOX_DAILY_CAP"
else
  DISPLAY_DAILY="$SESSION_DAILY"
  DISPLAY_DAILY_CAP="$DAILY_CAP"
fi

audit() { echo "$(/bin/date -u +%Y-%m-%dT%H:%M:%S)	$1	daily=${DISPLAY_DAILY}/${DISPLAY_DAILY_CAP}+box=${BOX_DAILY}/${BOX_DAILY_CAP}	weekly=${3:-$WEEKLY}/${WEEKLY_CAP}	$SESSION" >> "$AUDIT" 2>/dev/null; }

# Permanent bypass
if [ -f /tmp/agent-budget-disabled ]; then
  audit disabled
  exit 0
fi

# Single-use bypass: consume + allow (still record the dispatch in the ledger)
if [ -f /tmp/agent-budget-bypass ]; then
  rm -f /tmp/agent-budget-bypass
  printf '%s\t%s\n' "$NOW_EPOCH" "$SESSION" >> "$LEDGER" 2>/dev/null
  audit bypass-used
  exit 0
fi

# Block if already at/over cap (do NOT append a denied attempt)
BLOCK_REASON=""
if [ "$SESSION" != "unknown" ] && [ "$SESSION_DAILY" -ge "$DAILY_CAP" ]; then
  BLOCK_REASON="Per-session Agent cap hit: $SESSION_DAILY/$DAILY_CAP in this session in the last 24h"
elif [ "$BOX_DAILY" -ge "$BOX_DAILY_CAP" ]; then
  BLOCK_REASON="Box-wide Agent cap hit: $BOX_DAILY/$BOX_DAILY_CAP across all sessions in the last 24h"
elif [ "$WEEKLY" -ge "$WEEKLY_CAP" ]; then
  BLOCK_REASON="7-day Agent cap hit: $WEEKLY/$WEEKLY_CAP across all sessions in the last 7d"
fi

if [ -n "$BLOCK_REASON" ]; then
  audit deny "$DISPLAY_DAILY" "$WEEKLY"
  REASON="${BLOCK_REASON} Use bash/grep/Read for lookups, ~/bin/codex-review for code review, ~/bin/ai-do for one-shots, or WebSearch for research. Override once: touch /tmp/agent-budget-bypass. Disable: touch /tmp/agent-budget-disabled."
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"${REASON}"}}
EOF
  exit 0
fi

# Under cap → record this dispatch and allow.
printf '%s\t%s\n' "$NOW_EPOCH" "$SESSION" >> "$LEDGER" 2>/dev/null

# Trim ledger to last ~14 days so it never grows unbounded (best-effort).
if [ -f "$LEDGER" ]; then
  TMP="$LEDGER.tmp.$$"
  if /usr/bin/awk -F'\t' -v k="$KEEP_AGO" '$1+0 > k' "$LEDGER" > "$TMP" 2>/dev/null; then
    mv -f "$TMP" "$LEDGER" 2>/dev/null || rm -f "$TMP" 2>/dev/null
  else
    rm -f "$TMP" 2>/dev/null
  fi
fi

audit allow "$DISPLAY_DAILY" "$WEEKLY"
exit 0
