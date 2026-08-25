#!/bin/bash
# probe-dedupe: PreToolUse(Bash). Warns on the 2nd and 3rd look at a subject
# already probed this session, blocks on the 4th.
#
# Logic lives in lib/probe-dedupe.py, following websearch-cache.sh: an inline
# implementation there once hard-coded a helper filename, the rename made every
# call raise FileNotFoundError, and a trailing 2>/dev/null swallowed it, so the
# hook reported success while doing nothing. Keep it in a file that can be run
# and tested on its own, and do NOT silence its stderr.
set -uo pipefail

# Resolve lib/ from THIS FILE, not from $HOME. The hook works when it is
# installed and also when it is run straight out of a clone, which is what
# the test suite and anyone evaluating it before installing will do. The
# $HOME form failed both, with an error that reads as the guard refusing.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/lib/probe-dedupe.py"
[ -f "$LIB" ] || LIB="$HOME/.claude/hooks/lib/probe-dedupe.py"

cat | /usr/bin/python3 "$LIB"
rc=$?

# Drop session state older than a day so the directory cannot grow without bound.
find "$HOME/.claude/state/probe-dedupe" -type f -mtime +1 -delete 2>/dev/null

exit $rc
