# Development Workflow

> This file extends [common/git-workflow.md](./git-workflow.md) with the full feature development process that happens before git operations.

The Feature Implementation Workflow describes the development pipeline: research, planning, TDD, code review, and then committing to git.

## Found Bugs: Fix Them, Do Not Ask

**Standing rule, all sessions, all repos.** A defect noticed while doing something else gets fixed in the same session. Do not stop and ask permission to fix it. Do not report it as an open question. Do not leave it for later.

This includes bugs that are pre-existing, orthogonal to the current task, or discovered incidentally while debugging something unrelated. "I found X but did not fix it because it was out of scope" is a failure, not discipline. If it was worth noticing and worth writing a paragraph about, it was worth the two-line fix.

**Scope is handled by commit boundaries, not by leaving bugs on the floor.** If the fix is unrelated to the work in flight, land it as its own commit with its own message. That keeps history clean without deferring the repair.

Report found bugs in the past tense - what broke, what the fix was, how it was verified. Not as a menu of options.

### The narrow exceptions

Still ask first when the thing found is a **decision**, not a defect:

- The fix is destructive or irreversible - data loss, history rewrite, force-push, dropping a column.
- Repairing it means **changing intended behaviour**, not restoring it. If it is unclear whether the current behaviour is a bug or the spec, that is a question.
- The correct fix depends on a fact only the owner has (business rule, which of two outputs is authoritative, what a customer actually needs).
- The fix touches live/production state, credentials, or anything with blast radius beyond the repo.

These are narrow on purpose. A missing `mkdir`, an unhandled error path, a late-and-ugly traceback, a wrong constant, a swallowed exception: fix instantly, no question asked.

## Feature Implementation Workflow

0. **Research & Reuse** _(mandatory before any new implementation)_
   - **GitHub code search first:** Run `gh search repos` and `gh search code` to find existing implementations, templates, and patterns before writing anything new.
   - **Library docs second:** Use Context7 or primary vendor docs to confirm API behavior, package usage, and version-specific details before implementing.
   - **Exa only when the first two are insufficient:** Use Exa for broader web research or discovery after GitHub search and primary docs.
   - **Check package registries:** Search npm, PyPI, crates.io, and other registries before writing utility code. Prefer battle-tested libraries over hand-rolled solutions.
   - **Search for adaptable implementations:** Look for open-source projects that solve 80%+ of the problem and can be forked, ported, or wrapped.
   - Prefer adopting or porting a proven approach over writing net-new code when it meets the requirement.

1. **Plan First**
   - Use **planner** agent to create implementation plan
   - Generate planning docs before coding: PRD, architecture, system_design, tech_doc, task_list
   - Identify dependencies and risks
   - Break down into phases

2. **TDD Approach**
   - Use **tdd-guide** agent
   - Write tests first (RED)
   - Implement to pass tests (GREEN)
   - Refactor (IMPROVE)
   - Verify 80%+ coverage

3. **Code Review**
   - Use **code-reviewer** agent immediately after writing code
   - Address CRITICAL and HIGH issues
   - Fix MEDIUM issues when possible

4. **Commit & Push**
   - Detailed commit messages
   - Follow conventional commits format
   - See [git-workflow.md](./git-workflow.md) for commit message format and PR process
