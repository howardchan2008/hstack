# Repo Hygiene (standing rule 2026-06-26)

Applies to every git repo. Note: the `claude` repo is PRIVATE (verified 2026-09-04), so the business-content clause does not bite there.

## Code-only repos
Keep: source, config, schema/migrations, tests, CI workflows, build files, and repo-meta (README, LICENSE, SECURITY, CONTRIBUTING, AGENTS). Engineering docs that document the code stay (architecture notes, runbooks, `.claude/`, `.github/`).
Out of a SHARED repo, kept locally on disk: decks, notes, screenshots, generated artifacts, business/strategy/fundraising/legal content, SOT and personal docs.

## Branch discipline
main is canonical. Short-lived branches, merge, delete. No stale, merged, dependabot or worktree branches on the remote. Bundle before any bulk branch delete or history rewrite.

## Mechanism (non-destructive)
`git rm -r --cached <path>` leaves the file on disk, then add it to `.gitignore`. NEVER `rm` the local file.

## Keep only the latest version
No `v1`/`v2`/`-old`/`_archive` duplicates tracked. Two files covering the same thing: keep the newest.

## Already-shared content
`git rm --cached` stops future sharing, but history still holds it. A real scrub needs `git filter-repo` plus force-push, which breaks collaborators' clones: coordinate first and treat it as destructive.
