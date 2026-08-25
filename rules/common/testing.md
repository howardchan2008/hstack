# Testing Requirements

## Minimum Test Coverage: 80%

This is the bar for code being written, not a description of the repos. Measured 2026-08-14
across every repo under `~/repos`: 8 have tests, 1 has a coverage config, 2 have an E2E
runner. Do not read the requirement as a claim that it is already met somewhere.

Test Types (ALL required):
1. **Unit Tests** - Individual functions, utilities, components
2. **Integration Tests** - API endpoints, database operations
3. **E2E Tests** - Critical user flows (framework chosen per language)

## Test-Driven Development

MANDATORY workflow:
1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
5. Refactor (IMPROVE)
6. Verify coverage (80%+)

## Failing tests

Check isolation, then the mocks, then fix the implementation rather than the test (unless
the test is the thing that is wrong). **tdd-guide** owns this and the write-tests-first pass.
