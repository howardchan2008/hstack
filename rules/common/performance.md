# Performance Optimization

## Model selection is NOT decided here
Canonical ladder: engine-routing tree in `~/CLAUDE.md`, backed by `~/.claude/reference/engine-routing-decision.md`. Route by lane (Codex: live web + bounded review; Ollama: no-web text; Max: neither), then model. Opus default; Fable for ultracode at 2x cost.

## Context window
Avoid last 20% for large refactors, multi-file features, complex debugging. Single-file edits, utilities, docs, simple fixes: context-insensitive.

## Extended thinking
`alwaysThinkingEnabled` true, no `MAX_THINKING_TOKENS` cap. Don't check. Deep reasoning: plan mode + critique passes same thread, never role-playing subagents.

## Compute is shared across sessions, and so is the waste
Measured 2026-08-26 across 9 concurrent sessions and 4,578 Bash calls: 735 (16%) asked subject another session answered; dedupe guard session-keyed so can't see them.
**Machine-global facts go through `factcache`**: `factcache run <key> -- <command>`, `factcache bust <prefix>` after machine changes. Loaded launchd jobs, tool versions, ollama tags, listening ports, sysctl, disk free, daemon liveness.
**Never cache a repo- or cwd-scoped answer.** `git status` differs per checkout; tool refuses those keys. Stale repo answer = wrong + authoritative-looking. Each entry carries TTL.
**Prefer a write over a message.** Durable facts in always-loaded surface. Peer message reaches one lane, costs two full contexts.

## Finish the job in one prompt: background work continues the turn for free
Longest autonomous run: 91 tool calls from single trigger (background task notification). Job with `run_in_background: true` re-invokes when done.
- >~30s → background so turn ends on real work.
- `bgrun` for hang risk: deadline + WORKING/STALLED verdict.
- `ScheduleWakeup` only for unreportable state (external queue, CI).
- NEVER poll background job. Sleep-loop costs full-context call per check to learn what arrives free.

Waste (measured order): probe answered by other session (factcache), probe answered this session (probe-dedupe), stable fact re-derived not read, agent for shell work.