#!/bin/bash
# curl-router: catch the hand-rolled HTTP call when a wired tool owns that host.
#
# Born 2026-08-14. websearch-router.sh guards the WebSearch reflex, which was
# measured at 166 calls. The bigger reflex was never guarded: 906 of the 20,579
# Bash calls on this box are curl, and several of them hit hosts that already have
# a keyed, tested, documented tool sitting one directory away. Guardian and NYT
# were being queried by hand on the same day `newswire` was written to do it.
#
# Routes come from reference/capability-routes.json ("curl_hosts"), the same file
# the websearch router reads, so a lane is added once and both reflexes learn it.
#
# Deliberately narrow, because a Bash PreToolUse hook sees every shell command on
# the box and a false positive here is a wall in front of ordinary work:
#   - only fires when the command actually invokes curl, wget or httpie
#   - only when a route host matches
#   - default is PRINT AND ALLOW. Only a route with "block": true stops the call,
#     and the one that does (SERP-by-hand) has a strictly better free replacement.
# Fails OPEN on any parse problem: an unreadable payload here is an ordinary shell
# command, not a suspected violation, which is the opposite of click-credit-guard's
# situation where the matcher guarantees the call was a paid one.
set -u

INPUT=$(cat)
STATE_DIR="$HOME/.claude/state"
OVERRIDE=/tmp/curl-router-approved
ROUTES="$HOME/.claude/reference/capability-routes.json"
mkdir -p "$STATE_DIR"

[ -f "$ROUTES" ] || exit 0

# --- one-call override -------------------------------------------------------
if [ -f "$OVERRIDE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$OVERRIDE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt 600 ]; then rm -f "$OVERRIDE"; exit 0; fi
  rm -f "$OVERRIDE"
fi

CMD=$(printf '%s' "$INPUT" | /usr/bin/python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if d.get("tool_name") != "Bash":
    sys.exit(0)
c = (d.get("tool_input") or {}).get("command") or ""
print(c.replace("\n", " ")[:4000])
' 2>/dev/null)

[ -z "${CMD:-}" ] && exit 0

# Must be an actual fetch. `grep curl file.txt` is not one, and neither is a
# comment mentioning curl, so require the binary in command position.
printf '%s' "$CMD" | grep -Eq '(^|[;&|(]|\bthen |\bdo |\$\()[[:space:]]*(sudo[[:space:]]+)?(curl|wget|http|https)\b' || exit 0

# The tools themselves shell out to these same hosts. Routing a tool into itself
# would be an infinite scold, and the ledger line below would fire on every run.
printf '%s' "$CMD" | grep -Eq '\.claude/bin/(newswire|enrich-contact|notify|websearch|exa)|bin/(fireflies|gsc\.py|gmail-organize)' && exit 0

HIT=$(printf '%s' "$CMD" | /usr/bin/python3 -c '
import sys, re, json, os
cmd = sys.stdin.read()
try:
    routes = json.load(open(os.path.expanduser("~/.claude/reference/capability-routes.json"))).get("curl_hosts", [])
except Exception:
    sys.exit(0)
for r in routes:
    if re.search(r["when"], cmd, re.I):
        print("\x1f".join([r["lane"], r["use"], r.get("derives", ""), "block" if r.get("block") else "warn"]))
        break
' 2>/dev/null)

[ -z "${HIT:-}" ] && exit 0

LANE=$(printf '%s' "$HIT" | cut -d$'\x1f' -f1)
USE=$(printf '%s' "$HIT" | cut -d$'\x1f' -f2)
WHY=$(printf '%s' "$HIT" | cut -d$'\x1f' -f3)
MODE=$(printf '%s' "$HIT" | cut -d$'\x1f' -f4)

printf '{"ts":"%s","lane":"%s","mode":"%s","cmd":%s}\n' \
  "$(date -u +%FT%TZ)" "$LANE" "$MODE" \
  "$(printf '%s' "$CMD" | /usr/bin/python3 -c 'import sys,json;print(json.dumps(sys.stdin.read().strip()[:200]))' 2>/dev/null || echo '""')" \
  >> "$STATE_DIR/curl-router.jsonl"

cat >&2 <<MSG
◇ CURL-ROUTER: that host is $LANE, and it already has a tool.

  Use instead:
  $USE

  Why it is better: $WHY
MSG

if [ "$MODE" = "block" ]; then
  cat >&2 <<MSG
If the tool genuinely cannot do this one, say why in chat, then:
  touch $OVERRIDE && re-run
MSG
  exit 2
fi
exit 0
