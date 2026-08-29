# Testing

```bash
bash tests/run.sh
```

Five stages, cheapest failure first.

| stage | what it proves |
|---|---|
| syntax | every hook parses. A `PreToolUse` hook with a syntax error exits non-zero on every payload, which blocks every tool call in the session |
| parity | the repo agrees with itself: manifest, example settings, the checker's roster, the docs table, the count in the README |
| self-tests | the eleven hooks that carry their own logic tests |
| negative control | every guard refuses what it exists to refuse, and lets ordinary work through |
| dead branches | every regex in every hook is load-bearing: corrupt it and that hook's own self-test must notice |

## Dead branches

The stage above it passes while a rule has quietly stopped working, which is why
this one exists. A self-test only proves the branches it exercises, and a branch
nobody exercises can be deleted without any test going red. It still reads as
coverage in every audit.

So `tests/dead-branch-sweep.py` corrupts one regex at a time so that it cannot
match, re-runs that hook's own self-test, and reports every regex the test did
not miss.

Run against the private tree this repo is built from, the first sweep found 31
dead regexes. Some sat inside blocking rules, so those rules could have stopped
enforcing while the suite still reported PASS. Three were not merely untested
but unreachable: one was an exemption applied only to sentences another regex
had already matched, and the two word lists were disjoint, so it could never
exempt anything.

Direction decides the arm, and this is the part that is easy to get wrong:

- a dead **detector** under-blocks, so it needs a case that it alone catches
- a dead **exemption** over-blocks, so it needs a case that stays clean *only*
  because the exemption matched

An arm can also pass for the wrong reason, which is worse than no arm. Two arms
in this repo asserted the right thing and never reached the regex they were
meant to protect, because a different check had already rejected the line. The
sweep is what found them.

## Negative control

The idea comes from a different measurement that turned out to be worthless. A
credential probe reported 51 slots live. Re-running each probe with a
deliberately corrupted key showed 5 of them still passing, so for those, "live"
carried no information: the probe was reading a status endpoint that answers
before it looks at credentials.

The same question applies to a guard. Feed it the exact payload it exists to
refuse and assert that it refuses. Then feed it ordinary work and assert that it
stays out of the way, because a guard that blocks everything gets bypassed
within a day and is equally useless.

Four verdicts, because collapsing them reports working code as broken:

- **block**: exit 2, or a JSON decision object saying deny or block.
- **allow**: exit 0, no refusal.
- **warn**: exit 0 on purpose, but the routing text must still appear. A
  silenced warn is a dead guard that every green sweep counts as fine.
- **nudge**: refuses once to surface a better lane, then yields on the retry.
  Asserted twice, because a nudge that never clears is a block.

```bash
python3 tests/negative-control.py --list        # the cases and why each exists
python3 tests/negative-control.py --only dash   # substring filter
python3 tests/negative-control.py --json        # machine output
```

Cases run against `hooks/` in this repo by default. Point them at an installed
copy with `HSTACK_HOOKS=~/.claude/hooks`.

## What is deliberately not tested

`agent-budget.sh` has an allow arm and no block arm. Its block arm needs a spent
budget, and faking that state means writing a counter file the real hook reads,
which tests the fixture rather than the hook. Stated here rather than left as a
silent gap.

Anything with a network or clock dependency is out. A suite that fails on a
train is a suite people stop running.

## Parity

`tests/parity.py` asserts five things against `hooks.manifest.json`:

1. every hook on disk is in the manifest, and every manifest entry is on disk
2. `settings.example.json` is exactly what the installer would write
3. `wiring-verify.sh`'s roster equals the shipped set
4. `docs/HOOKS.md` documents every hook
5. any hook count written in the README prose is the real one

`python3 tests/parity.py --write` regenerates the example settings.

Check 5 looks petty and is not. A README that says "sixteen hooks" over a
directory of twenty-five is the visible tip of the failure this repo keeps
hitting: one fact stored in six places and updated in one. Every real defect
found here so far has been that, and all of them were silent.

## CI

`.github/workflows/ci.yml` runs the suite on Ubuntu and macOS for every push and
pull request, plus `shellcheck` on the shell hooks. macOS is in there because
this was developed on BSD tooling and Ubuntu keeps the GNU assumptions honest.

A red X in CI can also mean the job never started. Check the run annotations
before reading it as a test failure; "log not found" is not the same claim as
"the tests failed".

---

Written by Howard Chan.
[linkedin.com/in/howardchan2008](https://www.linkedin.com/in/howardchan2008/).
