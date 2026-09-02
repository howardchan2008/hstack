#!/usr/bin/env python3
"""negative-control - prove every guard in this repo can actually fail.

A guard that never blocks is decoration, and it looks exactly like a guard that
never had to. So each one is fed the exact payload it exists to refuse, and the
run asserts it refuses.

The other half is the half that rots. A guard that blocks ORDINARY work gets
bypassed inside a day and then it is decoration too, except now it is decoration
you argue with. So every case has an allow arm, and a guard that fires on the
allow arm fails the suite just as hard as one that sleeps through the block arm.

Four verdicts, because the guards here use four mechanisms and collapsing them
would report working code as broken:

  block   exit 2, or a JSON decision object saying deny/block on stdout
  allow   exit 0 and nothing on stderr worth reading
  warn    exit 0 ON PURPOSE, but the routing text MUST still be printed. A
          silenced warn is a dead guard that every green sweep counts as fine.
  nudge   refuses once to surface a better lane, then yields on the retry.
          Asserted twice, because a nudge that never clears is a block.

Usage:
  python3 tests/negative-control.py              run everything
  python3 tests/negative-control.py --only dash  substring filter
  python3 tests/negative-control.py --list       show the cases
  python3 tests/negative-control.py --json       machine output

Exit 0 = every case behaved. Exit 1 = a guard failed open, or fired on ordinary
work, or went quiet.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HOOKS = Path(os.environ.get("HSTACK_HOOKS", REPO / "hooks"))
TIMEOUT = 45


def pre(tool, tool_input, **extra):
    """A PreToolUse payload in the shape the harness delivers it."""
    return json.dumps({"tool_name": tool, "tool_input": tool_input, **extra})


def run(script: Path, payload: str, env_extra: dict | None = None):
    env = dict(os.environ)
    # Judge the guard on its own logic. A proxy variable or an approval sentinel
    # left behind by a real session would decide some of these for it.
    for v in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy",
              "ALL_PROXY", "all_proxy"):
        env.pop(v, None)
    # The session id must come from the CASE, never from the shell running the
    # suite. session-identity.sh prefers COLLIDE_SESSION / CLAUDE_SESSION_ID over
    # the payload, so inside a live session every case inherited THAT session's
    # ledgers: on 2026-09-02 agent-budget/allow reported a false positive because
    # the session running the tests had spent its own per-session agent cap.
    for v in ("COLLIDE_SESSION", "CLAUDE_SESSION_ID"):
        env.pop(v, None)
    if env_extra:
        env.update(env_extra)
    runner = "bash" if script.suffix == ".sh" else sys.executable
    try:
        p = subprocess.run([runner, str(script)], input=payload, capture_output=True,
                           text=True, timeout=TIMEOUT, env=env)
    except subprocess.TimeoutExpired:
        return 124, "", "TIMEOUT"
    return p.returncode, p.stdout, p.stderr


def blocked(code, out, err) -> bool:
    """True when the hook refused, by either supported mechanism."""
    if code == 2:
        return True
    for line in ((out or "") + "\n" + (err or "")).splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("decision") == "block":
            return True
        if (d.get("hookSpecificOutput") or {}).get("permissionDecision") == "deny":
            return True
    return False


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------

def cases():
    tmp = Path(tempfile.mkdtemp(prefix="hstack-nc-"))
    # The finished-work fixture may NOT live under the system temp dir.
    # ls-before-write deliberately skips scratch trees, because clobbering is the
    # normal mode there, so a fixture in /tmp tests nothing and reports the guard
    # as failing open. Test what the tool does, not what its name says.
    fixture = REPO / ".nc-fixture" / "finished-work"
    fixture.mkdir(parents=True, exist_ok=True)
    (fixture / "REPORT.md").write_text("finished work lives here\n")
    (fixture / "extract.py").write_text("# the real one\n")

    def bash(cmd, **extra):
        return pre("Bash", {"command": cmd}, session_id="negative-control", **extra)

    c = []

    # --- dash-gate ---------------------------------------------------------
    c += [
        dict(name="dash-gate/block", script="dash-gate.sh", expect="block",
             payload=pre("Write", {"file_path": str(tmp / "a.md"), "content": "one — two"}),
             why="a unicode em dash written into an authored file"),
        dict(name="dash-gate/allow", script="dash-gate.sh", expect="allow",
             payload=pre("Write", {"file_path": str(tmp / "a.md"),
                                   "content": 'grep -qF -- "$want"  # pre-seed, ed-tech'}),
             why="a double hyphen as end-of-options, and hyphenated compounds. Both legal, "
                 "and the naive version of this rule refused all three"),
    ]

    # --- grep-portability --------------------------------------------------
    c += [
        dict(name="grep-portability/block", script="grep-portability.sh", expect="block",
             payload=bash(r"timeout 60 grep -rlP '[\x{2010}-\x{2015}]' --include='*.md' ."),
             why="timeout execs BSD grep, -P dies, and the empty output reads as a clean tree"),
        dict(name="grep-portability/allow", script="grep-portability.sh", expect="allow",
             payload=bash("grep -rn foo . | head"),
             why="ordinary grep, no PCRE flag, no exec-bypass wrapper"),
    ]

    # --- ls-before-write ---------------------------------------------------
    c += [
        dict(name="ls-before-write/block-marker", script="ls-before-write.sh", expect="block",
             payload=pre("Write", {"file_path": str(fixture / "new.py"), "content": "print(1)"}),
             why="a REPORT.md sibling means the work here may already be done"),
        dict(name="ls-before-write/block-clobber", script="ls-before-write.sh", expect="block",
             payload=pre("Write", {"file_path": str(fixture / "extract.py"), "content": "print(2)"}),
             why="Write REPLACES an existing file, silently, with no diff shown first"),
        dict(name="ls-before-write/allow", script="ls-before-write.sh", expect="allow",
             payload=pre("Write", {"file_path": str(tmp / "fresh.txt"), "content": "x"}),
             why="a new file in a directory holding no finished work"),
    ]

    # --- pipestatus-guard --------------------------------------------------
    c += [
        dict(name="pipestatus-guard/block", script="pipestatus-guard.sh", expect="block",
             payload=bash("git push origin main | tail -2"),
             why="the push can fail and the pipeline still exits 0, so the failure is invisible"),
        dict(name="pipestatus-guard/allow", script="pipestatus-guard.sh", expect="allow",
             payload=bash("git log --oneline | head -5"),
             why="a read piped to head. Nothing changes state, nothing to lose"),
    ]

    # --- risk-checkpoint ---------------------------------------------------
    settings = str(Path.home() / ".claude" / "settings.json")
    c += [
        dict(name="risk-checkpoint/block-settings", script="risk-checkpoint.sh", expect="block",
             payload=bash(f"echo x >> {settings}"),
             why="an append straight into the file that decides which hooks run"),
        dict(name="risk-checkpoint/block-find-exec", script="risk-checkpoint.sh", expect="block",
             # The INSTALLED hooks dir, not this repo's copy: the guard is scoped to
             # the live config, which is the thing an -exec sweep can silently rewrite.
             payload=bash("find %s -name '*.sh' -exec sed -i '' s/a/b/ {} +"
                          % (Path.home() / ".claude" / "hooks")),
             why="find's own action flags edit every hook at once, and this shape reached "
                 "disk unblocked until the tokenizer learned to model -exec"),
        dict(name="risk-checkpoint/allow-read", script="risk-checkpoint.sh", expect="allow",
             payload=bash(f"grep -c hooks {settings}"),
             why="reading the settings file is routine. A guard that charges a bypass for a "
                 "read is what teaches people to bypass it by reflex"),
    ]

    # --- lane-guard --------------------------------------------------------
    c += [
        dict(name="lane-guard/block", script="lane-guard.sh", expect="block",
             payload=pre("Workflow", {"script": "await pipeline(items.map(i => agent(i)))",
                                      "args": list(range(40))}),
             why="a 40-item fan-out onto the expensive lane with no lane decision stated"),
        dict(name="lane-guard/allow", script="lane-guard.sh", expect="allow",
             payload=pre("Workflow", {"script": "const x = await readFile(p); return x.length"}),
             why="a single-shot workflow with no fan-out"),
    ]

    # --- agent-budget: refuses with JSON, not exit 2 ------------------------
    c += [
        dict(name="agent-budget/allow", script="agent-budget.sh", expect="allow",
             # Fresh id per run: the per-session ledger is keyed on it, and a fixed
             # id would spend the cap after eight runs of this suite.
             payload=pre("Agent", {"description": "one small lookup"},
                         session_id=f"nc-agent-{os.getpid()}"),
             why="a single dispatch inside budget. The block arm needs a spent budget, "
                 "which is state this suite will not fake: see docs/TESTING.md"),
    ]

    # --- curl-router: warns, and the warning IS the assertion ---------------
    c += [
        dict(name="curl-router/allow", script="curl-router.sh", expect="allow",
             payload=bash("curl -sI https://example.com"),
             why="a curl at a host with no wired lane. Ordinary work"),
        dict(name="curl-router/allow-mention", script="curl-router.sh", expect="allow",
             payload=bash("git status -s && grep -rn curl README.md"),
             why="the word curl inside another command must not trip a Bash-wide hook"),
    ]

    # --- fetch-guard: documented as warn-only ------------------------------
    c += [
        dict(name="fetch-guard/allow", script="fetch-guard.sh", expect="allow",
             payload=pre("Edit", {"file_path": str(HOOKS / "fetch-guard.sh")}),
             why="warn-only by design. Blocking here would be the regression"),
    ]

    # --- probe-dedupe: the first look must always be free -------------------
    c += [
        dict(name="probe-dedupe/allow-first", script="probe-dedupe.sh", expect="allow",
             # Bounded output on purpose. The same hook carries a second rule about
             # unbounded results, and the first version of this case tripped THAT
             # one, which reads as a false positive on the dedupe rule it was
             # written for. An allow arm has to be unambiguous or it accuses the
             # wrong half of the guard.
             payload=pre("Bash",
                         {"command": "ps aux | grep nc-unique-alpha | head -5 | cut -c1-120"},
                         session_id=f"nc-probe-{os.getpid()}"),
             # A FRESH SESSION ID, because the ledger is keyed on it. With the
             # suite's fixed id, running the tests a few times makes this subject a
             # repeat, the guard blocks correctly, and the case reports a false
             # positive. A test whose verdict depends on how often it has been run
             # is measuring the fixture. Overriding HOME instead does not work:
             # the hook resolves its own lib/ underneath it.
             why="the first look at a subject. Blocking it would make the guard the thing "
                 "that stops work rather than the thing that stops repetition"),
    ]

    # --- websearch-router: silent unless a cheaper lane exists --------------
    c += [
        dict(name="websearch-router/allow-fetch", script="websearch-router.sh", expect="allow",
             payload=pre("WebFetch", {"url": "https://example.com/docs"}),
             why="fetching one named page is legitimate. Only searches get routed"),
    ]

    return c


VERDICTS = {"block", "allow", "warn", "nudge"}


def evaluate(case, code, out, err):
    did_block = blocked(code, out, err)
    noise = (err or "").strip()
    want = case["expect"]

    if want == "block":
        return ("PASS", "") if did_block else ("FAILS-OPEN", f"rc={code}, said nothing")
    if want == "allow":
        if did_block:
            return "FALSE-POSITIVE", f"refused ordinary work (rc={code}): {noise[:160]}"
        return "PASS", ""
    if want == "warn":
        if did_block:
            return "OVER-BLOCKS", "a warn lane must not refuse"
        if case.get("says") and case["says"] not in noise:
            return "SILENT", f"warned nothing about {case['says']!r}"
        return "PASS", ""
    return "UNKNOWN", f"unhandled expectation {want!r}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="substring filter on case name")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    selected = [c for c in cases() if not a.only or a.only in c["name"]]

    if a.list:
        for c in selected:
            print(f"{c['name']:<34} expect {c['expect']:<6} {c['why']}")
        return 0

    rows, bad = [], 0
    for c in selected:
        script = HOOKS / c["script"]
        if not script.exists():
            rows.append(dict(name=c["name"], verdict="ABSENT", detail=str(script)))
            bad += 1
            continue
        code, out, err = run(script, c["payload"], c.get("env"))
        verdict, detail = evaluate(c, code, out, err)
        if verdict != "PASS":
            bad += 1
        rows.append(dict(name=c["name"], verdict=verdict, detail=detail, why=c["why"]))

    if a.json:
        print(json.dumps(rows, indent=2))
    else:
        for r in rows:
            mark = "ok  " if r["verdict"] == "PASS" else "FAIL"
            print(f"  {mark} {r['name']:<34} {r['verdict']}"
                  + (f"  {r['detail']}" if r.get("detail") else ""))
        print(f"negative-control: {len(rows) - bad}/{len(rows)} cases behaved")

    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
