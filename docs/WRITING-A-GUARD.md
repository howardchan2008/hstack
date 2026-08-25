# Writing a guard

The mechanics take ten minutes. The judgement is the part that decides whether
the guard is still installed in a month.

## Mechanics

A `PreToolUse` hook reads one JSON object on stdin:

```json
{ "tool_name": "Bash",
  "tool_input": { "command": "git push --force origin main" },
  "session_id": "…", "cwd": "/path/to/repo" }
```

Exit 0 to allow. Exit 2 to refuse, with the reason on stderr, which is what the
model reads. The minimum viable guard:

```bash
#!/usr/bin/env bash
set -uo pipefail
payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c \
  'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("command",""))')"

case "$cmd" in
  *"push --force"*|*"push -f "*)
    echo "REFUSED: force-push. Say which commits you are replacing and why." >&2
    exit 2 ;;
esac
exit 0
```

Register it, then run `./doctor.sh` to confirm it is armed. Present and
unregistered is the normal failure and it is invisible.

## The five rules that decide whether it survives

**1. Test what it does, not what it is called.** The test written for
`ls-before-write.sh` asserted the behaviour its NAME implies, put its fixture in
the system temp directory, and reported a working guard as failing open. The
hook skips scratch trees on purpose. Read the code, then write the case.

**2. Write the allow arm first.** The block arm is easy and it is not where
guards die. They die by firing on ordinary work until somebody adds a bypass,
and then the bypass becomes the habit. If you cannot state the payload that must
go through, you do not yet understand the rule you are encoding.

**3. Fail open unless the downside is money.** Missing helper, unreadable
payload, strange environment: exit 0. A guard that breaks the session when its
own dependency is absent is worse than the risk it covers. The exceptions are
metered calls and expensive fan-outs, where the wrong answer costs real money;
those fail closed, and then their allow arm is the thing that rots.

**4. Refuse with a next action.** "Blocked" restates the exit code. Name what
would make it acceptable: the flag, the safer command, the sentence the model
has to say first. A refusal with no route forward gets bypassed, correctly.

**5. Put the incident in the file.** Every hook here opens with the thing that
happened: the date, the number, the cost. Six months later you cannot tell a
load-bearing guard from a superstition without it, and the one with no story
gets deleted during a cleanup. That has already happened once here, to a
scheduled job that turned out to be load-bearing.

## Then add the case

In `tests/negative-control.py`:

```python
dict(name="my-guard/block", script="my-guard.sh", expect="block",
     payload=bash("git push --force origin main"),
     why="the shape that cost us the 2026-08-03 clobber"),
dict(name="my-guard/allow", script="my-guard.sh", expect="allow",
     payload=bash("git push origin feature-branch"),
     why="an ordinary push. Refusing this is how the guard gets uninstalled"),
```

Add it to `hooks.manifest.json` in the same commit. `tests/parity.py` fails the
build if you do not, which is on purpose: the manifest is what installs it,
tests it, and tells the checker it is allowed to exist.

## What does not belong here

A guard for something that has never happened. This is the whole editorial rule
of the repo. Speculative guards are the ones with false positives nobody has
priced, and they are the reason a hooks directory becomes something people turn
off wholesale.

If it has not refused something real, keep it in your own config until it has.

---

Written by Howard Chan.
[linkedin.com/in/howardchan2008](https://www.linkedin.com/in/howardchan2008/).
