#!/bin/bash
# cl2-observe.sh: entrypoint-normalizing, non-blocking wrapper for continuous-learning-v2.
#
# WHY THIS EXISTS
#   CL2's hooks/observe.sh records a session only when CLAUDE_CODE_ENTRYPOINT
#   is "cli" or "sdk-ts" (its Layer 1 guard). The Claude Desktop app reports
#   "claude-desktop", so observe.sh exits immediately and CL2 never learns
#   from desktop sessions. Desktop sessions are genuine interactive human
#   sessions and SHOULD be observed.
#
# WHAT IT DOES
#   1. Normalizes that one entrypoint value so observe.sh accepts the session.
#      Every other guard in observe.sh (subagent / automated / observer-session
#      filters: Layers 2-5) still runs unchanged, so automated sub-sessions are
#      still correctly excluded. observe.sh never stores the entrypoint in an
#      observation, so this only affects the guard check.
#
#   2. Runs observe.sh DETACHED (fire-and-forget) instead of inline.
#
# WHY DETACHED (perf, 2026-02)
#   observe.sh is a pure observer: every code path ends in `exit 0`, it emits
#   zero bytes on stdout, and it never returns a permissionDecision, so it
#   cannot gate, block, or modify a tool call. Nothing downstream consumes its
#   result. Yet it was measured at ~181ms (pre) + ~185ms (post) = ~366ms of
#   BLOCKING latency on EVERY tool call, because it cold-starts python3 five to
#   six times per invocation. At ~400 tool calls that is ~2.4 min/session of
#   pure dead wait.
#
#   Detaching moves that work off the critical path. Claude Code waits only for
#   this wrapper to fork (~3-5ms); the observation is still written, just a few
#   ms later. Observation fidelity is unchanged: same script, same stdin, same
#   guards.
#
#   Safety: stdin is fully drained into memory BEFORE forking, so the child
#   never races Claude Code closing the pipe. HUP/INT/TERM are ignored in the
#   child so a fast-exiting parent cannot kill an in-flight write.
#
# ESCAPE HATCH
#   CL2_OBSERVE_SYNC=1  -> run inline (old blocking behaviour), for debugging.
#
# WHY A WRAPPER (not a patch)
#   This file is owned by the owner, so CL2 skill updates will not overwrite it.
#   If CL2 later adds "claude-desktop" to its own allowlist, this wrapper
#   becomes a harmless passthrough.
#
# USAGE (from ~/.claude/settings.json hooks)
#   PreToolUse  -> bash ~/.claude/hooks/cl2-observe.sh pre
#   PostToolUse -> bash ~/.claude/hooks/cl2-observe.sh post
set -u

case "${CLAUDE_CODE_ENTRYPOINT:-}" in
  claude-desktop|sdk-cli) export CLAUDE_CODE_ENTRYPOINT=cli ;;
esac

OBSERVE_SH="$HOME/.claude/skills/continuous-learning-v2/hooks/observe.sh"

[ -r "$OBSERVE_SH" ] || exit 0

# Debug / opt-out: run inline exactly as before.
if [ "${CL2_OBSERVE_SYNC:-0}" = "1" ]; then
  exec bash "$OBSERVE_SH" "$@"
fi

# Drain stdin fully before forking. Hook payloads are bounded (observe.sh
# truncates input/output to 5000 chars each downstream), so this is cheap and
# removes any dependency on the parent's stdin staying open.
payload=$(cat)
[ -n "$payload" ] || exit 0

# Fire and forget. Child ignores signals aimed at the exiting parent's group.
#
# The redirections MUST be on the subshell itself, not on the pipeline inside
# it. A background subshell inherits the parent's stdin/stdout/stderr fds and
# holds them open until it exits. Redirecting only the inner pipeline leaves
# the subshell holding Claude Code's stdout pipe, so any hook runner that
# drains stdout to EOF (rather than merely waiting for the parent to exit)
# blocks for the FULL duration of observe.sh: measured 150ms vs 11ms, i.e.
# the entire optimization silently reverts. Closing all three fds here means
# the parent's stdout sees EOF the instant the wrapper exits.
(
  trap '' HUP INT TERM
  printf '%s' "$payload" | bash "$OBSERVE_SH" "$@"
) </dev/null >/dev/null 2>&1 &

disown 2>/dev/null || true
exit 0
