# Contributing

## The most useful thing you can send

**A guard that failed open on you.** The payload it let through, and what it
cost. That is the same evidence every hook here was built from, and it is worth
more than a new hook, because it turns into a test case that keeps working after
the report is forgotten.

Second most useful: **a guard that fired on ordinary work.** That is how a hooks
directory dies. One false positive teaches a bypass, the bypass becomes a habit,
and the whole thing gets turned off. Paste what it refused and it becomes an
allow arm in the suite.

There are issue templates for both.

## Adding a hook

One rule, and it is the editorial line of the whole repo: **it has to have
refused something real.** Not a rule you would like to enforce. A thing that
happened, with a date and a cost.

Speculative guards are the ones whose false positives nobody has priced. If
yours has not refused anything yet, keep it in your own config until it has.

Then:

1. The hook, with the incident in the header comment. Date, number, what it cost.
2. An entry in `hooks.manifest.json`. Nothing installs, tests, or recognises a
   hook that is not in there, and `tests/parity.py` fails the build without it.
3. Two cases in `tests/negative-control.py`: the payload it must refuse, and the
   ordinary payload it must let through. Write the allow arm first.
4. An entry in `docs/HOOKS.md`. Parity checks this too.
5. `bash tests/run.sh` green.

Read [docs/WRITING-A-GUARD.md](docs/WRITING-A-GUARD.md) first. It is short and it
covers the judgement, which is the part that decides whether a guard is still
installed in a month.

## Style

The code here is commented at an unusual density and that is deliberate. Six
months later you cannot tell a load-bearing guard from a superstition without
the story, and the one with no story gets deleted in a cleanup. Write the
reasoning, not the mechanism: the mechanism is already visible one line down.

Shell is `bash`, `set -uo pipefail`, and fail open on anything unexpected.
Python is 3.9+ and standard library only. No dependencies, in either language.
Both are a hard requirement: a hook runs before every tool call, and an import
error there takes the session with it.

Prose in this repo does not use em dashes. That is a house style rule and there
is a hook enforcing it, which will refuse your commit if you try.

## Before you open a pull request

```bash
bash tests/run.sh
```

CI runs the same thing on Ubuntu and macOS. macOS is there because this was
developed on BSD tooling and Ubuntu keeps the GNU assumptions honest.

## Not accepted

- Hooks for a failure that has not happened.
- Dependencies.
- Anything that makes a hook fail closed without a stated reason. The two that
  do fail closed both cost money when they are wrong, and both say so in the file.

## Questions

Open an issue, or find me on
[LinkedIn](https://www.linkedin.com/in/howardchan2008/). If one of these guards
caught something interesting on your machine, that story is worth hearing even
if it never becomes a pull request.

---

Howard Chan.
