#!/bin/bash
# PreToolUse(Bash): refuse a state-changing command whose exit code is thrown away
# by a pipe.
#
# WHY THIS EXISTS, with the number. An audit on 2026-08-25 read 116 correction
# events across 12 weeks of transcripts and confirmed 85 assertions that were
# false when made. The largest class, 41 of 85 (48%), was MEASUREMENT ARTIFACT:
# a tool's output misread as fact. The single most repeated instance is this one.
#
#   git push -q origin main 2>&1 | head -2
#
# `$?` there is head's status, not git's. head almost always succeeds, so a
# failed push reads as a clean one. That exact line ran in this session, printed
# nothing, and was reported to the owner as "pushed" while the commit was still
# local. The same shape hides a failed kill, a failed launchctl, a failed commit.
#
# NARROW ON PURPOSE. Only verbs where a false success gets reported to the owner as
# done: push, commit, kill, launchctl. Piping `ls` or `grep` into head is
# completely fine and must never be blocked, because a guard that fires on
# ordinary commands earns 19% idle blocks and gets worked around rather than
# heeded. Measured shape of the guards that already exist here: dash-gate blocks
# 290 times with 0% idle because it only fires on a real defect.
#
# THE FIX IT ASKS FOR is cheap: drop the pipe, or capture first and filter after,
# or read ${PIPESTATUS[0]}. Any of those makes the failure visible.
set -u

payload="$(cat)"
cmd="$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
print((d.get("tool_input") or {}).get("command") or "")' 2>/dev/null)"

[ -n "$cmd" ] || exit 0

# Already handled: the caller is reading the real status, or asked the shell to
# propagate it. Either way there is nothing to warn about.
case "$cmd" in
  *PIPESTATUS*|*pipefail*) exit 0 ;;
esac

# A verb whose failure gets reported as success, immediately followed by a pipe
# into a filter, with no intervening command separator.
# `git -C <path> push` is the form used most often here and the first version of
# this pattern missed it entirely, because it required the subcommand to follow
# `git` directly. The live end-to-end test caught that, not the unit cases.
gitpre='git([[:space:]]+-[Cc][[:space:]]*[^[:space:]]+)*[[:space:]]+'
verbs="${gitpre}(push|commit)|kill[[:space:]]|launchctl[[:space:]]+(kickstart|bootout|bootstrap|load|unload)"
filters='head|tail|grep|cut|awk|sed|wc|sort|uniq|tr'

# Strip redirections BEFORE matching. `2>&1` contains an ampersand, and treating
# that as a command separator made the guard miss the exact line that motivated
# it: `git push -q origin main 2>&1 | head -2` sailed through the first test run.
# Caught by the negative control, not by reading the regex.
clean="$(printf '%s' "$cmd" | /usr/bin/sed -E 's/[0-9]*>&[0-9]*//g; s/[0-9]*>>?[[:space:]]*[^ |;&]+//g')"

hit="$(printf '%s' "$clean" \
  | /usr/bin/grep -oE "(${verbs})[^|;&]*\|[[:space:]]*(${filters})" \
  | /usr/bin/head -1)"

[ -n "$hit" ] || exit 0

cat >&2 <<EOF
⛔ pipestatus-guard: this command's exit code is discarded by the pipe.

  $hit

The status you would read back is the filter's, not the command's, and the
filter nearly always succeeds. A failed push, commit, kill or launchctl will
look identical to a clean one. That exact mistake was reported to the owner as
"pushed" on 2026-08-25 while the commit was still local, and measurement
artifacts of this kind are 41 of the 85 false claims found across 12 weeks.

Do one of these instead:
  1. Drop the filter:            git push origin main
  2. Capture, then filter:       out=\$(git push origin main 2>&1); rc=\$?; printf '%s' "\$out" | tail -2
  3. Read the real status:       git push origin main | tail -2; [ "\${PIPESTATUS[0]}" -eq 0 ]

Then VERIFY the outcome independently rather than trusting the exit code at all,
which for a push means: git rev-list --count HEAD --not --remotes
EOF
exit 2

