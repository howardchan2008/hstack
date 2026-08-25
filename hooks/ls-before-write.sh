#!/usr/bin/env bash
# PreToolUse(Write): refuse to write blind into a directory you have not looked at.
#
# WHY THIS EXISTS: on 2026-08-11 a session re-ran an entire finished audit from
# scratch because it never listed the working directory. The sequence was:
#
#   mkdir -p ~/repos/.attic/_data/the owner-os-data/unfixable-audit && echo ok   -> printed "ok"
#   Write .../extract.py                                   -> clobbered the real one
#
# mkdir -p is idempotent and silent, so "ok" means "the directory exists now",
# never "I created it". Write shows no siblings, so a directory holding REPORT.md
# and 7 finished scripts is indistinguishable from an empty one. The result was a
# rebuilt pipeline, an overwritten candidates.jsonl, and a report whose own file
# manifest no longer matched the file it described.
#
# TWO BLOCKING CASES, both narrow:
#
#   1. The target file already exists. This is a clobber. Claude Code nominally
#      wants a Read first; it did not stop the 2026-08-11 case, so this does.
#   2. The target file is new, but the directory contains a completion marker
#      (REPORT.md, FIX-BACKLOG.md, SUMMARY.md, RESULTS.md, FINDINGS.md). That is
#      the signal the job in this directory is already done. Read it first.
#
# Everything else passes silently: new file, ordinary directory, no interruption.
#
# The block message carries the actual listing, so the very next thing in context
# is the thing that was missing. /bin/ls is used deliberately: `ls` is aliased to
# eza in this shell and produces NO output non-interactively, which is how the
# directory stayed invisible in the first place.
#
# Block contract matches dash-gate.sh and risk-checkpoint.sh: reason on stderr,
# exit 2. Escape hatch once acknowledged: LS_GATE_OFF=1.
set -u
[ "${LS_GATE_OFF:-}" = "1" ] && exit 0
payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0

printf '%s' "$payload" | /usr/bin/python3 -c '
import json, os, subprocess, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if (d.get("tool_name") or "") != "Write":
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ti.get("path") or ""
if not path:
    sys.exit(0)

path = os.path.expanduser(path)
parent = os.path.dirname(path) or "."

# A directory that does not exist yet cannot be hiding finished work.
if not os.path.isdir(parent):
    sys.exit(0)

MARKERS = ("REPORT.md", "FIX-BACKLOG.md", "SUMMARY.md", "RESULTS.md", "FINDINGS.md")

# Skip scratch and machine-managed trees, where clobbering is the normal mode.
SKIP = ("/tmp/", "/var/folders/", "/node_modules/", "/.git/", "/__pycache__/",
        "/.claude/projects/", "/scratchpad/")
if any(s in path for s in SKIP):
    sys.exit(0)

try:
    entries = sorted(os.listdir(parent))
except OSError:
    sys.exit(0)

exists = os.path.exists(path)
present = [m for m in MARKERS if m in entries]

if not exists and not present:
    sys.exit(0)

try:
    listing = subprocess.run(
        ["/bin/ls", "-la", parent],
        capture_output=True, text=True, timeout=10).stdout.rstrip()
except Exception:
    listing = "\n".join("  " + e for e in entries[:40])

if exists:
    try:
        sz = os.path.getsize(path)
    except OSError:
        sz = -1
    why = "TARGET EXISTS: this Write REPLACES it (%d bytes)." % sz
    fix = "Read %s first. If replacing is intended, re-run with LS_GATE_OFF=1." % path
else:
    why = ("DIRECTORY HAS A COMPLETION MARKER: %s. The work here may already be "
           "finished." % ", ".join(present))
    fix = ("Read %s before writing. If it is genuinely unrelated, re-run with "
           "LS_GATE_OFF=1." % os.path.join(parent, present[0]))

sys.stderr.write(
    "BLOCKED: writing blind into a directory you have not listed.\n\n"
    "  file: %s\n  %s\n\nDirectory now:\n\n%s\n\n%s\n\n"
    "Rule: memory feedback-mkdir-p-masked-finished-work. mkdir -p is never proof\n"
    "of newness, and Write shows no siblings.\n" % (path, why, listing, fix))
sys.exit(2)
'
rc=$?
[ "$rc" = "2" ] && exit 2
exit 0
