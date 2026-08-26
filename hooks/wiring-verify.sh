#!/usr/bin/env bash
# wiring-verify.sh: assert the guard hooks are actually armed in settings.json.
#
# Why this exists: the lines that arm risk-checkpoint, stop-justify, lane-guard
# and agent-budget live ONLY in ~/.claude/settings.json, which is gitignored
# because it carries private env. Nothing in the repo can restore them and
# nothing checked them. Drop a matcher and the guard stays on disk, passes every
# "is the file there?" test, and is silently inert.
#
# Runs at SessionStart. Prints ONE line when healthy (a verifier that is
# silent on success is indistinguishable from a dead one) and a loud block
# when not. Always exits 0: this must never be the reason a session fails.
#
# WHAT THIS CANNOT DO. If the hooks block is wiped wholesale, this script is
# itself unwired and prints nothing. Absence of output is therefore the loudest
# possible failure, and no in-hook design can fix that from the inside. The
# mitigation is the settings backup below, not more checking in here.
#
# It also does not verify hook CONTENT. A path that resolves inside hooks/ to a
# real non-empty file passes even if that file was rewritten to do nothing.
# Pinning content would need a manifest of blessed hashes, and a self-refreshing
# manifest launders exactly the change it exists to catch. Left deliberately undone.

set -uo pipefail
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
BACKUP_DIR="${CLAUDE_SETTINGS_BACKUPS:-$HOME/.claude/backups/settings}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "!! WIRING-VERIFY DEAD: python3 not found. Guard wiring UNVERIFIED."
  exit 0
fi

ok_frags=""

python3 - "$SETTINGS" "$BACKUP_DIR" <<'PY' > /tmp/wiring-verify.$$ 2>&1
import glob, hashlib, json, os, sys, time

settings   = sys.argv[1]
backup_dir = sys.argv[2]

# Canonical hooks dir. Any wired command must resolve INSIDE this, after
# symlinks: "the file exists" is not the same claim as "the file is mine".
HOOKS_DIR = os.path.realpath(os.path.expanduser("~/.claude/hooks")) + os.sep

# event | script basename | tool names the matcher MUST cover
REQUIRED = [
    ("PreToolUse",       "risk-checkpoint.sh",     ["Bash", "Edit", "Write"]),
    ("PreToolUse",       "lane-guard.sh",          ["Workflow"]),
    ("PreToolUse",       "agent-budget.sh",        ["Agent"]),
    ("Stop",             "stop-justify.sh",        []),
    ("UserPromptSubmit", "state-verify-inject.sh", []),
]

