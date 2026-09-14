# Slash commands: when to use which

Written 2026-09-07. Counts come from 479 session transcripts covering 2026-05-19 to 2026-09-07, 12,959 of your messages, 10,972 of them substantive.

## What you actually use today, and what you already use instead

COVERAGE FIRST, because the first draft of this section was unfair. open-pstack was installed on 2026-09-07, the day this was written. Fifty-two of the 61 skills below had zero opportunity to be used before today, so "you have not used them" says nothing about you.

Nine skills were genuinely available for months. You use them, constantly, as persistent modes and named tools rather than as slash commands. Counting your own messages that name each one, out of 10,972 real messages:

| You named | In how many of your messages |
|---|---|
| codex | 314 |
| design | 239 |
| guild | 139 |
| lanes | 93 |
| caveman | 87 |
| websearch | 53 |
| playwright | 42 |
| jobq | 26 |
| findmsg | 6 |
| deep-research | 6 |
| wp-ssh-deploy | 5 |

Slash invocations over the same window: 170, of which 149 are housekeeping (`/model` 115, `/autocompact` 22, `/compact` 12). Alongside that you directed 12,959 messages across 479 sessions and routed 680 jobs through the queue since 2026-08-28.

So the pattern is not that you avoid tooling. You drive it in plain language and let modes stay on, which is why the slash menu stayed small for you. What changed today is that 52 skills appeared behind that menu, and those are worth learning deliberately because plain language will not summon them by name.

## The five to start with, chosen from my own error record

These are ranked by the classes I actually fail on this week, not by what reads well:

| Use | Because |
|---|---|
| /pstack:how before any change to a subsystem you have not touched recently | `ignored-what-he-already-said` is 42 incidents and my second most expensive class. Forcing a read of the current system first is the direct counter. |
| /pstack:tdd for any bug with a reproducible failure | `claimed-without-verifying`, 9 incidents. A failing test first makes the claim checkable before I make it. |
| /pstack:interrogate on any diff that touches money, sends, or production | It runs several models against the diff. My worst class, `repeated-defect-after-correction`, is me being confidently wrong twice. |
| /pstack:architect when a change crosses a module boundary | Settles types and shape before code, which is where the expensive rewrites come from. |
| /pstack:babysit once a PR is open | Carries CI failures and review comments to mergeable without you watching. |

## Full reference

Type these in Claude Code. In Codex say the name instead, for example "Use pstack:architect for this design".


### 1. Start here

| Command | Use it when |
|---|---|
| /pstack:poteto-mode | poteto's agent style for concise, detailed responses, deliberate subagents, unslopped prose, simple code, and verified work. Use for poteto, /poteto-mode, or requests to work in this style. |
| /pstack:setup-pstack | Configure pstack's provider-qualified models, per-family requested effort, and parent-owned routes per role. Verifies native and external Claude, Codex, and Grok lanes before writing the ove |

### 2. Understand before changing anything

