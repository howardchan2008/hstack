#!$HOME/.venvs/agent-libs/bin/python
# written-call-guard.py: PreToolUse(Write|Edit). Refuse WRITING a metered
# generation call into a file.
#
# THE HOLE THIS CLOSES, found by auditing my own guards on 2026-08-27 after
# charging the owner JPY 405.51. Every command guard on this box matches on the
# TEXT OF THE COMMAND. So all of them, including the paid-inference guard
# written the same hour, are defeated by:
#
#     Write("/tmp/gen.py", "<the billing call>")   # no guard looks at content
#     Bash("python3 /tmp/gen.py")                  # command text is innocent
#
# Verified: that pair walked past the paid-inference guard, the outbound copy
# gate and the risk checkpoint. It is not a flaw in any one of them, it is what
# text matching cannot do. A file has to be CREATED before it can be run, and
# every creation path except a shell heredoc goes through Write or Edit, so this
# is the layer where the content is still visible. Heredocs and `echo >` keep
# the text inside the Bash command, where the other guard sees it.
#
# It refuses the WRITE, not the file's existence: rename the intent, use the
# wrapper, or pass the explicit override on the eventual run.

import json
import os
import re
import sys

METERED = re.compile(
    r"api\.openai\.com|generativelanguage\.googleapis\.com|aiplatform\.googleapis\.com|"
    r"openai\.azure\.com|cognitiveservices\.azure\.com|api\.higgsfield\.ai|"
    r"api\.elevenlabs\.io|api\.replicate\.com|api\.stability\.ai|api\.deepseek\.com|"
    r"api\.x\.ai", re.I)

BILLS = re.compile(
    r"/(chat/)?completions|/images?/(generations|edits|variations)|"
    r"/audio/(speech|transcriptions)|/embeddings|:generateContent|"
    r":streamGenerateContent|:predict|:predictLongRunning|/text2image|/video", re.I)

# SECOND FAMILY, added the same hour the first was verified: endpoints that
# REACH A PERSON. The audit that found the money bypass ran the same test against
# the outbound gates and they fell to it identically, which is the more serious
# result: a script on disk could message a real contact and no gate would see it.
# Money is recoverable and a wrong message to a client is not.
OUTBOUND = re.compile(
    # Match the SEND VERB, never the host alone. `gmail.googleapis.com` appears
    # in every read of the mailbox too, and a guard that refuses reading mail
    # gets switched off within a day. The self-test asserts the read passes.
    r"/message/send|/messages/send|/sendMessage|/mail/send|/v2/messages|"
    r"api\.resend\.com|api\.telegram\.org/bot|api\.sendgrid\.com|smtplib|"
    r"127\.0\.0\.1:8081/message|/ugcPosts|/conversations/.*\bsend",
    re.I)

# A script that routes THROUGH an approved lane is fine wherever it lives: the
# lane does the DNC, cooldown and lint work. Only a direct hit on a send
# endpoint skips those.
VIA_LANE = re.compile(
    r"pm-send|a venture-outbound|wa\.py\s+send|outreach-day|dispatch\.|"
    r"from\s+dispatch|import\s+dispatch|send_via|OUTREACH_LANE", re.I)

# The sanctioned callers. These files ARE the wrappers; they are supposed to
# contain the endpoint, and refusing to edit them would make the lane
# unmaintainable, which is how a guard gets removed instead of respected.
SANCTIONED = re.compile(
    r"(vertex_image|imagen|higgsfield|/ox$|/cx$|lane-bench|paid-inference-guard|"
    r"written-call-guard|keychain-probe|negative-control|"
    # THE APPROVED OUTREACH SYSTEM. Corrected 2026-08-27, same hour, by the
    # owner: unattended outbound on LinkedIn and email is AUTHORISED, so a guard
    # that blocks it is the over-blocking failure his own rules warn about, and
    # it would have been switched off within a day. These paths ARE the lanes
    # that carry the do-not-contact list, the repeat/cooldown checks and the
    # copy lint. Editing them is maintaining the approved automation.
    r"outreach/|dispatch/|pm-send|a venture-outbound|whatsapp/wa\.py|"
    r"outreach-day|outreach-pool|outreach-letters|react_post|ab\.py)", re.I)


def payload_text(inp):
    """Everything this call would put on disk."""
    parts = []
    for k in ("content", "new_string", "new_str", "text"):
        v = inp.get(k)
        if isinstance(v, str):
            parts.append(v)
    edits = inp.get("edits")
    if isinstance(edits, list):
        for e in edits:
            if isinstance(e, dict) and isinstance(e.get("new_string"), str):
                parts.append(e["new_string"])
    return "\n".join(parts)


