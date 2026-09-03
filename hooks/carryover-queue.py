#!/usr/bin/env python3
# carryover-queue.py: UserPromptSubmit. A new prompt is ADDITIVE, never a cancel.
#
# The failure this fixes, the owner 2026-08-16: "when i interrupt an existing section
# with a new prompt, still do my original prompt's commands but queue them, so u
# dont miss anything at all". Measured before writing this: 198 `Request interrupted
# by user` markers across 83 transcripts. Every one of them is a point where in-flight
# work could silently evaporate, because the model's default reading of a new prompt
# is "the old one is superseded". It is not. It is a push onto a stack.
#
# This is the same class as the rules/common "answer EVERY part of the message" rule,
# pointed at the time axis instead of the sentence axis. That rule is prose and prose
# was measured at ~40% failure. This one is injected text carrying the actual item
# list, so the model cannot forget WHAT was pending, only choose to ignore it.
#
# Two independent signals, because either alone has a hole:
#   A. Open tasks in ~/.claude/tasks/<session_id>/*.json (status not completed or
#      cancelled). Solid when TaskCreate was used. Empty when it was not.
#   B. The previous turn ended on an interrupt marker in the transcript. Catches the
#      case where nothing was ever written down, which is exactly the case where
#      work is most likely to be lost.
#
# Fails open, always. A carryover reminder is never worth blocking a prompt over.

import json
import os
import sys
import glob
import re

# Overridable so the self-test can actually reach a fixture. Without this the first
# test run printed a clean PASS while open_tasks() had silently read the real task
# dir and returned nothing, so the task half of the hook was never exercised at all.
TASK_ROOT = os.environ.get("CARRYOVER_TASK_ROOT") or os.path.expanduser("~/.claude/tasks")
OPEN_STATES = {"pending", "in_progress", "in-progress", "blocked", "active"}
TAIL_BYTES = 400_000  # enough for the last few turns without reading a 40MB transcript

# the owner saying any of these means the queue is genuinely being dropped, so the hook
# must not then insist. It still names the items, because "drop it" needs to point at
# something specific: dropping the wrong item silently is the same defect mirrored.
CANCEL = re.compile(
    r"\b(drop (that|it|those|the)|forget (that|it|about)|cancel (that|it)|"
    r"never ?mind|scrap (that|it)|abandon|stop (that|doing)|skip (that|it)|"
    r"don'?t bother|no longer|leave (that|it))\b",
    re.I,
)


