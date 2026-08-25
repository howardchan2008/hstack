# Security

## What these hooks are

Programs that run automatically, before every tool call, with your shell's
privileges. That is an arbitrary-code-execution surface by design, and it is the
reason `wiring-verify.sh` treats an unexplained ADDITION to the hooks directory
as seriously as a deletion.

Read anything you install here. That includes this repo. Twenty-five files of
shell and python, forty to three hundred lines each, no dependencies in either
language, and the reasoning is in the comments.

## What they do not do

No network calls. No telemetry. Nothing is sent anywhere. State is written under
`~/.claude/state/` and is cache and session bookkeeping: a probe ledger, a search
cache, a snapshot of where the last session left off. Delete it and you lose one
session of dedupe history.

`install.sh` writes to `~/.claude/hooks/`, `~/.claude/rules/` and
`~/.claude/settings.json`, backs the settings file up first, and touches nothing
else.

## Reporting

Something exploitable, rather than a guard that behaved wrongly: open a GitHub
security advisory on this repository, or message
[LinkedIn](https://www.linkedin.com/in/howardchan2008/). A guard that failed open
or fired on ordinary work is an ordinary issue and there are templates for both.

## A note on the redaction

This repo is extracted from a working private configuration by a scrubber that
re-scans its own output and fails the build on a single surviving match. The
scrubber does not ship, because its rules are a list of every private string it
knows about.

If you find something that survived, that is the highest-priority issue this
repository can receive. Please report it privately rather than in a public issue.
