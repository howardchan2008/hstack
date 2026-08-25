# Troubleshooting

## A hook does nothing

Run `./doctor.sh -v`. The usual answer is that the file is on disk and
registered nowhere, which is invisible by construction: a guard that never runs
looks exactly like a guard that never had to. `./install.sh` registers what is
missing.

If the file is registered and still silent, check the runner. Four hooks are
python, and a `python3` that resolves to something without the standard library
on `PATH` fails quietly at the top of the file.

## Everything is blocked

A `PreToolUse` hook that exits non-zero for any reason refuses the call, and a
syntax error is a non-zero exit on every payload. `bash tests/run.sh` catches
that in its first stage. To get moving again, remove the offending entry from
`settings.json` (there is a timestamped backup beside it from the install) and
then find out why it is failing.

## A guard fires on ordinary work

That is a bug and it is the one worth reporting. It is also the way a hooks
directory dies: one false positive teaches a bypass, the bypass becomes a habit,
and then the whole thing gets turned off.

Two short-term options. Delete the registration for that hook. Or edit the hook,
since they are forty to two hundred lines of shell or python with the reasoning
in comments.

Then open an issue with the payload it refused. Every guard here has an allow
arm in the suite for exactly this class of failure, and yours becomes one.

## `probe-dedupe.sh` or `websearch-cache.sh` never fire

Both delegate to a module in `hooks/lib/`. Copy that directory too. The first
published version of this repo left it out, and both hooks were inert no-ops for
anyone who installed it.

## A routing hook recommends a command I do not have

`curl-router.sh`, `websearch-router.sh` and `click-credit-guard.sh` each hold a
table mapping a host or an API to the local command that already does that job.
The tables name the author's commands. Edit them: put your own in, or delete the
rows you have no replacement for. All three fall silent when the command they
would recommend is not on disk, so an unedited install is quiet rather than
wrong.

## The dash guard refuses text I want to write

`dash-gate.sh` enforces one person's house style. Uninstall it with
`./install.sh --uninstall --only dash-gate.sh`, or keep it and change the
character class. It is about forty lines.

## macOS and Linux differences

Developed on macOS, so BSD tooling is the default assumption and the places it
diverges are commented in the code. The ones that bite:

- `stat -f %m` on BSD, `stat -c %Y` on GNU.
- `date -v -1d` on BSD, `date -d '1 day ago'` on GNU.
- BSD `grep` has no `-P`, and `timeout` execs the BSD one even when a GNU grep
  is first on `PATH`. `grep-portability.sh` exists for exactly this, because the
  failure prints nothing and an empty result reads as a clean tree.
- `setsid`, `mapfile` and `readarray` are absent on macOS.

CI runs the suite on both, which is what keeps these honest.

## An unmatched glob kills a whole command

In `zsh`, an unmatched glob aborts the entire compound command by default. That
was the single largest class of failed shell calls in one measured corpus:
2,006 across 3,857 sessions. The fix is one line in `~/.zshenv`:

```sh
[[ -o interactive ]] || setopt nonomatch
```

Not a hook, and worth more than most of them.

## Session-start output is too noisy

`wiring-verify.sh` and `session-collide.sh` are the talkative ones. Both are
reporters and neither blocks, so removing their registrations costs nothing but
the report. Before you do: if `wiring-verify.sh` is printing REVIEW lines about
hooks you added, add them to its roster, which is what those lines are asking
for. `tests/parity.py` will then keep it in step.

---

Written by Howard Chan.
[linkedin.com/in/howardchan2008](https://www.linkedin.com/in/howardchan2008/).