# Every hook expected to be present. The hooks block is an arbitrary-code-
# execution surface that runs before every tool call, so an ADDITION is as
# interesting as a deletion. Anything not on this list gets surfaced for review.
# Adding a hook on purpose means adding it here on purpose.
KNOWN = {
    "context-save.sh", "stop-justify.sh", "prettier.sh", "cl2-observe.sh",
    "lane-guard.sh", "risk-checkpoint.sh", "agent-budget.sh",
    "session-collide.sh", "context-restore.sh", "wiring-verify.sh",
    "burn-context.sh", "state-verify-inject.sh", "auto-push.sh",
    "dash-gate.sh",   # PreToolUse Write|Edit: blocks em dashes in written output
    # Added 2026-08-17, same reason as the eleven below: it landed committed
    # (9210a9d) from a concurrent session and printed REVIEW at every start.
    # Added 2026-08-14. All eleven below were registered, on disk, deliberate,
    # and printed REVIEW at EVERY session start because this list had not been
    # updated since they landed. Twelve lines of false alarm per session is not
    # a check: the one line that would ever mean something is buried in eleven
    # that never do, so the reader learns to skip the whole block.
    "websearch-cache.sh",     # PostToolUse WebSearch|WebFetch
    "fetch-guard.sh",         # PreToolUse Write|Edit
    "grep-portability.sh",    # PreToolUse Bash
    "curl-router.sh",         # PreToolUse Bash
    "linkedin-path-guard.sh", # PreToolUse browser MCPs
    "ls-before-write.sh",     # PreToolUse Write
    "click-credit-guard.sh",  # PreToolUse mcp__.*__click_.*
    "websearch-router.sh",    # PreToolUse WebSearch|WebFetch
    "closeout-preflight.sh",  # UserPromptSubmit: injects the DONE/YOUR MOVE contract.
                              # Twelfth of the same class as the eleven above: real,
                              # deliberate, and printing REVIEW every session because
                              # nobody added it here when it landed.
    # Added 2026-08-16. Thirteenth through fifteenth of that same class. The first
    # two were printing REVIEW at every session start for days before anyone read
    # the line. The pattern is now unambiguous: this list goes stale by DEFAULT,
    # because landing a hook and registering it here are two separate acts and only
    # the first one is load-bearing at the moment you do it. A guard whose false
    # alarms outnumber its true ones trains the reader to skip it, which is the
    # same end state as having no guard at all.
    "linkedin-browser-ban.sh",  # PreToolUse Bash: refuses to launch the LinkedIn lane
    "pipestatus-guard.sh",   # PreToolUse Bash: exit code lost to a pipe
    "carryover-queue.py",       # UserPromptSubmit: injects unfinished work after an
                                # interrupt, so a new prompt adds to the queue instead
                                # of silently replacing what was in flight.
    "prompt-items.py",          # UserPromptSubmit: re-injects the ITEMS of the previous
                                # prompt. Covers the hole carryover-queue.py cannot see,
                                # a single multi-part prompt where only part one gets
                                # answered: no interrupt marker, no open task, nothing
                                # fires. Added 2026-08-20 on the owner's instruction.
                                # (gdoc, per-tab SOT page, memory, capability map) as paths
                                # and commands rather than a reminder to go look. Added
                                # 2026-08-20 after measuring that only 37% of sessions
                                # touched any SOT layer at all. Silent by default: it fires
                                # on ~10% of human turns, which is the point.
    # Added 2026-08-24. Sixteenth through eighteenth of the same class, and the
    # last three that were printing REVIEW at every session start. All three are
    # committed, deliberate and load-bearing:
    "outbound-copy-gate.py",  # PreToolUse whatsapp/linkedin/mail: copy-lint sees
                              # every message before a real person does (795c9ab).
    "probe-dedupe.sh",        # PreToolUse Bash: warns on the 2nd and 3rd look at a
                              # subject already probed, blocks the 4th (8c6922b).
                              # before a second agent starts work on it (1da63de).
    # Completed from the manifest at build time: every hook
    # this repo ships is known to the checker that verifies it.
    "closeout-shape.py",
    "item-coverage.py",
    "session-identity.sh",
}

try:
    with open(settings) as f:
        hooks = json.load(f).get("hooks", {})
except Exception as e:
    print("!! WIRING-VERIFY DEAD: cannot read %s (%s). Guard wiring UNVERIFIED." % (settings, e))
    sys.exit(0)


def covers(matcher, tool):
    if matcher in (None, "", "*"):
        return True
    return tool in [p.strip() for p in matcher.split("|")]


def resolve(tok):
    """Return (ok_inside_hooks_dir, realpath)."""
    p = os.path.realpath(os.path.expanduser(tok))
    return p.startswith(HOOKS_DIR), p


problems = []
review   = []

