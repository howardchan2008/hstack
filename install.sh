#!/usr/bin/env bash
# install.sh - put the hooks on disk and register them in settings.json.
#
# Three properties this has to hold, because each one is a way installs go wrong:
#
#   IDEMPOTENT   running it twice registers each hook once. A merge that appends
#                blindly gives you a settings.json with the same guard listed
#                four times, and every Bash call then pays for four processes.
#
#   REVERSIBLE   settings.json is copied to a timestamped backup before it is
#                touched, and --uninstall puts the hooks back the way it found
#                them. A config tool with no exit is a config tool people avoid.
#
#   HONEST       --dry-run prints the exact diff and writes nothing, and the
#                real run ends by calling doctor.sh. "Installed" is a claim; the
#                doctor output is the evidence.
#
# Usage:
#   ./install.sh                 install everything into ~/.claude
#   ./install.sh --dry-run       print what would change, write nothing
#   ./install.sh --only dash-gate.sh,stop-justify.sh
#   ./install.sh --prefix DIR    install somewhere else (default ~/.claude)
#   ./install.sh --uninstall     remove the hooks and their registrations
#   ./install.sh --force         overwrite files that differ from this repo

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${HSTACK_PREFIX:-$HOME/.claude}"
DRY=0
FORCE=0
UNINSTALL=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY=1 ;;
    --force)     FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --only)      ONLY="${2:-}"; shift ;;
    --prefix)    PREFIX="${2:-}"; shift ;;
    -h|--help)   sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "install.sh: python3 is required (the settings merge and four hooks need it)" >&2
  exit 69
fi

MANIFEST="$REPO/hooks.manifest.json"
[ -f "$MANIFEST" ] || { echo "install.sh: hooks.manifest.json is missing" >&2; exit 66; }

say() { printf 'hstack: %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------
copy_tree() {
  local rel="$1" src dst
  src="$REPO/$rel"
  [ -d "$src" ] || return 0
  while IFS= read -r f; do
    local sub="${f#"$src"/}"
    dst="$PREFIX/$rel/$sub"
    if [ -n "$ONLY" ] && [ "$rel" = "hooks" ]; then
      case ",$ONLY," in *,"$(basename "$f")",*) ;; *) continue ;; esac
    fi
    if [ -f "$dst" ] && ! cmp -s "$f" "$dst"; then
      if [ "$FORCE" -eq 0 ]; then
        say "differs, keeping yours (use --force to overwrite): $rel/$sub"
        continue
      fi
      [ "$DRY" -eq 1 ] || cp "$dst" "$dst.hstack-backup"
    fi
    if [ "$DRY" -eq 1 ]; then
      say "would write $rel/$sub"
    else
      mkdir -p "$(dirname "$dst")"
      cp "$f" "$dst"
      # `[ -x ] && chmod` as the LAST command in the loop body returns 1 for
      # every non-executable file, which under `set -e` ends the script on the
      # first markdown file it copies. It did exactly that, silently, and the
      # run still exited 0 because the caller piped it. Keep the `if`.
      if [ -x "$f" ]; then chmod +x "$dst"; fi
    fi
  done < <(find "$src" -type f ! -name '.*')
}

remove_tree() {
  local rel="$1"
  [ -d "$REPO/$rel" ] || return 0
  while IFS= read -r f; do
    # Two statements, not one `local a=.. b=$a`. Bash does not guarantee the
    # second assignment sees the first, and under `set -u` that reads as
    # "sub: unbound variable" during an uninstall, after the settings file has
    # already been rewritten. Half an uninstall is the worst of both.
    local sub dst
    sub="${f#"$REPO/$rel"/}"
    dst="$PREFIX/$rel/$sub"
    [ -f "$dst" ] || continue
    if [ "$DRY" -eq 1 ]; then say "would remove $rel/$sub"; else rm -f "$dst"; fi
  done < <(find "$REPO/$rel" -type f ! -name '.*')
}

