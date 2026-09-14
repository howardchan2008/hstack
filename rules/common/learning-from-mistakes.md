# Learning From Mistakes & Token Efficiency

## Error-to-memory
On mistake, write `feedback` memory same session with three elements: symptom quoted exactly, root cause, rule future session applies before acting. Dir: `~/.claude/projects/-Users-<github-user>/memory/`, indexed `MEMORY.md`. Mistake producing no memory gets made again.

## Token efficiency, ranked
1. Parallel over sequential: batch independent tool calls into one block.
2. Documented over discovered: read SOT, config or `--help` instead of probing.
3. Subset over full: 24 hours of logs, 10 samples to find pattern.
4. Cache over recompute: check memory and prior findings first.
5. Exclude over include: target directories, filter noise.

## Anti-patterns
Searching workspace for documented path. Sequential calls that could be one. Re-investigating solved problem. Writing fresh analysis where doc answers it. Debugging live when log has answer.

## Causal claims are verified or not shipped
"X started when Y changed" needs the count around the boundary before it ships. Failure this encodes (2026-08-26): a regression was explained by "the proxy started compressing sessions today"; per-day counts showed thousands of compressed requests on each of the seven prior days. Two individually true cached facts composed into timeline is most convincing kind of wrong.
- Plausible mechanism is HYPOTHESIS. Naming as cause without boundary check is fabrication.
- `I don't know what changed` is acceptable finding; wrong mechanism is not.