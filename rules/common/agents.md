# Agent Orchestration

## There is no remote worker lane on this machine

This file used to open by telling every session to prefer OpenClaw workers over local
subagents. Measured 2026-08-14: no `openclaw` on PATH, no `~/.openclaw` or
`~/.config/openclaw`, and no such MCP server in `~/.claude.json` (global servers are
guild and linkedin-mcp; context7 and whatsapp were removed 2026-08-20). The only hits inside
`plugins/cache/everything-claude-code/` and one echo line in `bin/usage-verdict.sh`.
So the first routing instruction in the always-loaded rules pointed at a lane that has
never existed here. Local subagents are the only agent lane. The genuine offload lanes
are Codex and local Ollama, ranked in the engine-routing ladder in `~/CLAUDE.md`.

## Available Agents

Located in `~/.claude/agents/`:

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| planner | Implementation planning | Complex features, refactoring |
| architect | System design | Architectural decisions |
| tdd-guide | Test-driven development | New features, bug fixes |
| code-reviewer | Code review | After writing code |
| security-reviewer | Security analysis | Before commits |
| build-error-resolver | Fix build errors | When build fails |
| e2e-runner | E2E testing | Critical user flows |
| refactor-cleaner | Dead code cleanup | Code maintenance |
| doc-updater | Documentation | Updating docs |
| advisor | Read-only second opinion | Commitment boundaries, architecture, 3+ file refactors |

Language specialists, listed as they actually exist (checked 2026-08-14, because the line
here used to name six languages as if each had both halves, and two of them do not):

| | reviewer | build-resolver |
|---|---|---|
| python, typescript, database | yes | no |
| go, cpp | yes | yes |
| pytorch | **no** | yes |

So `pytorch-reviewer` is not a thing to dispatch; `pytorch-build-resolver` is. Rust, Java,
Kotlin and Flutter were archived 2026-08-14 (zero source files of those languages on this
machine); restore with `mv ~/.claude/agents-archive/<name>.md ~/.claude/agents/`.

## Immediate Agent Usage

No user prompt needed:
1. Complex feature requests - Use **planner** agent
2. Code just written/modified - Use **code-reviewer** agent
3. Bug fix or new feature - Use **tdd-guide** agent
4. Architectural decision - Use **architect** agent

## Parallel means one message, not more agents

When two agents are genuinely warranted, dispatch them in ONE message so they run
concurrently. Never send them one at a time and wait.

That is a batching rule, and it is the whole of it. It used to read "ALWAYS use parallel
Task execution", with a worked example of three agents on one question and a five-role
review panel below it, which is a spending instruction wearing a latency instruction's
clothes. The agent budget breaker blocks at 8 dispatches per SESSION per 24h, 40 across the
box per 24h, 200 per 7d (changed 2026-09-02: the old box-wide 8/day let one session lock out
every other session for a day; 193 of 406 lifetime attempts had been denied). Cost is per
agent, not per message, and the ceiling is real. Sub-agents inherit the parent model: on a
Fable 5.1 session pass `model: sonnet` or `haiku` to a worker.

Before a second agent: name the independent subtree it owns. Two agents whose scope
overlaps return the same findings twice at twice the price, which is how one audit spent
243 Explore calls on the same tree. Shell pre-scan first (`rg`, `/bin/ls`, `sed`), read
known files directly, and spend an agent only on what is left.

PROVENANCE, and it applies to every number on this page. The 243 is a HISTORICAL
single-audit figure, not reproducible from the current corpus. Reproduce the live counts by
walking `message.content` in both `~/.claude/projects/**/*.jsonl` and
`~/Archive/claude-transcripts/**/*.jsonl.gz`, tallying `tool_use` blocks by `name` and by
`input.subagent_type`. Run on 2026-08-23 across all 3,857 transcripts that gives 0 top-level
`Explore` calls and 100 Agent dispatches with `subagent_type: Explore`, out of 495 dispatches
total. Quote those instead; treat 243 as the anecdote it is.

## TALK TO THE OTHER SESSIONS. They are running right now and you are not alone

the owner, 2026-08-24: *"since when can u message teammates, this is a fucking useful
feature literally u shd use it much more from now on"*.

`ListAgents` names every live session on this machine; `SendMessage({to, message})`
delivers into one. Measured across every live transcript on the day this was written:
**SendMessage 12 calls ever, ListAgents 4**, against 83 Agent dispatches. The lane
existed and was effectively unused, while 5 to 7 sessions run concurrently in these
repos every working day (`guild-session.sh` prints the roster at every session start).

WHAT IT COSTS, in the units that matter, because "cheap" was the wrong word on day
one. Today's median context is 328,356 tokens per call, so at the 0.10 cache-read
weight one call is about 33,000 billable-equivalent input tokens. A message is TWO:
one in the sender's context and a full turn in the receiver's, so roughly 66,000 for a
paragraph. That is still a bargain against a lane rediscovering a fact you already
hold, which is a dozen calls at its own full context plus the owner's attention: the
a venture case burned 15 classifier refusals and then escalated a wrong diagnosis
to him. It is a terrible price for "confirmed, thanks".

WRITE IT ONCE BEATS TELLING EVERYONE. Amended 2026-08-24 the same day it was added,
the owner: *"wouldnt it be nicer just to have one sync or one single permanent change such
that u dont hv these back and forths, anything shd be one msg one way max unless there's
good reason to start a convo"*. He is right, and the first day of using this got it
wrong: 4 messages sent, 3 of them into ONE lane, one of which was a courtesy reply.

The default for a DURABLE fact is not a message, it is a WRITE. Put it in the
always-loaded surface (`~/CLAUDE.md`, `rules/`, the tool's own header) and every session
gets it at start for free, including the ones not running yet. A message reaches one
lane, once, and dies with it. It also costs twice what it looks like: one call in the
sender's context and a full turn in the receiver's, so at today's 328k median that is
roughly 66k billable-equivalent tokens for a paragraph.

MESSAGE ONLY WHEN A FILE CANNOT DELIVER IT IN TIME. The test is narrow:
- Time-critical AND session-specific. "Your browser calls are failing right now for
  this reason" cannot wait for their next session start. "Reddit needs auth" can.
- The thing is already on fire and they are mid-loop.
If the fact outlives the hour, write it instead. If it does both, write it AND send one
line pointing at where you wrote it.

ONE MESSAGE, ONE DIRECTION. Do not open a thread.
- No acknowledgements, no "confirmed", no thanks, no closing the loop. A peer's reply
  needs no reply. Silence is the correct response to agreement.
- Say everything in the first message. If you find yourself sending a second one to the
  same lane in a session, the first was incomplete and that is the defect.
- A peer mentioning a third repo is NOT a task. Scope creep arrives by message: on
  2026-08-24 a peer's aside about a venture pulled this session into a third repo's
  compliance question it was never asked about. Note it for the owner, do not adopt it.
- Answer a peer only when the answer CHANGES WHAT THEY DO NEXT. "It is mine, thanks"
  does not. "Do not commit that file, the owner is deciding" does.

DO NOT send: status pings, "just checking in", a summary of your own work nobody asked
for, or anything you have not verified. A wrong message costs more than silence,
because the receiving lane will act on it. The same standard applies as to any claim
made to the owner: verify first, then send, and say what you measured.

A message to another session is NOT outbound communication to a person. It needs no
approval and no draft-first step: it is one agent telling another agent a fact.
