#!/bin/bash
# Auto-push for the .claude config repo. Runs on Stop.
#
# Deliberately narrow. This repo is worked by concurrent Claude sessions, that
# is why session-collide.sh exists, so an unconditional push would publish
# another session's half-finished main under this session's name. Every
# condition below is a refusal to publish something nobody asked to publish:
#
#   - only this repo, only branch main
#   - only when the tree is CLEAN. Dirty means work in flight, not work ready
#     to share, and the Stop guard is already the thing that argues about that.
#   - only when actually ahead of origin
#   - NEVER force, NEVER auto-rebase or auto-merge. A non-fast-forward means
#     another session pushed first; reconciling that is a human decision and a
#     hook that guesses will silently destroy someone's commit.
#   - single-flight lock, so two sessions stopping at once do not race
#   - credential prompts disabled, so a missing token fails fast instead of
#     hanging the Stop hook on an invisible password prompt
#
# Failure NEVER blocks Stop. Worst case is an unpushed commit and a log line.

# Overridable ONLY so the test harness can drive this against a scratch repo and
# a throwaway bare origin. Without it the only way to exercise a push hook is to
# push the live repo, which is not a test, it is a deploy. Every safety condition
# below still applies to the override, it redirects which repo is examined, it
# does not relax what has to be true before anything leaves the machine.
REPO="${CLAUDE_AUTOPUSH_REPO:-$HOME/.claude}"
BRANCH="main"
# This is the HOOK's log, not the repo's, so it deliberately does NOT follow
# $REPO. Writing it inside the repo being pushed is how this hook silently
# wedges itself: the untracked logs/ dir dirties the work tree, and the dirty
# check below then skips every subsequent push, forever, with no output. The
# live repo happens to mask that, because its .gitignore is an allowlist that
# swallows logs/, but the CLAUDE_AUTOPUSH_REPO override and any other repo
# these hooks get dropped into do not. Same reasoning as VIS_DIR below: an
# operational log of a background hook is not repo state.
LOG="${CLAUDE_AUTOPUSH_LOG:-$HOME/.claude/logs/auto-push.log}"
# Overridable for the same reason LOG and VIS_DIR are: the suite drives this
# hook against a throwaway repo, and sharing the real lock with ~9 live sessions
# lets each side starve the other. Default stays the production path.
LOCK="${CLAUDE_AUTOPUSH_LOCK:-/tmp/claude-auto-push.lock}"
PUSH_TIMEOUT=25

# Publication gate. The cache lives OUTSIDE the repo, deliberately. Putting it
# under $REPO would work here only because this repo's .gitignore is an
# allowlist that excludes it; drop these hooks into a repo without that line and
# the first cached lookup leaves an untracked file, a dirty tree makes this hook
# skip, and auto-push wedges permanently. A cache keyed by remote slug is not
# repo state anyway. Overridable so tests do not touch the real cache.
VIS_DIR="${CLAUDE_AUTOPUSH_VIS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-auto-push/repo-visibility}"
VIS_TIMEOUT=6
VIS_TTL_MIN=1440   # 24h. Only paid on pushes that add files, so it can be short.

# Stop hooks receive their payload as JSON on stdin; CLAUDE_SESSION_ID is not set
# in that environment, so every line of this log read "nosid". In the one repo
# that is worked by concurrent sessions BY DESIGN, that made "which session
# pushed this commit" unanswerable from the push log itself, and the answer had
# to be reconstructed from reflog timestamps instead.
#
# Resolved once, up front, before any log() call. Safe because auto-push reads
# stdin for nothing else: the only cat in this file reads a cache file. Guarded
# on a non-tty stdin with a short timeout so a manual run cannot hang.
#
# -d '' slurps to EOF rather than to the first newline. Without it a
# pretty-printed payload -- where "session_id" is not on line 1 -- read exactly
# one line, matched nothing, and logged "nosid": the bug this block exists to
# fix, still present for that shape. The timeout still bounds the read, so the
# no-hang property above is unchanged.
#
# Fractional -t needs bash >= 4. settings.json invokes this as `bash <path>`,
# which resolves to Homebrew bash 5.x, so that is the path that matters. Under
# Apple's /bin/bash 3.2 (the shebang, i.e. a direct ./ run) the read fails and
# SID falls back to "nosid": degraded, never hung, never wrong.
SID="${CLAUDE_SESSION_ID:-}"
if [ -z "$SID" ] && [ ! -t 0 ]; then
  IFS= read -r -d '' -t 0.2 STOP_PAYLOAD 2>/dev/null || true
  SID="$(printf '%s' "${STOP_PAYLOAD:-}" \
    | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"
fi

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s | %s | %s\n' "$(date '+%F %T')" "${SID:-nosid}" "$1" >> "$LOG" 2>/dev/null
}

