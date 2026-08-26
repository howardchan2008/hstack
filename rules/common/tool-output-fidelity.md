# Tool-output fidelity (what must never be lossily rendered)

Long tool output may be compressed into a rendered image. The axis that matters is
**not length** - it is whether downstream use needs verbatim fidelity or only gist.
Decide before the call, not after.

## Never let it compress - pre-slice instead

1. **Anything to be quoted or attributed.** Named-source positions, contract clauses,
   transcript lines, mentor advice. Misattribution is silent and travels into deliverables.
2. **Anything to be pattern-matched mechanically.** `Edit` needs byte-exact `old_string`.
   A render cannot supply one.
3. **Numbers landing in money or legal artifacts.** Amounts, dates on instruments,
   hashes, signatures.
4. **Whitespace-significant content.** Diffs, YAML, nested markdown, aligned tables.
5. **Absence checks.** A negative cannot be proven from a lossy render - a line that is
   present but unreadable reads as absent. "Does X contain Y" needs text.

## Fine to compress

Orientation scans, directory listings, long output that will be narrowed before acting on,
re-confirmation of already-processed content, and real UI screenshots (image *is* the artifact).

## Method

Pre-slice at the call site to stay under the threshold: `cut -c1-N`, `sed -n 'A,Bp'`,
`head`, targeted `grep` with a known window. If merely scanning, let it compress.

## Known gap

Identifier sidecars rescue *tokens* but not *bindings* - they report that a value occurs,
not which clause it belongs to. For legal/financial documents the binding is the whole
point, so those must never go through a render.

## Backstop

Never assert from a render anything that would be embarrassing to get wrong. Re-read
narrowly first; it is one cheap call.
