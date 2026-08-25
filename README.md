# hstack

Claude Code guards. Sixteen hooks that refuse the operator, and the incident
behind each one.

## Why this exists

Most Claude Code configurations are about making the agent do more: more agents,
more skills, more roles. `gstack` is the best of them and has 129,000 stars.

This is the other half. Every file here exists because an agent did something it
should not have, and the fix was a hook that refuses rather than a prompt that
asks nicely. The agent is fast and confident and wrong often enough that "be
careful" is not a control.

The test for including anything: **it must have refused something real.**

## What is in here

### Guards that stop an operation

| hook | what it refuses | the incident |
|---|---|---|
| `risk-checkpoint.sh` | launchd, cron, force-push, destructive DDL | high-blast-radius commands ran with no rollback stated |
| `lane-guard.sh` | expensive model fan-outs on cheap work | a single run spent tens of millions of tokens doing work a free lane could do |
| `stop-justify.sh` | ending a turn with work left on the floor | close-outs that named unfinished work and stopped anyway |
| `dash-gate.sh` | unicode dashes in authored files | a house style rule that prose alone never enforced |
| `ls-before-write.sh` | writing to a directory never listed | files written into paths that did not exist |
| `curl-router.sh` | raw curl where a routed lane exists | credentials and proxies handled inconsistently |
| `probe-dedupe.sh` | asking the same question repeatedly | 406 shell calls in one session, 71 of them the same probe reworded |
| `click-credit-guard` pattern | metered API calls when a free lane covers it | paid credits spent on general web search |

### Checks that verify the work

| hook | what it checks |
|---|---|
| `wiring-verify.sh` | the guards are actually armed, at session start |
| `session-collide.sh` | who else is live in this repo before you rewrite history |
| `prompt-items.py` | every item in the request got answered, not just the first |
| `closeout-shape.py` | the report answers the question that was asked |
| `session-identity.sh` | which session did what, when several share a repo |

### Rules

`rules/common/` holds the always-loaded rules the guards enforce: coding style,
testing, security, agent orchestration, and a file on learning from mistakes that
is mostly a list of them.

## The one that matters most

A guard that blocks everything is as useless as one that blocks nothing, and only
the second failure is visible. So the guards are themselves tested against a
payload they must refuse **and** a payload they must allow. A guard that cannot
fail is not a measurement.

## Install

Copy `hooks/` and `rules/` into `~/.claude/`, then register the hooks in
`~/.claude/settings.json`. See `settings.example.json`.

Each hook reads a JSON payload on stdin and exits non-zero to refuse. They are
independent: take one, take all of them, or read them and write your own.

## What has been removed

This is extracted from a working private configuration. Names, email addresses,
credential slot names, home paths and business specifics are stripped by a
scrubber that then re-scans its own output and fails the build on a single leak.

The scrubber itself does **not** ship, and that was a real bug caught before this
was published: a scrubber's rules are a list of every private string it knows
about, so including it for transparency would have published exactly the thing it
removes. Transparency about a redaction cannot be the redaction list.

The incidents keep their facts and lose their cast. "The outreach lane sent to a
contact" is a real thing that happened; the person's name is not yours to have.

## Licence

MIT.
