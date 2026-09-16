#!/usr/bin/env python3
"""probe-gate.py: a Stop hook that asks the owner's questions before the owner has to.

Howard, 2026-09-16: "u see what im consistently doing, im probing u, identifying
holes in ur story, so that u can fill the gaps and improve, why isnt it possible for
u to do this process urself within the harness an additional hook". This is that
hook. It runs on Stop. It finds strategy-shaped markdown the session wrote (pitch,
strategy, plan, deck, proposal, usp, positioning, gtm), asks a local model the fixed
question set below in the owner's register, and refuses the Stop until the file
carries a section answering them. Zero Claude tokens: the model is the local Ollama
lane (measured 2026-09-16: qwen3.8:27b-mlx, 2.4 s per question). If no local model
answers in time it fails OPEN and says so, because a silent block is worse than a
missed probe.

Wired as: "Stop": {"type": "command", "command": "/usr/bin/python3 ~/.claude/hooks/probe-gate.py"}
Env: PROBE_GATE_MODEL (default qwen3.8:27b-mlx), PROBE_GATE_OLLAMA (default http://localhost:11434),
     PROBE_GATE_WINDOW_MIN (default 240: only files modified this recently), PROBE_GATE_OFF=1 to disable.
Exit 0 = pass. Exit 2 = refuse with the questions on stderr (the harness shows them to the agent).
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

NAME_RE = re.compile(r"(pitch|strateg|plan|deck|proposal|usp|position|gtm|go-to-market|launch)", re.I)
SECTION = "## Holes the harness found"
ROOTS = [Path.home() / "repos", Path.home() / "Downloads", Path.home() / "code"]
SKIP_DIRS = {"node_modules", ".git", ".venv", "venv", "dist", "build", ".next", "__pycache__", ".codex-reviews"}

QUESTIONS = [
    "Who is this for, in one sentence a person who only uses ChatGPT would repeat back?",
    "Why would a stranger share this with a friend? Name the moment they would do it.",
    "Which words on the page are technical, and what is the plain word for each?",
    "What is being claimed that has not been shown to a single outside person?",
    "Who pays, how much, and by what date? If the answer is a category, say so.",
    "Where do the first hundred users come from, without ads and without cold outreach?",
    "Which lesson from the owner's earlier ventures does this repeat (build before buyer, supply before demand, automated reach with generic material)?",
]


def _files(window_min: int) -> list[Path]:
    cutoff = time.time() - window_min * 60
    out: list[Path] = []
    for root in ROOTS:
        if not root.exists():
            continue
        for p in root.rglob("*.md"):
            if any(part in SKIP_DIRS for part in p.parts):
                continue
            try:
                if p.stat().st_mtime < cutoff or not NAME_RE.search(p.name):
                    continue
            except OSError:
                continue
            out.append(p)
    return sorted(out, key=lambda p: p.stat().st_mtime, reverse=True)[:3]


def _ask(model: str, base: str, doc: str, question: str, timeout: int = 60) -> str | None:
    body = {
        "model": model, "stream": False, "think": False,
        "options": {"num_predict": 160, "temperature": 0.2},
        "messages": [
            {"role": "system", "content": "You are a hostile investor and a mainstream reader at once. Answer in at most two sentences, plain words, no preamble, no praise. If the document already answers the question, quote the line that answers it and say ANSWERED."},
            {"role": "user", "content": f"DOCUMENT:\n{doc[:12000]}\n\nQUESTION: {question}"},
        ],
    }
    req = urllib.request.Request(f"{base}/api/chat", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r).get("message", {}).get("content", "").strip() or None
    except (OSError, ValueError):
        return None


def probe(path: Path, model: str, base: str) -> tuple[bool, str]:
    """Return (passes, report). A file passes when it carries the section and every
    question has an entry under it, or when every probe answer says ANSWERED."""
    doc = path.read_text(errors="replace")
    if SECTION in doc:
        tail = doc.split(SECTION, 1)[1]
        answered = sum(1 for q in QUESTIONS if q[:30] in tail)
        if answered >= len(QUESTIONS):
            return True, f"{path}: holes section present, {answered}/{len(QUESTIONS)} questions carried"
    lines = [f"{path}", SECTION, ""]
    open_holes = 0
    for q in QUESTIONS:
        a = _ask(model, base, doc, q)
        if a is None:
            return True, f"{path}: local model did not answer within the limit; probe skipped (fails open)"
        status = "answered" if a.upper().startswith("ANSWERED") or " ANSWERED" in a.upper() else "OPEN"
        if status == "OPEN":
            open_holes += 1
        lines.append(f"- {q}\n  {status}: {a}")
    report = "\n".join(lines)
    return open_holes == 0, report


def main() -> int:
    if os.environ.get("PROBE_GATE_OFF") == "1":
        return 0
    try:
        sys.stdin.read()
    except Exception:  # noqa: BLE001
        pass
    model = os.environ.get("PROBE_GATE_MODEL", "qwen3.8:27b-mlx")
    base = os.environ.get("PROBE_GATE_OLLAMA", "http://localhost:11434")
    window = int(os.environ.get("PROBE_GATE_WINDOW_MIN", "240"))
    files = _files(window)
    if not files:
        return 0
    failures = []
    for f in files:
        ok, report = probe(f, model, base)
        if not ok:
            failures.append(report)
    if not failures:
        return 0
    sys.stderr.write("PROBE GATE: the owner's questions, asked before he has to. Answer each OPEN\n"
                     "line inside the file under the section below, then stop again.\n\n")
    sys.stderr.write("\n\n".join(failures) + "\n")
    return 2


def _self_test() -> int:
    import tempfile
    d = Path(tempfile.mkdtemp())
    good = d / "pitch-good.md"
    good.write_text("# Pitch\n\n" + SECTION + "\n\n" + "\n".join(f"- {q}\n  answered: yes" for q in QUESTIONS))
    ok, rep = probe(good, "none", "http://127.0.0.1:9")
    assert ok, rep
    bad = d / "strategy-bad.md"
    bad.write_text("# Strategy\n\nWe sell an agentic ledger with ed25519 signatures.")
    ok, rep = probe(bad, "none", "http://127.0.0.1:9")  # no model: must fail open
    assert ok and "fails open" in rep, rep
    assert NAME_RE.search("go-to-market-2026.md") and not NAME_RE.search("README.md")
    print("probe-gate self-test: ok")
    return 0


if __name__ == "__main__":
    sys.exit(_self_test() if "--self-test" in sys.argv else main())
