#!/usr/bin/env python3
"""Write what WebSearch/WebFetch returned to the cache the router reads.

Lives in a real file rather than inline in the .sh on purpose. The first version of
this was embedded as `python3 -c '...'` inside the hook, the shell ate every inner
single quote, and the result raised NameError and exited silently. A cache writer
that fails quietly is worse than none: the router keeps passing calls through and
nothing ever reports that the other half is dead.
"""
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from websearch_key import key as cache_key  # noqa: E402

CACHE = os.path.expanduser("~/.claude/state/websearch-cache")
MIN_BODY = 200
MAX_BODY = 400_000


def main() -> int:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0

    tool = d.get("tool_name", "")
    if tool not in ("WebSearch", "WebFetch"):
        return 0

    i = d.get("tool_input") or {}
    q = i.get("query") or ""
    u = i.get("url") or ""

    out = d.get("tool_response")
    if out is None:
        out = d.get("tool_result", "")
    if not isinstance(out, str):
        try:
            out = json.dumps(out, indent=2, ensure_ascii=False)
        except Exception:
            out = str(out)

    # A near-empty body is a failed fetch. Caching it would teach the router to block
    # the retry with a file that answers nothing, which is worse than no cache at all.
    if len(out.strip()) < MIN_BODY:
        return 0

    if len(out) > MAX_BODY:
        out = out[:MAX_BODY] + "\n\n[truncated by websearch-cache]"

    stamp = datetime.datetime.now().isoformat(timespec="seconds")
    hdr = (
        f"# cached {tool}\n"
        f"# when : {stamp}\n"
        f"# query: {q or '-'}\n"
        f"# url  : {u or '-'}\n"
        "# NOTE : point-in-time. Anything hourly (prices, fares, live filings) is stale.\n"
        + ("-" * 78)
        + "\n"
    )

    os.makedirs(CACHE, exist_ok=True)
    try:
        with open(os.path.join(CACHE, cache_key(f"{q} {u}") + ".txt"), "w") as f:
            f.write(hdr + out)
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
