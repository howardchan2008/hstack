# Learning From Mistakes & Token Efficiency

## Error-to-memory
On a mistake, write a `feedback` memory the same session with three elements: the symptom quoted exactly, the root cause, and the rule a future session applies before acting. Dir: `~/.claude/projects/-Users-<github-user>/memory/`, indexed in `MEMORY.md`. A mistake that produces no memory gets made again.

## Token efficiency, ranked
1. Parallel over sequential: batch independent tool calls into one block.
2. Documented over discovered: read the SOT, config or `--help` instead of probing.
3. Subset over full: 24 hours of logs, 10 samples to find the pattern.
4. Cache over recompute: check memory and prior findings first.
5. Exclude over include: target directories, filter noise.

## Anti-patterns
Searching the workspace for a documented path. Sequential calls that could be one. Re-investigating a solved problem. Writing fresh analysis where a doc answers it. Debugging live when the log has the answer.

## Causal claims are verified or not shipped
"X started when Y changed" needs the count around the boundary before it ships. Failure this encodes (2026-08-26): a regression was explained by "the proxy started compressing sessions today"; per-day counts showed thousands of compressed requests on each of the seven prior days. Two individually true cached facts composed into a timeline is the most convincing kind of wrong.
- A plausible mechanism is a HYPOTHESIS. Naming it as the cause without the boundary check is fabrication.
- "I don't know what changed" is an acceptable finding; a wrong mechanism is not.
