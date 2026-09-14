# Agent Orchestration

Subagents PROHIBITED except three `caveman:cavecrew-*` types (see `~/.claude/CLAUDE.md`). Below: genuine authorisation only.

## There is no remote worker lane on this machine
No openclaw binary, config or MCP server (measured 2026-08-14).
Local subagents: only agent lane.
Genuine offload: Codex, local Ollama.

## No agent-to-agent framework here (market checked 2026-09-03, verdict stands)
Frameworks solve discovery/transport between isolated agents.
Claude and Codex share: filesystem, sqlite queue (`~/.claude/state/jobq.db`), keychain.

**The queue plus the inbox IS the protocol.**
Claude→Codex: `jobq add`, then `jobq wait <id>` background; completion re-invokes session.
Codex→Claude: `jobq inbox`; results stay until `jobq ack <id>`; `hooks/carryover-queue.py` injects unacked into next prompt.
Never poll `jobq status`.
Other side: `~/.codex/AGENTS.md`.

## Available agents
`~/.claude/agents/`: advisor (read-only), architect, planner, tdd-guide, code-reviewer, security-reviewer, build-error-resolver, python-reviewer, typescript-reviewer, caveman trio.
Rest archived 2026-09-05 (context cost); restore: `mv ~/.claude/agents-archive/<name>.md ~/.claude/agents/`.

## Parallel means one message, not more agents
Dispatch in ONE message.
Cost: per agent, not message.
Budget: 8/session/24h, 40/box/24h, 200/7d.
Sub-agents inherit parent model; Fable session: pass `model: sonnet` or `haiku`.
Before second agent: name independent subtree.
Shell pre-scan first (`rg`, `/bin/ls`, `sed`); read files directly; agent only for remainder.

## TALK TO THE OTHER SESSIONS (2026-08-24)
*"since when can u message teammates, this is a fucking useful feature literally u shd use it much more from now on"*.

`ListAgents`: names live sessions.
`SendMessage({to, message})`: delivers to one.
5–7 sessions concurrent daily.

COST: message = TWO full-context calls ≈ 66k billable-equivalent tokens.

WRITE ONCE BEATS TELL ALL. Durable facts → always-loaded surface (free to all sessions, even future ones).

MESSAGE only: time-critical AND session-specific AND mid-loop. If outlives the hour, write instead.

ONE MESSAGE, ONE DIRECTION.
No acks, thanks, loop-closing.
Say everything in first message.
Peer mentioning third repo: not a task.
Answer peer only: changes next action.
Never: status pings or unverified claims (receiving lane acts on it).

Session messages ≠ outbound to person; need no approval.