# macOS ships no timeout(1); use it only if present (coreutils/gtimeout).
pick_timeout() {
  command -v timeout  >/dev/null 2>&1 && { printf 'timeout %s' "$1"; return; }
  command -v gtimeout >/dev/null 2>&1 && { printf 'gtimeout %s' "$1"; return; }
}
VIS_TO=$(pick_timeout "$VIS_TIMEOUT")

# Parse ONLY github.com into owner/repo. Anything else, including GitHub
# Enterprise hosts, returns failure and is treated as unknown: assuming an
# unrecognised host follows github.com's visibility semantics is how a gate
# starts lying.
github_slug() {
  s=""
  case "$1" in
    https://github.com/*)   s=${1#https://github.com/} ;;
    http://github.com/*)    s=${1#http://github.com/} ;;
    ssh://someone@example.com/*) s=${1#ssh://someone@example.com/} ;;
    someone@example.com:*)       s=${1#someone@example.com:} ;;
    *) return 1 ;;
  esac
  s=${s%.git}; s=${s%/}
  # Exactly two non-empty segments.
  case "$s" in
    */*/*|/*|*/) return 1 ;;
    */*) printf '%s' "$s" ;;
    *) return 1 ;;
  esac
}

# PUBLIC | PRIVATE | UNKNOWN. Never prompts, never blocks longer than
# VIS_TIMEOUT, and answers UNKNOWN rather than guessing.
repo_visibility() {
  slug="$1"
  [ -n "$slug" ] || { echo UNKNOWN; return; }
  cache="$VIS_DIR/$(printf '%s' "$slug" | tr '/' '_')"
  if [ -f "$cache" ] && [ -z "$(find "$cache" -maxdepth 0 -mmin +"$VIS_TTL_MIN" 2>/dev/null)" ]; then
    cat "$cache" 2>/dev/null; return
  fi
  command -v gh >/dev/null 2>&1 || { echo UNKNOWN; return; }
  p=$(GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 \
      $VIS_TO gh repo view "$slug" --json isPrivate -q .isPrivate 2>/dev/null)
  case "$p" in
    true)  v=PRIVATE ;;
    false) v=PUBLIC ;;
    *)     echo UNKNOWN; return ;;   # never cached: unknown is a failure, not an answer
  esac
  mkdir -p "$VIS_DIR" 2>/dev/null && printf '%s' "$v" > "$cache" 2>/dev/null
  echo "$v"
}

# Test entrypoint. Resolves a URL and exits, mutating nothing. Must sit above
# the cd below, which exits 0 on a nonexistent repo.
if [ -n "$CLAUDE_AUTOPUSH_SELFTEST" ]; then
  repo_visibility "$(github_slug "$1" 2>/dev/null)"
  exit 0
fi

cd "$REPO" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$cur" = "$BRANCH" ] || { log "skip: on branch '$cur', not $BRANCH"; exit 0; }

# Dirty tree is never pushable. Also means this hook cannot fight with the
# uncommitted-work half of stop-justify.sh: that one blocks, this one skips.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  log "skip: working tree dirty"; exit 0
fi

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
  || { log "skip: no upstream configured"; exit 0; }

# Cheap pre-filter on the possibly-stale remote-tracking ref. A stale ref sits at
# an OLD remote position, so it can over-report ahead but never under-report it:
# a 0 here is trustworthy and lets the overwhelmingly common "nothing to push"
# Stop cost zero network. Anything non-zero gets re-decided below, post-fetch.
ahead=$(git rev-list --count "$upstream"..HEAD 2>/dev/null)
case "$ahead" in ''|*[!0-9]*) log "skip: cannot count ahead"; exit 0;; esac
[ "$ahead" -gt 0 ] || exit 0   # nothing to do, stay silent

# Single flight. mkdir is atomic; a stale lock older than 5 min is reclaimed so
# a killed session cannot wedge pushing forever.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || { log "skip: lock contended"; exit 0; }
  else
    log "skip: another push in flight"; exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# macOS ships no timeout(1); use it only if present (coreutils/gtimeout).
TO=""
command -v timeout  >/dev/null 2>&1 && TO="timeout $PUSH_TIMEOUT"
[ -z "$TO" ] && command -v gtimeout >/dev/null 2>&1 && TO="gtimeout $PUSH_TIMEOUT"

# Refresh the remote-tracking ref so the divergence check below is about the
# remote as it is now, not as it was whenever this clone last talked to origin.
#
# This is INSIDE the lock deliberately. Fetching before taking it would leave a
# window where another session pushes between our fetch and our push, exactly
# the race the fetch exists to catch, reintroduced by the fetch. Lock, look,
# push: the whole decision is one critical section.
#
# We were about to hit the network anyway (we are ahead, a push is coming), so
# this costs a round-trip only on Stops that were already paying for one.
#
# Fetch failure is NOT fatal. Offline should degrade to the previous behaviour,
# push attempts, gets refused, gets reported, not to a silent refusal to push,
# which would let a transient DNS blip quietly stop publishing for hours.
if ! GIT_TERMINAL_PROMPT=0 $TO git fetch --quiet origin 2>/dev/null; then
  log "warn: fetch failed, deciding on stale refs"
fi

# Re-decide on fresh data. Ahead can now be 0: someone else pushed our commits
# (shared branch, or the same work landed twice). Nothing to do, stay quiet.
ahead=$(git rev-list --count "$upstream"..HEAD 2>/dev/null)
case "$ahead" in ''|*[!0-9]*) log "skip: cannot count ahead"; exit 0;; esac
[ "$ahead" -gt 0 ] || { log "skip: already on origin after fetch"; exit 0; }

# Diverged: we are ahead AND behind. Push would be rejected anyway; say so with
# the real reason rather than letting git's non-fast-forward text imply a bug.
behind=$(git rev-list --count HEAD.."$upstream" 2>/dev/null)
case "$behind" in ''|*[!0-9]*) behind=0;; esac
if [ "$behind" -gt 0 ]; then
  log "REFUSE: diverged (ahead $ahead, behind $behind): needs a human, not a hook"
  echo "auto-push: refusing, main has diverged from origin (ahead $ahead, behind $behind). Reconcile manually."
  exit 0
fi

# PUBLICATION GATE. Fires only when this push would ADD files the remote has
# never held, which is the one case where "push" means "publish" rather than
# "update something already visible to the same audience". Modifying a tracked
# file in a public repo changes nothing about who can see it; adding a file that
# has only ever existed on this machine does.
#
# The asymmetry is deliberate: ONLY a positive, fresh determination of PUBLIC
# refuses. Missing gh, no auth, timed-out lookup, non-GitHub remote and
# unparseable URL all fail OPEN and push, for the same reason the fetch above
# is non-fatal. This file's contract is that failure never stops publishing, and
# a gate that blocks on "I could not tell" turns a keyring hiccup into hours of
# silently unpushed work. It is a speed bump on first publication, not a
# security boundary, and it is not load-bearing against a hostile actor.
#
# Cost on the common path is zero: no added files means no lookup and no network.
if [ -z "$CLAUDE_AUTOPUSH_ALLOW_PUBLIC" ]; then
  added=$(git diff --name-only --diff-filter=A "$upstream"..HEAD 2>/dev/null)
  if [ -n "$added" ]; then
    vis=$(repo_visibility "$(github_slug "$(git remote get-url origin 2>/dev/null)")")
    if [ "$vis" = "PUBLIC" ]; then
      n=$(printf '%s\n' "$added" | grep -c .)
      sample=$(printf '%s\n' "$added" | head -3 | tr '\n' ' ')
      log "REFUSE: origin PUBLIC, $n new file(s) would be first-published: $sample"
      echo "auto-push: refusing. origin is PUBLIC and this push first-publishes $n new file(s): $sample"
      echo "  Review what is in them, then push with: CLAUDE_AUTOPUSH_ALLOW_PUBLIC=1 git push origin $BRANCH"
      exit 0
    fi
    [ "$vis" = "UNKNOWN" ] && log "warn: visibility unknown, proceeding (gate fails open)"
  fi
fi

head_short=$(git rev-parse --short HEAD 2>/dev/null)
out=$(GIT_TERMINAL_PROMPT=0 $TO git push origin "$BRANCH" 2>&1)
rc=$?

if [ $rc -eq 0 ]; then
  log "pushed $ahead commit(s) -> origin/$BRANCH @ $head_short"
else
  # Surfaced, not swallowed: an unpushed commit that nobody mentions is exactly
  # the silent miss this repo's Stop guard is built to prevent.
  squashed=$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)
  log "FAILED rc=$rc @ $head_short: $squashed"
  echo "auto-push: FAILED (rc=$rc), $ahead commit(s) still local. See $LOG: $squashed"

  # An ARCHIVED origin is not a transient failure. GitHub keeps serving fetches
  # and refuses every push with 403, so the retry-next-Stop behaviour that
  # rescues a DNS blip strands the work permanently instead. That is how 12
  # commits accumulated in this repo unnoticed on 2026-08-13, after claude-hooks
  # was archived into the claude monorepo: the tree was clean, the branch had no
  # upstream problem, and every Stop reported a failure nobody read.
  #
  # This used to call a mirror that copied the tree into the claude monorepo as a
  # second published home. That path is gone as of 2026-08-14 and is not coming
  # back: the copy it maintained had drifted from the live tree, its only logged
  # runs in a full day were `skip` lines for the test suite's scratch repos, and
  # re-creating it on failure would resurrect exactly the duplicate the fold
  # removed. Worse, once the subtree was deleted the mirror answered `skip: no
  # files tracked` with rc=0, so the hook would have reported a publication that
  # never happened. A refusal now says what it is and what to do about it.
  case "$out" in
    *archived*|*read-only*|*403*)
      echo "auto-push: origin REFUSES pushes (archived or read-only). Retrying next Stop cannot fix this. $ahead commit(s) exist only on this laptop until the repo is unarchived or a new remote is added: git remote set-url origin <new>"
      ;;
  esac
fi

exit 0