def queued_interjections(transcript_path):
    """His mid-turn messages that the HARNESS queued and no hook ever read.

    ADDED 2026-08-30. the owner: "i still dont think that u queue tasks, i think
    when i interject mid turn u drop the older ones and only do the new ones."

    Measured before writing this. Claude Code DOES queue: every mid-turn message
    is written to the transcript as {"type":"queue-operation","operation":
    "enqueue","content":"<his words>"} and later dequeued. 65 of them exist in
    the session where he said this. And grepping every hook on disk for
    "queue-operation" returned NOTHING: the harness kept a perfect record of
    exactly the thing he was worried about, and no guard here had ever looked at
    it. carryover-queue read TaskCreate json (0.4% coverage), an interrupt
    marker, and the repo backlog. Not this.

    So the items are injected by name on the next prompt, and an item he raised
    mid-turn can no longer disappear just because a newer one arrived.

    Only enqueues since the last assistant PROSE reply are returned: anything
    before that has already had a reply, whatever its quality, and re-injecting
    the whole session would be noise.
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return []
    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
                fh.readline()
            tail = fh.read().decode("utf-8", errors="replace").splitlines()
    except OSError:
        return []
    pending, seen = [], set()
    for ln in tail:
        if '"type"' not in ln:
            continue
        try:
            d = json.loads(ln)
        except Exception:
            continue
        t = d.get("type")
        if t == "assistant":
            c = (d.get("message") or {}).get("content")
            if isinstance(c, list) and any(
                isinstance(b, dict) and b.get("type") == "text"
                and len(b.get("text", "").strip()) > 200 for b in c
            ):
                pending, seen = [], set()      # a reply landed; the slate clears
        elif t == "queue-operation" and d.get("operation") == "enqueue":
            txt = (d.get("content") or "").strip()
            if not txt or txt.startswith(("<task-notification", "<system-reminder",
                                          "[SYSTEM", "<cross-session", "/")):
                continue
            key = txt[:120]
            if key in seen:
                continue
            seen.add(key)
            pending.append(re.sub(r"\s+", " ", txt)[:180])
    return pending


BACKLOG_NAMES = ("OPEN-ITEMS.md",)


def repo_backlog(cwd):
    """Unchecked items in the repo's own backlog file.

    ADDED 2026-08-29, and it is the reason this hook existed without working.
    Measured that day: "CARRYOVER QUEUE" appears in ZERO transcripts, live (270)
    and archived (3,638). The hook is correct when handed a payload, proved by
    running it, but its only store is ~/.claude/tasks/<session_id>/, written by
    TaskCreate. 16 task dirs exist across 3,908 sessions (0.41%), and 6 of those
    hold an open item. So the real coverage is about one session in seven hundred,
    and the queue died at session end every other time.

    the owner, 2026-08-29: "im asking u to audit why the agent has repeatedly failed
    to comply with my requests, delegating my ask the next term". A promise made in
    one session had no carrier into the next, so R10 in closeout-shape.py can tell
    the model to record a deferral, and THIS is what makes the record come due.

    A file in the repo survives the session, is committed with the work, and is
    visible to every lane in that tree. One store per repo, per the SOT rule: this
    reads the file that is already there and never creates a second one.
    """
    out = []
    if not cwd or not os.path.isdir(cwd):
        return out
    root, d = None, os.path.abspath(cwd)
    for _ in range(8):
        if os.path.isdir(os.path.join(d, ".git")):
            root = d
            break
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    if not root:
        return out
    seen = set()
    for name in BACKLOG_NAMES:
        cands = [os.path.join(root, name), os.path.join(root, "docs", name)]
        cands += sorted(glob.glob(os.path.join(root, "*", "docs", name)))[:4]
        for path in cands:
            if path in seen or not os.path.isfile(path):
                continue
            seen.add(path)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    body = fh.read(120_000)
            except Exception:
                continue
            items = re.findall(r"^\s*[-*]\s*\[ \]\s*(.+)$", body, re.M)
            if items:
                rel = os.path.relpath(path, root)
                out.append((rel, [re.sub(r"\s+", " ", i).strip()[:110] for i in items]))
    return out


def open_tasks(session_id):
    """Items this session opened and never closed."""
    out = []
    if not session_id:
        return out
    d = os.path.join(TASK_ROOT, session_id)
    for f in sorted(glob.glob(os.path.join(d, "*.json"))):
        try:
            with open(f, encoding="utf-8", errors="replace") as fh:
                t = json.load(fh)
        except Exception:
            continue
        if not isinstance(t, dict):
            continue
        status = str(t.get("status") or "").lower()
        if status in OPEN_STATES:
            subject = str(t.get("subject") or t.get("description") or "").strip()
            if subject:
                out.append((status, subject[:120]))
    return out


def was_interrupted(transcript_path):
    """True when the most recent user record is an interrupt marker.

    Read the tail only. A long session's transcript runs to tens of megabytes and
    this hook sits in front of every single prompt.
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return False
    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
                fh.readline()  # discard the partial line the seek landed inside
            tail = fh.read().decode("utf-8", errors="replace")
    except Exception:
        return False

    last_user = None
    for line in tail.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        msg = r.get("message") or {}
        if msg.get("role") == "user" or r.get("type") == "user":
            last_user = json.dumps(msg.get("content"))[:4000]
    return bool(last_user and "Request interrupted" in last_user)


