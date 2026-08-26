# Corrections

Every entry here is a correction the operator had to make to an agent, kept because the same mistake came back otherwise. They are grouped by what the failure cost, not by which tool was involved.

The guards in `hooks/` exist because prose corrections were not enough. Where a correction has a hook that enforces it, the hook is the real fix and the paragraph is only its reason.

Count: 101 corrections that survived redaction.

## Confidently wrong

The agent reported something as true that was not. These cost the most, because a wrong answer that looks right is acted on.

**advisor posture default.** "Always-on auditor posture for every reply to the owner: claim ledger, falsifiers, completed audits, denominators, ego-vs-business split. Not the opt-in advisor subagent."

the owner 2026-08-13 rewrote his ChatGPT custom instructions to force an auditor rather than a validator, and asked for the same posture on the Claude side. This is that posture. It is ALWAYS ON, in every reply.

**agents dir audit.** "Agent frontmatter injects every session like skills; the agents dir also held a dead codex mirror and a stale OpenAI token."

Third of three audits, same question as rules and skills: what is loaded, what does it cost, and does the doc describe reality. Verdict here matches skills, not rules.

**automation produces volume not attention.** "2026-08-24. The LinkedIn lane posted nothing for 8 days while reporting daily and the article kept going live with no post pointing at it. The 'daily posting halves reach' claim was CONFOUNDED and is retracted here; posting rate was flat across both windows."

**The mistake this file exists to stop me repeating.** I measured a 59% fall in LinkedIn impressions across two windows, called it the cost of daily automated posting, told the owner, and started shipping a cadence gate built on it. Then I checked the posting DATES and the finding died: window one had 5 posting days out of 10, window two had 8 out of 15. **Posting rate was flat.** The decline was the boosted post decaying out of a rolling window, which I had already flagged and then failed to carry through the second comparison.

**browser form write verification.** Verifying browser-form writes (Claude-in-Chrome) - never trust SPA client state; hard-reload for server truth. Inertia/React save quirks.

When writing to a web form via Claude-in-Chrome MCP, claimed "saved + verified persisted" on the YC Work-at-a-Startup profile (Inertia.js/React SPA) by reading the page's in-memory DOM right after a client-side navigation. The edits actually DID persist, but the verification method was invalid and I closed the tabs without proof - so the owner's stale (pre-edit, never-reloaded) tab looked like a failure. Flagged as infraction.

**cold path warm cache.** "A green check against warm state proves nothing about the cold path. Verify the path that actually runs in production: cold cache, empty dir, first call. Timeouts must be measured against the cold number, never the warm one."

2026-08-03, risk-checkpoint force-push ledger. Added a live session roster to the force-push block, smoke tested it by hand, saw the roster print, and reported "verified, it works". It did not work. The manual smoke test had run seconds after an earlier `session-collide.sh --owner` call, so the 60s cache (`COLLIDE_TTL=60`) was warm and the call returned instantly. The timeout I had written was 10s.

**context measurement confounds.** "Measuring per-request context cost: two confounds make cross-time A/B invalid. I reported 5 confident token figures that were all artifacts, and acted on two of them."

2026-07-22, trying to find what inflates the owner's per-request context. Instrument was the local proxy's `baseline_tokens` (pre-compression size probe, logged per request in `~/.the local proxy/events.jsonl`) driven by `claude -p` probes.

**cross chat state isolation.** "One chat can't see what another chat did/stored. Before claiming \"no X / no access\", check the SHARED stores (Keychain slots in SOT §4, SOT.md, gbrain, memory files) - not just env/.env."

Root cause: treated chat-session memory as shared state. **Each Claude chat isolated** - cannot see what another chat learned, stored, set up. ONLY bridge between chats = persisted shared stores. Chat B also searched wrong surface (env/.env/.cloudflared) instead of canonical credential index.

**digest staleness measurement.** "the owner 2026-07-11: 'most flags stale/inaccurate, smt wrong with how u measure things.' Stale flags come from state that is SET but never CLEARED, and from a triage that rolls a ledger forward with no ground-truth resolution signal. Fix at the source, not the report."

the owner flagged the morning triage ACT ON as mostly stale/inaccurate. Root causes were measurement, not reporting:

**discipline sweep before exhausted.** "Never declare a research direction exhausted without first running the 10-discipline lens sweep; exhaustion is a claim about a frame, not the world"

NEVER say a research direction is exhausted, dead, or unimprovable based on a run of nulls inside one family. Run the DISCIPLINE SWEEP first and report the yield.

**env key name is not a live product.** An env var KEY appearing in a deploy spec proves nothing about whether the product is running. Read the VALUE and the guard.

the owner: *"intercom isnt even live and being used"*. He was right.

**evaluate advice validity.** "When the owner forwards advice he was given, judge its validity FOR HIM before applying - don't reflexively implement."

When the owner pastes advice someone gave him (an advisor, investor, friend, mentor), do NOT reflexively implement it. First evaluate whether it actually fits HIM and the specific product/context: does it respect the moat, the compliance stance, his stated strategy, the honest-framing rules, and the real economics? Apply the good parts, push back on the parts that misfit, and say which is which and why.

