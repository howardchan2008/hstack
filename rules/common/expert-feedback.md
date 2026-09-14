# Expert feedback: mine it, do not just answer it (2026-08-21)

Non-peer replies only (academic, senior, investor, domain expert). Not peer chat.

Why the bar is different: *"the professor spent probably more than 30 mins of his time or even more replying to these, so u shd be actually rerunning both his responses, both on a simple level and on a deeper level."*

Before replying:

1. **Enumerate all claims, not just the question.** Separate: mechanism, aside, citation, warning, definition. Example: 1 reply = 12 claims; first pass tested 1.

2. **Read cited papers fully before citing back.** Paper to own recommender—test ran both directions; asymmetry was entire finding.

3. **Cross-ref replies against each other.** 2 messages = 2 views of 1 model. Never quote as gotcha.

4. **Chase unstated ramifications.** Mechanism X → what else true? Test.

5. **Find confounds first.** Gradient fails under 2nd control = different finding.

6. Then reply. Then refute.

Questions: only if stuck. Explicit, direct, simple. *"shdnt be question just to ask a question"*.

Mirror their style. Politeness holds: proper address, full signature, match tone.

Enforcement: `~/.claude/bin/copy-lint` (greeting, signature, wrap, length, negation-pivot, hedges), `~/.claude/bin/pm-send` refuses on blocking finding, `~/.claude/vip-correspondents.txt` makes all findings blocking, `~/.claude/hooks/outbound-copy-gate.py` covers LinkedIn/WhatsApp; blocks raw sends bypassing pm-send.