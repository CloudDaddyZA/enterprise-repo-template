# Tests

This directory contains all test suites for the project.

## Structure

```
tests/
├── unit/              # Unit tests (fast, isolated)
├── integration/       # Integration tests (external dependencies)
├── e2e/               # End-to-end tests (full system)
└── fixtures/          # Shared test data and mocks
```

## Running Tests

```bash
# Run all tests
# npm test / dotnet test / go test ./... / pytest

# Run unit tests only
# npm run test:unit / pytest tests/unit/

# Run with coverage
# npm run test:coverage / pytest --cov=src tests/

# Run integration tests (requires environment setup)
# npm run test:integration / pytest tests/integration/
```

## Guidelines

- Unit tests should be fast (< 100ms each)
- Integration tests should use test containers or mocks
- E2E tests should run against a staging-like environment
- Aim for >80% code coverage on critical paths
- Name tests clearly: `should_[expected]_when_[condition]`
- Use fixtures for shared test data
- Never commit real credentials in test files
