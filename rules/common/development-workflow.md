# Development Workflow

Extends [git-workflow.md](./git-workflow.md) with what happens before git operations.

## Found bugs: fix them, do not ask
A defect noticed while doing something else gets fixed in the same session, including pre-existing and incidental ones. "Out of scope so I left it" is a failure. Scope is handled by COMMIT BOUNDARIES: land the unrelated fix as its own commit. Report found bugs in the past tense (what broke, what the fix was, how it was verified), never as a menu.

### Narrow exceptions, when the thing found is a DECISION not a defect
- Destructive or irreversible (data loss, history rewrite, force-push, dropping a column).
- The repair changes INTENDED behaviour rather than restoring it, or it is unclear which is the spec.
- The right fix depends on a fact only the owner has.
- It touches live/production state, credentials, or anything with blast radius beyond the repo.
A missing `mkdir`, an unhandled error path, a wrong constant, a swallowed exception: fix instantly.

## Feature implementation workflow
0. **Research and reuse (mandatory before new implementation).** `gh search repos` and `gh search code` first; vendor/Context7 docs second; Exa only when those are insufficient. Check npm/PyPI/crates before writing utility code. Prefer forking or porting something that solves 80% over net-new code.
1. **Plan first** (planner agent when authorised): PRD, architecture, task list, phases, risks.
2. **TDD**: RED, GREEN, refactor, verify 80%+ coverage.
3. **Code review** immediately after writing code; fix CRITICAL and HIGH.
4. **Commit and push** with conventional-commit messages.
