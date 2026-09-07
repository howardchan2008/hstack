# Testing Requirements

80% minimum coverage for code being written (not a claim about existing repos: measured 2026-08-14, 8 repos have tests, 1 has a coverage config, 2 have an E2E runner).

Required types: unit, integration (API and DB), E2E for critical flows.

TDD is mandatory: write the test (RED), see it fail, minimal implementation (GREEN), see it pass, refactor, verify coverage.

Failing tests: check isolation, then the mocks, then fix the implementation rather than the test, unless the test is what is wrong.
