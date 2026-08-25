#!/bin/bash

# PROVENANCE, added 2026-08-23. adherence rates, emission counts and the n=42 comparison were measured 2026-08-04 to 2026-08-06 against the then-live transcript tree.
# That tree is NOT the corpus any more: transcript-archive moved 3,638 of the
# 3,857 transcripts to ~/Archive/claude-transcripts on 2026-08-18, so the live
# tree is about 6% of sessions. These numbers are HISTORICAL and are not
# reproducible as stated. Re-derive across BOTH trees before citing them; see
# ~/.claude/bin/claims-audit and hooks/lib/probe-dedupe-backtest.py for the shape.
# UserPromptSubmit: promote STATE-VERIFY from CLAUDE.md (file channel, 53% adherence)
# into injected context (hook channel, 83% adherence, p=0.008 vs file, n=42).
# Source of truth remains CLAUDE.md sec.1; this is a compaction, not a fork.
#
# 2026-08-04: gated (the owner directive). Measured: the full block is ~480 tokens
# and was re-emitted byte-identical on EVERY prompt, about 54k tokens per
# 100-prompt session, carrying zero new information after the first.
#
# It now emits in full only when the prompt plausibly touches an externally
# visible claim. It never goes fully silent: a non-matching prompt still gets a
# one-line pointer, because a false negative here is precisely the failure this
# rule exists to prevent, and a wrong claim in a sent email is permanent.
#
# Matching is deliberately done against the RAW payload, not a parsed prompt
# field. No interpreter spawn on the hot path, and any false positive fires the
# full block, which is the safe direction. Missing or unreadable input also
# fires the full block.

PAYLOAD="$(cat 2>/dev/null || true)"

# Channels that reach a human, claims about what a system currently IS, and
# anything numeric. Over-broad on purpose.
TRIGGER='email|e-mail|dm |slack|deck|pitch|form|publish|post|send|draft|outreach|reply|linkedin|call prep|newsletter|intro|tweet|message'
TRIGGER="$TRIGGER"'|live|deploy|shipped|ship|launch|production|prod|serving|status|ready|verif|health|uptime|down|broken|works|working'
TRIGGER="$TRIGGER"'|rule out|rule in|confirm|coverage|how many|count|metric|stats|auc|revenue|users|customers|number|date'

