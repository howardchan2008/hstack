# Hooks System

## Events configured in `~/.claude/settings.json`
PreToolUse (validation and refusal, every guard lives here), PostToolUse, UserPromptSubmit (injected content is read; a reminder to go look is not), SessionStart, PreCompact, SessionEnd, Stop.
Read the live set before adding one and update this list in the same change:
`python3 -c "import json;print(sorted(json.load(open('$HOME/.claude/settings.json'))['hooks']))"`

## Permissions
The allowlist is `permissions.allow` in `~/.claude/settings.json`. There is no `allowedTools` key in `~/.claude.json`. An allow entry does not outrank a hook: PreToolUse still runs and can still refuse. Never pass the dangerously-skip-permissions flag.

## Task tracking: check the live tool list, never assume
`TodoWrite` is gone; `TaskCreate`/`TaskUpdate` were removed on newer models and `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is set but unreliable (they vanished mid-session and a Sonnet 5 subagent could not load them). Look at the live tool list before naming a task tool; when absent, carry the decomposition into the close-out. A rule ordering a tool the model cannot call fails silently every turn: `cc-whatsnew` flags that class as DEAD-RULE.

## Redundancy audit, 2026-09-02
Full table: `~/.claude/reference/hooks-audit-2026-09-02.md`.
- One principle lives in one hook. The deferral check is closeout-shape R10 only; stop-justify keeps the git facts no regex can see.
- A hook that writes what nothing reads is removed, not tuned.
- A guard that acts on one keyword carries `"if": "Bash(*keyword*)"` so the harness skips the spawn.
- Pasted hook output is never mined for items or facts: `hooks/lib/hookpaste.py`.
- Before adding a hook: which existing hook owns this principle, what does it cost per call, who reads what it writes.
