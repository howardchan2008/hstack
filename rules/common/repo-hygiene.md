# Repo Hygiene (the owner standing rule - added 2026-06-26)

Applies to EVERY git repo, public AND private. Enforce whenever touching any repo; apply to new files on sight.

## Code-only repos

Only code belongs in a repo. Keep in the repo:
- source, config, schema/migrations, tests, CI workflows, build/package files
- standard repo-meta: README, LICENSE, SECURITY, CONTRIBUTING, AGENTS / AGENT-INSTRUCTIONS

Technical documentation that documents the code stays (architecture notes, schema/RLS runbooks, deploy notes, `.claude/` agent tooling, `.github/` templates) - the line removes BUSINESS and PERSONAL content, not engineering docs that belong next to the code.

Out of the repo (stays local in the working copy; the working tree is the private copy, only pushed content is shared):
- decks, notes, screenshots/media, generated artifacts, sample/case-study output
- business / strategy / fundraising / pitch / competitor / legal / compliance content
- source-of-truth and personal docs

## Branch discipline

main is canonical. Branch off main, keep it short-lived, merge, delete. No long-lived parallel branches, no stale/merged/dependabot/worktree branches left on the remote - prune to main + active short-lived branches only ("retain most updated"). Back up (bundle) before any bulk branch delete or history rewrite.

## Mechanism (non-destructive)

- Remove tracked non-code with `git rm -r --cached <path>` - this leaves the file on disk (the private copy) and drops it from the shared remote.
- Add the path to `.gitignore` so it never re-enters. Mirror the existing local-only pattern (e.g. `outreach/`, `projects/`, `docs/`, `design/`).
- NEVER delete the local file as part of this - untrack, don't `rm`.

## Keep only the latest version

Remove all non-updated / superseded versions; retain only the most-updated canonical file. No `v1`/`v2`/`-old`/`_archive` duplicates tracked in the repo. When two files cover the same thing, keep the newest and drop the rest.

## Caveat on already-shared content

`git rm --cached` stops future sharing and removes the file from the current tree, but past commits still contain it - anyone with the repo can recover it from `git log`. For sensitive data already pushed, a full scrub needs a history rewrite (`git filter-repo`) + force-push; that is disruptive on a shared repo (breaks collaborators' clones) - coordinate before doing it, and treat it as a careful/destructive op.

## Why

Repos are often shared (collaborators, contractors, public). Business, strategy, and personal content must not leak through a shared repo. Keeping repos code-only also avoids bloat and stale-version confusion.