def check(path, text):
    """Returns (kind, what) for a refusable write, else None."""
    if path and SANCTIONED.search(path):
        return None
    text = text or ""
    host = METERED.search(text)
    if host and BILLS.search(text):
        return ("METERED GENERATION CALL", host.group(0))
    # An outbound send is only refusable when it is RAW: a fresh script talking
    # straight to a send endpoint, skipping the lane that holds the DNC list and
    # the lint. Sending itself is approved and must stay frictionless.
    out = OUTBOUND.search(text)
    if out and not VIA_LANE.search(text):
        return ("RAW OUTBOUND SEND", out.group(0))
    return None


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    inp = d.get("tool_input") or {}
    hit = check(str(inp.get("file_path") or ""), payload_text(inp))
    if not hit:
        sys.exit(0)
    kind, host = hit
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason":
            f"WRITING A {kind} TO DISK ({host}).\n\n"
            "Every command guard here matches on command text, so writing the "
            "call into a file and running the file defeats all of them: the "
            "command becomes `python3 gen.py` and the URL is nowhere in it. "
            "That pair was verified to walk past the paid-inference guard, the "
            "outbound gate and the risk checkpoint.\n\n"
            "Use the sanctioned wrapper, which carries the credit check and, for "
            "sends, the do-not-contact and copy checks. Money is recoverable; a "
            "wrong message to a real contact is not. If the action is genuinely "
            "approved, run it inline so it stays greppable rather than buried in "
            "a script."}}))
    sys.exit(0)


def _self_test():
    bad = 0
    def ck(c, m):
        nonlocal bad
        if not c:
            bad += 1
            print(f"FAIL {m}")

    burl = 'urlopen("https://api.openai.com/v1/images/generations")'
    ck(check("/tmp/gen.py", burl), "the exact bypass must be refused")
    ck(check("/tmp/g.sh", 'curl https://generativelanguage.googleapis.com/v1beta/models/m:generateContent'),
       "gemini generateContent in a script must be refused")
    # wrappers must stay editable or the guard gets deleted instead of obeyed
    ck(not check("scripts/photos/vertex_image.py", burl), "the wrapper itself must stay editable")
    ck(not check("~/.claude/hooks/paid-inference-guard.sh", burl), "the guard must stay editable")
    # ordinary writes must never trip it
    ck(not check("/tmp/notes.md", "we call the openai api for images"),
       "prose mentioning a vendor must not fire")
    ck(not check("/tmp/x.py", 'urlopen("https://api.openai.com/v1/models")'),
       "a listing call is not a billing call")
    ck(not check("/tmp/x.py", "print('hello')"), "ordinary code must not fire")
    # the outbound family, which fell to the same bypass
    ck(check("/tmp/send_dm.py", 'requests.post("http://127.0.0.1:8081/message/sendText")'),
       "a RAW whatsapp send in an ad-hoc script must be refused")
    ck(check("/tmp/mail.py", "import smtplib"), "raw smtplib must be refused")
    ck(check("/tmp/g.py", 'gmail.googleapis.com/gmail/v1/messages/send'),
       "a raw gmail send must be refused")
    # AUTOMATED OUTBOUND IS APPROVED. These must all pass or the guard is wrong.
    ck(not check("/tmp/campaign.py", "subprocess.run(['pm-send', letter])"),
       "sending THROUGH the approved lane must pass")
    ck(not check(os.path.expanduser("~/repos/claude/outreach/dispatch/send.py"),
                 "requests.post('http://127.0.0.1:8081/message/sendText')"),
       "maintaining the approved outreach system must pass")
    ck(not check("/tmp/x.py", "wa.py send --to 44 --text hi"),
       "the sanctioned whatsapp lane must pass")
    ck(not check("/tmp/read.py", "gmail.googleapis.com/gmail/v1/messages/list"),
       "reading mail is not sending mail")

    # --- DEAD-BRANCH ARM 2026-08-29. VIA_LANE could be corrupted to never match
    # and this test stayed green: the wa.py arm passes because OUTBOUND misses
    # it, not because VIA_LANE exempts it. This one reaches the exemption.
    ck(not check("/tmp/send.py", "pm-send --to someone@example.com posting to "
                 "https://api.resend.com/emails from the approved lane"),
       "VIA_LANE: a send through the sanctioned lane must pass")
    print("SELF-TEST PASS" if not bad else f"SELF-TEST FAILED ({bad})")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    main()
