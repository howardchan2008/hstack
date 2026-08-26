# Expert feedback: mine it, do not just answer it (the owner directive 2026-08-21)

Applies to any reply from someone who is not a peer: an academic, a senior
operator, an investor, a practitioner who knows more than we do about the thing
they wrote about. Not to peer chat.

## Why the bar is different

A professor who replies has spent thirty minutes or more of unpaid attention on
our problem. Answering the one question he asked and stopping wastes most of
what he gave. the owner, 2026-08-21: *"the professor spent probably more than 30
mins of his time or even more replying to these, so u shd be actually rerunning
both his responses, both on a simple level and on a deeper level."*

## The method, before writing a single line of reply

1. **Enumerate every claim, not just the question.** Split the reply into
   numbered assertions. A mechanism, an aside, a citation, a warning and a
   definition are each a separate item. a contact's second message carried twelve;
   the first pass tested one.
2. **Read the papers they cite, in full, before citing them back.** On
   2026-08-21 a paper was named in a reply to its own recommender without being
   read. Reading it revealed that the authors run the test in BOTH directions
   and that the asymmetry is the entire finding, which had been done one way.
   The citation was a bluff that happened to survive.
3. **Cross-reference their replies against each other.** Two messages from the
   same expert are two views of one model. Use the second to confirm or correct
   the read of the first. Never quote one back at the other as a gotcha.
4. **Chase the ramifications they did not state.** If the mechanism is X, what
   else must be true? Test that too. a contact's rulebook story implies a continuum,
   not a binary split, and implies model capacity should matter. Both were
   testable and neither was asked for.
5. **Look for the confound before reporting the result.** A gradient that
   survives one control and dies under another is a different finding from a
   clean one, and the expert will find it if we do not.
6. **Only then reply**, and only then run any refutation.

## Questions back

Explicit, direct, simple. Only where genuinely stuck. Never a question asked to
look engaged. the owner: *"shdnt be question just to ask a question"*.

## Register

Model how they write and use that register back at them, on every channel. Short
declaratives if they write short declaratives. Contractions if they use
contractions.

**Politeness is not part of the register and is never matched away.** Greeting
and signature stay courteous whatever the thread sounds like: address the person
properly, sign with a full name. Enforced by `copy-lint`.

## Enforcement

- `~/.claude/bin/copy-lint` carries the greeting, signature, hard-wrap, length,
  negation-pivot and hedge rules.
- `~/.claude/bin/pm-send` runs it on the unwrapped body and refuses to send on a
  blocking finding.
- `~/.claude/vip-correspondents.txt` lists the addresses where every finding
  blocks, advisory included.
- `~/.claude/hooks/outbound-copy-gate.py` applies the same to LinkedIn and
  WhatsApp, and refuses raw mail sends that bypass `pm-send`.
