#!/bin/bash

# PROVENANCE, added 2026-08-23. the ~40% prose-failure rate came from the 2026-08-12 feedback-file study, 97 files with 39 topic recurrences.
# That tree is NOT the corpus any more: transcript-archive moved 3,638 of the
# 3,857 transcripts to ~/Archive/claude-transcripts on 2026-08-18, so the live
# tree is about 6% of sessions. These numbers are HISTORICAL and are not
# reproducible as stated. Re-derive across BOTH trees before citing them; see
# ~/.claude/bin/claims-audit and hooks/lib/probe-dedupe-backtest.py for the shape.
# click-credit-guard: meters and routes calls to the useclick.ai Click MCP.
#
# Born 2026-08-13, the day the Click MCP was connected on a 7-day / 70-credit
# trial. Click sells 500 credits for $49/month (verified live at
# useclick.ai/pricing that day), so a credit is worth about $0.098 and the whole
# trial is worth about $6.90. That is small enough that a single unattended loop
# empties it, and large enough that emptying it on capability the owner ALREADY OWNS
# is a real loss.
#
# Click's tool surface overlaps the existing stack in three places. Each of those
# is denied here with the free replacement named in the refusal, because a rule
# that only lives in prose has a measured ~40% failure rate at changing behaviour
# (CLAUDE.md, 2026-08-12). The unique lanes (Apify social search, Google Maps,
# Meta ad library, travel fares, Crustdata/Fiber people search, Particle entity
# resolution) pass through and are metered.
#
# Fires on PreToolUse for matcher  mcp__.*__click_.*
# The Click server is registered under a UUID name that changes if the connector
# is re-added, so the matcher deliberately does NOT pin the UUID.
#
# Ledger:  ~/.claude/state/click-credits.jsonl   (one line per call seen)
# Budget:  ~/.claude/state/click-budget          (integer, default 70)
# Report:  ~/.claude/bin/click-credits
set -u

INPUT=$(cat)

STATE_DIR="$HOME/.claude/state"
LEDGER="$STATE_DIR/click-credits.jsonl"
BUDGET_FILE="$STATE_DIR/click-budget"
OVERRIDE=/tmp/click-credit-approved
mkdir -p "$STATE_DIR"

# --- FAIL CLOSED on an unparseable payload -----------------------------------
# settings.json binds this hook to the Click matcher only, so a payload we
# cannot read is a Click call we failed to inspect, never some other tool.
# Treating "cannot parse" as "not Click, therefore fine" would silently disarm
# the meter exactly when it matters. Same reasoning as lane-guard.sh.
TOOL=$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
if [ -z "$TOOL" ]; then
  cat >&2 <<'MSG'
⛔ CLICK-CREDIT-GUARD: payload unparseable, failing closed.
This is a guard malfunction, not a verdict on your call. The routing and budget
rules were never evaluated. Repair the hook rather than routing past it.
Override for one call: touch /tmp/click-credit-approved && re-run.
MSG
  exit 2
fi

case "$TOOL" in
  *__click_*) ;;
  *) exit 0 ;;
esac

# Strip the mcp__<server>__ prefix, leaving click_<provider>_<verb>.
SHORT="${TOOL##*__}"

# --- one-call override --------------------------------------------------------
if [ -f "$OVERRIDE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$OVERRIDE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt 600 ]; then
    rm -f "$OVERRIDE"
    printf '{"ts":"%s","tool":"%s","decision":"override"}\n' \
      "$(date -u +%FT%TZ)" "$SHORT" >> "$LEDGER"
    exit 0
  fi
  rm -f "$OVERRIDE"
fi

# --- lane 1: DENY duplicates of capability the owner already owns ---------------
DUP_WHY=""
case "$SHORT" in
  click_exa_*)
    DUP_WHY='Exa is already yours, BUT the key hit its credit limit on 2026-08-22 (HTTP 402
