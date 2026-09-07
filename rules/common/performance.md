# Performance Optimization

## Model selection is NOT decided here
Canonical ladder: the engine-routing tree in `~/CLAUDE.md`, backed by `~/.claude/reference/engine-routing-decision.md`. Route by lane first (Codex for live web and bounded review, local Ollama for no-web text, Max for what neither can do), then by model. Opus is the everyday default; Fable is reserved for ultracode at twice the cost.

## Context window
Avoid the last 20% for large refactors, multi-file features, and complex debugging. Single-file edits, utilities, docs and simple fixes are context-insensitive.

## Extended thinking
`alwaysThinkingEnabled` is true and no `MAX_THINKING_TOKENS` cap is set. Nothing to enable; do not spend a turn checking. Deep reasoning means plan mode and more critique passes on the same thread, never a panel of role-playing subagents.

## Compute is shared across sessions, and so is the waste
Measured 2026-08-26 across 9 concurrent sessions and 4,578 Bash calls: 735 (16%) asked a subject another session had already answered, and the dedupe guard is session-keyed so it cannot see them.
**Machine-global facts go through `factcache`**: `factcache run <key> -- <command>`, `factcache bust <prefix>` after anything that changes the machine. Loaded launchd jobs, tool versions, ollama tags, listening ports, sysctl, disk free, daemon liveness.
**Never cache a repo- or cwd-scoped answer.** `git status` is a different fact in every checkout; the tool refuses those keys, because a stale repo answer is a wrong answer that looks authoritative. Every entry carries a TTL.
**Prefer a write over a message.** A durable fact belongs in the always-loaded surface; a peer message reaches one lane once and costs two full contexts.

## Finish the job in one prompt: background work continues the turn for free
The longest autonomous run measured here was 91 tool calls from a single trigger, and the trigger was a background task notification. A job started with `run_in_background: true` re-invokes the session when it finishes.
- Anything over ~30s goes in the background so the turn ends on real work.
- Wrap it in `bgrun` when it can hang: deadline plus a WORKING/STALLED verdict.
- `ScheduleWakeup` only for state no notification can report (external queue, CI).
- NEVER poll a background job you started. A sleep-loop costs a full-context call per check to learn what arrives free.
Waste, in measured order: a probe another session answered (factcache), a probe this session answered (probe-dedupe), a stable fact re-derived instead of read, an agent dispatched for work a shell command does.
