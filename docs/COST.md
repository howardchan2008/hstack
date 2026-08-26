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
compressed, the number appears to collapse: 85 to 88% in the first ten days,
13 to 23% in the last ten. A fourfold regression, apparently caused by the
reliability fixes.

**That reading is wrong, and catching it is the actual lesson on this page.**

Split the same data by whether the uncompressed request could have been sent at
all. The context window is 1,000,000 tokens. In the first period the median
request had an uncompressed size of 1,072,902 tokens, and **56% of requests were
larger than the window they would have had to fit in**. In the last period, 0%
were. So the early 88% was measured against a counterfactual that could not
happen: without the proxy those requests were not billed differently, they were
impossible, and the session would have truncated its history far sooner and sent
a fraction of that content.

The late figure is measured against a baseline that is real. It is also the only
one that agrees with the single measurement here that had a genuine control arm:
a six-day randomised holdout, 604 conversations, which put the cost-weighted
saving at 22.1% with a 95% interval of 7.4 to 34.3%.

So the saving did not fall. **The early number was never a saving.** It was a
third instance of the same error this page opened with, and it was produced by
someone who had just written the first two paragraphs warning about it.

Two rules survive this:

**A saving measured once is a saving you no longer know.** Recompute after every
change to the thing that produces it, and split by date rather than pooling,
because pooling hides a trend inside an average.

**Before believing a saving, ask what the alternative actually was.** Not the
arithmetic difference against a hypothetical, but the thing that would really
have happened. A baseline that could never have been executed is not a baseline,
and any percentage computed against one is decoration.

## Interception has a blast radius

A proxy that terminates TLS to inspect traffic is also a proxy that answers
requests the client did not mean for it. One documented case: the client's
feature-availability check reached the proxy instead of the vendor, the proxy
answered with its own page, and the client read that page as the vendor saying
the feature was disabled. The feature was not disabled, and nothing in the error
named the proxy.

Anything routed through an interception layer inherits that layer's uptime and
its failure modes. Worth it for a measured saving. Not worth it silently.
