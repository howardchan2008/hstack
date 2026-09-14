# Repo Hygiene (standing rule 2026-06-26)

Applies to every git repo. `claude` repo PRIVATE (verified 2026-09-04) — business-content clause N/A.

## Code-only repos

Keep: source, config, schema/migrations, tests, CI workflows, build files, repo-meta (README, LICENSE, SECURITY, CONTRIBUTING, AGENTS), engineering docs (architecture notes, runbooks, `.claude/`, `.github/`).

Out of SHARED repos, keep locally: decks, notes, screenshots, artifacts, business/strategy/fundraising/legal, SOT, personal.

## Branch discipline

main canonical. Short-lived branches: merge → delete. No stale/merged/dependabot/worktree on remote. Bundle before bulk delete/rewrite.

## Mechanism (non-destructive)

`git rm -r --cached <path>` leaves file on disk; add to `.gitignore`. NEVER `rm` local file.

## Keep only the latest version

No `v1`/`v2`/`-old`/`_archive` duplicates. Keep newest when two files cover same thing.

## Already-shared content

`git rm --cached` stops future sharing; history persists. Real scrub: `git filter-repo` + force-push (breaks others' clones). Coordinate first; treat as destructive.