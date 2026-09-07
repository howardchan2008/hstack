# Git Workflow

## Commit message format
`<type>: <description>` then an optional body. Types: feat, fix, refactor, docs, test, chore, perf, ci.

Attribution is off: `"attribution": {"commit": "", "pr": "", "sessionUrl": false}` in `~/.claude/settings.json` (set 2026-08-14, after 221 commits across 7 repos shipped `Co-Authored-By: Claude`). `includeCoAuthoredBy` is the deprecated spelling; do not restore it.

## Pull requests
Analyse the full commit history, use `git diff [base]...HEAD`, write a comprehensive summary, include a test plan, push new branches with `-u`.

Full pre-git process: [development-workflow.md](./development-workflow.md).
