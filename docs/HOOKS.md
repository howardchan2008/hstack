# The hooks

Twenty-five, grouped by the event they run on. Each entry says what it refuses,
what it costs you when it is wrong, and the incident that produced it.

Two things to read first.

**How a hook refuses.** Two mechanisms are in use and both count. Exit 2 stops
the call and hands stderr back to the model. A JSON object on stdout with
`decision: block` or `permissionDecision: deny` does the same thing with more
structure. A hook that only prints and exits 0 is a reporter; it never stops
anything, and it is judged on whether the text appears at all.

**Routing hooks name tools you do not have.** `curl-router.sh`,
`websearch-router.sh` and `click-credit-guard.sh` each carry a table mapping a
host or an API to the local command that already does that job better. The
tables here name the author's commands. They are meant to be edited: put your
own in, or delete the rows you have no replacement for. Every one of the three
falls silent when the command it would recommend is not on disk, so an unedited
install is quiet rather than wrong.

---

## PreToolUse

Runs before the tool call. This is the only event that can stop anything.

### `risk-checkpoint.sh` &nbsp;·&nbsp; `Bash|Edit|Write` &nbsp;·&nbsp; exit 2

Refuses a high-blast-radius command that arrives with no rollback stated:
loading a launchd job or cron entry, force-pushing, destructive DDL, writing
into the harness settings file, sweeping a directory with `find -exec sed -i`.

The most-fired guard in the set, and for a long time the only one with no test.
That is how both of its bugs survived: a read-only inventory command was refused
because a one-letter python variable collided with the `-d` in `tr -d ' '`, and
a `find … -exec sed -i` sweep over every hook went through unblocked. A guard
that charges you a bypass for reading a file is the guard people learn to
bypass by reflex, so the false-positive arm matters as much as the other one.

### `probe-dedupe.sh` &nbsp;·&nbsp; `Bash` &nbsp;·&nbsp; warns twice, then exit 2

Refuses the fourth look at a question already answered three times this session.

One audited session made 406 shell calls. 71 were the same CPU probe, 54 the
same antivirus check, 47 the same daemon, 31 `git status`. Only 5 of the 406
were byte-identical, so hash-based dedupe finds essentially nothing: the repeats
are one question re-asked with different wording. The matchers work on subject,
not on string. The first look is always free, and the second and third only
warn, because a guard that stops the first probe is a guard that stops work.

Logic lives in `hooks/lib/probe-dedupe.py`, which carries its own `--self-test`.

### `curl-router.sh` &nbsp;·&nbsp; `Bash` &nbsp;·&nbsp; warns

Prints the better route when a hand-rolled HTTP call goes at a host that a local
tool already wraps, and then gets out of the way.

906 of 20,579 shell calls on one machine were `curl`, and several went at hosts
with a keyed, tested, documented command sitting one directory away. Two news
APIs were being queried by hand on the same day the wrapper for them was
written. This one warns rather than blocks on purpose: a hand-rolled call often
hits an endpoint the wrapper does not cover, and refusing those would be a false
positive on ordinary work.

### `grep-portability.sh` &nbsp;·&nbsp; `Bash` &nbsp;·&nbsp; exit 2

Refuses a grep PCRE flag that will silently degrade to an empty result.

`timeout 60 grep -rlP '[\x{2010}-\x{2015}]' --include='*.md' .` looks like a
careful search for unicode dashes. `timeout` execs BSD grep, which has no `-P`,
and the command fails in a way that prints nothing. An empty result reads as a
clean tree. A false zero is the most dangerous measurement there is, because it
makes unfinished work look finished.

### `pipestatus-guard.sh` &nbsp;·&nbsp; `Bash` &nbsp;·&nbsp; exit 2

Refuses a state-changing command whose exit code is thrown away by a pipe.

`git push origin main | tail -2` exits with `tail`'s status. The push can fail
outright and the pipeline still reports success, so the session moves on
believing the work is on the remote. Reads piped to `head` are fine and stay
fine; the guard only cares when the left-hand side changes something.

