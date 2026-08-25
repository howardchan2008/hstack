#!/bin/bash
# agent-budget.sh: PreToolUse hook on Agent dispatches.
# Blocks Agent invocations when daily/weekly dispatch count exceeds threshold,
# unless a bypass sentinel is present.
#
# Wired into PreToolUse with matcher "Agent".
#
# Threshold logic:
#   - DAILY:  default 8 dispatches in last 24h
#   - 7-day:  default 80 dispatches in last 7d (rationale at WEEKLY_CAP below)
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
# Override via env: AGENT_BUDGET_DAILY=20 AGENT_BUDGET_7D=100 claude ...

set -uo pipefail

DAILY_CAP="${AGENT_BUDGET_DAILY:-8}"
# 7d is a loose backstop only. daily=8 is the real brake. The 7d window must sit
# ABOVE what daily implies (~56/wk if maxed) so one legit heavy multi-agent day
# cannot pathologically lock out the rest of the week, that was the 2026-06
# lockout cause (115/50 jam). Reset the ledger when bumping this.
WEEKLY_CAP="${AGENT_BUDGET_7D:-80}"

LEDGER="$HOME/.claude/agent-dispatch.log"
AUDIT="$HOME/.claude/agent-budget-audit.log"

NOW_EPOCH=$(/bin/date +%s)
DAY_AGO=$(( NOW_EPOCH - 86400 ))
WEEK_AGO=$(( NOW_EPOCH - 7 * 86400 ))
KEEP_AGO=$(( NOW_EPOCH - 14 * 86400 ))

# Read hook input from stdin JSON. PreToolUse is already gated to "Agent" by the
# settings.json matcher; double-check defensively, and grab the session id.
INPUT=$(cat 2>/dev/null || echo "{}")
TOOL=$(echo "$INPUT" | /usr/bin/grep -oE '"tool_name":"[^"]+"' | head -1 | /usr/bin/sed 's/"tool_name":"//;s/"//')
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

audit() { echo "$(/bin/date -u +%Y-%m-%dT%H:%M:%S)	$1	daily=${2:-?}/${DAILY_CAP}	weekly=${3:-?}/${WEEKLY_CAP}	$SESSION" >> "$AUDIT" 2>/dev/null; }

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

# Count existing ALLOWED dispatches in the rolling windows from the ledger.
if [ -f "$LEDGER" ]; then
  read -r DAILY WEEKLY < <(/usr/bin/awk -F'\t' -v d="$DAY_AGO" -v w="$WEEK_AGO" \
    '{ if ($1+0 > w) wk++; if ($1+0 > d) dy++ } END { print dy+0, wk+0 }' "$LEDGER")
else
  DAILY=0; WEEKLY=0
fi
DAILY=${DAILY:-0}; WEEKLY=${WEEKLY:-0}

# Block if already at/over cap (do NOT append a denied attempt)
BLOCK_REASON=""
if [ "$DAILY" -ge "$DAILY_CAP" ]; then
  BLOCK_REASON="Daily Agent cap hit: $DAILY/$DAILY_CAP dispatches in last 24h."
elif [ "$WEEKLY" -ge "$WEEKLY_CAP" ]; then
  BLOCK_REASON="7-day Agent cap hit: $WEEKLY/$WEEKLY_CAP dispatches in last 7d."
fi

if [ -n "$BLOCK_REASON" ]; then
  audit deny "$DAILY" "$WEEKLY"
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

audit allow "$DAILY" "$WEEKLY"
exit 0
