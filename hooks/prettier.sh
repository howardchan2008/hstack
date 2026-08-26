#!/usr/bin/env bash
# PostToolUse hook: format ONLY the file just edited/written.
#
# Claude Code delivers hook data as JSON on stdin (tool_input.file_path).
# The previous version read "$@", which is always empty for this hook, so it
# fell through to `git ls-files --modified --others` and reformatted the whole
# dirty tree on every edit: ~9KB of stdout into model context, ~3s per edit.
#
# stdout from a PostToolUse hook lands in model context. Keep it silent.

set -u

payload=$(cat 2>/dev/null || true)

file=""
if [ -n "$payload" ]; then
  file=$(printf '%s' "$payload" | /usr/bin/python3 -c '
import json,sys
try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input") or {}
    print(ti.get("file_path") or ti.get("path") or "")
except Exception:
    print("")
' 2>/dev/null)
fi

# still honour an explicit path argument
if [ -z "$file" ] && [ $# -gt 0 ]; then
  file="$1"
fi

[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# NOTE: *.md is deliberately EXCLUDED. Verified 2026-07-23: prettier escapes a
# literal tilde in markdown, so `~/the owner-os/scripts/x.py` is rewritten to
# `~~/the owner-os/scripts/x.py`: corrupting every home-relative path it touches.
# It also re-flows plain lines into list continuations and injects blank lines.
# Running it across ~/.claude/**/memory/*.md was silently damaging the corpus on
# every edit. Do not add *.md back without re-testing that repro.
case "$file" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.yaml|*.yml|*.css|*.scss|*.html|*.toml) ;;
  *) exit 0 ;;
esac

if command -v prettier >/dev/null 2>&1; then
  prettier --write "$file" >/dev/null 2>&1
elif command -v npx >/dev/null 2>&1; then
  npx --yes prettier --write "$file" >/dev/null 2>&1
fi

exit 0
