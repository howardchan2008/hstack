# Install

```bash
git clone https://github.com/howardchan2008/hstack && cd hstack
./install.sh --dry-run     # see exactly what would change
./install.sh               # do it
```

`install.sh` copies `hooks/` and `rules/` into `~/.claude/`, merges the
registrations into `~/.claude/settings.json`, and then runs `doctor.sh` so the
last thing you see is evidence rather than a claim.

## What it does to settings.json

It backs the file up to `settings.json.hstack-<timestamp>` before touching it,
writes through a temporary file and an atomic rename (a half-written
`settings.json` takes the harness down), and merges on the command string, so
running it twice registers each hook once. Anything already in the file that
hstack did not put there is left exactly where it is.

If `settings.json` is not valid JSON, it refuses and changes nothing.

## Flags

| flag | effect |
|---|---|
| `--dry-run` | print the change, write nothing |
| `--only a.sh,b.sh` | install just those hooks |
| `--prefix DIR` | install somewhere other than `~/.claude` |
| `--force` | overwrite a hook that differs from this repo (keeping a `.hstack-backup`) |
| `--uninstall` | remove the hooks and their registrations |

Without `--force`, a file that differs from the repo copy is left alone and
reported. That is deliberate: if you have edited a routing table to name your own
tools, an upgrade should not quietly throw that away.

## Taking one hook instead of all of them

```bash
./install.sh --only dash-gate.sh
```

Or by hand: copy the file into `~/.claude/hooks/`, then add it under the right
event in `settings.json`. `settings.example.json` shows the full shape, and it is
generated from `hooks.manifest.json` rather than maintained by hand, so it cannot
drift from what the installer does.

Two hooks need their `lib/` companions to do anything: `probe-dedupe.sh` and
`websearch-cache.sh` both delegate to a python module under `hooks/lib/`. Copy
that directory too. The first published version of this repo left it out, and
those two hooks were inert no-ops for anyone who installed it.

## Verifying

```bash
./doctor.sh -v
```

Four checks per hook, in the order they go wrong: the file is there, it is
executable and its interpreter exists, `settings.json` registers it under the
right event and matcher, and it survives a plain payload without a traceback.

Exit 0 means every hook in the manifest is armed. A hook that is present but
unregistered is the failure this exists to catch, because it is invisible: a
guard that never runs looks exactly like a guard that never had to.

`doctor.sh` also lists registered hooks that hstack does not own. It never
removes them. They are probably yours.

## Uninstalling

```bash
./install.sh --uninstall
```

Removes the hook files and their registrations, and drops any event group left
empty. `rules/` is left in place, because those are plain markdown that you may
have edited.

## Requirements

Claude Code, `bash`, and `python3` (four hooks are python, and the settings merge
uses it). Developed and used on macOS. The places where BSD and GNU tools differ
are called out in the code at the line where they bite: `stat -f` against
`stat -c`, `date -v` against `date -d`, and BSD `grep` having no `-P`.

---

Written by Howard Chan.
[linkedin.com/in/howardchan2008](https://www.linkedin.com/in/howardchan2008/).
