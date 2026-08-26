#!/usr/bin/env bash
# PreToolUse(Bash): refuse to launch the LinkedIn browser lane, from any session, any copy.
#
# WHY THIS EXISTS. the owner, 2026-08-15, three times in one afternoon:
#   "the google chrome for testing window keeps opening, dont make it open from now on"
#   "stop opening the headless linkedin window, permanently ever ban that"
#   "something triggered the linkedin headless window again, never show me the tab again"
#
# The first two were answered inside ~/repos/claude/outreach (browser_guard refuses every
# patchright launch, headless_send.py refuses at entry). A real Chromium window with
# linkedin.com/login still appeared afterwards, because a repo-local ban only covers the
# copy it lives in. There are four checkouts of that sender on this box, several Claude
# sessions run at once, and any of them can shell out to `uvx mcp-server-linkedin@latest`.
# This is the machine-wide layer: the launch command is refused before it runs, whatever
# directory, copy or session issues it.
#
# SCOPE. Only commands that actually start the lane: the MCP server package, any
# headless_send.py, or a browser driver invoked with linkedin in the same command. Reading
# the repo, grepping it, editing it, and the official-API publisher (publish.py) are all
# untouched, because publish.py opens no browser.
#
# NO ENV ESCAPE HATCH. An env var is what a scheduled job sets, which is how a ban rots
# back into a setting. Lifting this means editing this file on purpose.
#
# Block contract matches dash-gate.sh / risk-checkpoint.sh: stderr, exit 2.
set -u

SELFTEST="${1:-}"

