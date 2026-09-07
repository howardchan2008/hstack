# Security Guidelines

## Before any commit
No hardcoded secrets. Inputs validated. Parameterized queries. Sanitized HTML. CSRF protection. Auth verified. Rate limiting on endpoints. Errors leak nothing sensitive.

## Secrets
Environment variables or a secret manager, never source. Validate required secrets at startup. Rotate anything that may have been exposed.

## If a security issue is found
Stop, run the security-reviewer pass, fix CRITICAL before continuing, rotate exposed secrets, then sweep the codebase for the same pattern.

## A guard inside a wrapper is not a guard
A spend control or safety check inside a CLI protects only callers who use that CLI. The agent holds a shell, so the billing endpoint is always one `curl` away. This has cost real money twice: a credit check built into an image CLI was bypassed the same hour by calling the endpoint directly, and an earlier run used a Google endpoint whose key sat outside the credit assumed to cover it.
- **Put the control at PreToolUse.** It is the only layer between the agent and every path.
- **Order the checks so the expensive verb decides first.** A read-allow rule matching a PREFIX of a billing path is a hole: `/models/` appears inside `:generateContent`, `/deployments/` inside `/images/generations`.
- **Keep the audit path open** (listing models, reading usage), or shutting a lane down safely becomes impossible.
- **An override must be explicit and greppable**, never a silent exception.
