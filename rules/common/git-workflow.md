# Git Workflow

## Commit Message Format
```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Attribution: `"attribution": {"commit": "", "pr": "", "sessionUrl": false}` in
`~/.claude/settings.json`. Empty strings hide the byline on commits and PR bodies.

This line claimed attribution was already off. It was not: no such key existed, and 221
commits across 7 repos carry `Co-Authored-By: Claude`, including public ones. Actually set
2026-08-14. `includeCoAuthoredBy` is the deprecated spelling per the live settings schema,
so do not restore it. The old commits keep the trailer; only new ones are clean.

## Pull Request Workflow

When creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> For the full development process (planning, TDD, code review) before git operations,
> see [development-workflow.md](./development-workflow.md).
