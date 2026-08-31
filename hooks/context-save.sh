#!/bin/bash
# context-save.sh: Stop hook. Snapshots where work left off so the next session
# can resume instead of cold-starting (cuts cache_create on session sprawl).
# Writes ~/.claude/last-context.md. Fast, read-only on the repo. Never blocks Stop.
#
# Disable: touch /tmp/context-save-disabled

set -uo pipefail
[ -f /tmp/context-save-disabled ] && exit 0

CWD="$(pwd)"
# The Stop payload carries transcript_path. Read it once; never block on it.
PAYLOAD="$(cat 2>/dev/null || true)"
TRANSCRIPT="$(printf '%s' "$PAYLOAD" | /usr/bin/python3 -c 'import json,sys
try: print((json.load(sys.stdin) or {}).get("transcript_path") or "")
except Exception: print("")' 2>/dev/null)"

# PER-REPO, fixed 2026-08-30. This wrote one global ~/.claude/last-context.md,
# last writer wins. Five to ten sessions run concurrently across different
# repos here, so a premier-trophy session starting up restored whichever repo
# happened to stop last. Checked on the day: the file said "repo: hstack" while
# the owner was asking why his premier-trophy sessions carry nothing over. It was
# not that the carryover was missing, it was that it belonged to another repo.
#
# The global path is still written, so context-restore keeps working for a
# session outside any repo, but the per-repo copy is what a repo session reads.
REPO_SLUG="$(basename "$CWD" 2>/dev/null | tr -c 'A-Za-z0-9._-' '-' | tr -d '\n')"
mkdir -p "$HOME/.claude/context" 2>/dev/null
OUT="$HOME/.claude/context/${REPO_SLUG}.md"
OUT_GLOBAL="$HOME/.claude/last-context.md"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

{
  echo "# Last context: $NOW"
  echo ""
  echo "cwd: $CWD"
  if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BR="$(git -C "$CWD" branch --show-current 2>/dev/null)"
    echo "repo: $(basename "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)")  branch: $BR"
    echo ""
    echo "## uncommitted (git status -s, top 20)"
    git -C "$CWD" status -s 2>/dev/null | head -20
    echo ""
    echo "## last 5 commits"
    git -C "$CWD" log --oneline -5 2>/dev/null
    # Two different questions, and `@{u}..` alone answers only one of them badly.
    # It ERRORS on a branch with no upstream, and 2>/dev/null turns that error into
    # "0 unpushed" for commits that exist nowhere but this disk. `HEAD --not --remotes`
    # needs no upstream and no network, and catches exactly that case.
    UNBACKED="$(git -C "$CWD" rev-list --count HEAD --not --remotes 2>/dev/null)"
    case "${UNBACKED:-}" in ''|*[!0-9]*) UNBACKED=0 ;; esac
    if git -C "$CWD" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1; then
      UNPUSHED="$(git -C "$CWD" rev-list --count '@{u}..HEAD' 2>/dev/null)"
      case "${UNPUSHED:-}" in ''|*[!0-9]*) UNPUSHED=0 ;; esac
    else
      UNPUSHED=$UNBACKED
    fi
    [ "$UNPUSHED" != "0" ] && echo "" && echo "⚠ $UNPUSHED unpushed commit(s) on $BR"
    [ "$UNBACKED" != "0" ] && echo "⚠ $UNBACKED commit(s) on NO remote at all (lost if this disk dies)"
  else
    echo "(not a git repo)"
  fi

  # WHAT THE SESSION WAS ACTUALLY DOING, added 2026-08-30. Until now this file
  # was cwd, branch and five commit subjects: about 600 bytes, which is a git
  # log and not a memory. The owner, on a new session in the same repo: "these are
  # some gaps none of the previous optimizations flagged". He is right. The
  # transcript already holds the two things worth carrying, so carry them.
  if [ -n "${TRANSCRIPT:-}" ] && [ -f "$TRANSCRIPT" ]; then
    /usr/bin/python3 - "$TRANSCRIPT" <<'PYEOF' 2>/dev/null || true
import json, os, re, sys
p = sys.argv[1]
try:
    size = os.path.getsize(p)
    with open(p, "rb") as fh:
        if size > 3_000_000:
            fh.seek(size - 3_000_000); fh.readline()
        lines = fh.read().decode("utf-8", "replace").splitlines()
except OSError:
    raise SystemExit
ask = done = None
NOISE = ("<system-reminder", "[SYSTEM", "<local-command", "Caveat:",
         "<task-notification", "<cross-session", "This session is being continued")
for ln in lines:
    if '"type"' not in ln:
        continue
    try:
        d = json.loads(ln)
    except ValueError:
        continue
    c = (d.get("message") or {}).get("content")
    if d.get("type") == "user" and d.get("toolUseResult") is None:
        t = c if isinstance(c, str) else ""
        if isinstance(c, list):
            t = "".join(b.get("text", "") for b in c
                        if isinstance(b, dict) and b.get("type") == "text")
        t = t.strip()
        if t and not t.startswith(NOISE) and "tool_result" not in t[:40]:
            ask = re.sub(r"\s+", " ", t)[:400]
    elif d.get("type") == "assistant" and isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text" \
               and b.get("text", "").strip().startswith("DONE"):
                done = b["text"].strip()
if ask:
    print("\n## what he last asked for\n\n" + ask)
if done:
    keep = [l for l in done.splitlines() if l.strip()][:14]
    print("\n## how the last session closed out\n\n" + "\n".join(keep)[:1400])
PYEOF
  fi
} > "$OUT" 2>/dev/null

cp -f "$OUT" "$OUT_GLOBAL" 2>/dev/null || true
exit 0
