#!/usr/bin/env python3
"""dead-branch-sweep - is every regex in every hook actually load-bearing?

negative-control.py proves a guard can refuse. The suite's syntax and parity
sections prove the repo agrees with itself. None of them can see a rule whose
regex has quietly stopped mattering, because a self-test that never exercises a
branch stays green when that branch dies.

So this sweeps the hooks the only way that settles it: corrupt one regex at a
time so it can never match, re-run that hook's own self-test, and report every
regex the test did not miss.

WHY IT IS WORTH A FILE. Run against the private tree this was built from, the
first sweep found 31 dead regexes across the hooks and the surrounding CLI. Some
sat inside BLOCKING rules, so those rules could have stopped enforcing while the
suite still reported PASS. Three were not merely untested but unreachable: an
exemption applied only to sentences another regex had already matched, where the
two word lists were disjoint, so it could never exempt anything. It had been
reading as coverage in every audit for months.

DIRECTION MATTERS, and it is why one arm shape does not cover a rule. A dead
DETECTOR under-blocks: the rule silently stops firing. A dead EXEMPTION
over-blocks, which is worse, because an over-blocking guard gets bypassed or
deleted rather than obeyed. Both need an arm, and they are different arms.

This is the mirror of the rule negative-control.py already encodes. A gate that
always FAILS is a gate nobody reads. A gate that always PASSES is a gate nobody
notices, and that one is worse: it reports success while enforcing nothing.

Exit 1 if any regex can be corrupted with its hook's self-test still green.
Exit 0 when every regex is load-bearing.
"""
from __future__ import annotations

import ast
import os
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
HOOKS = REPO / "hooks"
TIMEOUT = 90
PY = os.environ.get("PYTHON", sys.executable)

# Regexes deliberately not covered, each as (filename, NAME) with the reason in
# a comment. Keep this SHORT and justified, or it becomes the hole the sweep
# exists to close.
EXEMPT: set[tuple[str, str]] = set()


def regex_names(src: str) -> list[str]:
    """Module-level `NAME = re.compile(...)` assignments, in source order."""
    return [n.targets[0].id for n in ast.parse(src).body
            if isinstance(n, ast.Assign)
            and isinstance(n.value, ast.Call)
            and getattr(n.value.func, "attr", "") == "compile"
            and getattr(getattr(n.value.func, "value", None), "id", "") == "re"
            and isinstance(n.targets[0], ast.Name)]


def corrupt(src: str, name: str) -> str | None:
    """Replace exactly one assignment with a regex that can never match.

    Uses AST line spans. A naive cut to the next blank line is what made the
    first version of this sweep wrong in BOTH directions: it deleted several
    regexes at once, so the test then failed for an unrelated reason and the
    branch was scored as covered, and it crashed outright on a regex containing
    a parenthesis inside a raw string.
    """
    lines = src.splitlines(True)
    for n in ast.parse(src).body:
        if (isinstance(n, ast.Assign)
                and isinstance(n.value, ast.Call)
                and getattr(n.value.func, "attr", "") == "compile"
                and isinstance(n.targets[0], ast.Name)
                and n.targets[0].id == name):
            lines[n.lineno - 1:n.end_lineno] = [
                '%s = re.compile(r"ZZZNEVERMATCHZZZ")\n' % name]
            return "".join(lines)
    return None


def sweep() -> int:
    dead: list[tuple[str, str]] = []
    total = 0
    for path in sorted(HOOKS.glob("*.py")):
        src = path.read_text(encoding="utf-8", errors="ignore")
        if "--self-test" not in src:
            continue
        try:
            names = regex_names(src)
        except SyntaxError:
            continue                      # the syntax section owns that failure
        for name in names:
            if (path.name, name) in EXEMPT:
                continue
            broken = corrupt(src, name)
            if broken is None:
                continue
            total += 1
            tmp = None
            try:
                with tempfile.NamedTemporaryFile(
                        "w", suffix=".py", delete=False, encoding="utf-8") as fh:
                    fh.write(broken)
                    tmp = fh.name
                rc = subprocess.run([PY, tmp, "--self-test"],
                                    capture_output=True, text=True,
                                    timeout=TIMEOUT).returncode
            except Exception:
                rc = -9                   # a crash is not a pass
            finally:
                if tmp:
                    os.unlink(tmp)
            if rc == 0:
                dead.append((path.name, name))
    print("dead-branch-sweep: %d regex(es) checked" % total)
    if dead:
        print("  %d regex(es) can be corrupted with the self-test still GREEN:"
              % len(dead))
        for f, n in dead:
            print("     %-28s %s   <- untested branch, counted as coverage" % (f, n))
        print("  Add an arm that DIES when this regex dies. For a detector that")
        print("  means a case it alone catches; for an exemption, a case that")
        print("  stays clean only because it matches.")
        return 1
    print("  ok: every regex is load-bearing in its hook's self-test")
    return 0


def self_test() -> int:
    """The sweep must be able to FIND a dead branch, not just report none.

    Builds a throwaway hook with one covered regex and one uncovered one, and
    asserts the sweep flags exactly the uncovered one. Without this, a sweep
    that silently matched nothing would print a clean bill of health forever,
    which is the exact failure the tool exists to detect.
    """
    fake = (
        "# --self-test\n"
        "import re, sys\n"
        'LIVE = re.compile(r"alpha")\n'
        'UNTESTED = re.compile(r"beta")\n'
        "def _self_test():\n"
        '    return 0 if LIVE.search("alpha") else 1\n'
        'if __name__ == "__main__":\n'
        '    sys.exit(_self_test())\n'
    )
    d = tempfile.mkdtemp(prefix="dbs-selftest-")
    try:
        p = os.path.join(d, "fake-hook.py")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(fake)
        src = open(p, encoding="utf-8").read()
        names = regex_names(src)
        if names != ["LIVE", "UNTESTED"]:
            print("FAIL: regex_names returned %r" % names)
            return 1
        found = []
        for name in names:
            q = os.path.join(d, "broken.py")
            with open(q, "w", encoding="utf-8") as fh:
                fh.write(corrupt(src, name) or "")
            if subprocess.run([PY, q, "--self-test"],
                              capture_output=True).returncode == 0:
                found.append(name)
        if found != ["UNTESTED"]:
            print("FAIL: expected ['UNTESTED'], got %r" % found)
            return 1
        print("dead-branch-sweep self-test: PASS")
        return 0
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else sweep())
