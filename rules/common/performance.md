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