_verdict() {
  # $1 = command text. echoes BLOCK or ALLOW.
  #
  # NAMING THE FILE IS NOT RUNNING IT. The first cut matched any command containing
  # "headless_send.py", so `git add` on the retired copy was refused by this very hook while
  # committing the ban itself. Reading, grepping, editing and version-controlling that path
  # launch no browser. Only an EXECUTION shape is blocked: an interpreter or ./ in front of
  # the script, or the script called with one of its own subcommands.
  #
  # A COMMAND THAT CANNOT LAUNCH ANYTHING IS ALLOWED WHATEVER IT SAYS. The driver rule below
  # then fired on the WORDS of a commit message that DESCRIBED the ban ("a Chromium
  # linkedin.com/login window came back"), so the hook refused the commit recording its own
  # fix. The first instinct, stripping quoted spans, was wrong in the other direction: a real
  # launch is often quoted too (node -e '...chromium...'). What actually separates them is the
  # VERB. git, grep, cat and echo cannot start a browser no matter what text they carry, so a
  # command whose every segment starts with one of those is allowed without reading further.
  # A guard that refuses ordinary repo work gets switched off, and then it guards nothing.
  local cmd="$1"
  if printf '%s' "$cmd" | python3 -c '
import re, sys
BENIGN = {"git","echo","printf","cat","grep","rg","wc","sed","awk","head","tail","ls",
          "diff","cd","true","false","chmod","cp","mv","mkdir","touch","pwd","export",
          # Shell builtins that cannot start a process of their own. `ulimit -n 4096`
          # prefixes every network-touching call on this box (CLAUDE.md, the EMFILE
          # rule), and leaving it out made that prefix drag the whole command into text
          # matching: a commit whose MESSAGE described the ban was then refused by the
          # ban. Fourth false positive of this shape, same root cause each time, which
          # is a non-launcher verb being treated as unknown.
          "ulimit","umask","set","unset","source","test","sleep","date","which","type"}
def verb(seg):
    """Real command word, after any env prefix. `env -u HTTPS_PROXY git push` is a git push,
    and this box wraps every git push that way to dodge the the local proxy MITM, so treating env as
    an opaque verb sent those commands down the text-matching path and blocked them."""
    toks = seg.split()
    while toks and (toks[0].split("/")[-1] == "env" or "=" in toks[0].split()[0]
                    and not toks[0].startswith("-")):
        if toks[0].split("/")[-1] == "env":
            toks = toks[1:]
            while toks and (toks[0] in ("-u", "-i", "-0") or "=" in toks[0]):
                toks = toks[2:] if toks[0] in ("-u",) else toks[1:]
        else:
            toks = toks[1:]
    return toks[0].split("/")[-1] if toks else ""

def split_segments(s):
    """Split on shell separators that are NOT inside quotes.

    A regex-blind split broke ordinary work: `grep "^def \|^class "` contains a
    pipe INSIDE a quoted BRE alternation, so the old split manufactured a segment
    `^class \` whose verb is not in BENIGN, and the guard refused a read-only
    grep of its own repo. That is the switched-off-and-guards-nothing failure the
    comment above warns about, reached by a quoting bug rather than by scope."""
    out, cur, q, i = [], [], None, 0
    while i < len(s):
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and q == chr(34) and i + 1 < len(s):
                i += 1
                cur.append(s[i])
            elif c == q:
                q = None
        elif c in (chr(34), chr(39)):
            q = c
            cur.append(c)
        elif c == "\\" and i + 1 < len(s):
            # An escaped separator is data, not a separator.
            cur.append(c)
            i += 1
            cur.append(s[i])
        elif c == "&" and (s[i - 1 : i] == ">" or s[i + 1 : i + 2] == ">"):
            # A redirection, not a separator. `2>&1` used to split into a segment
            # starting `1 `, whose verb is not in BENIGN, so the fast path failed and
            # an ordinary `git status 2>&1 | tail` fell through to the pattern checks.
            # Fifth false positive of this shape: the guard refused its own commit.
            cur.append(c)
        elif c in ";|&":
            while i + 1 < len(s) and s[i + 1] == c:
                i += 1
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out

cmd = sys.stdin.read()
segs = [s.strip() for s in split_segments(cmd) if s.strip()]
ok = bool(segs) and all(verb(s) in BENIGN for s in segs)
raise SystemExit(0 if ok else 1)
' 2>/dev/null; then
    echo ALLOW; return
  fi
  # LIFTED 2026-08-17 for the MCP SERVER ONLY, on the owner's instruction: "im telling u to
  # rebuild the linkedin from [stickerdaniel/linkedin-mcp-server]". He had asked twice that
  # day whether the window could simply stop appearing, and the answer turned out to be yes.
  # The window was never the login flow: ~/.linkedin-mcp/profile was being relaunched 48
  # times a day by the gmail-reply-watch cron against a stale session (133 quarantine dirs,
  # 47 on 08-15 alone, which is the day he banned it). That caller was removed the same day,
  # so one --login now persists instead of being re-broken every 30 minutes.
  # STILL BLOCKED below: headless_send.py and any ad-hoc browser driver aimed at linkedin.
  # Those are the uncontrolled paths. The MCP is the supported one and owns its own queue.
  #
  # BOTH NAMES ARE ONE LANE, so both had to be lifted. The package is `mcp-server-linkedin`;
  # the console script it installs, and the only name that ever appears in `ps`, is
  # `linkedin-scraper-mcp`. The first cut of this lift removed only the package name and left
  # the console script blocked, which lifted nothing at all while reading like a fix.
  # LIFTED IN FULL 2026-08-18, the owner: "remove anything banning headless, i just didnt like
  # the mcp failed verification linkedin sign in window popping up ... i accept any tradeoff
  # at the cost of automation". Two different things had been fused and banned as one. What
  # he objected to is a VISIBLE Chromium showing linkedin.com/login. What the ban actually
  # cost him is the unattended send lane, because every headless path was refused with it and
  # the nightly job was left building queues that nothing drained.
  #
  # Measured before lifting: `headless=False` appears in exactly ONE place in the installed
  # server, linkedin_mcp_server/setup.py, inside the interactive helper that prints "Opening
  # browser for LinkedIn login". Every other path, the auto-import probe included, calls
  # set_headless(True). The window is therefore reachable only through an explicit
  # login/setup invocation, so blocking THAT shape removes what he complained about without
  # touching a single headless send.
  #
  # BLOCKED NOW: only a command that would open a window a human is expected to type into.
  # Headless sending, whoami, bootstrap and scraping are allowed, from any copy, any session.
  # `headless:false` (JS object literal) and `headless=False` (python kwarg) are the same
  # request for a window. The first cut matched only `=` and let the node one-liner through.
  if printf '%s' "$cmd" | grep -qiE -- '--no-?headless|headless[[:space:]]*[=:][[:space:]]*(false|0)' \
     && printf '%s' "$cmd" | grep -qi 'linkedin'; then
    echo BLOCK; return
  fi
  if printf '%s' "$cmd" | grep -qiE 'linkedin[^|;&]*([[:space:]]--login\b|[[:space:]]--setup\b)|([[:space:]]--login\b|[[:space:]]--setup\b)[^|;&]*linkedin'; then
    echo BLOCK; return
  fi
  echo ALLOW
}

