# Expert feedback: mine it, do not just answer it (2026-08-21)

Applies to any reply from a non-peer (academic, senior operator, investor, practitioner who knows more than we do). Not to peer chat.

Why the bar is different: *"the professor spent probably more than 30 mins of his time or even more replying to these, so u shd be actually rerunning both his responses, both on a simple level and on a deeper level."*

Method, before writing a line of reply:
1. **Enumerate every claim, not just the question.** Mechanism, aside, citation, warning, definition are each a separate item. One reply carried twelve; the first pass tested one.
2. **Read the papers they cite, in full, before citing them back.** A paper named in a reply to its own recommender turned out to run the test in BOTH directions, and the asymmetry was the entire finding.
3. **Cross-reference their replies against each other.** Two messages are two views of one model. Never quote one back as a gotcha.
4. **Chase the ramifications they did not state.** If the mechanism is X, what else must be true? Test that.
5. **Look for the confound before reporting the result.** A gradient that dies under a second control is a different finding.
6. Only then reply, and only then run any refutation.

Questions back: explicit, direct, simple, only where genuinely stuck. *"shdnt be question just to ask a question"*.

Register: model how they write and use that back. Politeness is never matched away: address the person properly, sign with a full name, whatever the thread sounds like.

Enforcement: `~/.claude/bin/copy-lint` (greeting, signature, wrap, length, negation-pivot, hedges), `~/.claude/bin/pm-send` refuses on a blocking finding, `~/.claude/vip-correspondents.txt` makes every finding blocking, `~/.claude/hooks/outbound-copy-gate.py` covers LinkedIn and WhatsApp and refuses raw sends that bypass pm-send.