# --- 1. required guards are wired, cover their tools, and point at real files ---
for event, script, tools in REQUIRED:
    entries = []
    for group in hooks.get(event, []) or []:
        for h in group.get("hooks", []) or []:
            if script in (h.get("command") or ""):
                entries.append((group.get("matcher"), h.get("command") or ""))

    if not entries:
        problems.append("%s NOT WIRED in %s: guard is inert" % (script, event))
        continue

    for tool in tools:
        if not any(covers(m, tool) for m, _ in entries):
            problems.append("%s wired in %s but matcher does not cover %s: inert for %s"
                            % (script, event, tool, tool))

    # Check EVERY entry, not just the first: a second, shadowing entry pointing
    # somewhere else is precisely the thing worth catching.
    for _, cmd in entries:
        toks = [t.strip('"\'') for t in cmd.split() if t.strip('"\'').endswith(script)]
        if not toks:
            problems.append("%s wired in %s but no path token found in: %s"
                            % (script, event, cmd[:60]))
            continue
        for tok in toks:
            if "/" not in tok:
                problems.append("%s wired in %s by BARE NAME (%s): resolves via PATH/cwd, "
                                "not verifiable and hijackable" % (script, event, tok))
                continue
            inside, path = resolve(tok)
            if not inside:
                problems.append("%s wired in %s resolves OUTSIDE hooks/: %s" % (script, event, path))
            elif not os.path.isfile(path):
                problems.append("%s wired in %s but file MISSING: %s" % (script, event, path))
            elif os.path.getsize(path) == 0:
                problems.append("%s wired in %s but file is EMPTY: %s" % (script, event, path))

# --- 2. full inventory: what ELSE is wired into the execution surface? ---
total = 0
for event, groups in hooks.items():
    for group in groups or []:
        matcher = group.get("matcher")
        for h in group.get("hooks", []) or []:
            total += 1
            cmd = (h.get("command") or "").strip()
            base = None
            # .py and .js belong here as much as .sh: a hook is whatever the
            # harness executes. Accepting only .sh/.md made every python hook
            # permanently UNRECOGNISED, so guild-claim-owner.py could never be
            # blessed no matter what the KNOWN list said. Fixed 2026-08-14.
            for t in cmd.split():
                t = t.strip('"\'')
                if t.endswith((".sh", ".md", ".py", ".js", ".ps1")):
                    base = os.path.basename(t)
                    break
            if base is None:
                review.append("UNRECOGNISED %s entry: %s" % (event, cmd[:70]))
            elif base not in KNOWN:
                review.append("UNEXPECTED hook %s (%s, matcher=%s): %s"
                              % (base, event, matcher, cmd[:70]))
                # Wildcard is only alarming on a hook nobody blessed: arbitrary
                # code on every single tool call, from an unknown source. On a
                # KNOWN hook it is a decision already made, and repeating it
                # every session taught the reader to skip the block it sits in.
                if matcher == "*":
                    review.append("  ^ and it runs on EVERY %s call (wildcard matcher)" % event)

# --- 3. timestamped backup of settings.json ------------------------------------
# Deliberately NOT a "blessed good state" file that refreshes itself, which
# would launder the change it exists to catch. These are dated copies, deduped,
# capped. They live in backups/, which the allowlist .gitignore excludes, so
# private env in settings.json can never reach the repo.
def backup():
    try:
        os.makedirs(backup_dir, exist_ok=True)
        os.chmod(backup_dir, 0o700)
        raw = open(settings, "rb").read()
        prior = sorted(glob.glob(os.path.join(backup_dir, "settings.*.json")))
        if prior:
            with open(prior[-1], "rb") as f:
                if hashlib.sha256(f.read()).digest() == hashlib.sha256(raw).digest():
                    return "unchanged"
        dest = os.path.join(backup_dir, "settings.%s.json" % time.strftime("%Y%m%d-%H%M%S"))
        with open(dest, "wb") as f:
            f.write(raw)
        os.chmod(dest, 0o600)
        for old in sorted(glob.glob(os.path.join(backup_dir, "settings.*.json")))[:-20]:
            os.remove(old)
        return "saved " + os.path.basename(dest)
    except Exception as e:
        return "BACKUP FAILED (%s)" % e

bstat = backup()

# --- 4. report ------------------------------------------------------------------
if problems:
    print("!! " + "=" * 66)
    print("!! WIRING-VERIFY FAILED: a guard is installed-looking but inert.")
    for p in problems:
        print("!!   - " + p)
    print("!! Fix in %s (gitignored, not restorable from the repo)." % settings)
    print("!! Dated copies: %s" % backup_dir)
    print("!! " + "=" * 66)