| Command | Use it when |
|---|---|
| /pstack:how | Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which package owns this\", \"is this t |
| /pstack:why | Use for 'why does X work this way', 'why we picked Y', design rationale, regressions, postmortems, or data-backed thresholds. Discovers available MCPs and queries each evidence category (sou |
| /pstack:blast-radius | Find what a change could break somewhere else before it ships, beyond the diff, and prove the one fact it's safe because of by running real code instead of writing it up. Use for 'blast radi |
| /pstack:figure-it-out | Design an auditable playbook when no narrower one fits: a large migration, an ambitious multi-part change, or work a human reviews after stepping away. Scales rigor to the task, runs a hypot |
| /pstack:recall | Reconstruct your recent working context from your own chat history, live state, and the shared record (user reports, prior fixes, incidents), then hand back a tight current-state brief. Use  |

### 3. Decide the design

| Command | Use it when |
|---|---|
| /pstack:architect | Sketch types, signatures, and module structure before code, then stay in the loop while implementation fills in. Use for /architect, 'architect this', 'design this', or non-trivial work wher |
| /pstack:arena | Spawn N parallel candidates at the same task, pick a base, graft the strongest parts of the losers into it. Use for /arena, 'arena this', 'throw it in the arena', or when one attempt at a no |
| /pstack:interrogate | Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Multiple LLM reviewers c |
| /pstack:swarm | Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration. |

### 4. Write it and prove it runs

| Command | Use it when |
|---|---|
| /pstack:tdd | Use only when the user explicitly asks for TDD, a failing test, or a regression test, OR when the bug has an obvious cheap local test target. Skip when the test path is unclear, expensive, i |
| /pstack:create-verification-skill | Generate a project-local verification skill that drives your app the way a user does — any language, framework, or platform. Use for /create-verification-skill, \"make a control skill for th |
| /pstack:maintain-verification-skill | Periodic pass that keeps a project's verification skill and feature map honest: parallel source readers per feature, one live session driving every feature, at most one PR of proven correcti |
| /pstack:show-me-your-work | Keep a reviewable decision trail for long-running or unattended work: a TSV log with one row per decision (what, why, evidence, result). Local by default; commit it when a reviewer needs the |

### 5. Get the PR merged

| Command | Use it when |
|---|---|
| /pstack:babysit | Watch an open PR — fix failing CI, handle the straightforward review comments, and drive it to a mergeable state. Claude Code analog of Cursor's built-in /babysit. Use after opening a PR whe |
| /pstack:fix-ci | Find failing PR checks, inspect logs or external check links, and apply focused fixes |
| /pstack:get-pr-comments | Fetch and summarize review comments from the active pull request |
| /pstack:make-pr-easy-to-review | Prepare PRs for review by cleaning noisy history, improving PR descriptions, and adding reviewer guidance without changing code behavior. Use for "make this easy to review", "tidy this PR",  |
| /pstack:fix-merge-conflicts | Resolve merge conflicts non-interactively, validate build and tests, and finalize conflict resolution |

### 6. Clean up what exists

| Command | Use it when |
|---|---|
| /pstack:deslop | Remove AI-generated code slop and clean up code style |
| /pstack:unslop | Cut AI tells from any writing. Must always apply. |
| /pstack:no-comments | Spawn the comment-sicko subagent, fix accepted findings, and offer encodings for claimed constraints. |
| /pstack:thermo-nuclear-code-quality-review | Run an extremely strict maintainability review for abstraction quality, giant files, and spaghetti-condition growth. Use for a thermo-nuclear code quality review, thermonuclear review, deep  |
| /pstack:typescript-best-practices | TypeScript best practices. Use when reading or editing any .ts or .tsx file. |
| /pstack:technical-writing | Layered technical-writing standard: Diátaxis structure, Google developer style sentences, STE instruction rules, Global English syntax. Use for /technical-writing or when writing or reviewin |

### 7. Learn from the run

| Command | Use it when |
|---|---|
| /pstack:reflect | Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect. |
| /pstack:what-did-i-get-done | Summarize authored commits over a user-specified time period into a concise update |
| /pstack:teach | Explain a body of work plainly so a person actually understands it. Runs the `how` and `why` skills and weaves what they find into one clear explanation. Use for 'teach me this', 'help me re |
| /pstack:automate-me | Use for \"automate me\", \"create/update/refresh my -mode skill\", \"turn/capture my preferences or working style into a skill\", or wanting agents to follow how the user works. Drafts or re |

### Principles, 21 of them

These are reference material the workflows pull in. You do not need to call them by hand. Names all start with `/pstack:principle-`, for example `principle-prove-it-works`, `principle-fix-root-causes`, `principle-guard-the-context-window`.

### Your own skills, already installed

| Command | Use it when |
|---|---|
| /deep-research | Multi-source deep research using the websearch CLI (fused Exa probes) plus Click MCP for social, local, and people data. Searches the web, synthesizes findings, and delivers cited reports wi |
| /design | Comprehensive design skill: brand identity, design tokens, UI styling, logo generation (55 styles, Gemini AI), corporate identity program (50 deliverables, CIP mockups), HTML presentations ( |
| /playwright | Use when the task requires automating a real browser from the terminal (navigation, form filling, snapshots, screenshots, data extraction, UI-flow debugging) via `playwright-cli` or the bund |
| /wp-ssh-deploy | > |
| /everything-claude-code | Development conventions and patterns for everything-claude-code. JavaScript project with conventional commits. |

### Caveman

| Command | Use it when |
|---|---|
| /caveman:caveman | > |
| /caveman:caveman-compress | > |
| /caveman:caveman-stats | > |
| /caveman:cavecrew | > |

## Cost

pstack adds about 4,588 tokens to every session for the skill index, plus 1,259 characters of session-start instruction. Skills load their full text only when invoked. Multi-model skills (arena, interrogate, swarm) spend the Codex and Grok allowances, not only Claude.
