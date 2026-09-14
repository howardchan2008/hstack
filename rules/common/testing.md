# Testing Requirements

80% minimum coverage (not existing repos claim; measured 2026-08-14: 8 repos tests, 1 config, 2 E2E runners).

Required: unit, integration (API/DB), E2E critical flows.

TDD mandatory: test (RED) → fail → implement (GREEN) → pass → refactor → verify coverage.

Failing tests: check isolation → mocks → fix implementation, not test (unless test wrong).