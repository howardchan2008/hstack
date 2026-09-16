#!/usr/bin/env python3
"""long-run-gate: no polling loop without a measured ETA, no paid GPU job without a smoke run.

Howard, 2026-09-16: "u wasted so many turns coz u didnt time the run properly, ship a fix so
this cant ever happen again". Measured that day: a 105-minute local run and a 5-hour cloud
run were watched with 55-minute Bash loops, eleven watcher turns that reported "still
running"; and six Vertex jobs failed one config error at a time (image tag, library
version, torch floor, torchvision ABI, renamed argument, eval memory), each costing a
10-minute round trip that a CPU dry run would have caught in one.

PreToolUse:Bash. Two rules, both fail closed:

1. A wait loop (`while`/`until` ... `sleep N`) must carry `JOB_ETA=<seconds>` in the
   command text, the estimate from a measured rate (steps done / seconds elapsed). Above
   3300 s the loop is refused outright: the harness caps a background call at an hour,
   so a longer wait is a guaranteed empty turn. The lane for that is
   `jobq add --lane local --deadline <eta+slack> -- <poll command>`: the drainer runs it
   with no cap and the result is injected into the next prompt by carryover-queue.py.

2. A paid GPU submission (`gcloud ai custom-jobs create`, `sky launch`, `modal run`,
   `az ml job create`, `aws sagemaker create-training-job`) must carry `SMOKE_OK=1` and
   a smoke marker `~/.claude/state/smoke-ok` younger than two hours, written only by a
   dry run of the same trainer on CPU (`cloud/smoke.sh` in the merit repo is the model).

Self-test: `python3 long-run-gate.py --self-test`.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

LOOP_RE = re.compile(r"\b(while|until)\b[^\n]*?\bsleep\s+\d+", re.S)
ETA_RE = re.compile(r"\bJOB_ETA=(\d+)\b")
JOBQ_RE = re.compile(r"\bjobq\s+add\b")
CAP = 3300
GPU_SUBMIT_RE = re.compile(
    r"gcloud\s+(?:alpha\s+|beta\s+)?ai\s+custom-jobs\s+create|\bsky\s+launch\b|\bmodal\s+run\b|"
    r"\baz\s+ml\s+job\s+create\b|\baws\s+sagemaker\s+create-training-job\b"
)
SMOKE_MARK = Path(os.environ.get("LONG_RUN_SMOKE_MARK", str(Path.home() / ".claude/state/smoke-ok")))
SMOKE_MAX_AGE = 2 * 3600


def check(cmd: str, now: float | None = None) -> str | None:
    """Return a refusal message, or None to allow."""
    now = now or time.time()
    if JOBQ_RE.search(cmd):
        return None  # the jobq lane is the sanctioned home for a long wait; its drainer has no hour cap
    if LOOP_RE.search(cmd):
        m = ETA_RE.search(cmd)
        if not m:
            return (
                "LONG-RUN GATE: a wait loop needs a measured ETA. Add JOB_ETA=<seconds> to the command, "
                "from a measured rate (units done / seconds elapsed x units left), not a guess. "
                f"If it is over {CAP} s, do not loop: `jobq add --lane local --deadline <eta+slack> -- <poll cmd>` "
                "and the result reaches the next prompt through the inbox."
            )
        eta = int(m.group(1))
        if eta > CAP:
            return (
                f"LONG-RUN GATE: JOB_ETA={eta} s is over the {CAP} s background cap; this loop would time out and "
                "produce an empty turn. Route it: `jobq add --lane local --deadline "
                f"{eta + 1800} -- bash -c '<poll until done; print summary>'`, then stop waiting."
            )
    if GPU_SUBMIT_RE.search(cmd):
        if "SMOKE_OK=1" not in cmd:
            return (
                "LONG-RUN GATE: a paid GPU job needs a CPU dry run first. Run the trainer's smoke script "
                "(imports, config, TrainingArguments, model class, on CPU with the same pins), which writes "
                f"{SMOKE_MARK}, then resubmit with SMOKE_OK=1 in the command."
            )
        if not SMOKE_MARK.exists() or now - SMOKE_MARK.stat().st_mtime > SMOKE_MAX_AGE:
            return (
                f"LONG-RUN GATE: SMOKE_OK=1 claimed but {SMOKE_MARK} is missing or older than two hours. "
                "Run the smoke script again; the marker must come from the dry run, not from touch."
            )
    return None


def self_test() -> int:
    tmp = Path("/tmp/long-run-gate-smoke-test")
    global SMOKE_MARK
    SMOKE_MARK = tmp
    if tmp.exists():
        tmp.unlink()
    cases = [
        ("while :; do sleep 60; done", None, True),
        ("JOB_ETA=1200; while :; do sleep 60; done", None, False),
        ("JOB_ETA=18000; until grep -q DONE log; do sleep 300; done", None, True),
        ("ls; git status", None, False),
        ("jobq add --lane local --deadline 21600 -- bash -c 'until done; do sleep 600; done'", None, False),
        ("gcloud ai custom-jobs create --region=x --config=y", None, True),
        ("SMOKE_OK=1 gcloud ai custom-jobs create --region=x --config=y", None, True),  # no marker
    ]
    fails = 0
    for cmd, _, want_refuse in cases:
        got = check(cmd) is not None
        ok = got == want_refuse
        fails += not ok
        print(("ok  " if ok else "FAIL"), "refuse" if got else "allow ", cmd[:60])
    tmp.write_text("smoke")
    got = check("SMOKE_OK=1 gcloud ai custom-jobs create --region=x --config=y") is not None
    print(("ok  " if not got else "FAIL"), "allow  fresh marker + SMOKE_OK=1")
    fails += got
    old = time.time() - 3 * 3600
    os.utime(tmp, (old, old))
    got = check("SMOKE_OK=1 gcloud ai custom-jobs create --region=x --config=y") is not None
    print(("ok  " if got else "FAIL"), "refuse stale marker")
    fails += not got
    tmp.unlink()
    print("self-test", "PASS" if not fails else f"FAIL ({fails})")
    return 1 if fails else 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if payload.get("tool_name") != "Bash":
        return 0
    cmd = str(payload.get("tool_input", {}).get("command", ""))
    msg = check(cmd)
    if msg:
        print(msg, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