# ---------------------------------------------------------------------------
# settings.json
#
# The merge is keyed on the COMMAND STRING, so re-running finds the entry it
# wrote last time instead of adding a second one. Anything already in the file
# that hstack did not put there is left exactly where it is.
# ---------------------------------------------------------------------------
merge_settings() {
  local mode="$1"
  "$PY" - "$MANIFEST" "$PREFIX" "$mode" "$DRY" "$ONLY" <<'PYEOF'
import json, os, shutil, sys, time
from pathlib import Path

manifest, prefix, mode, dry, only = sys.argv[1:6]
dry = dry == "1"
only = {s for s in only.split(",") if s}
spec = json.loads(Path(manifest).read_text())["hooks"]
if only:
    spec = [h for h in spec if h["file"] in only]

settings = Path(prefix) / "settings.json"
data = {}
if settings.exists():
    try:
        data = json.loads(settings.read_text() or "{}")
    except json.JSONDecodeError as e:
        print(f"hstack: {settings} is not valid JSON ({e}); refusing to touch it")
        sys.exit(65)

hooks = data.setdefault("hooks", {})


def command_for(h):
    return f'{h["runner"]} $HOME/.claude/hooks/{h["file"]}'.replace(
        "$HOME/.claude", prefix.replace(str(Path.home()), "$HOME"))


changes = []
for h in spec:
    cmd = command_for(h)
    groups = hooks.setdefault(h["event"], [])
    # Find the group whose matcher is ours, or make one. A null matcher means
    # "every payload for this event" and is stored without the key, which is
    # what the harness itself does.
    target = None
    for g in groups:
        if g.get("matcher") == h["matcher"] or (h["matcher"] is None and "matcher" not in g):
            target = g
            break
    if target is None:
        target = {} if h["matcher"] is None else {"matcher": h["matcher"]}
        target["hooks"] = []
        if mode == "install":
            groups.append(target)
        else:
            continue
    entries = target.setdefault("hooks", [])
    present = [e for e in entries if e.get("command") == cmd]
    if mode == "install":
        if present:
            continue
        entries.append({"type": "command", "command": cmd})
        changes.append(f"+ {h['event']}  {h['file']}")
    else:
        if not present:
            continue
        target["hooks"] = [e for e in entries if e.get("command") != cmd]
        changes.append(f"- {h['event']}  {h['file']}")

# Drop groups and events left empty by an uninstall, so the file does not
# accumulate hollow scaffolding across install/uninstall cycles.
for event in list(hooks):
    hooks[event] = [g for g in hooks[event] if g.get("hooks")]
    if not hooks[event]:
        del hooks[event]

if not changes:
    print("hstack: settings.json already matches the manifest, nothing to do")
    sys.exit(0)

for c in changes:
    print(f"hstack: {c}")

if dry:
    print(f"hstack: dry run, {settings} not written")
    sys.exit(0)

if settings.exists():
    backup = settings.with_suffix(f".json.hstack-{time.strftime('%Y%m%d-%H%M%S')}")
    shutil.copy2(settings, backup)
    print(f"hstack: backed up {settings.name} to {backup.name}")

settings.parent.mkdir(parents=True, exist_ok=True)
tmp = settings.with_suffix(".json.hstack-tmp")
tmp.write_text(json.dumps(data, indent=2) + "\n")
os.replace(tmp, settings)          # atomic: a half-written settings.json bricks the harness
print(f"hstack: wrote {settings}")
PYEOF
}

# ---------------------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
  say "uninstalling from $PREFIX"
  merge_settings uninstall
  remove_tree hooks
  # Bytecode caches and the now-empty lib/ are ours, and leaving them behind
  # makes a second install look like a partial one.
  if [ "$DRY" -eq 0 ] && [ -d "$PREFIX/hooks" ]; then
    find "$PREFIX/hooks" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
    find "$PREFIX/hooks" -type d -empty -delete 2>/dev/null || true
  fi
  say "rules/ left in place: they are yours to keep or delete by hand"
  exit 0
fi

say "installing into $PREFIX"
copy_tree hooks
copy_tree rules
merge_settings install

if [ "$DRY" -eq 0 ]; then
  echo
  bash "$REPO/doctor.sh" --prefix "$PREFIX" || true
fi