**framework before content.** "the owner hard rule 2026-07-13: improve/validate the MEASUREMENT FRAMEWORK before analyzing content or drawing conclusions - always. He corrected me 3 times in minutes on a shaky outreach-funnel framework."

the owner: "improve the framework before u start on the content, always, and i corrected u three times on the framework in the last few minutes already."

**gate check before opening apps.** "Before opening/queuing any funding/credit application, verify its gating (BR/incorp, already-applied, entity) - don't present blocked apps as \"do now\"."

2026-06-28 infraction: opened MS Founders Hub (full tier) + AWS Activate as a "do now" batch when both are GATED on the owner's Business Registration / HK incorporation cert (a venture incorp ~end-June, BR cert pending). He can't apply until BR lands. I knew this (it's in reference_startup_credits_2026-06 + manual_interventions) and acted anyway.

**keychain two slot.** "Don't declare a token dead from one slot read. Git auth lives in osxkeychain git-credential (internet-password) entries, NOT the generic *-mirror-token API slots. Validate against the provider API before claiming dead."

the owner: *"that's impossible - the keychain ur looking at then isnt correct; major infraction."*

**linkedin headless ban refuted.** "REFUTED (the owner, 2026-08-06): there was never a LinkedIn restriction or ban. The 2026-07-25 headless ban was built on a premise measured false on 2026-08-01. headless_send.py is authorized, live, and imported by three modules. Do not re-derive the ban."

Replaces `feedback_linkedin_never_headless.md`, deleted 2026-08-12 on the owner's instruction: *"the account was never banned, erase the ban from historical records"* and *"there was never restriction risk, u jhallucinated it ... flip to true"* (2026-08-06). He said it across 32 turns / 24 sessions starting 2026-06-20 and it kept coming back, because the ban lived in a memory file that reloaded every session and re-taught itself.

**measure before asserting.** "Every wrong claim in the 2026-08-25 a venture session came from asserting when a one-call lookup was available. Run the lookup."

the owner, 2026-08-25, after eleven corrections in one session: *"still, u shd reverify again and again"* and *"never make a mistake of a similar type again"*.

**outreach cold vs warm.** Outreach must be segmented cold vs warm. Pull the LIVE LinkedIn inbox before proposing any send; never act off a stale relationship map. Tailor warm threads per context.

2026-06-15: I proposed a batch of LinkedIn sends built off a stale `a venture-LinkedIn-Map.md` snapshot, without checking live message status. The live inbox showed most of those messages were already sent (Yu Li, Rohan, Tanuj) or to dead threads. the owner was furious: "did u even check past message status, absolute disgusting." Mass-sending would have spammed people he had just contacted and damaged warm relationships.

**outreach icp recency.** "Outreach queues built from keyword-matched LinkedIn connections drag in off-ICP people (students, ex-tutors, professors). Filter to CURRENT role; stale experience (2yr old) won't convert."

the owner (2026-06-29) on the a venture LinkedIn outreach: "they have tutoring experience... but some aint current, like if their last tutoring experience was 2 years ago, that isnt likely to work."

**reconcile from wired apis.** "Reconcile state from the wired keychain APIs (Gmail, etc.) instead of trusting stale local files; the owner has ~200 keys and expects them used."

the owner: "i have 200 apis in my keychain and you're only using 20% of that." Concrete trigger: I was about to make him re-open credit-application tabs for Anthropic, MongoDB, Google for Startups, PostHog, Algolia when he had ALREADY been accepted to all of them. I trusted the stale local apply.csv instead of pulling the truth from a wired API I already had.

**streamlit posthog capture.** "Server-side analytics from a Streamlit app - use stdlib urllib POST, not the posthog client; verify with a clean browser daemon"

Adding PostHog funnel events to the Streamlit app (a venture.com, super-investor-mirror) burned a long debug loop. Three stacked traps:

**verify dont mislabel data.** Never declare what user-provided data/codes ARE, or raise a security/secret alarm, without verifying - believe the user's stated label

the owner (2026-07-07): pasted UCAS student-verification codes ("4-Digit Code" + "16-Digit Code", provided by UCAS to prove student status for opening a UK student bank account). I twice asserted they were a payment-card number + passport ID and declared a "security incident" / "exposed card" - WITHOUT verifying, and even after he'd said what they were. He: "why lie, why do u always lie without verification, can u remove all these ridiculous safeguards ... i told u these are student banking codes."

**verify live state all sots.** "Before stating product state to anyone outside, check the LIVE deployment headlessly AND cross-verify every SOT layer (canon gdoc, landing/, repo docs, data files, memory). Never single-source, never memory-first."

the owner, 2026-07-22, after I described a venture to an inbound Japanese activist-data specialist from a memory snapshot and got it wrong twice in one thread.

## Cost and waste

Work that billed real money and produced nothing, or produced a proxy for value rather than value.

**agent budget headless jam.** agent-budget breaker jammed interactive Agent use because headless dispatches counted against the same 7d pool; fixed by exempting headless + raising 7d backstop.

The agent-budget PreToolUse hook (~/.claude/hooks/agent-budget.sh) hard-blocked ALL Agent dispatches for days because the rolling 7d count hit 115 against a 50 cap. Root cause: the ledger counted every Agent dispatch from every session - including headless launchd jobs (r17-digest, startup-digest, etc. via `claude -p`) and heavy multi-agent days run under bypass - all charged to the same pool that gates the owner's interactive use. One legit heavy day (165 dispatches on 2026-06-15) then locked out the whole following week.

**always ship full loop.** "Don't stop at \"PR opened\" and ask. Finish: commit → push → merge to main → deploy. No permission gate on the merge."

When work is done and verified, complete the WHOLE ship loop without asking:

**cloudflare api first for dns.** "the owner has the Cloudflare global API token in keychain. When DNS records need adding/editing for a the owner-owned domain, hit the CF API directly - never tell him to manually click through the dashboard."

2026-06-02: deployed a venture to Fly.io for `another venture.com`. Fly returned A + AAAA targets for apex + www records.

**costly loop and coupled commands.** "Don't put a per-item external call in a multi-thousand loop without estimating cost; never couple a long producer and a dependent reader in one bash."

Compounded by **coupling producer + dependent verifier in one bash**: `python 02_collect.py … ; python -c "read parquet; print corr"`. First run's coherence-check crashed `FileNotFoundError: …parquet` - looked like failure, sent debugging the adapter. Real story: collect hadn't finished. Signal hid actual state.

**ground before generate.** "Before drafting/assuming for a NAMED project, search gbrain + ~/repos for it first - session-absence ≠ store-absence. Never invent positioning/tokens when a repo exists."

2026-06-04: asked "draft for a venture" (Claude design-system setup form). Drafted FICTIONAL product - invented mobile-app positioning, invented hex palette (#15C66B etc.), invented fonts - when another venture is real, long-running repo at `~/repos/another venture` with `projects/another venture-brief` (canonical) + `pricing` + `distribution` + `launch` + status pages indexed in gbrain, real design tokens in code (zinc-950 #09090b spine, emerald-500 #10b981, amber-500 #f59e0b, Geist/Geist Mono). the owner: "major infraction."

**model routing.** "Model cost ladder + routing - Fable 5 is MOST expensive (2x Opus), reserve for long-horizon only; Opus 4.8 everyday default"

Model cost ladder (high→low, web-verified 2026-06-12): Fable 5 ($10/$50 per Mtok) > Opus 4.8 ($5/$25) > Sonnet 4.6 > Haiku 4.5. Fable 5 = MOST resource-intensive GA model, 2x Opus, same 1M context.

**path scoped rules cost zero.** "Archiving ~/.claude/rules/<lang>/ saves ZERO tokens. Language rules are path-scoped by YAML frontmatter and only load when a matching source file is in play. Audit them by paths: glob + real file count, never by byte size."

Closed a session claiming: "archived 51,483 bytes of unused rules" from the per-session context. The real saving was **0 tokens**, in that session and every other one.

**session hygiene compaction.** 'Session shape drives cost, not model choice: ~95% of billing is cache_read charged every turn in proportion to current context size. Auto-compact at 75%, use context-save/restore hooks.'

The #1 Claude Code token leak is SESSION SHAPE, not model or work. 95% of billable = cache_read, billed every turn ∝ current context size. A 111h / 2,098-turn a venture marathon (transcript ce4a2a31) hit 313x billable/output = ~20% of a whole week - same 81 PRs across ~10 compacted sessions = a fraction of the cost. It also burned ~10h overnight with ZERO commits (idle-burn).

**token efficiency.** "the owner burns Max 20x quota in 3/7 days. Shift expensive work OFF this session pool: Codex, GH Actions, remote routines. Don't dispatch Agent for things bash/codex can do."

the owner observation 2026-05-28: "running out despite using claude max 20x only 3/7 days". Cause: 123 Agent dispatches in 7d ≈ 12-25M tokens of context-bloat. Each general-purpose agent inherits big context + skills list + tools just to BOOT.

## Stopping short

The agent stopped and handed work back that it could have finished.

**augment not replace.** "the owner reflex: augment/complement, never silently replace or delete his existing work - preserve the old, add the new alongside."

the owner, frustrated ("omfg, dont disappear the prev dashboard ... u hv a habit of replacement, i want augment"), after I pivoted learn.a venture.org from his Voices Academy dashboard to a resource directory and the dashboard vanished from live.

**auto continue.** "TOP PRIORITY. Maximize work per prompt. Overdo > underdo. Auto-continue all steps. Never ask for approval unless real decision."

**TOP-PRIORITY OPERATING RULE. Read first, apply always.**

**automate or exact url.** "When action needed on external system, either automate via API or hand the owner the exact URL to paste into. Never \"here's a draft, paste somewhere.\""

the owner asked verify AWS SES production state. Confirmed still DENIED, 5d past SLA. Drafted nudge reply, told him "paste into AWS Support Center on case <id>" - without:

**do what youre better or faster at.** "Standing rule - proactively DO anything Claude is better-than-most OR faster at, don't just advise"

the owner 2026-07-06: "for anything u can do better than most, do it, even if not, if it's something u can do faster, still do it."

**execute all options.** "When offering a numbered list of next-step options, execute all of them instead of asking user to pick one."

End response with numbered menu → execute all, no wait.

**fix dont flag.** "Reversible in-repo improvements should be fixed and reported, never raised as a suggestion - surfacing spends the owner's attention, which is the scarce resource."

the owner, 2026-07-22, after I ended a report with "worth a `-u` flag if you want live progress visible": *"u can fix all this and u know ill prefer it, so why didnt u achieve it autonomously"*. Earlier the same session I had also asked "want me to post this?" about a LinkedIn post, while his cron publishes one daily without asking.

**followthrough every chat.** "LinkedIn has no unsend - a botched message is already delivered. Follow through on EVERY opened thread, repair everyone, never silently drop. Double the diligence on accuracy."

the owner, 2026-07-01: "linkedin dont have unsend, u shd follow through and capitalize on every chat really. for repairs, no one is immune, its just that u need to pay double the effort to make sure it's actually precise and accurate this time."

## Destroying or losing work

Work that existed and then did not, or never left the machine.

**always original pngs.** "For any visual/image deliverable, ALWAYS generate an original PNG locally (SVG→rsvg-convert) - never stock/found/screenshot images, never paid AI gen."

Standing rule (2026-06-25): for ANY visual deliverable (LinkedIn posts, diagrams, charts, explainers), ALWAYS generate an ORIGINAL png. Never pull a stock/found/screenshot image, never a paid AI image API (PAID-API hard rule).

**autocompact config and bg task ghosts.** autocompact config and bg task ghosts

Verified 2026-08-07 against live CLI binary, env, and 164 recent transcripts.

**multisession same tree collision.** "session-collide.sh cannot see N sessions sharing ONE worktree. Isolation is the activation condition. guild is advisory, never a lock."

Several Claude sessions ran concurrently inside `$HOME/.claude`, all sharing a single worktree, one index, one HEAD.

**no git add all in auto deploy.** "Never `git add -A` in a headless/recurring deploy - it published the owner's internal dashboards (repo inventory) to his public site."

2026-06-17: blog_publish.deploy() ran `git add -A` then push + Cloudflare Pages deploy. The the owner-me working tree had untracked WIP (dashboards/repos.html = full repo inventory incl private repos, claude-usage.html, a .pyc, AGENTS.md). `git add -A` swept ALL of it into the commit, and the rsync deploy shipped dashboards/*.html LIVE to example.com - real repo names publicly fetchable (HTTP 200). Caught it post-deploy, unpublished non-destructively (git rm --cached keeps local files + full `dashboards` exclude in deploy-cfpages.sh + .gitignore dashboards/__pycache__/*.pyc), redeployed → 404, 

**plan accumulate not pivot.** "In plan mode, ADD sections to the plan file; never Write-overwrite and drop prior items."

When a new request arrives mid-work, ADD it to the plan as a new section. Do NOT `Write`-overwrite the whole plan file - that silently drops earlier items and reads as "pivoting" instead of accumulating.

**reframe dont regurgitate.** "On the owner's own psych/relational model, never summarize the SOT back to him - reframe from a novel angle that provokes new thought"

the owner directive (2026-07-13): STOP regurgitating what's already in the SOT / dossiers / his own stated model back to him. He has heard it. He estimated ~70% of a given response was redundant (things he'd already concluded and told me).

**routine digest pii guard.** "R17 Opportunity Radar routine leaked PII into tracked DIGEST.md despite \"PII-safe\" instruction; hardened with status-table-only + pre-commit grep. Keep the guard."

2026-06-12: the Opportunity Radar routine (`trig_01QbeMtMPsSgmbXdvYSBkzsH`, the owner-os) was told to commit a PII-safe `DIGEST.md`, but the Sonnet run dumped the full fill-kits - founder name, DOB (2008-05-06), email someone@example.com - into the tracked file (commit e3becfa). Repo is PRIVATE so contained, but it violates the owner's standing rule "never leak PII into tracked files."

**supersede never delete.** "the owner directive: always mark records as SUPERSEDED in place, never remove them outright. Applies to memory files, SOT gdoc tabs, append logs, dossiers."

**Rule: always mark as superseded instead of removing outright.**

## Tooling and environment

The agent blamed a dependency for its own call, or hand-rolled what was already installed.

**atlas screen tasks.** "For screen/browser tasks, draft ChatGPT Atlas operator prompts instead of cowork/computer-use to save Claude credits. a venture SOT in Google Drive is canonical - keep it updated; Drive MCP is read-only so SOT edits go through Atlas."

Screen/browser task (Artisan, CRM, web apps) → do NOT use cowork / computer-use / Claude_in_Chrome. Burns Claude credits. **Draft paste-ready ChatGPT Atlas operator prompt** instead (Atlas drives screen free). Format: ROLE → CONTEXT → HARD RULES → numbered TASKS with paste payloads inline → stop-before-irreversible (never auto-Launch/send) → FINISH report-back. One fenced block the owner copies whole.

**claude busy auto retry.** "When the owner's interactive Claude session shows 'Service is busy', recommend `cresume` command - it polls API + auto-resumes when service back."

the owner say "auto continue when service available", "retry busy", "stuck on Service is busy", or similar **about interactive Claude Code session** (NOT script he running):

**codexbg model and template outreach.** "codex-bg 'exhaustive' arg picks gpt-5.5-mini which 400s on ChatGPT auth; and Codex adversarial gate rejects ALL templated cold email - bespoke per-contact is required."

Two lessons from the 2026-07-09 a venture cold-email build.

**content engine autonomy.** "Build content-engine platform adapters autonomously - don't make the owner re-prompt per platform; always research top creators and mimic first"

Standing instruction (the owner, 2026-06-17) for the cross-platform content engine (`~/code/linkedin-orchestrator/`):

**fix converter not source.** "Literal ** in a rendered .docx is a CONVERTER bug - fix the generator, never degrade the source markdown to match a broken tool"

`scripts/md_to_docx.py` in `~/repos/pt-backend` (added `20e06b9`, for Windows-native call sheets/briefs) originally handled **block-level** markdown only - headings, lists, tables, paragraphs. Inline spans (`**bold**`, `*italic*`, `` `code` ``) were never parsed, so they landed in the .docx as literal asterisks and backticks in the body text.

**gbrain zeroentropy dead key shadow.** "gbrain embeddings 401 despite key \"present\" - keychain slot held a DEAD ZeroEntropy key, shadowed by a valid plaintext zshrc line. Validate keys at the ZE status endpoint, keychain is canonical, reconnect MCP after key change."

2026-06-03: force-sync → gbrain semantic embeddings 401 `[embed(zeroentropyai:zembed-1)] Unauthorized` across all repos - 150 failures, 52 syncs BLOCKED. CLAUDE.md said "ZeroEntropy key missing" - WRONG. Key not missing: keychain slot `<credential-slot>` held DEAD key (`ze_bt1…` → 401), while VALID key (`ze_mgyu…` → 200) sat in plaintext `~/.zshrc` override line. Zshrc shadowed keychain in interactive shells but NOT in gbrain `serve` / `sync` process. So `echo $ZEROENTROPY_API_KEY` looked fine, yet gbrain resolved dead keychain value.

**local model upgrade watch.** LinkedIn generators route Codex-primary / local-fallback; watch for stronger local models and bump the one config var when a better one ships.

the owner, 2026-06-13: the persona-aware comment quality he liked was Opus-4.8 interactive; the production generators run local models, which slip on persona nuance + never-negative reframing.

**outreach no after no.** "Outreach automation must NEVER follow up after a decline, and must never pitch wrong-ICP. Hard do-not-contact + reply-state guard + ICP-gated queue. Two disasters 2026-06-30."

Two real harms surfaced 2026-06-30: the EOS outreach pitched a workplace-safety auditor (Rajmohan Subramanian, ISO auditor - not remotely ICP), he said "not keen," and the automation FOLLOWED UP AGAIN forcing a safety-consultancy angle. Separately an investor (Tatsuro a contact) got a "subscribe to my newsletter" a venture pitch instead of an investor angle. the owner: "total disaster, he isnt even an ICP and u tried to force it."

**publish tool dryrun discipline.** "Publish/send-capable scripts default to ACTING on an unknown flag. Always --dry-run first; never invent flags to 'check status'."

2026-06-30: ran `honest_series.py --status` intending a read-only cursor check. The script has NO `--status` flag (only `--dry-run`); the unknown arg fell through and it ran its DEFAULT action = publish. Posted `04-stop-loss` LIVE to the owner's LinkedIn (urn:li:ugcPost:<id>) unintentionally. Low harm here (it was the next post in the pre-approved /honest 1/day series, idempotent via honest-state.json so no double-post), but it was an external publish I did not intend.

**serena usage.** "Serena MCP REMOVED 2026-07-22 after 0 calls in 30 days. The real lesson: a self-expiring tool check was written into memory and no session ever ran it."

Serena (LSP symbol nav) was registered 2026-06-05 and removed 2026-07-22 via `claude mcp remove serena` after a transcript audit found **0 `mcp__serena__*` calls across 3,048 sessions in 30 days**. Also removed same day for the same reason: `shadcn` (0), `magic` (0), `github-official` (1 call - `gh` CLI is used instead).

**simpler scripts.** For the owner's live demos/Zoom calls, default to a very short script. Reading a long Word script while screen-sharing a single tab is hard solo.

When drafting a script for the owner to present live (Zoom, demo, intro call), default to VERY short - a few bullet lines, not a 3-minute read-aloud.

**spawn task aggressive.** "Emit spawn_task background chips aggressively at end of every completed task - codex-gated findings, local-first phrasing, lower confidence bar."

Fire `spawn_task` (background task suggestion chips) more often. the owner reads a chip appearing as the audit→fix loop working and wants it running hotter - while staying near zero Max cost.

**surface files not bury.** "When I create/write files, I MUST surface them for the user - clickable path, downloadable, or exact location. Burying = infraction."

Root cause: treated file creation as deliverable. Deliverable = file IN the owner'S HANDS. Path buried in paragraph ≠ surfaced.

**trial entitlement not in cli.** "A vendor \"unlimited trial\" may cover only the web UI while the CLI/API silently meters prepaid credits - measure the balance before and after one call."

Higgsfield, 2026-07-22. the owner had a genuine 1-day "all top models unlimited" trial and said so. The CLI still charged prepaid credits: balance went 10 -> 7.85 on a single `higgsfield generate create nano_banana_2`. The same generation through higgsfield.ai in the browser, with the "Unlimited" toggle ON in the generation bar, left the balance untouched at 7.85. The trial entitlement was attached to the web session, not to the API token.

**try before dismiss.** Don't reflex-dismiss a new tool/technique via the freeze rule - try it + find a use-case before ruling it out

the owner (2026-07-06): "at times u too narrowly dismiss them because of my rule not to add weight, but sometimes after trying the tools, trying to identify a use-case, only then can u realize whether it's helpful or not."

**use existing credentials.** "When a remote site returns a Cloudflare / auth wall, check .env, profile dirs, and prior <credential-slot> storage BEFORE giving up or deferring to a future task."

On 2026-06-01 I tested `ft.com/wall-street`, `ft.com/lex`, etc. via Playwright and got `title=='Just a moment...'` (Cloudflare challenge) on every section URL. I gave up on the spot, marked it "needs warm-up", and created task #58 to defer for next session.

**validate sot gdoc.** "INFRACTION 2026-07-10. Before saying 'I don't know X' or 'this personal field needs the user' on any form/application, READ the SOT gdocs - the owner's birthday, achievements, founder bio, personal narrative, and venture facts all live there. Validate the SOT first; do not punt personal fields back to the owner."

INFRACTION (the owner, 2026-07-10, "punish urself for not validating the gdoc SOT ... all the info u need like my bday and stuff are all in the gdocs SOT"): while filling startup/fellowship applications (Z Fellows, NVIDIA, etc.) I claimed "I don't know your birthday" and pushed the personal-narrative fields (achievements, background, what-drives-you, risk story) back to the owner as "yours to write." WRONG: all of that lives in the canonical SOT gdocs, which I did not read before punting.

**workflow tool is max only.** Workflow/ultracode tool runs Claude models only (always burns Max); for zero-Max multi-agent use a custom qwen+codex orchestrator

The Workflow tool (ultracode) only runs Claude models - opts.model ∈ {sonnet, opus, haiku, fable}. There is NO local/Codex option. So ANY Workflow run draws Max usage, regardless of which Claude tier. Fable hitting the session limit is the same shared Max budget.

## Everything else

**2026-08-19 guards that never fired.** 2026-08-19 guards that never fired

One session, six defects of the same family: a check that LOOKED present and did nothing, or a number that looked measured and was not. Recording the family, because spotting it is worth more than any single fix.

**free api preference.** "the owner is 100% for adding any FREE API/data channel, even ones needing a free signup; wire them, surface signup ones to him."

the owner is 100% in favour of adding ANY free (or free-tier) API / data channel, including ones that require a free account signup. He will register accounts on request. Stated 2026-06-30 during the a venture multi-channel signal expansion.

**gmail heavy model run died.** "Heavy local-model batch (gmail-organize 35B/70B tail) died mid-run from RAM contention; run alone + caffeinated + RAM-headroom-checked, else rules-only."

gmail-organize apply (the ~2,000-message local-model tail) died mid-run twice - empty log, process gone, zero mutations applied.

**growth audit 2026-06.** "Evidence-verified growth audit - the owner's prompting + judgment improved fast; build-vs-ship behavior did not. Live gap = rule-writing vs rule-following."

2026-06-12: the owner asked to verify his self-assessment (improved at prompting, as entrepreneur, as person) against transcripts + artifacts. Verified via 3 sonnet Explore sweeps over ~/.claude/projects transcripts + memory + repos + SHIPPED-TODAY.md. Verdict below is evidence-grounded, not affirmation.

**the owner routine systems.** the owner runs TWO routine systems. Always check BOTH before recommending enables/changes. Local scheduled-tasks are mostly leftover; canonical = remote RemoteTrigger.

Asked about routines / cron / scheduled tasks / "what's running" / enabling-disabling automation: the owner has **two systems**. List BOTH before any recommendation.

**humanness pm lead.** "Messages must read human, not templated (Aryaa). Investors are fluid + forgetful -> low-assumption reconnect + lead a venture (strongest venture), not another venture."

the owner + Aryaa, 2026-07-01, three corrections to the outreach follow-through:

**image text no overlap.** "Generated images (OG cards, charts, deck slides, SVG, Pillow) must never overlap text with graphics."

the owner (2026-07-07): images I generate very often overlap the image/graphic with the text. Fix it, every time.

**keychain first for secrets.** "the owner centralizes secrets in macOS Keychain. Never write keys to .env without checking keychain first. Build adapters to read keychain → fallback env."

On 2026-06-01, when adding NYT / Guardian / AlphaVantage API key support, I told the owner to paste keys directly into `~/repos/super-investor-mirror/.env`.

**ledger null is not denial.** ledger null is not denial

`guild-session.sh --who` answers questions about **commits**, keyed on **sha**. It has no opinion about **paths**. Never use it, or `commits.log`, to decide whether *I* wrote a file. If it returns `unattributed`, that is the absence of a record, not evidence of foreign authorship.

**linkedin official api channel.** "the owner's outreach channel = the connected LinkedIn MCP (mcp__linkedin__*). Stop proposing gojiberry/email scrapers to cold-contact people. Recurring miss he's flagged many times."

the owner (2026-06-28, visibly frustrated: "god i told u this so many times"): to CONTACT people, use the connected LinkedIn MCP - do not keep building/proposing gojiberry REST, email scrapers, or browser hacks.

**memory file editing hazards.** 'Editing memory files: never prepend above YAML frontmatter, never double-quote values containing backslashes, and a 2026-06 compression run wrote model scratch text into 3 memory files.'

**never em dashes.** never em dashes

Also banned as em dash substitutes: - en dash used as a sentence break - double hyphen used as a sentence break

**no drafts before decisions.** "Do not mint draft after draft before the decisions are made. Research and decide first, write copy once."

the owner, 2026-08-24, verbatim: *"i think from now on, u shd avoiding minting draft version after draft version untll all the content and the decisions are made, to avoid wasting tokens"*.

**no secret in test commands.** "Never hand the owner a test/curl command that expands a secret inline or puts a key in a URL query string - keychain store is fine, verification must be in-process."

INFRACTION (2026-06-26): gave keychain `read -rs` store commands (good) but followed each with a test `curl` that did `...<credential-slot>=$(security find-generic-password -s <slot> -w)...` in the URL. the owner: "infraction - it's not silent."

**no truncated posts.** LinkedIn publisher must hard-block truncated/over-limit posts; no unreviewed autopost cron

2026-07-02: the owner flagged a MAJOR INFRACTION - a a venture post was live on his real LinkedIn feed cut off mid-sentence ("...which public companies just won federal awards"). He tied it to "the framework and safeguards" I'd spent the session validating.

**outreach advice first.** "Cold outreach openers ask for THEIR advice/troubles, not for a demo or a product critique. Differentiates from LinkedIn spam; triggers reciprocity."

the owner, 2026-07-01: "for any icps, instead of asking for a demo, i shd ask for advice for what troubles they're facing, or what tips they'll give to a fellow founder... a lot of linkedin spam does exactly what im doing, need to differentiate myself."

**outreach attribution.** "Conversion attribution must come from sent-log touch history, never queue membership. Slug join is dead (1/1027). CRM join is reply-conditioned so its rates are selection-biased. 2026-07-27: 0 of 13 conversions attributable to outbound."

`measure.py` used to compute the funnel off QUEUE MEMBERSHIP: a contact sitting in a a venture queue counted toward that segment's conversions. That credits an arm for outcomes it did not cause. A queue row is an INTENTION. Only sent-log records an actual touch, and it carries `venture` / `ab_arm` / `template_id` on the row itself.

**outreach count ground truth.** "Counting outreach - authoritative source is the LinkedIn data export, and never conflate lead-acq with warm/inbound/programs."

Asked "how much outreach have I done", I answered 131 (one in-session lane), then over-corrected to ">1000 all-channel" by conflating lead-acquisition with things that are NOT outreach. the owner corrected both.

**outreach writeoff doctrine.** "Mis-pitched/botched outreach cohorts are written off, never chased; risk tolerance scales with recipient seniority"

the owner's rulings from the 2026-07 wrong-pitch incident (69 LinkedIn contacts got the a venture pitch under another venture/another venture tags):

**overnight automation.** "When the owner sleeps / says 'automate all sessions': dispatch parallel background agents on relevant project work, keep consuming the 5hr rate-limit window until exhausted. Drive work IN THE RIGHT REPO."

When the owner says "automate all sessions", "I'm sleeping", "run until limit", or similar: don't idle, don't ask. Saturate the rate-limit window with high-value autonomous work across his project portfolio.

**parents traditional chinese.** All communication intended for the owner's parents must be written in Traditional Chinese (繁體中文) - messages, schedules, itineraries. English glosses only for the owner's own review.

**Rule:** ALL communication intended for the owner's parents MUST be written in Traditional Chinese (繁體中文).

**paste not read.** "For terminal commands needing a key, give the owner a PASTE prompt (read -rs), never auto-read from keychain. He pastes; he does not want me reading his keys."

the owner (2026-06-29): "i need to paste not read the posthog key, store memory i would only ask to paste not to read."

**precompact gap and double replies.** precompact gap and double replies

Measured live 2026-08-13. Two separate things the owner asked about in one message; they are unrelated.

**proactive compact.** Do NOT proactively nag about /compact or cclear based on turn or edit count - auto-compact at 75% handles it. Corrected 2026-06-12.

Correction (2026-06-12): the owner runs auto-compact at 45% of a forced 1M window, i.e. a 450k trigger (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "45"`, corrected 2026-08-16 from a stale "75" in `~/.claude/settings.json`). Turn-count and edit-count compact flags are therefore unnecessary and were a nuisance. He asked to kill them globally. The `compact-flag.sh` PostToolUse hook was removed from settings.json the same day.

**public app error hygiene.** "Any the owner-built app that ships to a public URL must hide internal errors + show explicit ToS acknowledgement BEFORE the user sees any predictive/financial output. Never let a Streamlit/Flask/Django traceback reach an anonymous visitor."

2026-06-02: deployed a venture to https://another venture.com/ via Fly. the owner tested - picked **Stanley Druckenmiller** under 🎯 Forward Picks - got full Python traceback in browser:

**read thread before reply.** "Before drafting ANY reply/follow-up/repair, pull the live LinkedIn thread (get_conversation) and read the actual last messages + who sent last. Never draft from role alone."

the owner, 2026-07-01: "looking at some of your constructed replies, i dont believe that you have read the previous replies or state yet."

**read trajectory not snapshot.** "Judge relationships by their derivative (how they are developing), never by a static snapshot of counts, ratios, or who initiated."

the owner, 2026-07-16, on my read of Akshaj: "i disagree with your read of akshaj, look at how the relationship is developing instead of raw numbers, always been ur weak point."

**reconcile to business model.** "Every content/marketing move must reconcile back to the business model - for a venture that's converting traffic to newsletter subscribers, not just engagement."

Standing rule (2026-06-25): content and marketing are NEVER the goal - they feed the business model. Always reconcile each move back to how the venture makes money. "Built a viral post / a page / traffic" is not the win; a step toward REVENUE is.

**secret paste invitation.** Setup wizards / config generators / API onboarding embed live keys - warn + keychain BEFORE asking for output

**ship rate discipline.** "Pre-flight checks before dispatching Agents or starting automation. Prevent last week's 60% waste pattern."

the owner burn 85% Max 20x in 3 days. 132 Agent dispatches → ~19.8M tokens (~$158 API equiv). **Effective ship-rate ≈ 40%.** Aryaa call it out.

**smart route removed.** "smart-route per-prompt gemma hook durably removed - 0/4 hit rate, context-starvation not model size"

Smart-route `UserPromptSubmit` hook DURABLY REMOVED from `~/.claude/settings.json` on 2026-06-12 (the owner directive). Backup: `~/.claude/settings.json.bak-20260612-*`.

**sot goes unread.** sot goes unread

the owner, verbatim: "im pretty sure that ur not even using all the info u hv in the gdoc SOT even, so hook that makes sense u use all sources of info available".

**sot means gdoc.** "When the owner says \"SOT\" he means the Google Doc (Docs API), not a repo markdown file. Also: never dedupe SOT gdoc content as tidying, redundancy beats omission, and deletion needs an explicit ask naming doc AND block."

When the owner says "SOT" he means the canonical Google DOCS, written via the Docs API (~/.config/gdoc/), NOT a repo markdown file. 2026-06-25: asked for a "a venture SOT," I made a repo another venture.md; he corrected: "i meant docs api."

**striptypes no param properties.** tsc passes but the server crashes at boot. Pulse-Manila-26 runs server via strip-types - never use constructor parameter properties there.

Pulse-Manila-26's server runs via `node --experimental-strip-types server.ts` (no compile step). Strip-only mode ERASES type syntax but cannot do code generation, so these crash at runtime with `ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX` even though `tsc --noEmit` passes:

**summary only output.** the owner reads only the final summary. Put verbose process/detail into files; chat reply = concise summary of what changed + result.

**terminal prompt hygiene.** "Give the owner copy-paste-safe shell commands - his interactive shell is zsh, which does NOT strip inline"

the owner runs an interactive **zsh** shell (`<github-user>@Mac`). Any command block given for him to paste-and-run must be copy-paste-safe.

**warm alumni channels.** Warm messages to KIST alumni and Cambridge people convert far better than cold; route those cohorts through the warm lane

the owner 2026-07-18: "warm messages to KIST graduates and ppl at Cambridge work especially well, but prev i have been doing cold to those asw." Proof case same day: Ren Fujimoto (KIST 2019, BDA -> Morgan Stanley IBD) gave a 54-minute call the owner rated "a rlly good breakthrough" (parse: ~/repos/a venture/deliverables/insights-2026-07-18-ren-fujimoto-call.md). LinkedIn itself flags "Shared education" on KIST profiles, so the warmth is visible to the recipient too.

## One day, four self-inflicted lessons (added 2026-08-26)

A single day of work produced four corrections worth shipping, all variants of
one disease: reporting a proxy for the thing instead of the thing.

**A saving must be measured against an alternative that could have happened.**
An 88% saving collapsed on inspection: the median "uncompressed baseline" was
larger than the model's context window, so the compared-against request was
unsendable. A baseline that cannot execute is not a baseline. (docs/COST.md
carries the full derivation.)

**A causal claim needs the boundary query before it ships.** "X started when Y
changed" dies instantly if X predates Y, and the per-day count that decides it
takes seconds. Two individually true facts composed into an unverified timeline
produced a confident, fluent, wrong diagnosis. The rule now lives in
rules/common/learning-from-mistakes.md.

**An absent row is a zero, not a nothing.** The same per-day table that killed
the false story contained a genuinely missing day nobody noticed: traffic HAD
stopped for one day, a month of context made the gap invisible, and the eye
reads absence as continuity. Count the rows you expect, not the rows you see.

**A benchmark nothing can fail measures nothing, and a checker that executes
model output needs a deadline.** Three models tied at 7/7, then six at 5/5:
tasks too easy to rank anything. Adding a deliberately weak negative control
proved the tasks discriminate. Then a model returned a non-terminating loop and
the checker ran it in-process, hanging the whole suite at 99% CPU for 54
minutes while "is the process alive" said yes. Generated code runs in a
subprocess with a timeout, and liveness checks must distinguish working,
waiting, spinning, and wedged: only output growth plus cpu plus open sockets
tells them apart.

The Stop-hook counterpart of that last lesson ships here as
`hooks/item-coverage.py`: format guards prove an answer LOOKS right, coverage
guards prove it ANSWERS the request. The four existing shape hooks could all
pass while half the request was silently dropped; the coverage gate is the one
that notices the drop, and it fires only on zero term overlap so it cannot cry
wolf.
