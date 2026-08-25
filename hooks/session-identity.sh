#!/usr/bin/env bash
# Shared session-identity resolution for guild hooks.
#
# Sets SESSION_ID (possibly empty). Never guesses: an empty SESSION_ID is a
# recoverable missing roster line, a wrong one poisons every other session's
# view of who did what.
#
# Tiers, most authoritative first:
#   1. COLLIDE_SESSION / CLAUDE_SESSION_ID   explicit override, tests
#   2. hook payload JSON on stdin            real hook invocations
#   3. PID-anchored cache written by tier 2  manual runs from the Bash tool
#
# Tier 3 exists because a hook is a child process: it cannot export an env
# var back into the Bash tool that runs later. The cache is keyed by the
# owning claude-code process, so concurrent sessions on the same box cannot
# read each other's identity. Keying globally would be worse than unknown.

# Nearest ancestor process that is a claude-code binary. Deliberately does
# not match /Applications/Claude.app (the desktop shell) -- that one is
# shared by every session and would collapse them onto a single anchor.
guild_anchor_pid() {
  local p="${1:-$$}" i=0 info pp comm
  while [ "$i" -lt 12 ]; do
    i=$((i + 1))
    info="$(ps -o ppid=,comm= -p "$p" 2>/dev/null | sed -n '1s/^[[:space:]]*//p')"
    [ -n "$info" ] || return 1
    pp="${info%%[[:space:]]*}"
    comm="${info#*[[:space:]]}"
    case "$comm" in
      */claude-code/*/claude) printf '%s\n' "$p"; return 0 ;;
    esac
    case "$pp" in ''|0|1) return 1 ;; esac
    p="$pp"
  done
  return 1
}

# PID alone is not safe: the OS reuses pids. Pair it with the process start
# time so a recycled pid cannot inherit a dead session's identity.
guild_anchor_stamp() {
  ps -o lstart= -p "$1" 2>/dev/null | sed -n '1s/^[[:space:]]*//p'
}

guild_anchor_file() {
  local dir="${GUILD_HOME:-$HOME/.guild}/sessions/.anchors"
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s/%s\n' "$dir" "$1"
}

guild_anchor_store() {
  local sid="$1" pid f stamp
  [ -n "$sid" ] || return 0
  pid="$(guild_anchor_pid)" || return 0
  f="$(guild_anchor_file "$pid")" || return 0
  stamp="$(guild_anchor_stamp "$pid")"
  printf '%s\t%s\n' "$sid" "$stamp" > "$f" 2>/dev/null || true
}

guild_anchor_load() {
  local pid f line sid stamp now
  pid="$(guild_anchor_pid)" || return 1
  f="$(guild_anchor_file "$pid")" || return 1
  [ -r "$f" ] || return 1
  IFS= read -r line < "$f" || return 1
  sid="${line%%	*}"
  stamp="${line#*	}"
  [ -n "$sid" ] || return 1
  # Reject a recycled pid: the live process must have the same start time.
  now="$(guild_anchor_stamp "$pid")"
  [ "$stamp" = "$now" ] || return 1
  printf '%s\n' "$sid"
}

# Read the whole payload, not one line. Claude Code currently sends single
# line JSON, but a pretty-printed payload made `read -r` return "{" and the
# identity vanished silently -- the caller then reported itself as a
# stranger. Per-read timeout keeps a tty-attached manual run from hanging.
guild_read_payload() {
  local line payload=""
  [ -t 0 ] && return 1
  while IFS= read -r -t 2 line 2>/dev/null; do
    payload="$payload$line"
  done
  [ -n "$payload" ] || return 1
  printf '%s\n' "$payload"
}

guild_resolve_session_id() {
  SESSION_ID="${COLLIDE_SESSION:-${CLAUDE_SESSION_ID:-}}"
  if [ -n "$SESSION_ID" ]; then
    guild_anchor_store "$SESSION_ID"
    return 0
  fi

  local payload sid
  payload="$(guild_read_payload || true)"
  if [ -n "$payload" ]; then
    sid="$(printf '%s' "$payload" \
      | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -1)"
    if [ -n "$sid" ]; then
      SESSION_ID="$sid"
      guild_anchor_store "$SESSION_ID"
      return 0
    fi
  fi

  SESSION_ID="$(guild_anchor_load || true)"
  [ -n "$SESSION_ID" ] || SESSION_ID=""
  return 0
}
