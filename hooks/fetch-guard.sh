#!/usr/bin/env bash
# fetch-guard.sh: before editing a file, check whether upstream has moved that
# SAME file underneath you. Warns; never blocks by default.
#
# WHY THIS EXISTS (2026-08-01)
#   A session pushed twice into claude/culver-a venture-research-rnlnaj while
#   another session held work on the branch. Both times the push was rejected
#   as non-fast-forward and the fix was fetch + rebase. Both times it stayed
#   painless ONLY because the two sessions happened to be editing disjoint
#   files. That is luck, not design. CLAUDE.md already records the lesson
#   ("Pull before editing anything the other surface might be holding") but a
#   prose lesson is not a mechanism. This is the mechanism.
#
#   The cost being avoided is NOT the rejected push -- that is loud and cheap.
#   It is the silent case: two sessions edit the same file from different
#   bases, the rebase conflicts, and whoever resolves it hand-merges someone
#   else's reasoning at the worst possible moment.
#
# WHY IT WARNS AND DOES NOT BLOCK  (the opposite of lane-guard.sh)
#   lane-guard fails CLOSED because an unread payload there means an
#   uninspected fan-out that could burn ~50M tokens. The asymmetry is real:
#   there, wrongly allowing is catastrophic and wrongly blocking is a typo.
#   HERE it inverts. This hook sits on the Edit/Write path of every session in
#   every repo, and it touches the NETWORK. Fail-closed would mean a DNS blip,
#   an expired credential, or a slow remote freezes all editing for all live
#   sessions at once -- converting a transient network fault into a total work
#   stoppage. Wrongly allowing an edit here costs one rebase. So: unreadable
#   payload, no network, no upstream, detached HEAD, git missing, or fetch
#   timeout => exit 0 SILENTLY. An advisory hook must degrade to absent.
#   FETCH_GUARD_BLOCK=1 opts into exit 2 for anyone who wants teeth.
#
# WHY IT THROTTLES
#   PreToolUse(Write|Edit) fires at keystroke-level frequency during a burst of
#   edits. An unthrottled `git fetch` per edit is both slow and rude to the
#   remote. One fetch per repo per FETCH_GUARD_TTL seconds (default 120) is
#   enough: the window this closes is "another session pushed minutes ago",
#   not "another session pushed 3 seconds ago".
#
# WHY IT CHECKS THE FILE, NOT THE BRANCH
#   "branch is 3 commits behind" is true almost always on a shared branch and
#   trains you to ignore it. "the file you are about to edit moved upstream"
#   is rare and always actionable. Only the second is worth interrupting for.
#   Branch distance is shown as context, never as the trigger.
#
# MODES
#   default              warn on stdout, exit 0, never blocks
#   FETCH_GUARD_BLOCK=1  exit 2 when the target file moved upstream
#   FETCH_GUARD_TTL=N    seconds between fetches per repo (default 120)
#   FETCH_GUARD_DEBUG=1  explain every early exit instead of being silent
#
# Wired at PreToolUse(Write|Edit) in settings.json.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
DEBUG="${FETCH_GUARD_DEBUG:-0}"
dbg() { [ "$DEBUG" = "1" ] && echo "fetch-guard: $*" >&2; return 0; }

# ---- payload ---------------------------------------------------------------
# Parse as JSON, never by position. session-collide.sh learned this the hard
# way: "replace_all" can precede "file_path" in the Edit payload, so a
# positional/regex grab silently reads the wrong field.
read_field() {
  FG_INPUT="$INPUT" /usr/bin/python3 -c '
import os, sys, json
try:
    d = json.loads(os.environ["FG_INPUT"])
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
if sys.argv[1] == "tool":
    print(d.get("tool_name", ""))
else:
    print(ti.get("file_path") or ti.get("notebook_path") or "")
' "$1" 2>/dev/null
}

TOOL=$(read_field tool)
FILE=$(read_field path)

# Fail OPEN on an unreadable payload -- see header. An advisory network hook
# that cannot read its input must behave as if it were not installed.
[ -n "$TOOL" ] || { dbg "unreadable payload / no tool_name"; exit 0; }
case "$TOOL" in Write|Edit|NotebookEdit) ;; *) dbg "tool=$TOOL not an editor"; exit 0 ;; esac
[ -n "$FILE" ] || { dbg "no file_path in payload"; exit 0; }

command -v git >/dev/null 2>&1 || { dbg "git unavailable"; exit 0; }

# ---- resolve the repo from the FILE PATH, never from cwd -------------------
# session-collide.sh invariant #2. The cwd of a session is frequently $HOME,
# which is not a repo at all; resolving from cwd manufactures false negatives.
# The file may not exist yet (Write creating it), so resolve from its dirname.
DIR=$(dirname -- "$FILE")
[ -d "$DIR" ] || { dbg "dir does not exist: $DIR"; exit 0; }
ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) || { dbg "not a repo: $DIR"; exit 0; }
[ -n "$ROOT" ] || { dbg "empty toplevel"; exit 0; }

