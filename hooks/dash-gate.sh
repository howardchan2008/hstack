#!/usr/bin/env bash
# PreToolUse(Write|Edit): refuse to write a unicode dash into an authored file.
#
# WHY THIS EXISTS: "no em dashes" has lived in CLAUDE.md and memory since
# 2026-07-25 and still regressed repeatedly. Memory stops a session that reads
# it; it does nothing about a session that does not. This is the mechanical half.
#
# SCOPE IS DELIBERATELY NARROW, twice over:
#
#  1. Unicode dashes only, NOT the double hyphen. In shell the double hyphen is
#     the end-of-options marker: `grep -qF -- "$want"` is correct and
#     load-bearing, and rewriting it breaks argument parsing whenever the
#     operand starts with a dash. A gate that flags it teaches the next session
#     to introduce that bug. The prose case stays a human judgment call.
#
#  2. Authored extensions only. Captured third-party text (inbox dumps, scraped
#     pages, transcripts) legitimately contains em dashes and lands in
#     .json/.csv/.html. Gating those corrupts data capture to enforce a style
#     rule, so the gate never reads those extensions. Deliberate boundary with
#     a stated mechanism, not a defect noticed and left unfixed.
#
# The dash characters are built from CODEPOINTS, never written literally. If
# this file contained a literal em dash it would block every future edit to
# itself. Do not "simplify" those chr() calls back to literals.
#
# Block contract matches risk-checkpoint.sh: reason on stderr, exit 2.
# Escape hatch for a deliberate verbatim quote: DASH_GATE_OFF=1.
set -u
[ "${DASH_GATE_OFF:-}" = "1" ] && exit 0
payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0
printf '%s' "$payload" | /usr/bin/python3 -c '
import json, re, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

ti = d.get("tool_input") or {}
path = ti.get("file_path") or ti.get("path") or ""
if not path:
    sys.exit(0)

# Write carries full content; Edit carries only the replacement text.
parts = [ti.get(k) for k in ("content", "new_string")]
text = "\n".join(p for p in parts if isinstance(p, str))
if not text:
    sys.exit(0)

ENFORCED = (".md", ".sh", ".py", ".js", ".jsx", ".ts", ".tsx", ".txt")
if not path.endswith(ENFORCED):
    sys.exit(0)

EXEMPT = (
    r"CLAUDE\.original",
    r"\.original\.",
    r"\.prev\.",
    r"/hooks/README\.md$",
    r"/node_modules/",
    r"/\.git/",
    r"/(queue|transcripts|inbox)/",
)
if any(re.search(p, path) for p in EXEMPT):
    sys.exit(0)

DASHES = {chr(0x2014): "em dash", chr(0x2013): "en dash", chr(0x2015): "horizontal bar"}
hits = []
for i, line in enumerate(text.split("\n"), 1):
    for ch, name in DASHES.items():
        if ch in line:
            hits.append((i, name, line.strip()[:90]))
            break
if not hits:
    sys.exit(0)

out = ["BLOCKED: unicode dash in an authored file.", "  file: " + path, ""]
for ln, name, snip in hits[:6]:
    out.append("  line %d  %s:  %s" % (ln, name, snip))
if len(hits) > 6:
    out.append("  ... and %d more" % (len(hits) - 6))
out += [
    "",
    "Rule: CLAUDE.md line 1, NO EM DASHES. Replace with a colon, a comma, or",
    "split the sentence. Pick per site, do not blanket-substitute.",
    "",
    "Quoting someone verbatim and the dash must survive?  DASH_GATE_OFF=1",
]
print("\n".join(out), file=sys.stderr)
sys.exit(2)
'
