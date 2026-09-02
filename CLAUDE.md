# CLAUDE.md

## Working on Claude Fable 5.1 (added 2026-09-02)

Measured facts: 1M context, 128K output, thinking always on, effort `low` to `max`
(`/effort`); released 2026-09-01, knowledge cutoff Jun 2026; API $10 / $50 per MTok with
cache reads at $0.25.

How to work on it, from Anthropic's migration guide:

- Long single turns are normal (15 minutes on a hard task). Background anything over ~30s
  and let the completion notification bring you back. Never poll.
- State the goal and the constraints, not the steps. Over-prescriptive prompts and skills
  reduce output quality on this model.
- Delegate independent subtrees to sub-agents asynchronously and keep working.
- Audit every progress claim against a tool result from this session before reporting it.
  Unverified means "attempted", never "done".
- Keep a memory surface: one lesson per file, one-line summary on top.
- State boundaries: it takes adjacent unrequested actions. When the owner is thinking out
  loud, the deliverable is the assessment, not a change.
- Start it on the hardest unsolved problem: scope, ask only where genuinely stuck, execute.
