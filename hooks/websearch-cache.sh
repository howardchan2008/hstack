#!/bin/bash
# websearch-cache: store what WebSearch/WebFetch returned, so the next session can read
# it instead of paying for it again.
#
# This is the half that makes websearch-router.sh gate 1 mean anything. Without a writer,
# "you already fetched this" is an assertion with no file behind it.
#
# Measured 2026-08-13: 432 of 1035 web calls in 30 days re-fetched a URL or query already
# pulled in that same window. Nothing was keeping the answer, so the answer got bought twice.
#
# The logic lives in lib/websearch-cache.py, not inline here. It was inline once and it
# hard-coded the key helper's filename; renaming that helper made every write raise
# FileNotFoundError, and the `2>/dev/null` on the end swallowed it, so the hook kept
# reporting success while caching nothing. A cache writer that fails silently is worse
# than no writer: the router keeps passing calls through and nothing says the other half
# is dead. Keep it in a file that can be run and tested on its own.
set -uo pipefail

# Resolve lib/ from THIS FILE, not from $HOME. The hook works when it is
# installed and also when it is run straight out of a clone, which is what
# the test suite and anyone evaluating it before installing will do. The
# $HOME form failed both, with an error that reads as the guard refusing.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/lib/websearch-cache.py"
[ -f "$LIB" ] || LIB="$HOME/.claude/hooks/lib/websearch-cache.py"

cat | /usr/bin/python3 "$LIB"

# Keep the cache from growing without bound: drop anything older than 30 days.
find "$HOME/.claude/state/websearch-cache" -type f -mtime +30 -delete 2>/dev/null
exit 0
