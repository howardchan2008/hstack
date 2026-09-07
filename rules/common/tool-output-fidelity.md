# Tool-output fidelity

Long tool output may be compressed into a rendered image. The axis is whether downstream use needs verbatim fidelity or only gist. Decide before the call.

## Never let it compress, pre-slice instead
1. Anything to be quoted or attributed (misattribution is silent and travels into deliverables).
2. Anything to be pattern-matched mechanically: `Edit` needs a byte-exact `old_string`.
3. Numbers landing in money or legal artifacts: amounts, dates, hashes, signatures.
4. Whitespace-significant content: diffs, YAML, nested markdown, aligned tables.
5. Absence checks. A line present but unreadable reads as absent.

## Fine to compress
Orientation scans, directory listings, output that will be narrowed before acting, re-confirmation, and real UI screenshots.

## Method
Pre-slice at the call site: `cut -c1-N`, `sed -n 'A,Bp'`, `head`, targeted `grep`.

## Known gap
Identifier sidecars rescue tokens but not BINDINGS: they report that a value occurs, not which clause it belongs to. Legal and financial documents must never go through a render.

## Backstop
Never assert from a render anything that would be embarrassing to get wrong. Re-read narrowly first.
