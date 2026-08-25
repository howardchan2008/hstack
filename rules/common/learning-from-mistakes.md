# Learning From Mistakes & Token Efficiency

## Error-to-Memory Pattern

When you make a mistake, write a `feedback` memory the same session. Three elements, always:

1. What went wrong (the symptom, quoted exactly)
2. Why it happened (root cause, not the surface error)
3. How to prevent it (the rule a future session applies before acting)

Canonical memory dir: `~/.claude/projects/-Users-<github-user>/memory/`. Index every new file in `MEMORY.md`.

The point is that the error never repeats. A mistake that produces no memory gets made again.

## Token Efficiency, Ranked by Impact

1. **Parallel > sequential** - batch independent tool calls into one block; fan out agents at once, not one-by-one.
2. **Documented > discovered** - read the SOT / config / `--help` instead of probing a live system.
3. **Subset > full** - 24 hours of logs, not 3 months; 10 samples to find the pattern, not 134.
4. **Cache > recompute** - check memory and prior findings before re-solving a solved problem.
5. **Exclude > include** - target directories and filter noise instead of sweeping the tree.

## Anti-Patterns

- Searching the whole workspace for something whose path is documented
- Sequential shell/SSH calls that could have been one command
- Re-investigating a problem an earlier session already solved
- Writing fresh analysis where a doc already answers it
- Debugging live when the log already has the answer