# The quiet path requires a payload we actually understand. A non-empty but
# unparseable payload tells us nothing about whether the prompt was external
# facing, so it takes the full block like missing input does.
# 2026-08-30: match the prompt VALUE, not the raw envelope. The envelope always
# carries cwd=$HOME, and "users" is a TRIGGER token, so the quiet
# path could never fire in production. Fail-safe directions are unchanged:
# empty payload, no prompt field, or an unextractable value all take full block.
PROMPT_VAL="$(printf '%s' "$PAYLOAD" \
  | grep -o '"prompt"[[:space:]]*:[[:space:]]*"\(\\.\|[^"\\]\)*"' \
  | head -1 | sed 's/^"prompt"[[:space:]]*:[[:space:]]*//')"

if [ -n "$PAYLOAD" ] \
   && printf '%s' "$PAYLOAD" | grep -q '"prompt"' \
   && [ -n "$PROMPT_VAL" ] \
   && ! printf '%s' "$PROMPT_VAL" | grep -qiE "$TRIGGER"; then
  echo "STATE-VERIFY: active (no external-claim signal in this prompt). Full rules: CLAUDE.md sec.1. Before any externally-visible claim, check live and cross-verify."
  exit 0
fi

# ---- 2026-08-06: repeat suppression, compaction aware (the owner approved) ----
# Measured: 87.4% of full-block emissions (9,284 of 10,618) were byte-identical
# repeats costing ~4.46M tokens. Once injected the block persists in context, so
# re-stating it carries zero new information UNTIL the context is compacted,
# which is free to drop it. Compaction is observable in the transcript: 263
# structural events across 70 transcripts, each a paired system/compact_boundary
# + user/isCompactSummary record.
#
# Full block on the first triggering prompt of a session, and again on the first
# triggering prompt after each compaction. Pointer in between. Fail-safe
# directions unchanged: missing session id, missing or unreadable transcript,
# unusable state dir, or a non-numeric count all fall through to the full block.
SV_STATE_DIR="${CLAUDE_SV_STATE_DIR:-$HOME/.claude/.state-verify}"

# LAYER CHECK, added 2026-08-24. The compaction dedupe below works: measured across
# the live transcripts, 2,549 full blocks against 1,340 pointers, and the single
# 493-block session predates the 2026-08-06 dedupe commit. Post-commit the full
# block fires 7 to 37 times a day. But ~/CLAUDE.md carries this same rule as a
# 4,642-byte section that loads unconditionally in EVERY session, so even the
# FIRST emission is a second copy of something already in context. One fact, one
# always-loaded layer: emit the pointer whenever that section is verifiably
# present, and fall through to the full block when it is not (file missing, moved,
# or heading renamed). The check READS the file rather than assuming it loaded, so
# a session started somewhere ~/CLAUDE.md does not reach still gets the rules.
if grep -q 'STATE-VERIFY BEFORE YOU SPEAK' "$HOME/CLAUDE.md" 2>/dev/null; then
  if [ -n "$PROMPT_VAL" ] && printf '%s' "$PROMPT_VAL" | grep -qiE "$TRIGGER"; then
    echo "STATE-VERIFY: active. Full rules already in context this session (~/CLAUDE.md sec.1). Before any externally-visible claim: check live, cross-verify every SOT layer, numbers come from data not prose."
  fi
  exit 0
fi

if [ -n "$PROMPT_VAL" ] && printf '%s' "$PROMPT_VAL" | grep -qiE "$TRIGGER"; then
  SID="$(printf '%s' "$PAYLOAD" \
    | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//' | tr -cd 'A-Za-z0-9._-')"
  TPATH="$(printf '%s' "$PAYLOAD" \
    | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  if [ -n "$SID" ] && [ -n "$TPATH" ] && [ -r "$TPATH" ] \
     && mkdir -p "$SV_STATE_DIR" 2>/dev/null; then
    NCOMPACT="$(grep -c '"subtype":"compact_boundary"' "$TPATH" 2>/dev/null)"
    case "$NCOMPACT" in ''|*[!0-9]*) NCOMPACT='' ;; esac
    if [ -n "$NCOMPACT" ]; then
      SEEN="$(cat "$SV_STATE_DIR/$SID" 2>/dev/null || true)"
      if [ "$SEEN" = "$NCOMPACT" ]; then
        echo "STATE-VERIFY: active. Full rules already in context this session (CLAUDE.md sec.1). Before any externally-visible claim: check live, cross-verify every SOT layer, numbers come from data not prose."
        exit 0
      fi
      printf '%s' "$NCOMPACT" > "$SV_STATE_DIR/$SID" 2>/dev/null || true
      find "$SV_STATE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
    fi
  fi
fi

cat <<'MSG'
STATE-VERIFY BEFORE YOU SPEAK (the owner directive, hard):
Before ANY externally-visible statement of what a product/venture/system currently IS
(email, DM, deck, form, pitch, public copy, call prep), and before ruling anything in/out:
1. CHECK LIVE, HEADLESSLY. Deployed thing = what the recipient sees. Bash IS networked, NOT
   sandboxed. curl -> 000 means the the local proxy MITM cert is untrusted by curl, NOT network down:
   retry with --cacert ~/.the local proxy/mitm/ca.pem. WebFetch/WebSearch are DEFERRED tools: ToolSearch
   to load them instead of saying "no web access". Only if still unreachable after both, SAY SO
   and name the proxy used. Never imply a verification that did not happen.
2. CROSS-VERIFY EVERY SOT LAYER, never stop at the first that answers:
   canonical GDOC -> deploy source -> repo docs -> DATA FILES -> memory.
   Lower/fresher wins; patch the stale one same session.
3. NUMBERS COME FROM DATA, NOT PROSE. Counts/coverage/AUC/dates: read the json/parquet
   that builds the page. Markdown prose is the MOST stale layer.
4. NAMED EXAMPLES = flagship ones the recipient would test you on, from the roster.
5. MERGED != DEPLOYED != SERVING. Prove all three or name the one you skipped:
   ~/.claude/bin/verify-live.sh --url U [--do-app ID] [--commit SHA] [--gh-repo o/n]
   (exit 0=ok 1=real problem 2=UNVERIFIED; never round 2 down to 0).
   Looks-down-but-is-not: 403=Cloudflare vs curl's UA, resend as browser; 404=wrong path,
   locale rides Accept-Language, /en is not a route; 000=cert, see 1. A red CI X can mean
   the job NEVER STARTED (billing) - visible ONLY in run annotations, and nothing-ran is
   not tests-failed: it means CI gated nothing. "Is my commit live" = containment
   (git merge-base --is-ancestor), never SHA equality; a newer deploy still carries yours.
Memory snapshots are LAST layer, never first. A wrong internal note gets fixed; a wrong
claim in a sent email is permanent.
MSG