NO_MORE_CREDITS on every probe). Until it is topped up at dashboard.exa.ai, the
free lane is the BUILT-IN WebSearch and WebFetch tools, not Click.
    Use instead:  the built-in WebSearch / WebFetch tools FIRST (zero marginal cost)
                  curl against the primary source when the answer has one canonical page
                  ~/.claude/bin/exa and ~/.claude/bin/websearch BOTH route through the
                  dead key, so they 402 as well until it is topped up. Do not read a
                  402 from either of them as evidence that Click is the only lane.' ;;
  click_financial_datasets_*)
    DUP_WHY='Market and filing data is already wired, per keychain-use-cases.md.
    Use instead:  polygon - fmp - finnhub - tiingo - alphavantage - alpaca (prices, fundamentals)
                  edinet (JP) - opendart (KR) - companies-house (UK) - gbizinfo (JP) filings
                  a venture already pulls 13F/13D from these; do not pay Click for the same rows.' ;;
  click_context_dev_search_docs|click_context_dev_execute)
    DUP_WHY='Library documentation is free through the built-in tools.
    Use instead:  WebFetch on the vendor docs URL, then gh search code for real usage.
    (context7 MCP removed 2026-08-20: 3 real doc fetches ever, 2 procs per session.)' ;;
  click_apify_search_zillow)
    DUP_WHY='US residential real estate has no consumer in any active venture (a venture, Crystal
    Century, a venture, another venture). This is trial credit spent on nothing.' ;;
esac

if [ -n "$DUP_WHY" ]; then
  printf '{"ts":"%s","tool":"%s","decision":"denied_duplicate"}\n' \
    "$(date -u +%FT%TZ)" "$SHORT" >> "$LEDGER"
  {
    echo "⛔ CLICK-CREDIT-GUARD: $SHORT denied - duplicates a capability you already pay for."
    echo ""
    echo "$DUP_WHY"
    echo ""
    echo "Click credits are ~\$0.098 each and the trial holds 70. Spend them only on the lanes"
    echo "nothing else in the stack covers: social/UGC search (tiktok, instagram, reddit, x,"
    echo "youtube, facebook), facebook_ads, google_maps, crustdata/fiber people search,"
    echo "particle entity resolution, jinko travel fares."
    echo ""
    echo "Routing table: ~/.claude/reference/click-routing.md"
    echo "If this call genuinely has no free equivalent, say why in chat, then:"
    echo "  touch /tmp/click-credit-approved && re-run"
  } >&2
  exit 2
fi

# --- lane 2: budget ----------------------------------------------------------
BUDGET=$(cat "$BUDGET_FILE" 2>/dev/null)
case "$BUDGET" in ''|*[!0-9]*) BUDGET=70 ;; esac

USED=$(grep -c '"decision":"allowed"' "$LEDGER" 2>/dev/null || true)
USED=$(printf '%s' "${USED:-0}" | tr -cd '0-9')
: "${USED:=0}"

if [ "$USED" -ge "$BUDGET" ]; then
  {
    echo "⛔ CLICK-CREDIT-GUARD: Click trial budget exhausted - $USED/$BUDGET calls already spent."
    echo ""
    echo "Nothing here is broken. The trial is 70 credits (~\$6.90) and the meter says they are gone."
    echo "Re-check the real balance in the Click dashboard before assuming the meter is wrong;"
    echo "it counts CALLS, and a heavy Apify scrape may bill more than one credit."
    echo ""
    echo "Raise the ceiling only against a verified balance:"
    echo "  echo <n> > ~/.claude/state/click-budget"
    echo "Ledger: ~/.claude/state/click-credits.jsonl   Report: ~/.claude/bin/click-credits"
  } >&2
  exit 2
fi

# --- allow, and meter --------------------------------------------------------
printf '{"ts":"%s","tool":"%s","decision":"allowed","n":%s}\n' \
  "$(date -u +%FT%TZ)" "$SHORT" "$((USED + 1))" >> "$LEDGER"

REMAIN=$(( BUDGET - USED - 1 ))
if [ "$REMAIN" -le 15 ]; then
  echo "⚠️  CLICK-CREDIT-GUARD: $SHORT allowed. $REMAIN of $BUDGET trial calls left." >&2
fi
exit 0
