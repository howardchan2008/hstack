#!/bin/bash
# lane-guard: blocks large model fan-outs launched on the expensive lane without
# an explicit lane decision. Born <phone>: two Claude Workflow vision-review
# runs + a cache-missed resume burned ~50M subagent tokens on sheet classification
# that codex gpt-5.4-mini does free (owner infraction, "I want it to be the last
# time"). Mirrors risk-checkpoint.sh: mechanical gate > prose memory.
#
# Fires on PreToolUse for Workflow. Blocks when the call fans out (pipeline/
# parallel in script, or args array >20 items) unless /tmp/lane-check-approved
# exists and is fresh (<10 min). The bypass file must be written AFTER stating
# in chat: LANE (why not codex exec -i / local) · ITEMS · EST TOKENS CEILING ·
# CACHE-VERIFIED (for resumes: proof a 1-agent slice replayed from cache).
set -u
INPUT=$(cat)

# FAIL CLOSED (<phone>). Both reads below were `2>/dev/null` feeding a bare
# string compare, so ANY payload python could not parse left TOOL or FANOUT
# empty, the compare fell through, and this exited 0 having inspected nothing.
# The gate standing between us and a repeat of the ~50M-token burn was one
# malformed field away from silently disarming, and it logged a clean pass.
#
# settings.json binds this hook to matcher=Workflow, so an unreadable payload
# HERE is a Workflow call we failed to inspect, never some other tool. Reading
# it as "not Workflow, therefore fine" was exactly backwards.
#
# Recoverable BY DESIGN: /tmp/lane-check-approved still releases the block, so
# failing closed cannot wedge Workflow permanently, and the message below says
# WHICH of the two reasons fired, so a guard malfunction is never misread as a
# considered verdict that the call was safe.
UNREADABLE=0
TOOL=$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
if [ -z "$TOOL" ]; then
  UNREADABLE=1
elif [ "$TOOL" != "Workflow" ]; then
  exit 0
fi

FANOUT=$(LANE_INPUT="$INPUT" /usr/bin/python3 - <<'PY' 2>/dev/null
import os, sys, json
d = json.loads(os.environ["LANE_INPUT"])
ti = d.get("tool_input", {}) or {}
script = (ti.get("script") or "") + " "
args = ti.get("args")
n = 0
def count(x):
    if isinstance(x, list): return len(x)
    if isinstance(x, dict): return max([count(v) for v in x.values()] + [0])
    if isinstance(x, str):
        try: return count(json.loads(x))
        except Exception: return 0
    return 0
n = count(args)
resume = 1 if ti.get("resumeFromRunId") else 0
fan = 1 if ("pipeline(" in script or "parallel(" in script or n > 20 or resume) else 0
print(f"{fan} {n} {resume}")
PY
)
FAN=${FANOUT%% *}
# Empty FANOUT means the counter itself died, so the fan-out size is UNKNOWN,
# not small. Unknown is treated as fan-out: the cheap error is one extra
# approval keystroke, the expensive error is the <phone> run.
if [ "$UNREADABLE" = "1" ] || [ -z "$FANOUT" ]; then
  UNREADABLE=1
  FAN=1
fi
[ "$FAN" = "1" ] || exit 0

APPROVE=/tmp/lane-check-approved
if [ -f "$APPROVE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$APPROVE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt 600 ]; then rm -f "$APPROVE"; exit 0; fi
fi

if [ "$UNREADABLE" = "1" ]; then
  cat >&2 <<'MSG'
⛔ LANE-GUARD: the Workflow payload could not be parsed, so this is FAILING CLOSED.
This is a guard malfunction, NOT a finding that your call fans out. The fan-out
rules were never evaluated. Do not read this block as "lane-guard looked and
disagreed": it looked at nothing.
If the payload shape genuinely changed, repair the hook rather than routing past it.
To override for this one call: touch /tmp/lane-check-approved && re-run.
MSG
  exit 2
fi

cat >&2 <<'MSG'
⛔ LANE-GUARD: large Workflow fan-out blocked (CLAUDE.md engine routing + <phone> infraction).
Vision/sheet/classify fan-outs go to the FREE lane first:
  codex exec --ignore-user-config -c model=gpt-5.4-mini --skip-git-repo-check -i <sheet> -- "<prompt>"
  (or LOCAL qwen2.5vl for tolerant-quality labeling)
Claude subagent fan-out = last resort, and NEVER a >20-agent resume without cache-hit proof on a 1-agent slice.
To proceed, STATE IN CHAT: LANE (why codex/local cannot do this) · ITEMS · TOKEN CEILING · CACHE-VERIFIED (resumes).
Then: touch /tmp/lane-check-approved && re-run. Ultracode does NOT override this.
MSG
exit 2
