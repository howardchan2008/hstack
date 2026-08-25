#!/bin/bash

# PROVENANCE, added 2026-08-23. the 2,440-session / 1,035-call / 42%-refetch figures were measured 2026-08-13 against the then-live transcript tree.
# That tree is NOT the corpus any more: transcript-archive moved 3,638 of the
# 3,857 transcripts to ~/Archive/claude-transcripts on 2026-08-18, so the live
# tree is about 6% of sessions. These numbers are HISTORICAL and are not
# reproducible as stated. Re-derive across BOTH trees before citing them; see
# ~/.claude/bin/claims-audit and hooks/lib/probe-dedupe-backtest.py for the shape.
# websearch-router: stop WebSearch/WebFetch being the reflex when a wired lane is better.
#
# Born 2026-08-13 from a measurement, not a hunch. Across 2440 sessions / 30 days:
#   WebSearch + WebFetch ......... 1035 calls
#   every wired search provider ..   18 calls
#   (tavily, serper, brave, perplexity, firecrawl, apify: ZERO. exa: 10.)
# the owner pays for those keys. They went unused because the builtin is one token cheaper
# to think of, not because it is better.
#
# Second finding, larger than the first: 432 of the 1035 (42%) re-fetched a URL or query
# already pulled inside the same 30 days. There was no cache, so the reflex re-paid every time.
#
# Three gates, in order of how much they save:
#   1. CACHE     already fetched recently -> read the stored file instead
#   2. LANE      a wired key or MCP answers this better -> name it, exactly
#   3. NUDGE     plain search -> try `websearch` (fused Exa probes) once first
#
# Gate 3 is self-clearing on purpose: the SAME query coming back a second time means
# `websearch` was tried and returned thin, so it passes. A wall gets disabled; a gate
# that opens when you have done the better thing does not.
#
# Override any of it for one call:  touch /tmp/websearch-approved
set -uo pipefail

INPUT=$(cat)
STATE_DIR="$HOME/.claude/state"
CACHE_DIR="$STATE_DIR/websearch-cache"
NUDGE="$STATE_DIR/websearch-nudged"
OVERRIDE=/tmp/websearch-approved
mkdir -p "$CACHE_DIR" "$NUDGE"

# --- one-call override -------------------------------------------------------
if [ -f "$OVERRIDE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$OVERRIDE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt 600 ]; then rm -f "$OVERRIDE"; exit 0; fi
  rm -f "$OVERRIDE"
fi

# --- parse; FAIL OPEN here, deliberately -------------------------------------
# click-credit-guard.sh and lane-guard.sh fail CLOSED because letting one through
# spends real money. Nothing is spent here: the worst case of a malformed payload is
# a builtin search that costs zero. Blocking work to protect a zero-cost call would be
# the guard doing more damage than the thing it guards against.
# One field per line, not `read TOOL QUERY URL` off a single line: a multi-word query
# would spill into URL and the nudge would echo back one word of what was asked.
PARSED=$(printf '%s' "$INPUT" | /usr/bin/python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("_UNPARSEABLE_"); raise SystemExit
i = d.get("tool_input") or {}
clean = lambda s: (s or "").replace("\n", " ").replace("\r", " ").strip()
print(d.get("tool_name", ""))
print(clean(i.get("query")))
print(clean(i.get("url")))
' 2>/dev/null)
TOOL=$(printf '%s' "$PARSED" | sed -n 1p)
QUERY=$(printf '%s' "$PARSED" | sed -n 2p)
URL=$(printf '%s' "$PARSED" | sed -n 3p)
[ -z "${TOOL:-}" ] && exit 0
[ "$TOOL" = "_UNPARSEABLE_" ] && exit 0
case "$TOOL" in WebSearch|WebFetch) ;; *) exit 0 ;; esac

# The key must match websearch-cache.sh byte for byte or gate 1 never fires. Both sides
# call the same helper for exactly that reason; two hand-rolled normalisers drift apart.
# An empty KEY disables ONLY gate 1. It used to `exit 0` here, which silently switched
# off the lane and nudge gates too, so one bad path in the helper turned the whole hook
# into a no-op that still reported success. A broken cache is not a reason to stop
# routing.
SUBJECT="$QUERY $URL"
KEY=$(/usr/bin/python3 "$HOME/.claude/hooks/lib/websearch_key.py" "$SUBJECT" 2>/dev/null)