### `dash-gate.sh` &nbsp;·&nbsp; `Write|Edit` &nbsp;·&nbsp; exit 2

Refuses a unicode dash written into an authored file.

A house style rule that prose alone never enforced. Included less for the rule
than for the shape: it is the smallest complete example of a guard in this repo,
about forty lines, and the allow arm of its test is the interesting half.
`grep -qF -- "$want"` and `pre-seed` and `ed-tech` are all legal, and the naive
version of the rule refused all three.

### `ls-before-write.sh` &nbsp;·&nbsp; `Write` &nbsp;·&nbsp; exit 2

Refuses a blind write over a path that already holds finished work.

`Write` replaces an existing file with no diff and no prompt. The guard refuses
two shapes: the target already exists, and the directory carries a completion
marker such as a `REPORT.md`. It deliberately skips scratch trees and
directories that do not exist yet, because neither can be hiding finished work.

Worth reading as a lesson about testing: the first test written for this one
asserted what the NAME says, put its fixture in the system temp directory, and
reported a working guard as failing open. Test what a tool does.

### `fetch-guard.sh` &nbsp;·&nbsp; `Write|Edit` &nbsp;·&nbsp; warns

Warns when upstream has moved the same file underneath you since you read it.
Never blocks, by design, so the assertion in the test suite is that it stays out
of the way.

### `lane-guard.sh` &nbsp;·&nbsp; `Workflow` &nbsp;·&nbsp; exit 2

Refuses a large fan-out onto the expensive lane when no lane decision has been
stated.

One run spent tens of millions of tokens doing work a free lane covers, and a
failed cache replay re-ran 241 agents to recover 9 missing results. The rule it
enforces: before a fan-out, name the lane, the item count and the ceiling.

### `agent-budget.sh` &nbsp;·&nbsp; `Agent` &nbsp;·&nbsp; JSON deny

Refuses an agent dispatch once the daily or weekly count is spent, with a
documented bypass.

Agent cost is per agent, not per message. A five-role review panel on one
question is most of a day's budget, and the panels were being spawned by habit
rather than by need.

### `click-credit-guard.sh` &nbsp;·&nbsp; `mcp__.*__click_.*` &nbsp;·&nbsp; exit 2

Refuses a metered API call when a free lane in your own stack answers the same
question. Fails closed on an unreadable payload, so the allow arm of its test is
the one that can rot silently.

### `websearch-router.sh` &nbsp;·&nbsp; `WebSearch|WebFetch` &nbsp;·&nbsp; nudges once

Names the cheaper route for this subject before the search goes out, once per
subject, then yields.

432 of 1,035 web calls in a 30-day window re-fetched a URL or a query already
pulled inside that same window. The answer was bought twice because nothing was
keeping it. A nudge that never clears is a block, so the test asserts both arms.

### `outbound-copy-gate.py` &nbsp;·&nbsp; `Bash|mcp__linkedin.*|mcp__whatsapp.*` &nbsp;·&nbsp; json

Refuses an outbound message whose copy fails the house lint, and refuses a raw
send that goes around the sanctioned sender.

Every other guard in this repo protects a machine. This one protects a person on
the other end, and it is the only category of mistake here that cannot be
reverted: a bad commit is revertible, a bad message to a real contact is sent.
The lint it enforces is not taste. Each pattern was added after a specific reply
came back worse, so the checks are for verbless fragments, stacked clauses,
nominalised status phrases, the negation-pivot construction, and canned meeting
asks.

The second half matters more than the lint. A send is allowed only through the
sanctioned path, because a raw call to the messaging endpoint skips the repeat
check, the cooldown, and the do-not-contact list at once. Those three are what
stop the same person being messaged twice in a week.

### `linkedin-path-guard.sh` &nbsp;·&nbsp; browser MCP surfaces &nbsp;·&nbsp; exit 2

Refuses driving a social account through a browser surface that is not the
sanctioned one.