else:
    # MERGED 2026-08-24. This used to be its own line, and the three checks that
    # follow in bash each printed their own healthy line beside it: four lines of
    # "nothing is wrong" every session start. They are now one. Silence is NOT an
    # option here for the reason in the header (a verifier that says nothing on
    # success reads exactly like a dead one), so the fix is width, not deletion.
    print("SUMMARY %d/%d armed · %d entries · backup %s"
          % (len(REQUIRED), len(REQUIRED), total, bstat))

for r in review:
    print("wiring-verify: REVIEW: " + r)
PY

# --- hook regex compile check -----------------------------------------------------
# WIRED 2026-08-14. hook-regex-check.py was written 2026-07-24 to catch the exact
# failure it was born from: stop-justify.sh S2d used `[?]{0,400}` against BSD grep,
# which refuses the interval and returns "no match", so the gate was silently OFF
# while looking armed. The checker then sat with ZERO callers and ZERO transcript
# invocations for three weeks, which makes it the same category of thing it exists
# to detect. Silent on success. Reports, never blocks.
if [ -f "$HOME/.claude/tools/hook-regex-check.py" ]; then
  rxout="$(python3 "$HOME/.claude/tools/hook-regex-check.py" "$HOME"/.claude/hooks/*.sh 2>&1 | grep '!!' || true)"
  [ -n "$rxout" ] && printf '%s\n' "$rxout" | sed 's/^[[:space:]]*/wiring-verify: regex: /'
fi

# --- rule-surface pointer check ---------------------------------------------------
# WIRED 2026-08-18. Resolves every path, skill, agent and memory name cited in the
# ALWAYS-LOADED rule surface (CLAUDE.md, rules/**, MEMORY.md, cold-index.md) against
# the disk. Born from three pointers that each cost a wasted turn before anyone
# noticed: `~/CLAUDE-CODEX-HANDOFF.md` (moved under .claude/reference),
# `the owner-routine-author` (archived, so naming it routes nowhere), and
# `~/code/linkedin-orchestrator` (tree gone). A dead pointer never errors; it sends
# the next session looking, which is why prose alone could not hold it. The checker
# excuses names the surrounding text already retires, so retirement notes stay
# quotable. `--negative-control` proves it can both fire and stay quiet (8/8).
# Silent on success. Reports, never blocks.
if [ -x "$HOME/.claude/bin/pointer-check" ]; then
  pcout="$("$HOME/.claude/bin/pointer-check" 2>&1)" || printf '%s\n' "$pcout" | sed 's/^[[:space:]]*/wiring-verify: pointer: /'
fi

# claims-audit: how many numbers in the hooks and rules cannot be re-derived.
# ONE LINE, always, never the list. Three cited figures were wrong in the week of
# 2026-08-23 ("7855 close-outs", "24% repeat probes", "913 glob failures") and all
# three were live-tree slices written down as totals. A standing count keeps the
# debt visible; `claims-audit` with no argument prints the offenders.
if [ -x "$HOME/.claude/bin/claims-audit" ]; then
  caout="$("$HOME/.claude/bin/claims-audit" --count 2>/dev/null)"
  if printf '%s' "$caout" | grep -q ', 0 without provenance'; then
    ok_frags="$ok_frags · claims $(printf '%s' "$caout" | sed -n 's/.*: \([0-9]*\) measurement.*/\1/p')/0"
  elif [ -n "$caout" ]; then
    printf 'wiring-verify: %s\n' "$caout"
  fi
fi

# guard-verdict: are the guards costing more round trips than they prevent?
# negative-control already asks whether each guard CAN fire and CAN stay quiet.
# It cannot see a guard that fires correctly and still wastes a call, which is
# what probe-dedupe did on the day it shipped: 28 of that day's 111 failed Bash
# calls. The 25% threshold is the measured baseline plus headroom, not taste:
# `guard-verdict` over the live tree on 2026-08-24 read 1,215 blocks at 19%
# idle, and risk-checkpoint's arm-then-retry handshake is idle BY DESIGN, so it
# alone accounts for most of that. Re-derive with `guard-verdict --count`.
# Above the threshold, something is charging per call instead of per decision,
# and that gets its own line rather than a shared fragment.
if [ -x "$HOME/.claude/bin/guard-verdict" ]; then
  gvout="$("$HOME/.claude/bin/guard-verdict" --count 2>/dev/null)"
  gvpct="$(printf '%s' "$gvout" | sed -n 's/.*blocks, \([0-9]*\)% wasted.*/\1/p')"
  if [ -n "$gvpct" ] && [ "$gvpct" -lt 25 ] 2>/dev/null; then
    ok_frags="$ok_frags · guards ${gvpct}% idle"
  elif [ -n "$gvout" ]; then
    printf 'wiring-verify: %s (run guard-verdict for the per-guard table)\n' "$gvout"
  fi