# --- gate 1: cache -----------------------------------------------------------
HIT="$CACHE_DIR/$KEY.txt"
if [ -n "$KEY" ] && [ -f "$HIT" ]; then
  age_d=$(( ( $(date +%s) - $(stat -f %m "$HIT" 2>/dev/null || echo 0) ) / 86400 ))
  ttl=7; [ "$TOOL" = "WebSearch" ] && ttl=3
  if [ "$age_d" -le "$ttl" ]; then
    # Count the saves. The headline claim for this whole guard is that 42% of web
    # calls were repeats; without a counter that stays an assertion about the past
    # rather than a measurement of whether it is still true.
    printf '{"ts":"%s","tool":"%s","age_d":%s,"subject":%s}\n' \
      "$(date -u +%FT%TZ)" "$TOOL" "$age_d" \
      "$(printf '%s' "$SUBJECT" | /usr/bin/python3 -c 'import sys,json;print(json.dumps(sys.stdin.read().strip()[:200]))' 2>/dev/null || echo '""')" \
      >> "$STATE_DIR/websearch-cache-hits.jsonl"
    cat >&2 <<MSG
◇ WEBSEARCH-ROUTER: already fetched ${age_d}d ago. Read the cache, do not re-fetch.

  $HIT

42% of web calls in the last 30 days were repeats of something already pulled.
If the page genuinely changes hour to hour (prices, fares, live filings):
  touch $OVERRIDE && re-run
MSG
    exit 2
  fi
  rm -f "$HIT"
fi

