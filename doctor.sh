#!/usr/bin/env bash
# doctor.sh - report whether the guards are actually armed.
#
# "Installed" and "armed" are different claims and only the second one matters.
# A hook can be on disk, executable, mentioned in the README and registered
# nowhere, and the way you find out is that it never fires. That failure is
# invisible by construction: a guard that never runs looks exactly like a guard
# that never had to.
#
# So this checks four things per hook, in the order they can go wrong:
#   1. the file is there
#   2. it is executable, and its interpreter exists
#   3. settings.json registers it, under the right event and matcher
#   4. it responds to a payload at all, rather than dying on line one
#
# Exit 0 = every hook in the manifest is armed. Exit 1 = at least one is not.
# Warnings alone do not fail the run; a missing registration does.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${HSTACK_PREFIX:-$HOME/.claude}"
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)  PREFIX="${2:-}"; shift ;;
    -v|--verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "doctor.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  echo "doctor: python3 not found. Four hooks are python and the merge needs it." >&2
  exit 69
fi

"$PY" - "$REPO/hooks.manifest.json" "$PREFIX" "$VERBOSE" <<'PYEOF'
import json, os, shutil, subprocess, sys
from pathlib import Path

manifest, prefix, verbose = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
prefix = Path(prefix)
spec = json.loads(Path(manifest).read_text())["hooks"]

settings_path = prefix / "settings.json"
registered = set()
if settings_path.exists():
    try:
        s = json.loads(settings_path.read_text() or "{}")
    except json.JSONDecodeError as e:
        print(f"doctor: {settings_path} is not valid JSON: {e}")
        sys.exit(1)
    for event, groups in (s.get("hooks") or {}).items():
        for g in groups or []:
            for h in g.get("hooks") or []:
                cmd = h.get("command", "")
                registered.add((event, Path(cmd.split()[-1]).name if cmd else ""))

PAYLOAD = json.dumps({"tool_name": "Bash", "tool_input": {"command": "true"},
                      "prompt": "ok", "cwd": str(Path.cwd())})

armed = broken = 0
lines = []
for h in spec:
    name, event = h["file"], h["event"]
    path = prefix / "hooks" / name
    problems = []

    if not path.exists():
        problems.append("not installed")
    else:
        if not os.access(path, os.X_OK):
            problems.append("not executable")
        runner = h["runner"]
        if not shutil.which(runner):
            problems.append(f"{runner} not on PATH")

    if (event, name) not in registered:
        problems.append(f"not registered for {event}")

    # Liveness. A hook that dies on an ordinary payload is worse than absent:
    # depending on the event it either blocks every call or logs a traceback
    # into every session. Exit 2 here is a REFUSAL and therefore healthy.
    if not problems:
        try:
            p = subprocess.run([h["runner"], str(path)], input=PAYLOAD,
                               capture_output=True, text=True, timeout=20)
            if p.returncode not in (0, 2) and "Traceback" in (p.stderr or ""):
                problems.append(f"crashes on a plain payload (rc={p.returncode})")
        except subprocess.TimeoutExpired:
            problems.append("hangs on a plain payload")
        except OSError as e:
            problems.append(f"cannot run: {e}")

    if problems:
        broken += 1
        lines.append(f"  BROKEN  {name:<24} {event:<16} {'; '.join(problems)}")
    else:
        armed += 1
        if verbose:
            lines.append(f"  armed   {name:<24} {event:<16} refuses: {h['refuses'][:60]}")

# Anything registered under a hooks/ path that the manifest does not know is
# surfaced, never removed. It is probably yours; it is occasionally something
# that landed from elsewhere, and the hooks block runs before every tool call.
known = {h["file"] for h in spec}
foreign = sorted({n for _, n in registered if n and n not in known})

print(f"doctor: {armed} armed, {broken} not armed, prefix {prefix}")
for line in lines:
    print(line)
if foreign:
    print(f"doctor: {len(foreign)} registered hook(s) hstack does not own: {', '.join(foreign)}")
if broken:
    print("doctor: run ./install.sh to register what is missing")
sys.exit(1 if broken else 0)
PYEOF
