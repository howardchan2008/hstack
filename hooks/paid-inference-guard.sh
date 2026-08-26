#!/bin/bash
# paid-inference-guard.sh: PreToolUse(Bash). Refuse a raw call to a METERED
# generation endpoint. The wrappers stay open; the bypass does not.
#
# THE INCIDENT, 2026-08-27. A credit check was built INSIDE the `imagen` wrapper,
# proved to refuse correctly, and then bypassed by the same session calling the
# Azure endpoint with raw curl to win a factual argument. Charge: JPY 405.51.
# That is the second time this shape has cost real money: the JPY 4,400 misspend
# ran through generativelanguage.googleapis.com, whose key sits OUTSIDE the
# Google credit, and that host had no guard until this file existed.
#
# THE ARCHITECTURAL POINT, which is the whole reason this is a hook and not a
# check inside a script: A GUARD INSIDE A WRAPPER IS NOT A GUARD. The wrapper is
# one of many paths to the same billing endpoint, and the agent holds a shell.
# Only PreToolUse sits between the agent and every path, so a spend control that
# lives anywhere else is a suggestion.
#
# WHAT IT REFUSES: a shell command that reaches a metered host on a GENERATION
# path. What it ALLOWS, deliberately, because shutting a lane down safely
# requires them: model/deployment listing, billing and usage reads, `az`/`gcloud`
# management, and every wrapper that calls these hosts from inside python or node
# rather than from a shell curl.
#
# OVERRIDE: PAID_INFERENCE_OK=1 in the command, which is a deliberate,
# greppable act rather than an accident.

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print((json.load(sys.stdin).get("tool_input") or {}).get("command") or "")
except Exception: print("")' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Explicit, auditable override.
printf '%s' "$CMD" | grep -q 'PAID_INFERENCE_OK=1' && exit 0

# Only shell HTTP clients. A wrapper calling these hosts from python is the
# sanctioned path and never appears as a curl in a Bash command.
printf '%s' "$CMD" | grep -Eqi '(^|[|;&[:space:]])(curl|wget|http|https)([[:space:]]|$)' || exit 0

METERED='api\.openai\.com|generativelanguage\.googleapis\.com|aiplatform\.googleapis\.com|openai\.azure\.com|cognitiveservices\.azure\.com|api\.higgsfield\.ai|api\.elevenlabs\.io|api\.replicate\.com|api\.stability\.ai|api\.deepseek\.com|api\.x\.ai'
printf '%s' "$CMD" | grep -Eqi "$METERED" || exit 0

# ORDER IS LOAD-BEARING AND THE NEGATIVE CONTROL PROVED IT. The first version
# checked the read/management allow-list FIRST, and both money-losing bypasses
# walked straight through it: the Gemini URL is
# /v1beta/models/<m>:generateContent, which contains "/models/", and the Azure
# one is /openai/deployments/<d>/images/generations, which contains
# "/deployments/". An allow-rule that matches a PREFIX of a billing path is a
# hole shaped exactly like the incident. Decide on the billing verb first;
# only a command with no billing verb can qualify as a read.
BILLS='/(chat/)?completions|/images?/(generations|edits|variations)|/audio/(speech|transcriptions)|/embeddings|:generateContent|:streamGenerateContent|:predict|:predictLongRunning|/v1/messages|/text2image|/generate|/video'
printf '%s' "$CMD" | grep -Eqi "$BILLS" || {
  # No billing verb: this is a read or a management call, which a shutdown needs.
  exit 0
}

HOST=$(printf '%s' "$CMD" | grep -Eoi "$METERED" | head -1)
cat <<JSON
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"PAID INFERENCE BYPASS REFUSED: raw call to a metered generation endpoint ($HOST).\n\nThis exact shape has cost real money twice: JPY 405.51 on 2026-08-27 when a credit check inside a wrapper was bypassed with curl, and JPY 4,400 earlier through a Google key that sits outside the credit. A guard inside a wrapper is not a guard, because the wrapper is one of several paths to the same billing endpoint.\n\nUse the sanctioned wrapper, which carries the credit check. If there is genuinely no wrapper, say so and name the per-call cost BEFORE calling. If this is deliberate and the owner has approved this spend, prefix the command with PAID_INFERENCE_OK=1 so it is greppable afterwards.\n\nReads and management calls (list models, usage, billing, az/gcloud) are allowed and are not affected."}}
JSON
exit 0
