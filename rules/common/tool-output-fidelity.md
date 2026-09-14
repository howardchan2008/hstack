# Tool-output fidelity

Tool output → rendered image. Verbatim fidelity or gist? Decide pre-call.

## Never let it compress, pre-slice instead

1. Quoted/attributed: silent misattribution→deliverables.
2. Mechanical pattern-match: `Edit` needs byte-exact `old_string`.
3. Money/legal numbers: amounts, dates, hashes, signatures.
4. Whitespace-significant: diffs, YAML, nested markdown, aligned tables.
5. Present-but-unreadable = absent.

## Fine to compress

Orientation scans, dir listings, output narrowed before acting, re-confirmation, UI screenshots.

## Method

Pre-slice at call site: `cut -c1-N`, `sed -n 'A,Bp'`, `head`, targeted `grep`.

## Known gap

Identifier sidecars rescue tokens, not BINDINGS. Report value occurrence, not clause binding. Legal/financial docs: never render.

## Backstop

Re-read narrowly first. Never assert high-stakes items from render alone.