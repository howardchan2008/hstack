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
import ast
import collections
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

    # 6. PER-EVENT counts in prose must be the real ones too.
    #
    # Added 2026-08-29. Rule 5 above checks the TOTAL, and the total was right
    # while the breakdown in docs/ARCHITECTURE.md had been wrong for months:
    # the diagram claimed 5 UserPromptSubmit (6), 12 PreToolUse of which 9
    # refuse (18, of which 15), and 3 Stop of which 2 refuse (8, of which 6).
    # Three of four numbers wrong, in the first diagram a reader sees, with the
    # whole suite green. A number nobody re-derives is the prose form of a
    # regex nobody exercises: it reads as fact and nothing notices it rot.
    per_event = collections.Counter(h["event"] for h in hooks)
    refusing = collections.Counter(
        h["event"] for h in hooks
        if str(h.get("block", "none")).lower() not in ("none", "", "no"))
    EVENTS = set(per_event)

    for doc in (REPO / "docs" / "ARCHITECTURE.md", README):
        if not doc.exists():
            continue
        rel, text = doc.name, doc.read_text()

        # "SessionStart (4 hooks)" and the README's "18 `PreToolUse`"
        for ev, n in re.findall(r"\b(\w+)\s*\((\d+)\s+hooks?\)", text):
            if ev in EVENTS and int(n) != per_event[ev]:
                fails.append(f"{rel} says {ev} has {n} hooks; the manifest has {per_event[ev]}")
        for n, ev in re.findall(r"\b(\d+)\s+`?(\w+)`?", text):
            if ev in EVENTS and int(n) != per_event[ev]:
                fails.append(f"{rel} says {n} {ev}; the manifest has {per_event[ev]}")

        # The diagram: an event name, then "N hooks, M of them refuse" below it.
        current = None
        for line in text.splitlines():
            for ev in EVENTS:
                if re.search(rf"\b{ev}\b", line):
                    current = ev
            m = re.search(r"(\d+)\s+hooks?,\s+(none|\d+)\s+of them\s+(?:refuse|block)", line)
            if not m or not current:
                continue
            n = int(m.group(1))
            want_r = refusing[current]
            got_r = 0 if m.group(2) == "none" else int(m.group(2))
            if n != per_event[current]:
                fails.append(f"{rel} diagram says {current} has {n} hooks; "
                             f"the manifest has {per_event[current]}")
            if got_r != want_r:
                fails.append(f"{rel} diagram says {got_r} of {current} refuse; "
                             f"the manifest has {want_r}")

    # 7. the manifest's `block` column must match how the hook actually refuses.
    #
    # Added 2026-08-29, after closeout-shape.py was found never to have blocked
    # anything. The manifest said block: json for it and for item-coverage.py.
    # item-coverage emitted {"decision": "block"} and exited 0. closeout-shape
    # printed plain text and exited 1, which on a Stop hook is a NON-BLOCKING
    # error, so seven rules marked blocking had refused exactly nothing. The
    # contract was written down in this very file and nothing compared the two.
    #
    # Deliberately shallow: it asks whether the mechanism is PRESENT, not
    # whether it fires. negative-control.py owns whether it fires, and it can
    # only ask that of guards whose mechanism exists in the first place.
    # Written narrow first, and the first draft accused three WORKING guards.
    # That is the cry-wolf failure this suite exists to avoid, so the real
    # mechanisms are enumerated rather than assumed:
    #   - Stop hooks answer with {"decision": "block"}
    #   - PreToolUse hooks answer with hookSpecificOutput.permissionDecision
    #   - a shell hook may DELEGATE, piping stdin into a lib/ script, in which
    #     case the mechanism lives there (probe-dedupe.sh is two lines long)
    # The one real finding it kept: outbound-copy-gate.py was recorded as
    # block=json and refuses by exit 2. The code was right, the manifest was
    # wrong, and the manifest is what every reader trusts.
    JSON_BLOCK = re.compile(r'"decision"|permissionDecision')
    EXIT2 = re.compile(r"exit\s+2\b|sys\.exit\(2\)|return 2\b")

    def code_of(path: Path) -> str:
        """Source with comment lines removed.

        The first version grepped raw text and could not fail: deleting the
        real `"decision"` object from a hook left the WORD in the comment above
        it, and the check stayed green against the exact bug it was written
        for. A checker that matches prose is measuring documentation.
        """
        return "\n".join(ln for ln in path.read_text(errors="ignore").splitlines()
                         if not ln.lstrip().startswith("#"))

    def mechanism_text(path: Path) -> str:
        """A shell hook may delegate; follow the delegation, by NAME not guess.

        probe-dedupe.sh is two lines and pipes stdin into a lib script, so its
        refusal lives there. Resolved from the actual assignment in the file. A
        glob on the hook's own stem was the first attempt and it also could not
        fail, because it found the lib again even when the hook stopped
        pointing at it.
        """
        body = code_of(path)
        for lib in re.findall(r'lib/([\w.-]+\.py)', body):
            q = REPO / "hooks" / "lib" / lib
            if q.is_file():
                body += "\n" + code_of(q)
        return body

    for h in hooks:
        p = REPO / "hooks" / h["file"]
        if not p.is_file():
            continue
        body = mechanism_text(p)
        blk = str(h.get("block", "none")).lower()
        emits_json = bool(JSON_BLOCK.search(body))
        if p.suffix == ".py":
            # A TEXT match cannot tell emitting from referencing. This file's own
            # protocol arms read obj.get("decision"), which kept the check green
            # against the exact bug it was written for. A dict LITERAL with that
            # key is an answer being built; a .get() is a test reading one.
            try:
                emits_json = any(
                    isinstance(k, ast.Constant)
                    and k.value in ("decision", "permissionDecision", "hookSpecificOutput")
                    for node in ast.walk(ast.parse(p.read_text(errors="ignore")))
                    if isinstance(node, ast.Dict)
                    for k in node.keys)
            except SyntaxError:
                pass                              # the syntax stage owns that
        if blk == "json" and not emits_json:
            fails.append(f"{h['file']} is manifest block=json but emits no decision "
                         f"object, so it cannot refuse")
        if blk == "exit2" and not EXIT2.search(body):
            fails.append(f"{h['file']} is manifest block=exit2 but never exits 2, "
                         f"so it cannot refuse")

    for f in fails:
        print(f"  FAIL {f}")
    print(f"parity: {len(hooks)} hooks, {len(fails)} disagreement(s)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