fi

# --- did Claude Code itself change under us? ---------------------------------------
# A new version is announced by the tool list, never by the delta, so a capability that
# shipped is indistinguishable here from one that never existed. This prints only when
# the installed version moved since the last session, and it is silent every other time.
if [ -x "$HOME/.claude/bin/cc-whatsnew" ]; then
  "$HOME/.claude/bin/cc-whatsnew" --check 2>/dev/null
fi

# --- surface breadcrumbs that nothing else reads -----------------------------------
# Two pipelines here wrote their output where no reader existed. sot-people-refresh.sh
# writes a LOUD failure file on every broken session end and nothing ever looked at it,
# so it rotted silently from 2026-08-24. cl2-distill.sh distils 122MB of observations
# into a daily friction report whose only reference in the whole tree is the script that
# writes it. Producing a file is not value until something consumes it, which is the
# standing rule these two were quietly breaking. Both lines below are signal-gated and
# print nothing on a healthy day.
if [ -f "$HOME/.claude/SOT-REFRESH-BROKEN.md" ]; then
  _sr="$(sed -n 's/^\*\*Reason:\*\* //p' "$HOME/.claude/SOT-REFRESH-BROKEN.md" | head -1 | cut -c1-90)"
  printf 'wiring-verify: SOT refresh is broken since %s. %s\n' \
    "$(stat -f '%Sm' -t '%Y-%m-%d' "$HOME/.claude/SOT-REFRESH-BROKEN.md")" "$_sr"
fi
_fr="$HOME/.claude/homunculus/staging/friction-$(date +%Y-%m-%d).md"
if [ -f "$_fr" ]; then
  _top="$(sed -n 's/^- (\([0-9]*\)x) `\([^`]*\)`.*/\1x \2/p' "$_fr" | head -1)"
  [ -n "$_top" ] && printf 'wiring-verify: top friction today %s (see %s)\n' "$_top" "${_fr#$HOME/}"
fi

# --- did any scheduled job fail? --------------------------------------------------
# A silent-failure audit found most launchd jobs write logs nothing reads, so a daily
# job could fail for weeks unnoticed. Rather than wire a reader per job, use the one
# every job already reports: column 2 of `launchctl list` is the last exit status.
# NEGATIVE values are signals, not failures: -15 is the SIGTERM from a deliberate
# `launchctl kickstart -k`, and four jobs showed it purely because they had just been
# restarted. Only a POSITIVE status means the job itself returned an error.
_failed="$(launchctl list 2>/dev/null | awk '$3 ~ /the owner/ && $2 ~ /^[1-9][0-9]*$/ {print $3"("$2")"}' | tr '\n' ' ')"
[ -n "$_failed" ] && printf 'wiring-verify: scheduled job(s) last exited non-zero: %s\n' "$_failed"

# --- one healthy line for all four checks -----------------------------------------
# The python block wrote SUMMARY only when it found nothing wrong; every real
# finding it had already printed itself, above, in full. Emit the merged line last
# so it reads as the all-clear for everything on this page.
if [ -f "/tmp/wiring-verify.$$" ]; then
  grep -v '^SUMMARY ' "/tmp/wiring-verify.$$"
  sline="$(sed -n 's/^SUMMARY //p' "/tmp/wiring-verify.$$")"
  [ -n "$sline" ] && printf 'wiring-verify: %s%s\n' "$sline" "$ok_frags"
  rm -f "/tmp/wiring-verify.$$"
fi

exit 0
