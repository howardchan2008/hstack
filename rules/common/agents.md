# Agent Orchestration

Subagents are PROHIBITED except the three `caveman:cavecrew-*` types (see `~/.claude/CLAUDE.md`). Everything below applies when one is genuinely authorised.

## There is no remote worker lane on this machine
No openclaw binary, config or MCP server here (measured 2026-08-14). Local subagents are the only agent lane. The genuine offload lanes are Codex and local Ollama.

## No agent-to-agent framework here (market checked 2026-09-03, verdict stands)
Every orchestration framework solves discovery and transport between agents that cannot see each other. Here Claude and Codex share one filesystem, one sqlite queue (`~/.claude/state/jobq.db`) and one keychain.
**The queue plus the inbox IS the protocol.** Claude to Codex: `jobq add` then `jobq wait <id>` in the background; the completion notification re-invokes the session. Codex to Claude: `jobq inbox`, results sit there until `jobq ack <id>`, and `hooks/carryover-queue.py` injects unacked results into the next prompt. Never poll `jobq status`. Other side's copy: `~/.codex/AGENTS.md`.

## Available agents
`~/.claude/agents/`: advisor (read-only second opinion), architect, planner, tdd-guide, code-reviewer, security-reviewer, build-error-resolver, python-reviewer, typescript-reviewer, and the caveman trio. Everything else was archived 2026-09-05 for context cost; restore with `mv ~/.claude/agents-archive/<name>.md ~/.claude/agents/`.

## Parallel means one message, not more agents
When two are genuinely warranted, dispatch them in ONE message. Cost is per agent, not per message. Budget breaker: 8 dispatches per session per 24h, 40 box-wide per 24h, 200 per 7d. Sub-agents inherit the parent model; on a Fable session pass `model: sonnet` or `haiku`.
Before a second agent, name the independent subtree it owns. Shell pre-scan first (`rg`, `/bin/ls`, `sed`), read known files directly, spend an agent only on what is left.

## TALK TO THE OTHER SESSIONS (2026-08-24)
*"since when can u message teammates, this is a fucking useful feature literally u shd use it much more from now on"*. `ListAgents` names every live session; `SendMessage({to, message})` delivers into one. Five to seven sessions run concurrently here daily.
COST: a message is TWO full-context calls, roughly 66k billable-equivalent tokens.
WRITE IT ONCE BEATS TELLING EVERYONE. A durable fact goes in the always-loaded surface, where every session gets it free including the ones not started yet.
MESSAGE ONLY WHEN A FILE CANNOT DELIVER IT IN TIME: time-critical AND session-specific, and they are mid-loop. If it outlives the hour, write it instead.
ONE MESSAGE, ONE DIRECTION. No acknowledgements, no thanks, no closing the loop. Say everything in the first message. A peer mentioning a third repo is NOT a task. Answer a peer only when the answer CHANGES WHAT THEY DO NEXT. Never send status pings or unverified claims: the receiving lane will act on it.
A message to another session is not outbound communication to a person; it needs no approval.
