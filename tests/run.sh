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
#
# Exit 0 only if all four pass.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="${PYTHON:-python3}"
fail=0

section() { printf '\n== %s ==\n' "$1"; }

section "syntax"
for f in "$REPO"/hooks/*.sh; do
  if bash -n "$f" 2>/dev/null; then printf '  ok   %s\n' "$(basename "$f")"
  else printf '  FAIL %s does not parse\n' "$(basename "$f")"; fail=1; fi
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

printf '\n'
if [ "$fail" -eq 0 ]; then echo "hstack: suite PASS"; else echo "hstack: suite FAIL"; fi
exit "$fail"