### `linkedin-browser-ban.sh` &nbsp;·&nbsp; `Bash` &nbsp;·&nbsp; exit 2

Refuses launching an unsanctioned automation browser against a social account.
Worth its own guard because the penalty there is losing the account rather than
receiving an error code, so nothing in the transcript tells you it went wrong
until it already has.

---

### `written-call-guard.py` &nbsp;·&nbsp; deny

Closes the hole that defeats every other guard here. All command guards match
on command text, so writing the call into a file and running the file walks
past all of them at once: the command becomes `python3 gen.py` and the URL is
nowhere in it. Verified against the paid-inference guard, both outbound gates
and the risk checkpoint. A file has to be created before it can be run, and
every creation path except a shell heredoc goes through Write or Edit, so this
is the layer where the content is still readable; heredocs keep the text in the
command where the other guard sees it.

It covers two families. Metered generation calls, because that class already
cost real money twice. And RAW sends that talk straight to a send endpoint,
skipping the lane that holds the do-not-contact list and the copy lint. The
second one was narrowed within the hour after the operator pointed out that
unattended outbound is authorised: refusing sends outright would have blocked
the automation he approved, which is how a guard gets switched off rather than
respected. Routing through the sanctioned lane passes, and so does editing the
lane itself.

### `paid-inference-guard.sh` &nbsp;·&nbsp; deny

Refuses a raw shell call to a metered generation endpoint. Born from an
incident where a credit check was built inside an image CLI, demonstrated
refusing correctly, and then bypassed the same hour by calling the endpoint
directly with curl to settle a factual argument. A guard inside a wrapper
protects only the callers who use that wrapper, and the agent holds a shell.

Two details are load-bearing. The billing verb is checked BEFORE the
read-allow list, because an allow-rule matching a prefix of a billing path is
a hole shaped exactly like the incident: `/models/` appears inside
`:generateContent` and `/deployments/` inside `/images/generations`, and both
walked through the first version until a negative control caught them. And
listing, usage and management calls stay allowed, because shutting a lane down
safely requires them. The override is an explicit environment prefix, so a
deliberate spend stays greppable afterwards.

## PostToolUse

### `websearch-cache.sh` &nbsp;·&nbsp; `WebSearch|WebFetch` &nbsp;·&nbsp; reporter

Stores what a search or fetch returned so the next session can read it instead
of paying for it again. This is the half that makes the router's first gate mean
anything: without a writer, "you already fetched this" is an assertion with no
file behind it.

### `prettier.sh` &nbsp;·&nbsp; `Write|Edit` &nbsp;·&nbsp; reporter

Formats what was just written, so a diff never mixes a real change with a
whitespace change.

## SessionStart

### `wiring-verify.sh`

Checks that the guards are armed rather than merely present, and surfaces any
registered hook it does not recognise. The hooks block runs arbitrary code
before every tool call, so an addition is as interesting as a deletion.

Its roster is kept equal to the shipped set by `tests/parity.py`. That check
exists because the roster went stale by default: landing a hook and registering
it in the roster are two separate acts, and only the first is load-bearing at
the moment you do it. Eighteen real hooks printed a REVIEW line at every session
start for days before anyone read one of them. A checker whose false alarms
outnumber its true ones trains you to skip the block, which is the same end
state as having no checker.

### `session-identity.sh`

Resolves which session this is, from an explicit override, then the harness, then
the transcript. It never guesses. An empty id is a missing roster line and
recovers; a wrong id poisons every other session's view of who did what.

### `session-collide.sh`

Names who else is live in this tree before you rewrite history. Several agent
sessions share these repositories, and a force-push can delete commits another
live session pushed minutes ago, which exist nowhere else. That happened once.
The check compares content, not just mtime, because ordering is the thing you
cannot recover afterwards.

### `context-restore.sh`

If a fresh snapshot from the last session exists, surfaces a short "where you
left off" so the session resumes instead of re-deriving. Silent when the
snapshot is stale or missing. Disable with `touch /tmp/context-restore-disabled`.

