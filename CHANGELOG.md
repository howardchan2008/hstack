# Changelog

## 0.2.0

Nine more hooks, and the difference between a directory of files and something
a stranger can install.

**Added**

- Nine hooks: `agent-budget.sh`, `pipestatus-guard.sh`, `click-credit-guard.sh`,
  `fetch-guard.sh`, `carryover-queue.py`, `closeout-preflight.sh`,
  `state-verify-inject.sh`, `burn-context.sh`, `websearch-router.sh`.
  Sixteen to twenty-five.
- `hooks/lib/`. Two hooks shipped in 0.1.0 without the modules that hold their
  logic, so `probe-dedupe.sh` and `websearch-cache.sh` were inert no-ops for
  anyone who installed the repo. A hook that cannot fire is the same defect as a
  guard that cannot fail.
- `install.sh`: idempotent settings merge, timestamped backup, atomic write,
  `--dry-run`, `--only`, `--prefix`, `--uninstall`.
- `doctor.sh`: four checks per hook, ending in whether it is registered. Present
  and unregistered is the failure that is invisible from the inside.
- `hooks.manifest.json`: one source of truth for the wiring. The installer, the
  doctor, the parity check and the generated example settings all read it.
- `tests/`: `run.sh` (syntax, parity, self-tests, negative control),
  `negative-control.py` (20 cases, block and allow arms), `parity.py` (five
  invariants the repo kept breaking silently).
- `docs/`: hooks, install, architecture, writing a guard, testing,
  troubleshooting.
- CI on Ubuntu and macOS, `shellcheck`, and an install smoke test that installs
  into a scratch prefix, installs a second time to prove no duplicate
  registration, then uninstalls and asserts the settings file empties out.

**Fixed**

- The redaction rule for phone numbers was eating ISO dates. 199 provenance
  lines shipped reading "Added \<phone\>" instead of "Added 2026-08-14". The
  scrub destroyed the fact it exists to protect while looking like diligence.
- `wiring-verify.sh` shipped a roster naming eighteen hooks, fifteen of which
  this repo does not contain, so a stranger's first session printed fifteen
  REVIEW lines about files that were never theirs. The roster is now built from
  the manifest at scrub time and `tests/parity.py` keeps it equal.
- `stop-justify.sh` did not parse under bash 3.2, which is what `/bin/bash` is
  on macOS and will stay. A quoted heredoc inside a command substitution breaks
  there when the body contains an apostrophe, and this one has six. Under bash 5
  it was fine; on a stock Mac it is a Stop hook that exits non-zero on every
  turn. Found by CI on macos-latest, and `tests/run.sh` now parses every hook
  with every bash on the machine.
- `probe-dedupe.sh` and `websearch-cache.sh` resolved their `lib/` module from
  `$HOME`, so both failed when run out of a clone rather than an install. They
  resolve from their own location now, with the `$HOME` path as the fallback.
- A test fixture in `prompt-items.py` was a real prompt. Replaced with a
  synthetic one; the assertion it feeds is unchanged.

## 0.1.0

First public release. Sixteen hooks and eight rules, extracted from a private
configuration by a scrubber that re-scans its own output and fails the build on
a single surviving match.

Three leaks were caught before publication, each by a check rather than a
careful read:

- The scrubber was shipping itself. A scrubber's rules are a list of every
  private string it knows about, so publishing it for transparency would have
  published exactly what it removes.
- A venture name survived glued to a suffix, because `\b` does not fire
  mid-word.
- Two different names collapsed into one placeholder and made the sentence
  nonsense.
