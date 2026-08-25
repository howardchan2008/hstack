# Architecture

## The shape

A hook is a program. Claude Code runs it at one of seven lifecycle events, hands
it a JSON payload on stdin, and reads its exit code and its output. That is the
whole interface. Everything in this repo is one of those programs.

```
                    ┌──────────────────────────────┐
 user prompt ──────▶│ UserPromptSubmit             │  inject: items, carryover,
                    │  5 hooks, none of them block │  cost, the report contract
                    └──────────────┬───────────────┘
                                   ▼
                    ┌──────────────────────────────┐
   tool call ──────▶│ PreToolUse                   │  refuse: exit 2, or a
                    │  12 hooks, 9 of them refuse  │  deny object on stdout
                    └──────────────┬───────────────┘
                          refused ─┴─▶ back to the model with the reason
                                   ▼
                              the tool runs
                                   ▼
                    ┌──────────────────────────────┐
                    │ PostToolUse                  │  record what it returned
                    └──────────────┬───────────────┘
                                   ▼
                    ┌──────────────────────────────┐
   end of turn ────▶│ Stop                         │  refuse to finish with
                    │  3 hooks, 2 of them refuse   │  work left on the floor
                    └──────────────────────────────┘

  SessionStart (4 hooks): prove the guards are armed, say who else is live,
                          restore what the last session left behind.
```

## Why hooks and not prose

A rules file is read by a model that is optimising for the current task, and
"be careful with force-push" competes with everything else in the context. The
same instruction as a `PreToolUse` hook does not compete with anything. It is
not advice, it is the call not happening.

The measured version of this: an attempt to count how often a written rule was
actually followed could not be made to work, because this configuration
re-injects the rule text at session start, so every apparent recurrence traced
back to the rule's own wording rather than to a real violation. The honest
statement is that the failure rate of prose here is unmeasured. What is not in
doubt is the failure rate of a hook, because a hook either ran or it did not, and
that is in the exit code.

## Four kinds of file

**Guards** refuse. Exit 2, or a JSON decision object. Nine of the twelve
`PreToolUse` hooks and both blocking `Stop` hooks.

**Reporters** print and get out of the way. `fetch-guard.sh`, `curl-router.sh`,
`websearch-cache.sh`. These rot in a way guards do not: a reporter that goes
silent is indistinguishable from a reporter with nothing to say, and every green
sweep counts it as fine. That is why the test suite has a `warn` verdict that
asserts the text actually appears.

**Injectors** put something in front of the model before it decides. All five
`UserPromptSubmit` hooks. The lever is what gets read first.

**Checkers** verify a claim about the world. `wiring-verify.sh`, `doctor.sh`,
`tests/parity.py`. The rule for these: hand it a broken world and assert it says
so, or it is measuring nothing.

## Fail-open against fail-closed

Most hooks here fail open. An unreadable payload, a missing helper, an
unexpected environment: they exit 0 and let the call through. A guard that
breaks the session when its own dependency is missing is worse than the risk it
covers, and it gets deleted within a week.

Two fail closed on purpose, both where the downside is money rather than
inconvenience: `lane-guard.sh` and `click-credit-guard.sh`. For those, the ALLOW
arm of the test is the one that can rot silently, so it is the arm to watch.

## Single source of truth

`hooks.manifest.json` is the only place the wiring is written down. Four things
read it: `install.sh` to register, `doctor.sh` to check what is armed,
`tests/parity.py` to catch drift, and `settings.example.json`, which is generated
from it rather than maintained.

This is a direct response to the way this repo has actually broken. Every real
defect found so far was one fact stored in two places and updated in one: two
hooks whose logic files were left out of the manifest, a checker demanding
fifteen hooks the repo does not ship, a README naming a set that no longer
matched the directory. None of those is a hard bug. All of them are silent.

## State

Hooks that keep state write under `~/.claude/state/`. It is all cache and
session bookkeeping: a probe ledger, a search cache, a last-context snapshot.
Deleting the directory costs you one session of dedupe history and nothing else.

## Cost, since it drives several of these

Every tool call re-sends the entire conversation, so the bill is calls times
context. Measured across one three-day window of real work: cost-weighted input
was 91.4% of the bill and output 8.6%, and cached input read back 3.62 billion
tokens against roughly 13 million tokens of content actually produced.

The consequences are the reason `probe-dedupe.sh`, `burn-context.sh`,
`websearch-cache.sh` and `lane-guard.sh` exist, and they are worth stating
plainly because they are unintuitive:

- Reply length is not the lever. Output is under a tenth of the bill.
- A stable fact should be measured once. Re-probing a daemon's CPU 47 times in
  one session is not diligence.
- Independent probes belong in one call. Separate calls each pay full context.
- Cap tool output at the call site. Twenty-five oversized results were 10% of
  everything written in three days, and each one is re-sent on every later call.

---

Written by Howard Chan.
[linkedin.com/in/howardchan2008](https://www.linkedin.com/in/howardchan2008/).
