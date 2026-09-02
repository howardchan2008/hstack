# Hooks System

## Hook events

Seven are configured in `~/.claude/settings.json` (verified 2026-08-14):

- **PreToolUse**: before a tool runs. Validation and refusal. Every guard lives here.
- **PostToolUse**: after a tool runs. Auto-format, checks.
- **UserPromptSubmit**: on each prompt. Injected content is read; a reminder to go look is not.
- **SessionStart**: context injection, wiring checks, the the local proxy repatch.
- **PreCompact**: before compaction.
- **SessionEnd** and **Stop**: close-out verification and refusal.

This file listed only the first three until 2026-08-14, and PreCompact was the one event
with no hook at all, so a restore re-injected a `last-context.md` that nothing refreshed.
Read the live set before adding one, and update this list in the same change:
`python3 -c "import json;print(sorted(json.load(open('$HOME/.claude/settings.json'))['hooks']))"`

## Permissions

The allowlist is `permissions.allow` in `~/.claude/settings.json`. There is no `allowedTools`
key in `~/.claude.json` and there never was one on this box (grepped 2026-08-14, 0 hits), so
the pointer that used to sit here sent every reader to a file with nothing in it. An allow
entry does not outrank a hook: PreToolUse still runs and can still refuse. Never pass the
dangerously-skip-permissions flag.

## Task tracking: check the live tool list, never assume

`TodoWrite` is gone. `TaskCreate`/`TaskUpdate` were removed on Opus 4.8, Sonnet 5, Fable 5
and newer in Claude Code 2.1.233, and `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` is supposed to
restore them. That flag IS set in `~/.claude/settings.json` as of 2026-08-25 and it is
still not reliable: the tools appeared in one session, vanished mid-session when the
provider disconnected, and a Sonnet 5 subagent the same day could not load either of them
with the flag set globally. So the flag is worth having and is not worth trusting.

Look at the live tool list before naming a task tool. When it is there, use it. When it is
not, carry the decomposition into the close-out instead, where it is checked anyway. What
matters is that the list outlives the conversation, not which tool holds it.

The historical counts that used to sit here (TaskCreate 168, TaskUpdate 242) are all
pre-removal and prove nothing about today. The defect this section exists to prevent is a
rule ordering a tool the model cannot call: it fails silently every turn instead of once,
which is why the previous version survived so long. `cc-whatsnew` now flags that class as
DEAD-RULE.

## Redundancy audit, 2026-09-02

Every hook entry was measured (blocks and idle from `guard-verdict`, wall time per hook on a
benign payload, and a reader for every artifact a hook writes). Full table and verdicts:
`~/.claude/reference/hooks-audit-2026-09-02.md`. What it changed:

- One principle lives in one hook. The deferral check (work promised to a later turn) was in
  three Stop hooks with three disjoint phrase lists; it is now closeout-shape R10 only, and
  stop-justify keeps the git facts no regex can see.
- A hook that writes what nothing reads is removed, not tuned. cl2-observe ran twice per tool
  call and fed a digest with one reader; gone, with that reader.
- A guard that can only act on one keyword carries `"if": "Bash(*keyword*)"` so the harness
  skips the spawn. Verified live: compound commands match per part, wildcards anywhere work.
- Pasted hook output is never mined for items or facts: `hooks/lib/hookpaste.py`, wired into
  every UserPromptSubmit injector that reads the prompt.
- Before adding a hook, run the audit's three questions: which existing hook owns this
  principle, what does it cost per call, and who reads what it writes.
