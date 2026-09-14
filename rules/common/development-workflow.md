# Development Workflow

Extends [git-workflow.md](./git-workflow.md): pre-git workflow.

## Found bugs: fix them, do not ask

Defects noticed mid-task fixed in session (pre-existing, incidental). "Out of scope so I left it" is a failure. Scope via COMMIT BOUNDARIES: land unrelated fix separately. Report bugs past-tense (what broke, fix, verify). Not menu.

### Narrow exceptions, when the thing found is a DECISION not a defect

- Destructive/irreversible (data loss, history rewrite, force-push, column drop).
- Repair changes INTENDED behaviour (not restores), or spec unclear.
- Fix depends on fact only the owner has.
- Touches live/production, credentials, beyond-repo blast-radius.

Missing `mkdir`, unhandled error, wrong constant, swallowed exception: fix instantly.

## Feature implementation workflow

0. **Research and reuse (mandatory before new implementation).** `gh search repos`, `gh search code` first; vendor/Context7 second; Exa when insufficient. Check npm/PyPI/crates before utilities. Prefer fork/port 80%-solution vs new code.
1. **Plan first** (planner agent when authorised): PRD, architecture, tasks, phases, risks.
2. **TDD**: RED, GREEN, refactor, 80%+ coverage.
3. **Code review** after writing; fix CRITICAL and HIGH.
4. **Commit and push**: conventional-commit messages.