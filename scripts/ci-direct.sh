#!/bin/bash
# The ci.yml jobs, run on this machine. `ci-lane run` calls this when GitHub
# Actions cannot start jobs (billing block, 15 September 2026). The macOS leg
# of the matrix runs for real here; the Ubuntu leg cannot, and says so.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== suite (macOS leg; the Ubuntu leg needs Actions)"
bash tests/run.sh

echo "== shellcheck"
SHELLCHECK=$(command -v shellcheck || true)
[[ -z "$SHELLCHECK" && -x "$HOME/.venvs/agent-libs/bin/shellcheck" ]] && SHELLCHECK="$HOME/.venvs/agent-libs/bin/shellcheck"
if [[ -n "$SHELLCHECK" ]]; then
  "$SHELLCHECK" --severity=warning -e SC1090,SC1091,SC2016 \
    hooks/*.sh install.sh doctor.sh tests/run.sh
else
  echo "shellcheck not installed; pip install shellcheck-py into ~/.venvs/agent-libs" >&2
  exit 1
fi

echo "== install smoke into a scratch prefix"
PREFIX="$(mktemp -d)/claude"
./install.sh --prefix "$PREFIX"
./doctor.sh --prefix "$PREFIX" -v
./install.sh --prefix "$PREFIX"
python3 - "$PREFIX/settings.json" <<'PY'
import json, sys, collections
data = json.load(open(sys.argv[1]))
cmds = [h["command"]
        for groups in data["hooks"].values()
        for g in groups for h in g.get("hooks", [])]
dupes = [c for c, n in collections.Counter(cmds).items() if n > 1]
if dupes:
    print("duplicate registrations after a second install:", dupes)
    sys.exit(1)
print(f"{len(cmds)} registrations, no duplicates")
PY
rm -rf "$(dirname "$PREFIX")"

echo "ci-direct: all checks passed"