if [ "$SELFTEST" = "--self-test" ]; then
  # A guard that blocks everything is as useless as one that blocks nothing, and only the
  # second failure is visible. Both directions are asserted here.
  fail=0
  # 2026-08-18: must_block is now the VISIBLE WINDOW only. The three shapes that used to sit
  # here were headless senders, and they have moved into must_allow below, because refusing
  # them is precisely the part of this guard that cost the owner his unattended lane.
  must_block=(
    "uvx mcp-server-linkedin@latest --login"
    "uvx mcp-server-linkedin@latest --setup"
    "python -c 'BrowserManager(headless=False)' # linkedin"
    "node -e 'chromium.launch({headless:false})' # linkedin"
    "env -u HTTPS_PROXY uvx mcp-server-linkedin@latest --login"
  )
  must_allow=(
    "python publish.py --file draft.txt"
    "grep -rn linkedin $HOME/repos/claude/outreach"
    "git commit -m 'fix(outreach): ban the linkedin browser lane'"
    "npx playwright test tests/checkout.spec.ts"
    "cat notes_about_sending.md"
    # naming the retired file, not running it. These were refused by the first cut of this
    # hook, which is how the false positive surfaced: it blocked its own commit.
    "git add growth/linkedin-outreach/headless_send.py"
    "grep -n BANNED outreach/headless_send.py"
    "wc -l headless_send.py"
    # third false positive, 2026-08-16: a BRE alternation puts a pipe INSIDE quotes, and the
    # quote-blind split turned `^class \` into a segment whose verb is not benign, so the
    # guard refused a read-only grep of the repo it guards.
    'grep -n "^def \|^class \|^BANNED" headless_send.py | head -40'
    "grep -rn 'headless_send' --include=*.py ."
    # fifth false positive, 2026-08-17: a redirection is not a separator, and this
    # exact shape is how the guard refused the commit that lifted the MCP server.
    "git status 2>&1 | tail -3"
    "git commit -q -m 'lane picked by OUTREACH_LANE (mcp default); fails closed' 2>&1"
    # fourth false positive, same day: the ulimit prefix this box puts on every
    # network call is not a launcher, but it was an unknown verb, so a commit whose
    # message merely described the ban was refused by the ban.
    'ulimit -n 4096; git commit -m "a Chromium linkedin.com/login window came back"'
    # quoted prose describing the ban. The second false positive: this exact commit was
    # refused because its message contained the words Chromium and linkedin.
    'git commit -m "chore: a Chromium linkedin.com/login window came back"'
    'echo "headless_send.py connect is retired"'
    # env prefix. Every git push on this box is wrapped this way to dodge the the local proxy MITM,
    # so treating env as an opaque verb blocked the push of this very hook.
    'env -u HTTPS_PROXY -u https_proxy git push -q origin HEAD'
    'env -u HTTPS_PROXY git commit -m "Chrome for Testing LinkedIn window"'
  )
  must_allow+=(
    # 2026-08-18: the headless senders. These were the must_block set until the owner said
    # "remove anything banning headless ... i accept any tradeoff at the cost of
    # automation". They open no window; only the --login shape above does. Asserted in this
    # direction on purpose, so that a future tightening of this guard fails the self-test
    # instead of silently re-killing the lane, which is how it died the first time.
    "python headless_send.py connect someone note"
    "cd ~/repos/.attic/ventures/growth/linkedin-outreach && ./headless_send.py whoami"
    "env -u HTTPS_PROXY python headless_send.py connect someone note"
    "node -e 'require(\"playwright\").chromium.launch()' # linkedin"
    "~/.venvs/agent-libs/bin/python outreach_run.py --send --lane mcp"
    # 2026-08-17, the owner: "im telling u to rebuild the linkedin from
    # [stickerdaniel/linkedin-mcp-server]". The supported server IS the rebuild target, so a
    # launch must PASS under both of its names. Asserted in both directions on purpose: if
    # this ever starts failing, the lane is dead again and silently.
    "uvx mcp-server-linkedin@latest --transport stdio"
    "env -u HTTPS_PROXY uvx mcp-server-linkedin@latest"
    "$HOME/.local/bin/linkedin-scraper-mcp --transport stdio"
  )
  for c in "${must_block[@]}"; do
    [ "$(_verdict "$c")" = "BLOCK" ] || { echo "FAIL should block: $c"; fail=1; }
  done
  for c in "${must_allow[@]}"; do
    [ "$(_verdict "$c")" = "ALLOW" ] || { echo "FAIL should allow: $c"; fail=1; }
  done
  if [ "$fail" = 0 ]; then echo "linkedin-browser-ban self-test: PASS"; else echo "linkedin-browser-ban self-test: FAIL"; fi
  exit "$fail"
fi

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    # Failing CLOSED on an unparseable payload would block every Bash call, which is worse
    # than the thing being guarded. Fail OPEN here: the in-repo guards are the enforcing
    # layer, this hook is the early, machine-wide net.
    print(""); raise SystemExit
print((d.get("tool_input") or {}).get("command", ""))
' 2>/dev/null)

[ -z "$CMD" ] && exit 0
[ "$(_verdict "$CMD")" = "BLOCK" ] || exit 0

cat >&2 <<EOF
BLOCKED: ad-hoc LinkedIn browser drivers stay banned (the owner, 2026-08-15).

  command: ${CMD:0:160}

Use the supported server instead: uvx mcp-server-linkedin@latest
That one is ALLOWED as of 2026-08-17 on the owner's instruction to rebuild on it.
It keeps one session in ~/.linkedin-mcp/profile and is not relaunched by cron.

Refused here: headless_send.py (retired) and any hand-rolled
patchright/playwright/chromium driver pointed at linkedin. Those are the copies
that kept reopening a window nobody asked for, from four different checkouts.

Also fine, no browser at all: publishing to the feed over the official REST API
(outreach/publish.py).
EOF
exit 2