BRANCH=$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
  dbg "detached HEAD, no branch to compare"; exit 0; }
[ -n "$BRANCH" ] || exit 0

# Upstream must actually exist. A local-only branch has nothing to be behind.
UPSTREAM=$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || {
  dbg "no upstream for $BRANCH"; exit 0; }
[ -n "$UPSTREAM" ] || { dbg "empty upstream"; exit 0; }
REMOTE="${UPSTREAM%%/*}"
# The REMOTE branch name, which is not always the local one. A local branch may
# track a differently-named remote branch (`git branch -u origin/main mywork`).
# Fetching "$BRANCH" would then ask for a ref that does not exist on the remote,
# the fetch would fail, and this hook would degrade to silent -- another
# indistinguishable-from-working failure. Derive it from the upstream instead.
RBRANCH="${UPSTREAM#*/}"
[ -n "$RBRANCH" ] || { dbg "could not derive remote branch from $UPSTREAM"; exit 0; }

# ---- throttle --------------------------------------------------------------
TTL="${FETCH_GUARD_TTL:-120}"
STAMP="/tmp/fetch-guard-$(printf '%s' "$ROOT" | /usr/bin/shasum -a 1 2>/dev/null | cut -c1-12)"
NOW=$(date +%s)
LAST=0
[ -f "$STAMP" ] && LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac

if [ $((NOW - LAST)) -ge "$TTL" ]; then
  # macOS ships no timeout(1); use it only if present. Same convention as
  # auto-push.sh:176. Without a bound, a hung remote hangs the edit.
  TO=""
  command -v timeout  >/dev/null 2>&1 && TO="timeout 10"
  [ -z "$TO" ] && command -v gtimeout >/dev/null 2>&1 && TO="gtimeout 10"
  # Stamp BEFORE fetching, not after: if the remote is hanging, we must not
  # retry a 10s hang on every single edit in the burst.
  echo "$NOW" > "$STAMP" 2>/dev/null || true
  GIT_TERMINAL_PROMPT=0 $TO git -C "$ROOT" fetch --quiet "$REMOTE" "$RBRANCH" 2>/dev/null || {
    dbg "fetch failed or timed out (network/creds) -- degrading to silent"; exit 0; }
else
  dbg "throttled, last fetch $((NOW - LAST))s ago (ttl ${TTL}s)"
fi

# ---- did THIS FILE move upstream? ------------------------------------------
REF="refs/remotes/$UPSTREAM"
git -C "$ROOT" rev-parse --verify --quiet "$REF" >/dev/null 2>&1 || {
  dbg "no such ref $REF"; exit 0; }

# Path relative to the repo root. Do NOT use --show-prefix: that is relative to
# cwd, and cwd is not where the file is.
#
# realpath BOTH sides, not abspath (2026-08-01, caught in test). On macOS /tmp
# is a symlink to /private/tmp: `rev-parse --show-toplevel` returns the RESOLVED
# form while the hook payload carries the SYMLINKED form. abspath leaves the
# mismatch in place, relpath then yields "../../../../tmp/..." , and the
# `git log -- <path>` filter below matches nothing -- so the hook exits 0
# having detected nothing, on every edit, forever. It reads as "file is
# current" and is indistinguishable from working. Any symlink anywhere in the
# repo path reproduces it, not just /tmp.
REL=$(/usr/bin/python3 -c '
import os, sys
print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$FILE" "$ROOT" 2>/dev/null)
[ -n "$REL" ] || { dbg "could not relativise $FILE against $ROOT"; exit 0; }

MOVED=$(git -C "$ROOT" log --oneline "HEAD..$REF" -- "$REL" 2>/dev/null | head -5)
[ -n "$MOVED" ] || { dbg "$REL is current with $UPSTREAM"; exit 0; }

BEHIND=$(git -C "$ROOT" rev-list --count "HEAD..$REF" 2>/dev/null || echo "?")

echo "fetch-guard: $REL moved upstream on $UPSTREAM and you do not have it."
echo "  branch is $BEHIND commit(s) behind. Upstream commits touching this file:"
printf '%s\n' "$MOVED" | sed 's/^/    /'
echo "  Rebase before editing, or you will hand-merge someone else's work later:"
# $RBRANCH, not $BRANCH, for the same reason as the fetch above: the advice
# line must name the branch as the REMOTE spells it, or the command we hand
# over dies with "couldn't find remote ref". Wrong advice at the moment of
# maximum trust is worse than no advice.
echo "    git -C $ROOT pull --rebase $REMOTE $RBRANCH"

if [ "${FETCH_GUARD_BLOCK:-0}" = "1" ]; then
  exit 2
fi
exit 0
