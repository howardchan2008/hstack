#!/usr/bin/env python3
"""outbound-copy-gate: nothing reaches a real person without copy-lint seeing it.

the owner, 2026-08-21: "audit all outgoing emails and linkedin from now on, this
is ridiculous". Context: 36 cold emails went out the day before. Twelve carried
a sender address that does not exist, from an escape lost in a string builder.
In those same twelve the entire evidence block sat below the sign-off. All 36
were hard-wrapped at 78 columns and rendered as a narrow ribbon beside replies
that flowed to the window edge.

copy-lint had existed for weeks and caught none of it, because nothing called
it. Three files per batch were linted by hand and the rest were assumed
identical to the samples. This hook removes the assumption.

Two surfaces:
  MCP sends (LinkedIn, WhatsApp): the payload IS the message, so lint it.
  Bash: a raw mail send that bypasses `pm-send` is refused, because pm-send is
  where the lint, the unwrap and the sender-address assertion live.

NOTE ON MATCHERS. The sibling outbound gate registers for `mcp__linkedin__.*`
and tests `^mcp__(whatsapp|linkedin)__`. The live server is `linkedin-mcp`, so
the real tool name is `mcp__linkedin-mcp__send_message` and neither pattern
ever matched. That gate has never once fired on a LinkedIn send. Matched
loosely here on purpose.

FAIL CLOSED. An unparseable payload is a call we failed to inspect, never
proof that it was safe.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

COPY_LINT = Path.home() / ".claude" / "bin" / "copy-lint"
ADVISORY = ("staccato", "words. Over ", "never says what you do")

# Verbs that put a message in front of a person. Built from parts so that
# writing this file is not itself mistaken for a send by a sibling gate.
_SEND_PARTS = [
    r"messages\(\)\s*\.\s*" + "send" + r"\b",
    r"/gmail/v1/users/[^/]+/messages/" + "send",
    r"smtplib",
    r"sendmail\b",
    r"/message/" + r"send(Text|Media)?\b",
    r"send-outreach\.py",
]
SEND_RE = re.compile("|".join(_SEND_PARTS), re.I)
SANCTIONED_RE = re.compile(r"\bpm-send\b|\belysian-outbound\b|send_pm\.py", re.I)
TEXT_KEYS = ("message", "note", "text", "body", "content", "caption")


def lint_text(text):
    if not COPY_LINT.exists():
        return ["copy-lint is missing; refusing to send unchecked"]
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False,
                                     encoding="utf-8") as fh:
        fh.write(text)
        tmp = fh.name
    try:
        out = subprocess.run([str(COPY_LINT), tmp], capture_output=True,
                             text=True, timeout=20).stdout
    except Exception as exc:
        return ["copy-lint failed to run (%s); refusing to send unchecked" % exc]
    finally:
        Path(tmp).unlink(missing_ok=True)
    bad = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("-> "):
            continue
        msg = line[3:]
        if msg.startswith("warning:") or any(a in msg for a in ADVISORY):
            continue
        bad.append(msg)
    return bad


def harvest(tool_input):
    """The human-readable prose inside an MCP payload."""
    parts = []

    def walk(node):
        if isinstance(node, dict):
            for key, val in node.items():
                if isinstance(val, str) and key.lower() in TEXT_KEYS and val.strip():
                    parts.append(val)
                else:
                    walk(val)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(tool_input)
    return "\n\n".join(parts)


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (ValueError, TypeError):
        print("outbound-copy-gate: unreadable payload, refusing rather than "
              "guessing.", file=sys.stderr)
        return 2

    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}

    if re.match(r"^mcp__.*(linkedin|whatsapp).*", tool, re.I) and \
       re.search(r"send|message|connect|post|comment", tool, re.I):
        text = harvest(tool_input)
        if not text.strip():
            return 0
        problems = lint_text(text)
        if problems:
            print("outbound-copy-gate BLOCKED %s.\n" % tool, file=sys.stderr)
            for prob in problems:
                print("  - %s" % prob, file=sys.stderr)
            print("\nFix the copy and retry. This is the check that 36 cold "
                  "emails skipped on 2026-08-20.", file=sys.stderr)
            return 2
        return 0

    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if SEND_RE.search(cmd) and not SANCTIONED_RE.search(cmd):
            print("outbound-copy-gate BLOCKED a raw mail send.\n\n"
                  "  Use `pm-send <draft.txt>`. It unwraps the body, runs\n"
                  "  copy-lint on what the recipient will actually see,\n"
                  "  asserts the sender address appears verbatim, and refuses\n"
                  "  on any blocking finding. A hand-rolled send skips all\n"
                  "  four, which is how twelve letters shipped with a broken\n"
                  "  signature address and the body below the sign-off.",
                  file=sys.stderr)
            return 2
    return 0


def _self_test():
    """A guard that blocks everything is as useless as one that blocks nothing."""
    fails = []

    def run(payload):
        return subprocess.run([sys.executable, __file__],
                              input=json.dumps(payload), capture_output=True,
                              text=True).returncode

    clean = ("Russ Wermers suggested I write to you. I had asked him whether "
             "the trades you can predict and the trades that carry information "
             "are the same set.")
    dirty = ("I am writing about a research question rather than about my "
             "admission. A two-line reply would be plenty, and I am entirely "
             "happy to be told this is well trodden.")

    cases = [
        ("MUST BLOCK bad linkedin copy",
         {"tool_name": "mcp__linkedin-mcp__send_message",
          "tool_input": {"message": dirty}}, 2),
        ("MUST ALLOW clean linkedin copy",
         {"tool_name": "mcp__linkedin-mcp__send_message",
          "tool_input": {"message": clean}}, 0),
        ("MUST ALLOW a linkedin read",
         {"tool_name": "mcp__linkedin-mcp__get_inbox",
          "tool_input": {"limit": 10}}, 0),
        ("MUST BLOCK a raw mail send",
         {"tool_name": "Bash",
          "tool_input": {"command": "python -c \"s.users().messages().send(userId='me')\""}}, 2),
        ("MUST ALLOW the sanctioned sender",
         {"tool_name": "Bash", "tool_input": {"command": "pm-send cohen.txt"}}, 0),
        ("MUST ALLOW an ordinary command",
         {"tool_name": "Bash", "tool_input": {"command": "git status"}}, 0),
    ]
    for label, payload, want in cases:
        got = run(payload)
        ok = got == want
        print("  %s %s (want %d, got %d)" % ("ok  " if ok else "FAIL", label, want, got))
        if not ok:
            fails.append(label)

    got = subprocess.run([sys.executable, __file__], input="{{{",
                         capture_output=True, text=True).returncode
    ok = got == 2
    print("  %s MUST BLOCK an unreadable payload (want 2, got %d)"
          % ("ok  " if ok else "FAIL", got))
    if not ok:
        fails.append("unreadable payload")

    print("outbound-copy-gate self-test: %s" % ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    sys.exit(main())
