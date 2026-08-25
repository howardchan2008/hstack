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

cat | /usr/bin/python3 "$HOME/.claude/hooks/lib/probe-dedupe.py"
rc=$?

# Drop session state older than a day so the directory cannot grow without bound.
find "$HOME/.claude/state/probe-dedupe" -type f -mtime +1 -delete 2>/dev/null

exit $rc
