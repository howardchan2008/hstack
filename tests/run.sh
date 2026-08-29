#!/usr/bin/env bash
# run.sh - the whole suite, in the order that fails cheapest first.
#
#   1. syntax        every hook parses. A hook with a syntax error is a hook that
#                    exits non-zero on every payload, which on a PreToolUse event
#                    means it blocks every tool call in the session.
#   2. parity        the repo agrees with itself: manifest, settings example,
#                    the checker's roster, the docs table, the README count.
#   3. self-tests    the four hooks that carry their own.
#   4. negative      every guard refuses what it exists to refuse, and stays out
#                    of the way of ordinary work.
#   5. dead branches  every regex in every hook is load-bearing: corrupt it and
#                    that hook's own self-test must notice. Sections 3 and 4
#                    both pass while a rule's regex is dead, because neither
#                    checks that each BRANCH is exercised.
#
# Exit 0 only if all five pass.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="${PYTHON:-python3}"
fail=0

section() { printf '\n== %s ==\n' "$1"; }

section "syntax"
# Parsed by every bash on this machine, not just the newest one. /bin/bash on
# macOS is 3.2 and stays 3.2, and it cannot parse a quoted heredoc inside a
# command substitution when the body contains an apostrophe. One hook did
# exactly that: fine under bash 5, and a Stop hook that exits non-zero on every
# single turn for anyone on a stock Mac. CI on macos-latest is what found it.
SHELLS="bash"
if [ -x /bin/bash ] && [ "$(command -v bash)" != "/bin/bash" ]; then
  SHELLS="$SHELLS /bin/bash"
fi
for f in "$REPO"/hooks/*.sh "$REPO"/install.sh "$REPO"/doctor.sh; do
  ok=1
  for sh in $SHELLS; do
    "$sh" -n "$f" 2>/dev/null || { ok=0; printf '  FAIL %s does not parse under %s (%s)\n' \
      "$(basename "$f")" "$sh" "$("$sh" --version | head -1 | sed 's/.*version //;s/ .*//')"; }
  done
  [ "$ok" -eq 1 ] && printf '  ok   %s\n' "$(basename "$f")" || fail=1
done
for f in "$REPO"/hooks/*.py "$REPO"/hooks/lib/*.py "$REPO"/tests/*.py; do
  [ -e "$f" ] || continue
  if "$PY" -m py_compile "$f" 2>/dev/null; then printf '  ok   %s\n' "$(basename "$f")"
  else printf '  FAIL %s does not parse\n' "$(basename "$f")"; fail=1; fi
done

section "parity"
"$PY" "$REPO/tests/parity.py" || fail=1

section "hook self-tests"
for f in "$REPO"/hooks/*.py "$REPO"/hooks/lib/*.py; do
  [ -e "$f" ] || continue
  grep -q -- "--self-test" "$f" || continue
  out="$("$PY" "$f" --self-test 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then printf '  ok   %-24s %s\n' "$(basename "$f")" "$(printf '%s' "$out" | tail -1)"
  else printf '  FAIL %-24s %s\n' "$(basename "$f")" "$(printf '%s' "$out" | tail -3)"; fail=1; fi
done

section "negative control"
"$PY" "$REPO/tests/negative-control.py" || fail=1

section "dead branches"
"$PY" "$REPO/tests/dead-branch-sweep.py" || fail=1

printf '\n'
if [ "$fail" -eq 0 ]; then echo "hstack: suite PASS"; else echo "hstack: suite FAIL"; fi
exit "$fail"