def codex_inbox(cwd):
    """Finished Codex/local jobs enqueued from this repo that no session has acked.

    ADDED 2026-09-03. the owner: "in order for this loop to function effectively you
    and codex need to effectively poll each other". Codex's half already worked
    (the drain LaunchAgent ran 27 jobs); the Claude half did not exist. A finished
    job reached Telegram and a log file, and a session only learned of it if it
    happened to run `jobq status`. This reads the queue's sqlite directly (no
    subprocess: the hook runs on every prompt of every session) and injects the
    unacked results for THIS repo, so the next turn of the owning session carries
    them. `jobq ack <id>` clears one after the diff is reviewed. Fails open.
    """
    import sqlite3
    db = os.path.join(os.environ.get("JOBQ_STATE") or os.path.expanduser("~/.claude/state"), "jobq.db")
    if not cwd or not os.path.exists(db):
        return []
    root = os.path.realpath(cwd)
    out = []
    try:
        c = sqlite3.connect(db, timeout=5)
        c.row_factory = sqlite3.Row
        cols = {r[1] for r in c.execute("PRAGMA table_info(jobs)")}
        if "acked" not in cols:
            return []
        rows = c.execute("SELECT id,state,lane,cwd,cmd,out,note FROM jobs WHERE acked=0 "
                         "AND state IN ('done','failed','stalled') ORDER BY id").fetchall()
    except Exception:
        return []
    for r in rows:
        jcwd = os.path.realpath(r["cwd"] or "")
        if not (jcwd == root or jcwd.startswith(root + os.sep) or root in (r["cmd"] or "")):
            continue
        summ = r["note"] or ""
        try:
            lines = open(r["out"], errors="replace").read().strip().splitlines()
            for l in reversed(lines):
                t = l.strip()
                if t and not t.startswith(("tokens used", "warning", "UPGRADE_AVAILABLE")) \
                        and not re.fullmatch(r"[\d,]+", t):
                    summ = t[:200]
                    break
        except Exception:
            pass
        out.append((r["id"], r["state"], summ, r["out"] or ""))
    return out


def main():
    try:
        raw = sys.stdin.read()
    except Exception:
        return
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        payload = {}

    session_id = str(payload.get("session_id") or os.environ.get("CLAUDE_SESSION_ID") or "")
    # REJECT a malformed id, never scrub it. Stripping the bad characters out of
    # "../../SESSTEST" yields "SESSTEST", a real and DIFFERENT session, so the hook
    # would have quietly served another conversation's queue into this one. Caught
    # by the self-test's traversal case, which was written expecting silence.
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", session_id or ""):
        session_id = ""
    prompt = str(payload.get("prompt") or "")
    # hookpaste (2026-09-02): pasted hook output is the harness quoting itself, not
    # the owner asking. Wrapped so a missing lib can never take this hook down.
    try:
        import sys as _s, os as _o
        _s.path.insert(0, _o.path.join(_o.path.dirname(_o.path.abspath(__file__)), "lib"))
        from hookpaste import strip_hook_paste as _strip
        prompt = _strip(prompt)
    except Exception:
        pass

    tasks = open_tasks(session_id)
    interrupted = was_interrupted(payload.get("transcript_path"))
    backlog = repo_backlog(str(payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""))
    queued = queued_interjections(payload.get("transcript_path"))
    inbox = codex_inbox(str(payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""))

    if not tasks and not interrupted and not backlog and not queued and not inbox:
        # Nothing pending. Say nothing: a reminder that fires on every prompt is
        # noise, and noise is what taught the reader to skip the whole block.
        return

    cancelling = bool(CANCEL.search(prompt))

    lines = ["CARRYOVER QUEUE: this prompt is ADDITIVE, not a replacement.",
             "  ORDER: the prompt you just received goes FIRST. Additive means "
             "nothing is dropped, NOT that everything ranks equally: the newest "
             "instruction is the most current statement of what he wants, and it "
             "is often a correction of what you are doing right now. Answer it, "
             "then work back through the queue below in the same reply. "
             "(Added 2026-08-27 on his instruction: 'prioritize it but still take "
             "all items, even when i press interrupt'.)"]

    if interrupted:
        lines.append(
            "  The previous turn was INTERRUPTED. Whatever was in flight was not "
            "finished and was never reported. Name it in this reply, then either "
            "finish it or put it under YOUR MOVE with the blocker."
        )

    if tasks:
        lines.append("  Still open from earlier in this session:")
        for status, subject in tasks[:12]:
            lines.append("    - [%s] %s" % (status, subject))
        if len(tasks) > 12:
            lines.append("    - (+%d more in the task list)" % (len(tasks) - 12))

    if queued:
        lines.append("  HE INTERRUPTED %d time(s) since your last reply, and the harness "
                     "queued every one. These are his words, verbatim:" % len(queued))
        for q in queued[:8]:
            lines.append("    - %s" % q)
        if len(queued) > 8:
            lines.append("    - (+%d more)" % (len(queued) - 8))
        lines.append("    A later message does not retire an earlier one. Answer ALL of "
                     "them in this reply, or name the one you are refusing and why.")

    for rel, items in backlog:
        lines.append("  Owner backlog still open in %s (%d item%s):"
                     % (rel, len(items), "" if len(items) == 1 else "s"))
        for it in items[:3]:
            lines.append("    - %s" % it)
        if len(items) > 3:
            lines.append("    - (+%d more in that file)" % (len(items) - 3))
        lines.append(
            "    These are HIS asks, carried from an earlier session. An item leaves "
            "that file when it is done with evidence, or refused out loud by name. "
            "Check its status against the world before repeating it: the file is "
            "written from memory and has already carried a done item as open."
        )

    if inbox:
        lines.append("  CODEX RESULTS for this repo, finished and not yet reviewed (%d):" % len(inbox))
        for jid, state, summ, log in inbox[:6]:
            lines.append("    - #%d %s: %s  [log %s]" % (jid, state, summ or "(no summary)", log))
        if len(inbox) > 6:
            lines.append("    - (+%d more: jobq inbox --cwd .)" % (len(inbox) - 6))
        lines.append(
            "    Read the log, review the diff in the tree, commit only the files the spec "
            "named or refuse by name, then run `jobq ack <id>`. An unacked result is "
            "re-injected on every prompt; a stalled or failed one still needs a verdict."
        )

    if cancelling:
        lines.append(
            "  This prompt reads as a CANCEL. Name which of the items above it "
            "drops, drop exactly those, and keep the rest. Do not clear the whole "
            "queue on an ambiguous cancel."
        )
    else:
        lines.append(
            "  Handle the new prompt first if it is urgent, then clear the queue in "
            "the same session. No item may vanish silently. An item that cannot be "
            "done is refused out loud against its name, never dropped quietly."
        )

    # TaskCreate WAS ordered here and the tool no longer exists. It was removed
    # on Opus 4.8 and newer, CLAUDE_CODE_ENABLE_TODO_TOOLS is unreliable, and it
    # disconnected mid-session on 2026-08-30. An injected instruction naming a
    # tool the model cannot call fails silently on every single prompt, which is
    # the dead-rule class `cc-whatsnew` exists to flag, sitting inside the very
    # block that exists to stop work being lost. Point at the store that does
    # survive instead.
    lines.append(
        "  Before the first tool call: split the new prompt into its items. If a "
        "task tool is in the live tool list, use it; if not, write anything that "
        "outlives this session into this repo's docs/OPEN-ITEMS.md, which is what "
        "these injected lines are read from."
    )

    sys.stdout.write("\n".join(lines) + "\n")


