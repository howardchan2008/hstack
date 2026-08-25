#!/usr/bin/env bash
# PreToolUse(Bash): refuse a grep PCRE flag that will silently degrade to BSD grep.
#
# WHY THIS EXISTS: on 2026-08-03 a verification pass reported "no dashes found"
# across a tree it had not checked at all. The command was:
#
#     timeout 60 grep -rlP '[\x{2010}-\x{2015}]' --include='*.md' rules 2>/dev/null
#
# `grep` in this environment is a SHELL FUNCTION (see shell-snapshots/) that
# shims to the bundled ugrep, and ugrep DOES support -P. That is why the same
# flag works when typed bare. But `timeout` execs its argument directly, so the
# function never runs and the call lands on /usr/bin/grep, which is BSD grep and
# has no -P. It exits with "invalid option -- P", prints nothing to stdout, and
# `2>/dev/null` swallows the complaint. Empty output then reads as a clean
# result. A check that cannot fail loudly is not a check.
#
# SCOPE IS DELIBERATELY NARROW: this fires only when BOTH are true.
#   1. grep is invoked with a PCRE flag (-P, a bundle ending in P such as -oP or
#      -rlP, or --perl-regexp), and
#   2. that invocation bypasses the shell function, via a wrapper that execs
#      (timeout, xargs, env, find -exec, command, sh -c, bash -c) or via an
#      explicit path such as /usr/bin/grep.
#
# A bare `grep -P` is NOT blocked: the shim handles it and it works.
# A wrapped `grep -E` is NOT blocked: -E is POSIX and portable.
# Only the combination is always wrong, which keeps false positives at zero and
# means a block here is never something to argue with.
#
# Block contract matches risk-checkpoint.sh and dash-gate.sh: reason on stderr,
# exit 2. Escape hatch for a deliberate one-off: GREP_PORTABILITY_OFF=1.
set -u
[ "${GREP_PORTABILITY_OFF:-}" = "1" ] && exit 0
payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0
printf '%s' "$payload" | /usr/bin/python3 -c '
import json, re, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if (d.get("tool_name") or "") != "Bash":
    sys.exit(0)

cmd = ((d.get("tool_input") or {}).get("command") or "")
if not cmd:
    sys.exit(0)

# The escape hatch must be honoured from the COMMAND TEXT, not just the
# environment. Verified 2026-08-04: a hook is a separate process that Claude
# Code spawns BEFORE running the command, so an inline `VAR=1 cmd ...` prefix
# is never in the hook process environment and the env check alone can never
# fire. Documenting a hatch that cannot work is worse than having none, so
# match the assignment in the command string too.
if re.search(r"(?:^|[\s;&|])GREP_PORTABILITY_OFF=1(?:\s|$)", cmd):
    sys.exit(0)

# Wrappers that exec their argument, so the grep shell function never runs.
WRAPPER = re.compile(
    r"(?:^|[|;&\n(]|\s)(?:timeout(?:\s+-\S+)*\s+\S+|xargs(?:\s+-\S+)*|env|command|"
    r"sh\s+-c|bash\s+-c|zsh\s+-c)\s"
)
FIND_EXEC = re.compile(r"\bfind\b[^|;&\n]*?-(?:exec|execdir)\b")
# grep reached by an explicit path also bypasses the function.
PATHED = re.compile(r"(?:^|[|;&\n(]|\s)(?:/\S*/|\./)grep\b")
PCRE = re.compile(r"(?:^|\s)(?:-[A-Za-z]*P|--perl-regexp)(?:\s|=|$)")

# Split into pipeline/list segments; a wrapper only affects its own segment.
segments = re.split(r"\|\||&&|[|;\n]", cmd)

bad = []
for seg in segments:
    # \b excludes ugrep (u and g are both word chars, no boundary) but still
    # catches /usr/bin/grep and a quoted "grep inside bash -c.
    if not re.search(r"\bgrep\b", seg):
        continue
    if not PCRE.search(seg):
        continue
    bypass = None
    if PATHED.search(seg):
        bypass = "an explicit path to the grep binary"
    elif FIND_EXEC.search(seg):
        bypass = "find -exec"
    else:
        m = WRAPPER.search(seg)
        if m:
            bypass = m.group(0).strip()
    if bypass:
        bad.append((seg.strip()[:160], bypass))

if not bad:
    sys.exit(0)

seg, bypass = bad[0]
sys.stderr.write(
    "BLOCKED grep-portability: PCRE flag through a shim bypass.\n\n"
    "  segment: " + seg + "\n"
    "  bypassed by: " + bypass + "\n\n"
    "`grep` here is a shell function shimming to ugrep, which supports -P.\n"
    "The wrapper above execs the binary directly, so this call lands on\n"
    "/usr/bin/grep (BSD), which has no -P. It prints nothing and exits nonzero.\n"
    "With 2>/dev/null that silent failure is indistinguishable from a clean\n"
    "result, so the check passes while having verified nothing.\n\n"
    "Fix, in order of preference:\n"
    "  1. Drop the wrapper and call grep bare, so the shim applies.\n"
    "  2. Rewrite the pattern in POSIX ERE and use -E, which is portable.\n"
    "  3. For real PCRE (lookaround, \\K, \\x{...}) use python3 or perl, which\n"
    "     also lets the check fail loudly instead of silently.\n\n"
    "Never pair this with 2>/dev/null: that converts a hard error into a false\n"
    "pass. Deliberate one-off: GREP_PORTABILITY_OFF=1.\n"
)
sys.exit(2)
'
