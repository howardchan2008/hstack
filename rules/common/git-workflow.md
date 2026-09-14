# Git Workflow

## Commit message format
`<type>: <description>` + optional body. Types: feat, fix, refactor, docs, test, chore, perf, ci.

Attribution off: `"attribution": {"commit": "", "pr": "", "sessionUrl": false}` in `~/.claude/settings.json` (2026-08-14; 221 commits × 7 repos shipped `Co-Authored-By: Claude`). `includeCoAuthoredBy` deprecated; don't restore.

## Pull requests
Analyse commit history. `git diff [base]...HEAD`. Summary. Test plan. Push branches `-u`.

Full pre-git process: [development-workflow.md](./development-workflow.md).