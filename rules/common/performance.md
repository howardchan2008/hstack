# Performance Optimization

## Model selection is NOT decided here

The canonical ladder is the engine-routing decision tree in `~/CLAUDE.md`, backed by
`~/.claude/reference/engine-routing-decision.md` and memory `feedback_model_routing`.
Route by lane first (Codex for live web and bounded review, local Ollama for no-web text,
Max for what neither can do), and only then by model.

What stood here until 2026-08-14 was a three-model table sending main development work to
Sonnet and architecture to Opus. Both names were a generation stale, and the routing was
the reverse of the live rule, which is Opus for everyday work with Fable reserved for
ultracode at twice the cost. Two loaded rule files disagreeing about which model does the
work is worse than either one alone, because whichever is read second wins by accident.

Subagents are the one model choice that still belongs to the caller: pass
`model: sonnet` or `model: haiku` on a worker agent rather than letting it inherit Opus.

## Context Window Management

Avoid last 20% of context window for:
- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:
- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

## Extended thinking

Already on: `alwaysThinkingEnabled` is `true` in `~/.claude/settings.json`, verified
2026-08-14, and no `MAX_THINKING_TOKENS` cap is set in `env`. Nothing to enable, so do not
spend a turn checking. Cap it with that variable only when a run must be held down.

Deep reasoning on a hard task means plan mode and more critique passes on the same thread.
It does not mean a panel of role-playing subagents; see the budget note in `agents.md`.

## Compute is shared across sessions, and so is the waste

Five to seven sessions run concurrently on this machine every working day. Cost
is calls times context, so a probe that another live session already answered is
not cheap merely because the command is fast: it is a full-context call for a
fact that already exists.

Measured 2026-08-26 across 9 concurrent sessions and 4,578 Bash calls: **735
calls (16%) asked a subject another session had already answered.** The existing
dedupe guard is keyed by session id, so it cannot see any of them.

**Machine-global facts go through `factcache`.** One answer for the whole box:
loaded launchd jobs, brew and tool versions, ollama tags, listening ports,
sysctl values, disk free, whether a daemon is up.

```
factcache run <key> -- <command>     # cached answer, or run and store it
factcache bust <prefix>              # after anything that changes the machine
```

**Never cache a repo- or cwd-scoped answer.** `git status` is a different fact
in every checkout; two sessions asking it are asking different questions. The
tool refuses those keys outright, because a stale cached repo answer is worse
than a wasted call: it is a wrong answer that looks authoritative. Every entry
carries a TTL for the same reason.

**Prefer a write over a message.** A durable fact belongs in the always-loaded
surface where every session gets it free, including the ones not started yet. A
peer message reaches one lane once and costs two full contexts. Message only
when the fact is both time-critical and session-specific.
