# Security Guidelines

## Before any commit
No hardcoded secrets.
Inputs validated.
Parameterized queries.
Sanitized HTML.
CSRF protection.
Auth verified.
Rate limiting on endpoints.
Errors leak nothing sensitive.

## Secrets
Environment variables or secret manager, never source.
Validate required secrets at startup.
Rotate exposed secrets.

## If a security issue is found
Stop.
Run security-reviewer pass.
Fix CRITICAL before continuing.
Rotate exposed secrets.
Sweep codebase for same pattern.

## A guard inside a wrapper is not a guard
Guards inside CLI protect only CLI callers.
Agent has shell, endpoint always one `curl` away.
Cost real money twice: image CLI check bypassed by direct endpoint call, Google endpoint key outside assumed scope.

- **Put the control at PreToolUse.** Only layer between agent and every path.
- **Order the checks so the expensive verb decides first.** Read-allow rule matching PREFIX of billing path = hole: `/models/` in `:generateContent`, `/deployments/` in `/images/generations`.
- **Keep the audit path open** (listing models, reading usage) or unsafe shutdown.
- **An override must be explicit and greppable**, never a silent exception.