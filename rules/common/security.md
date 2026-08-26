# Security Guidelines

## Mandatory Security Checks

Before ANY commit:
- [ ] No hardcoded secrets (API keys, passwords, tokens)
- [ ] All user inputs validated
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (sanitized HTML)
- [ ] CSRF protection enabled
- [ ] Authentication/authorization verified
- [ ] Rate limiting on all endpoints
- [ ] Error messages don't leak sensitive data

## Secret Management

- NEVER hardcode secrets in source code
- ALWAYS use environment variables or a secret manager
- Validate that required secrets are present at startup
- Rotate any secrets that may have been exposed

## Security Response Protocol

If security issue found:
1. STOP immediately
2. Use **security-reviewer** agent
3. Fix CRITICAL issues before continuing
4. Rotate any exposed secrets
5. Review entire codebase for similar issues

## A guard inside a wrapper is not a guard

A spend control, a rate limit or a safety check placed inside a CLI protects
only the callers who use that CLI. The agent holds a shell, so the same billing
endpoint is always one `curl` away, and the wrapper is one path among several.

This has cost real money twice. A credit check was built into an image CLI,
demonstrated refusing correctly, and then bypassed the same hour by calling the
endpoint directly to settle a factual argument. An earlier incident ran through
a Google generative endpoint whose key sits outside the credit that was assumed
to cover it.

- **Put the control at PreToolUse.** That is the only layer between the agent
  and every path to the endpoint. Anywhere else is a suggestion.
- **Order the checks so the expensive verb decides first.** A read-allow rule
  that matches a PREFIX of a billing path is a hole shaped exactly like the
  incident: `/models/` appears inside `:generateContent`, and `/deployments/`
  inside `/images/generations`. Both walked through the first version of the
  guard until a negative control caught them.
- **Keep the audit path open.** Listing models, reading usage and management
  commands must still work, or shutting a lane down safely becomes impossible.
- **An override must be explicit and greppable**, never a silent exception.