---

## UserPromptSubmit

Injection, not refusal. The lever here is what the model reads before it starts.

### `prompt-items.py`

Splits the prompt into numbered items and re-injects them on the next turn, so a
three-part message cannot get its first part answered and its other two dropped.
Carries a `--self-test`, because a splitter nobody measures is a splitter that
quietly returns one item for everything.

### `carryover-queue.py`

Re-injects work that was interrupted mid-flight. A new prompt is additive by
default: an interrupt is a push onto the queue, never a cancel. The model's
instinct that a new instruction retires the old one is simply wrong, and this is
the file that disagrees with it. Also carries a `--self-test`.

### `closeout-preflight.sh`

States the report contract before the reply is written.

The Stop-event checker below detects the same failure perfectly and cannot fix
it: a Stop hook's only lever is to force another assistant message, which costs
a full extra turn to repair something that a sentence up front prevents. Detect
late, prevent early.

### `state-verify-inject.sh`

Demands a live check before any externally visible claim about what a system
currently is. Full text on the first triggering prompt of a session and after
each compaction, a pointer in between.

This exists because of a wrong product claim that went out in a sent email. An
internal note that is wrong gets fixed. A claim in a sent email is permanent.

### `burn-context.sh`

Puts the running cost in front of the model before it decides to fan out. The
bill is calls times context, and neither number is visible at the point of the
decision unless something puts it there.

---

### `owner-facts.py`

Carries forward what the operator STATED, not just what he asked for. Two hooks
already re-inject his prompts and both carry imperatives: one extracts things to
do, another keeps them owed. Nothing carried his assertions. So a fact he stated
in turn 3 is gone by turn 9, and when the agent's own inference disagrees with it
in turn 12 there is nothing left to disagree with. That is the whole mechanism
behind "you ignore what I tell you": the inference does not beat his fact, it
simply outlives it.

Measured over three days before this shipped: he repeated himself 46 times, and
his corrections ran between a fifth and a half of everything he wrote. A worked
case from the same day: he stated a component had been running for weeks, six
turns later the agent asserted it had never run and built a causal story on it,
and one query disproved it. His statement had been correct and in the
conversation the entire time.

It does not make the operator automatically right, and that distinction is the
point: the same day he stated something the shipped binary contradicts. The rule
is not "obey", it is "do not contradict SILENTLY" — quote what he said, show the
measurement, name the discrepancy. Lines he has already had to repeat once are
marked, because a repeat is evidence the agent lost it before.

## Stop

### `stop-justify.sh` &nbsp;·&nbsp; JSON block

Refuses to end the turn with work left on the floor: a dirty tree, a branch with
commits that exist on no remote, an item in the request that never got answered.

The nastiest case it covers is invisible rather than merely forgotten. Every
ahead-of-remote count is computed against the upstream, and that errors on a
branch that has none, so the count never exists and the branch scans as fully
pushed. Four commits across three branches existed on one laptop and nowhere
else, and nothing flagged them. `git rev-list --count HEAD --not --remotes`
needs no upstream and no network.

### `auto-push.sh` &nbsp;·&nbsp; reporter

Reports every checkout left dirty or unpushed at the end of a turn.

It walks sibling worktrees rather than only the directory the session started
in, because the common failure is a session whose working directory is one
checkout while the edits landed in another. A `git status` in the session's own
directory comes back clean and says nothing about the six modified files one
directory over.

### `closeout-shape.py` &nbsp;·&nbsp; JSON block

Refuses a report that answers something other than the question that was asked:
one that opens with method instead of the answer, that hands work back which
the agent could have done, or that offers to do a thing instead of doing it.
Carries a `--self-test`.

### `handoff-gate.py` &nbsp;·&nbsp; JSON block

