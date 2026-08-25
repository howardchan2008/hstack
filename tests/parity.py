#!/usr/bin/env python3
"""parity - assert the repo agrees with itself.

Every count in this repo is written down in more than one place: the hooks on
disk, the manifest that wires them, the example settings, the roster inside
wiring-verify.sh, the table in the docs, the number in the README. Six copies of
one fact drift, and the drift is silent, because each file is individually
correct and nothing reads two of them at once.

That is not hypothetical here. The first published version shipped two hooks
whose logic files were left behind, a checker that demanded fifteen hooks the
repo does not contain, and a README describing a set that no longer matched the
directory. All three were the same defect: a fact stored twice, updated once.

So the manifest is the source of truth and this asserts the rest against it.

  python3 tests/parity.py            check, exit 1 on any drift
  python3 tests/parity.py --write    regenerate what is generated, then check
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "hooks.manifest.json"
EXAMPLE = REPO / "settings.example.json"
ROSTER = REPO / "hooks" / "wiring-verify.sh"
DOCS = REPO / "docs" / "HOOKS.md"
README = REPO / "README.md"


def spec() -> list[dict]:
    return json.loads(MANIFEST.read_text())["hooks"]


def build_settings(hooks: list[dict]) -> dict:
    """The example settings, derived rather than maintained by hand."""
    events: dict[str, list] = {}
    for h in hooks:
        groups = events.setdefault(h["event"], [])
        target = None
        for g in groups:
            if g.get("matcher") == h["matcher"] or (h["matcher"] is None and "matcher" not in g):
                target = g
                break
        if target is None:
            target = {} if h["matcher"] is None else {"matcher": h["matcher"]}
            target["hooks"] = []
            groups.append(target)
        target["hooks"].append(
            {"type": "command", "command": f'{h["runner"]} $HOME/.claude/hooks/{h["file"]}'})
    return {"hooks": events}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="regenerate settings.example.json")
    a = ap.parse_args()

    hooks = spec()
    named = {h["file"] for h in hooks}
    fails: list[str] = []

    # 1. manifest against the directory, both directions
    on_disk = {p.name for p in (REPO / "hooks").iterdir()
               if p.is_file() and p.suffix in (".sh", ".py")}
    for extra in sorted(on_disk - named):
        fails.append(f"hooks/{extra} is on disk and not in hooks.manifest.json, "
                     f"so nothing installs or tests it")
    for missing in sorted(named - on_disk):
        fails.append(f"hooks.manifest.json names {missing}, which is not in hooks/")

    # 2. the example settings must be exactly what install.sh would write
    want = build_settings(hooks)
    if a.write:
        EXAMPLE.write_text(json.dumps(want, indent=2) + "\n")
    have = json.loads(EXAMPLE.read_text()) if EXAMPLE.exists() else {}
    if have != want:
        fails.append("settings.example.json does not match the manifest "
                     "(run: python3 tests/parity.py --write)")

    # 3. the checker's roster. A hook missing here is reported as an unexplained
    #    addition at every session start, which is a false alarm that teaches the
    #    reader to skip the one line that will eventually matter.
    if ROSTER.exists():
        body = ROSTER.read_text()
        block = re.search(r"^KNOWN = \{(.*?)^\}", body, re.S | re.M)
        if not block:
            fails.append("wiring-verify.sh has no KNOWN roster to check")
        else:
            roster = set(re.findall(r'"([^"]+)"', block.group(1)))
            for m in sorted(named - roster):
                fails.append(f"wiring-verify.sh does not know about {m}")
            for x in sorted(roster - named):
                fails.append(f"wiring-verify.sh demands {x}, which this repo does not ship")

    # 4. every hook documented
    if DOCS.exists():
        doc = DOCS.read_text()
        for m in sorted(n for n in named if n not in doc):
            fails.append(f"docs/HOOKS.md does not document {m}")

    # 5. any hook count written in prose must be the real one
    if README.exists():
        for n in re.findall(r"\b(\w+)\s+hooks\b", README.read_text()):
            words = {"twelve": 12, "sixteen": 16, "twenty": 20, "twentyfive": 25,
                     "eighteen": 18, "fifteen": 15}
            n_int = int(n) if n.isdigit() else words.get(n.lower())
            if n_int is not None and n_int != len(hooks):
                fails.append(f"README says {n} hooks; the manifest has {len(hooks)}")

    for f in fails:
        print(f"  FAIL {f}")
    print(f"parity: {len(hooks)} hooks, {len(fails)} disagreement(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
