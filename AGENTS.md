<!-- BEGIN codex-context-sync: managed block, edit the generator not this -->
## Shared context, identical in every repo on this box

You are one of two engines here. Claude holds the scarce window; you hold the execution
capacity. Work is handed to you because it is cheaper here, not because it is unimportant.

READ THESE BEFORE ASKING FOR ANYTHING THEY ALREADY ANSWER, in this order:
1. `~/.codex/AGENTS.md` - your operating instructions: account map, hard rails, secrets,
   SOT document ids, model routing. It loads globally for every seat, so it is already in
   your context; re-read it if a task touches money, secrets, deploys or the owner's copy.
2. `~/.claude/SOT-DIGEST.md` - the compact index of the source of truth. NOT auto-injected
   for you, so read it at the start of any non-trivial task.
3. `~/repos/hstack/CLAUDE.md` - the facts for THIS repo. It is the same file the other engine loads, which is what keeps the two of you in step.
4. `lanes` before hunting for data, and `~/.claude/reference/tool-use-cases.md` before
   writing any shell or python one-off. Most of what you are about to write already exists.

HOW WORK REACHES YOU AND HOW IT GETS BACK:
- Jobs arrive through `jobq`. The spec is a file in `~/.claude/reference/codex-specs/`.
- Finished work sits in `jobq inbox` until a session acknowledges it with `jobq ack <id>`,
  and is injected into the next prompt of whichever session owns this repo. So a clear
  final summary is the deliverable, not a courtesy.
- A job costs about 0.7% of a weekly seat window. Nothing here is worth rationing; the
  scarce thing is the owner's attention, not your capacity.

STANDING RULES THAT BITE MOST OFTEN, in full in `~/.codex/AGENTS.md`:
- Never `git add -A` or `git add .`. Stage named paths.
- Secrets come from the macOS Keychain at the point of use, never written to a file.
- Traditional Chinese only, never simplified, in anything a reader sees.
- No em dashes anywhere, including your own replies.
- Verify a capability against the live source before claiming it cannot be done.
- A completion claim carries the evidence that proves it, produced after the work.
<!-- END codex-context-sync -->
