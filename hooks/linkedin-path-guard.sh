#!/usr/bin/env bash
# PreToolUse: refuse to drive LinkedIn through the DOM / headed Chrome.
#
# WHY THIS EXISTS: LinkedIn automation in this setup has ONE supported path,
# the headless mcp-server-linkedin talking to the Voyager API (headless_send.py
# -> MCP -> voyager). It was built precisely because the DOM path does not work
# here, and it is the path every sender, verifier and reconciler already uses.
#
# The DOM/headed-Chrome path keeps getting re-derived from scratch anyway,
# because a fresh session sees a browser tool, sees a linkedin.com URL, and
# reaches for it. That path is not merely slower, it is WRONG in ways that
# corrupt state and burn the account:
#
#   - It reads rendered markup, so it cannot distinguish "message not
#     delivered" from "thread not rendered yet". Every NOT_DELIVERED
#     investigation that started from DOM evidence produced a false negative.
#   - It needs a logged-in headed profile, which means it can send from
#     WHATEVER account that Chrome happens to hold. outreach_run.py has an
#     explicit EXPECT_USER identity gate for exactly this risk; the browser
#     path has no equivalent and bypasses it entirely.
#   - Voyager returns structured, verifiable results. The DOM returns a
#     screenshot that a model then GUESSES about, which is how phantom
#     "confirmed sent" entries get written into sent-log.jsonl.
#
# SCOPE IS DELIBERATELY NARROW: browser tools stay fully available for every
# non-LinkedIn use (design review, QA, docs, localhost work). This blocks only
# when the payload actually references LinkedIn. A real need to inspect
# linkedin.com by eye, once, for a human reason: LINKEDIN_DOM_OK=1.
#
# Block contract matches dash-gate.sh / risk-checkpoint.sh: stderr, exit 2.
set -u
[ "${LINKEDIN_DOM_OK:-}" = "1" ] && exit 0
payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0
printf '%s' "$payload" | /usr/bin/python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = d.get("tool_name") or ""
ti = d.get("tool_input") or {}

BROWSER = ("claude-in-chrome", "Claude_Browser", "chrome-devtools", "playwright", "puppeteer")
is_browser = any(b in tool for b in BROWSER)

# Bash is in scope only for the retired DOM senders, not for grepping logs.
DOM_SENDER = ("cdp_linkedin", "linkedin_dom", "dom_send", "--headed", "headed_send")
cmd = ti.get("command") or ""
is_dom_bash = tool == "Bash" and any(s in cmd for s in DOM_SENDER)

if not (is_browser or is_dom_bash):
    sys.exit(0)

blob = json.dumps(ti).lower()
if "linkedin" not in blob:
    sys.exit(0)

what = "headed-Chrome/DOM browser tool" if is_browser else "retired DOM sender"
sys.stderr.write(
    "BLOCKED: " + what + " pointed at LinkedIn.\n"
    "  tool: " + (tool or "?") + "\n\n"
    "There is no browser path to LinkedIn on this machine any more.\n\n"
    "This guard used to send you to the headless MCP instead. That lane was\n"
    "BANNED on 2026-08-15 (the owner, after a Chromium linkedin.com/login window\n"
    "appeared for the third time): see hooks/linkedin-browser-ban.sh and the\n"
    "BANNED switch in outreach/headless_send.py. Pointing you at it now would\n"
    "just walk you into a second refusal.\n\n"
    "  post to feed  ->  outreach/publish.py  (official REST API, no browser)\n"
    "  connect / DM  ->  nothing. No API endpoint exists, so they are off.\n\n"
    "The DOM path additionally cannot tell undelivered from unrendered,\n"
    "bypasses the EXPECT_USER identity gate, and has written phantom sends\n"
    "into sent-log.jsonl. Do not rebuild it. Escape hatch: LINKEDIN_DOM_OK=1\n"
)
sys.exit(2)
'
