# Hooks System

## Events configured in `~/.claude/settings.json`
PreToolUse (validation and refusal, every guard lives here), PostToolUse, UserPromptSubmit (injected content is read; a reminder to go look is not), SessionStart, PreCompact, SessionEnd, Stop.

Check live set before adding; update this list.
`python3 -c "import json;print(sorted(json.load(open('$HOME/.claude/settings.json'))['hooks']))"`

## Permissions
`permissions.allow` in `~/.claude/settings.json`. No `allowedTools` key in `~/.claude.json`. Allow doesn't outrank hook: PreToolUse still runs, can refuse. Never pass dangerously-skip-permissions.

## Task tracking: check the live tool list, never assume
`TodoWrite` gone; `TaskCreate`/`TaskUpdate` removed on newer models; `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` unreliable (vanished mid-session, Sonnet 5 subagent couldn't load). Check live tool list before naming task tool; if absent, carry decomposition to close-out. Rule ordering unavailable tool fails silently each turn: `cc-whatsnew` flags as DEAD-RULE.

## Redundancy audit, 2026-09-02
Full table: `~/.claude/reference/hooks-audit-2026-09-02.md`.
- One principle per hook. Deferral check: closeout-shape R10 only; stop-justify keeps git facts regex can't see.
- Hooks writing unread output: removed, not tuned.
- Guards acting on one keyword carry `"if": "Bash(*keyword*)"` so harness skips spawn.
- Pasted hook output never mined for items/facts: `hooks/lib/hookpaste.py`.
- Before adding hook: which existing hook owns principle, cost per call, who reads output.