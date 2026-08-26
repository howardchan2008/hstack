# Cost

Every tool call re-sends the whole conversation. So the bill is
**calls times context**, and neither number appears where the decision to make
the call is taken. This page is what measuring that actually produced, including
the two measurements that were wrong.

## The shape of the bill

One audited window: 17 sessions, 13,379 API calls over three days.

| | |
|---|---|
| cost-weighted input | 91.4% of the bill |
| output | 8.6% |
| cached input tokens read back | 3.62 billion |
| unique content produced | roughly 13 million tokens |

That last pair is a 278x re-read amplification, and it is the whole argument.
Shortening what the agent writes attacks 8.6% of the bill. The lever is how many
calls are made and how large the context is when they are made.

The guards that act on this are `probe-dedupe.sh` (refuses the fourth look at an
already-answered question), `burn-context.sh`, `websearch-cache.sh` and
`websearch-router.sh` (refuse paying twice for the same fetch), and
`lane-guard.sh` (refuses sending cheap bulk work to the most expensive engine).

## Two measurements that were wrong, and how

Both survived for weeks because each produced a plausible number.

**A coverage counter read as a ratio.** A context-compression proxy reported a
`compressedChars` figure that was quoted as its saving. It counted how much text
the compressor had *looked at*, not how much it removed. The number was real,
the label was wrong, and nothing in the output distinguished the two.

**A cost measured against no benefit.** The same tool was later removed after its
failures were counted, correlated with payload size, and called root cause. The
saving those same payloads bought was never computed once. A cost measured
against no benefit always reads as pure cost, so the tool was removed on a
comparison that had only one side.

The rule both produced: **before removing an instrument, put a number on both
sides or state plainly that you did not.**

## The counterfactual is the hard part

Measuring a compression proxy honestly is harder than it looks, and the obvious
method overstates it by a lot.

The tempting comparison is *tokens the request would have contained* against
*tokens actually billed*. On real traffic that gives about 87%. It is wrong,
because billing is cache-aware and the baseline is not: most of that 87% is
prompt caching, which the same conversation would have received anyway, with or
without the proxy. Crediting the proxy for the cache's work is the same class of
error as the coverage counter above, in a new costume.

The honest question is narrower. **Did fewer tokens move, for the same
conversation?** Assume the cache mix is preserved proportionally and the algebra
collapses to exactly that: compare volume sent against volume that would have
been sent, and ignore the weights entirely.

Measured that way over 70,178 requests spanning a month, 36,279 of them
compressed:

| era | saving |
|---|---|
| first ten days | 85 to 88% |
| middle | 35 to 50% |
| final ten days | 13 to 23% |

**The saving degraded by a factor of four, and the cause was the fixes.** Image
caps were added to stop the proxy generating payloads the API rejected. They
worked: the 400s went to zero. They also skipped 4,558 requests in the final
period, and those skips are most of the fall. This is a real tradeoff honestly
arrived at, and it is invisible unless the number is recomputed after each fix
rather than quoted from the day it was first measured.

The general rule: **a saving measured once is a saving you no longer know.**
Recompute it after every change to the thing that produces it, and split the
history by date rather than pooling it, because pooling hides a trend inside an
average.

## Interception has a blast radius

A proxy that terminates TLS to inspect traffic is also a proxy that answers
requests the client did not mean for it. One documented case: the client's
feature-availability check reached the proxy instead of the vendor, the proxy
answered with its own page, and the client read that page as the vendor saying
the feature was disabled. The feature was not disabled, and nothing in the error
named the proxy.

Anything routed through an interception layer inherits that layer's uptime and
its failure modes. Worth it for a measured saving. Not worth it silently.