def _self_test():
    """Written 2026-08-17, because there was none.

    `~/.claude/CLAUDE.md` asserted "Self-test 13/13 including the silence arm" for this
    hook. No such test existed anywhere on disk, and `--self-test` was not a recognised
    flag: it fell through to main(), read an empty stdin, found nothing pending and exited
    0 silently. A run that cannot fail printed a clean exit, which is exactly the shape
    the negative-control rule in CLAUDE.md exists to catch. The comment on TASK_ROOT
    above even says it is overridable "so the self-test can actually reach a fixture",
    so the test was designed and then never landed.
    """
    import subprocess
    import tempfile

    here = os.path.abspath(__file__)
    root = tempfile.mkdtemp(prefix="carryover-selftest-")
    sid = "selftest-session"
    tdir = os.path.join(root, "tasks", sid)
    os.makedirs(tdir, exist_ok=True)

    def task(name, status, subject):
        with open(os.path.join(tdir, name), "w", encoding="utf-8") as fh:
            json.dump({"status": status, "subject": subject}, fh)

    def transcript(name, records):
        p = os.path.join(root, name)
        with open(p, "w", encoding="utf-8") as fh:
            for r in records:
                fh.write(json.dumps(r) + "\n")
        return p

    def user(content):
        return {"type": "user", "message": {"role": "user", "content": content}}

    def run(prompt="go", session=sid, transcript_path=None, task_root=None):
        env = dict(os.environ)
        env["CARRYOVER_TASK_ROOT"] = task_root or os.path.join(root, "tasks")
        payload = {"session_id": session, "prompt": prompt}
        if transcript_path:
            payload["transcript_path"] = transcript_path
        r = subprocess.run([sys.executable, here], input=json.dumps(payload),
                           capture_output=True, text=True, env=env)
        return r.returncode, r.stdout

    interrupted = transcript("int.jsonl", [user("earlier"), user("[Request interrupted by user]")])
    clean = transcript("clean.jsonl", [user("[Request interrupted by user]"), user("later prompt")])
    empty = transcript("empty.jsonl", [user("nothing special")])

    cases = []

    def check(name, cond):
        cases.append((name, bool(cond)))

    # 1. silence. No open task, no interrupt: the hook must say nothing at all.
    rc, out = run(transcript_path=empty)
    check("silence when nothing is pending", rc == 0 and out.strip() == "")

    # 2. an open task surfaces, by subject, not by a reminder to go look.
    task("a.json", "pending", "ship the reference audit")
    rc, out = run(transcript_path=empty)
    check("open task named in the injection", "ship the reference audit" in out)

    # 3. a closed task does not surface.
    task("b.json", "completed", "already finished thing")
    rc, out = run(transcript_path=empty)
    check("completed task stays out", "already finished thing" not in out)

    # 4. the interrupt marker alone fires, with no open tasks.
    os.remove(os.path.join(tdir, "a.json"))
    os.remove(os.path.join(tdir, "b.json"))
    rc, out = run(transcript_path=interrupted)
    check("interrupt alone fires", "INTERRUPTED" in out)

    # 5. an interrupt that is NOT the last user record must not fire. This is the arm
    #    that keeps the hook from shouting on every prompt for the rest of a session.
    rc, out = run(transcript_path=clean)
    check("stale interrupt does not fire", out.strip() == "")

    # 6. a cancel phrase gets the scoped-cancel clause.
    task("c.json", "in_progress", "half-done migration")
    rc, out = run(prompt="drop that", transcript_path=empty)
    check("cancel prompt gets the CANCEL clause", "reads as a CANCEL" in out)

    # 7. and a cancel still NAMES the items, because "drop it" has to point somewhere.
    check("cancel still names the open item", "half-done migration" in out)

    # 8. an ordinary prompt gets the do-not-vanish clause instead.
    rc, out = run(prompt="now do the next thing", transcript_path=empty)
    check("ordinary prompt gets the vanish clause", "may vanish silently" in out)

    # 9. The durable-store instruction rides along whenever the hook fires.
    #    This arm asserted "TaskCreate" in out until 2026-08-30, and it did its
    #    job: removing the dead tool name failed the self-test immediately. The
    #    assertion now names the store that actually survives a session ending.
    check("durable-store line present when firing", "OPEN-ITEMS.md" in out)
    check("no dead tool ordered in the injected block", "TaskCreate" not in out)

    # 10. more than 12 open items truncate with a count, rather than flooding context.
    for i in range(15):
        task("bulk%02d.json" % i, "pending", "bulk item %d" % i)
    rc, out = run(transcript_path=empty)
    check("over 12 items truncates with a count", "more in the task list" in out)

    # 11. a session id that tries to escape the task dir is refused.
    rc, out = run(session="../../etc", transcript_path=empty)
    check("path-traversal session id reads no tasks", "bulk item" not in out)

    # 12. a malformed task file is skipped without taking the good ones down with it.
    with open(os.path.join(tdir, "broken.json"), "w", encoding="utf-8") as fh:
        fh.write("{not json")
    rc, out = run(transcript_path=empty)
    check("malformed task file skipped, others survive", rc == 0 and "bulk item 0" in out)

    # 13. a transcript path that does not exist is not a crash.
    rc, out = run(transcript_path=os.path.join(root, "no-such-file.jsonl"))
    check("missing transcript path does not crash", rc == 0)

    bad = [n for n, ok in cases if not ok]
    for n, ok in cases:
        print("  %s %s" % ("ok  " if ok else "FAIL", n))
    print("carryover-queue self-test: %s (%d/%d)"
          % ("PASS" if not bad else "FAIL", len(cases) - len(bad), len(cases)))
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv[1:]:
        sys.exit(_self_test())
    try:
        main()
    except Exception:
        pass  # fail open, always
    sys.exit(0)