# --- gate 2: a wired lane answers this better --------------------------------
LANE=$(printf '%s' "$SUBJECT" | /usr/bin/python3 -c '
import sys, re, json, os

s = sys.stdin.read()

# Lanes added after 2026-08-14 live in data, not here: reference/capability-routes.json.
# A lane inside this heredoc can only be added by editing the hook, which is why the
# five below were the only ones that existed while ten wired tools sat unrouted. The
# JSON is consulted first so a data lane can pre-empt a hardcoded one. A missing or
# malformed file must not disarm the gate, so it degrades to the builtin list.
EXTRA = []
try:
    _p = os.path.expanduser("~/.claude/reference/capability-routes.json")
    for _l in json.load(open(_p)).get("websearch_lanes", []):
        EXTRA.append((_l["lane"], _l["when"], _l["use"], bool(_l.get("block", True))))
except Exception:
    pass

LANES = [
 # (name, pattern, replacement instruction)
 ("library / API / framework documentation",
  r"docs?\.(stripe|upstash|neon|vercel|supabase|cloudflare|anthropic|djangoproject|python|base44|prisma|drizzle|astro)|"
  r"(stripe|upstash|vercel|neon|supabase|cloudflare|prisma|tailwind|shadcn|drizzle|playwright|puppeteer)\.(com|dev|io|sh)/docs|"
  r"readthedocs|llms\.txt|npmjs\.com/package|pypi\.org/project|"
  r"\b(api reference|sdk (docs|reference)|how to use)\b.*\b(stripe|next\.?js|react|prisma|tailwind|django|fastapi|node|bun|deno|vercel|neon|drizzle|shadcn|playwright|express|astro|svelte|redis|postgres)\b",
  "context7 MCP, registered globally, costs nothing per call:\n"
  "    mcp__context7__resolve-library-id  libraryName=stripe  query=<what you need>\n"
  "    mcp__context7__query-docs          libraryId=/websites/stripe  query=<same>\n"
  "  resolve-library-id needs BOTH args. Passing one returns a validation error,\n"
  "  and dropping the other just returns the opposite error.\n"
  "  Training data lags releases. context7 does not."),

 ("company registry / statutory filings",
  r"company-information\.service\.gov\.uk|find-and-update\.company|companieshouse|"
  r"\b(companies house|company number|filing history|annual return|incorporation (record|document))\b|"
  r"dart\.fss|登記簿|法人番号|有価証券報告書",
  "the registry API keys already in the keychain:\n"
  "    companies-house (UK) . edinet (JP) . gbizinfo (JP) . opendart (KR)\n"
  "  Scraping a registry web UI that has a wired API is the exact miss the owner named."),

 ("market / company financial data",
  r"\b(stock price|share price|market cap|ticker|earnings (call|report|date)|10-[KQ]|13[FfDdGg]|"
  r"dividend|p/e ratio|quarterly results|institutional (holdings|investors)|short interest)\b",
  "the finance keys already wired, per ~/.claude/reference/keychain-use-cases.md:\n"
  "    polygon . fmp . finnhub . tiingo . alphavantage . alpaca\n"
  "  a venture already pulls 13F/13D through these. Do not re-derive from prose."),

 ("person / company contact lookup",
  r"\b(partner profile|linkedin profile|who works at|employees at|find (the )?email|"
  r"email address (of|for)|contact details (of|for)|hiring manager at)\b",
  "the people stack:\n"
  "    mcp__linkedin__get_person_profile / search_people   (the owner session, free)\n"
  "    apollo . hunter . snov . contactout . prospeo       (keychain)\n"
  "  A profile page read through a search engine is a worse copy of what the MCP returns."),

 ("search-engine result page fetched by hand",
  r"google\.com/search\?|bing\.com/search\?|duckduckgo\.com/\?q=|search\?q=.*&(gl|hl|num)=",
  "~/.claude/bin/websearch \"<query>\"\n"
  "  Fetching a SERP as HTML gets you a scrape of a search engine. `websearch` runs the\n"
  "  neural and keyword probes and fuses them, which is the thing you actually wanted."),
]

for name, pat, fix, block in EXTRA + [(n, p, f, True) for n, p, f in LANES]:
    if re.search(pat, s, re.I):
        print(name + "\x1f" + fix + "\x1f" + ("block" if block else "warn"))
        break
' 2>/dev/null)

if [ -n "$LANE" ]; then
  NAME="${LANE%%$'\x1f'*}"; REST="${LANE#*$'\x1f'}"
  FIX="${REST%$'\x1f'*}"; MODE="${REST##*$'\x1f'}"
  cat >&2 <<MSG
◇ WEBSEARCH-ROUTER: this is $NAME. the owner already pays for a better source.

  Use instead: $FIX
MSG
  # A lane marked "warn" in capability-routes.json names a tool that is better here
  # but not strictly better everywhere: social scraping spends Click trial credits,
  # SMS reaches a real customer. Blocking those would trade one wrong default for
  # another, so they surface the route and let the call through. They must not print
  # the override instructions either: telling the reader how to bypass a gate that
  # already let them through is how a warning gets read as a refusal.
  [ "$MODE" = "warn" ] && exit 0
  cat >&2 <<MSG

Measured 2026-08-13 across 30 days: 1035 builtin web calls against 18 to the wired
stack. tavily, serper, brave, perplexity, firecrawl, apify fired ZERO times.

If the wired lane genuinely cannot answer this one, say why in chat, then:
  touch $OVERRIDE && re-run
MSG
  exit 2
fi

# --- gate 3: plain search -> try the fused lane once -------------------------
# WebFetch of a specific page is legitimate work; only searches get nudged.
[ "$TOOL" != "WebSearch" ] && exit 0
[ ! -x "$HOME/.claude/bin/websearch" ] && exit 0

SEEN="$NUDGE/$KEY"
if [ -f "$SEEN" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$SEEN" 2>/dev/null || echo 0) ))
  # Same query again inside 30 min: `websearch` was tried and came back thin. Let it through.
  if [ "$age" -lt 1800 ]; then rm -f "$SEEN"; exit 0; fi
fi

# ONCE PER SESSION, NOT ONCE PER QUERY (2026-08-24). Keyed on the query alone,
# every NEW search cost a blocked call, and WebSearch became the worst-performing
# tool on the box: 16 of 26 calls failed since 2026-08-23, 61.5%, every one of
# them this nudge. The lesson is the one risk-checkpoint just learned, and it is
# the same lesson: a guard should charge per DECISION, not per call. Being told
# about the fused lane is one decision. A session that has been told, and chose
# WebSearch anyway for the next question, is not making the same mistake twice.
# The two real gates above this are untouched: those refuse a specific host or a
# metered lane, and each of those IS a per-call decision.
SESSION_NUDGE="$NUDGE/session-$(printf '%s' "${CLAUDE_SESSION_ID:-$PPID}" | tr -cd 'A-Za-z0-9._-')"
if [ -f "$SESSION_NUDGE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$SESSION_NUDGE" 2>/dev/null || echo 0) ))
  # Six hours, matching the probe-dedupe session window. Long enough that one
  # working session is told once; short enough that tomorrow gets the reminder.
  [ "$age" -lt 21600 ] && exit 0
fi
: > "$SESSION_NUDGE"

: > "$SEEN"
find "$NUDGE" -type f -mmin +360 -delete 2>/dev/null

cat >&2 <<MSG
◇ WEBSEARCH-ROUTER: run the fused lane first.

  ~/.claude/bin/websearch "$QUERY"

It runs a neural probe and a keyword probe over Exa (your own key, zero marginal cost),
merges them by reciprocal rank fusion, and prints a routing verdict when the question
needs a metered Click lane instead. One WebSearch call is a single probe with none of that.

Thin result? Re-issue this exact WebSearch and it passes: the gate opens on the second try.
Flags: --days N . --domain D . --fetch N . --contents URL . --json
MSG
exit 2