Refuses a close-out that hands the operator work the agent could have done.
Measured across every close-out in one week: 1,520 items were handed over and
only 9% genuinely needed a human. The rest asked for a decision between two
options the agent itself had generated, or permission for work already
authorised, or an action with an API the agent holds. A prose directive to
decide rather than ask had been in place for weeks and did not move the number,
because prose describes intent while this reads the item and asks whether it was
doable. The list of what genuinely belongs to a human is deliberately short:
credentials, their hands, their knowledge, their money. Backtested over 938 real
close-outs: fires on 28%, with no hit on a genuinely human item.

### `capability-claim-gate.py` &nbsp;·&nbsp; JSON block

Refuses a close-out that declares a named capability dead, disabled or
unavailable when nothing in the turn actually exercised it. The most-repeated
failure in this configuration's history, and the one a prose rule could not
stop: a credit had expired while the lane returned HTTP 200 and a real image; a
probe reported a service disabled because it ran as an identity that cannot
list services; a model was declared ungranted when the call had used the wrong
region and a working caller sat in the operator's own repository; telemetry was
called off because an environment variable was absent while the protocol default
already pointed at the live collector. Each was shipped as fact and each was
wrong. The gate accepts three exits: call the thing and show what it returned,
find a working caller and read how it differs, or say plainly that it was not
verified. Deliberately narrow, so ordinary negative findings ("the file is not
there", "no rows matched") never trip it. Carries a `--self-test` built from
those real cases.

### `person-claim-balance.py` &nbsp;·&nbsp; JSON block

The worst incident in this configuration's history, and the only one whose
subject was a person rather than a system. A session read the operator's
relationships out of message logs and produced thirteen claims about his
character. All thirteen were retracted. Every one was a deficit claim, every one
died in his favour, and none died the other way. He supplied the
counter-evidence himself, usually within one message, without the corpus in
front of him.

Random error does not produce a thirteen-nil split. A generator whose errors run
one hundred percent in one direction is not erring, it is expressing a prior: it
asked a bounded corpus what was MISSING and never what was PRESENT, and every
absence turned out to be an artifact of where the source stopped.

So the hook checks the balance and the coverage, not the claims. Deficit-only is
a finding about the question, not the person. An absence needs the source's
coverage stated, because a partial corpus answers everything and a short answer
is indistinguishable from a true negative.

Written only after a prose note failed. That note already documented four
instances in one week, and recorded that the fourth was committed inside the
document describing the first three. Its own sentence: "Writing the lesson down
did not install it." Building it caught three bugs in itself, each of which
would have let the real incident through: a credit counter that scored "you did
NOT broker" as a positive, a case-insensitive flag that made every word match
the capitalised-name pattern, and a zero-credit test that a single stray
positive sentence walked past.

### `item-coverage.py` &nbsp;·&nbsp; JSON block

Refuses a close-out that never mentions one of the request's items. The shape
hooks above prove an answer LOOKS right; this one proves it COVERS the request,
which is the difference between a well-formatted reply and a complete one. Term
overlap rather than line counting (one line can honestly answer two items), it
judges only items with a real fingerprint, skips pasted content, fires solely
on ZERO overlap, and blocks at most once per turn so it cannot nag. Born from
an operator complaint that only a small part of each prompt was getting done
while every format check passed. Carries a `--self-test`, which caught two bugs
in its own first draft: a wrong store schema that would have made it silently
never fire, and a stopword list that ate the fingerprint it was looking for.

### `context-save.sh`

Snapshots where the work left off so the next session resumes instead of cold
starting. Never blocks. Disable with `touch /tmp/context-save-disabled`.

---

## The rules directory

`rules/common/` holds the always-loaded rules the guards enforce: coding style,
testing, security, agent orchestration, browser hygiene, development workflow,
and a file on learning from mistakes that is mostly a list of them.

They are ordinary markdown and they work in any Claude Code setup. Keep the ones
you agree with. The reason they ship alongside the hooks is the point the whole
repo is making: the rules are the intent, and the hooks are the part that holds
when the intent is inconvenient.

---

Written by Howard Chan. More on agent reliability and cost control:
[linkedin.com/in/howardchan2008](https://www.linkedin.com/in/howardchan2008/).
