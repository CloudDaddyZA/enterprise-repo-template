# ============================================================================
# GitHub Copilot Instructions
# ============================================================================
# These instructions guide GitHub Copilot's behavior in this repository.
# They establish coding standards, security requirements, and conventions.
# ============================================================================

## Project Context

This is an enterprise application following strict governance and security standards.

## Coding Standards

- Follow conventional commits for all commit messages
- Use meaningful variable and function names (no abbreviations)
- Keep functions small and focused (single responsibility)
- Prefer composition over inheritance
- Write self-documenting code; add comments only for complex business logic
- All public APIs must have documentation

## Security Requirements (MANDATORY)

- NEVER hardcode secrets, API keys, tokens, or passwords
- NEVER log sensitive data (PII, credentials, tokens)
- Always validate and sanitize user input at system boundaries
- Use parameterized queries for database operations (prevent SQL injection)
- Implement proper authentication and authorization checks
- Use HTTPS for all external communications
- Follow the principle of least privilege for all access controls
- Encode output to prevent XSS attacks
- Use secure random number generation for security-sensitive operations

## Architecture Conventions

- Follow the project's established directory structure
- Infrastructure as Code: Terraform for multi-cloud, Bicep for Azure-only
- Use environment variables for configuration (12-factor app)
- Implement health check endpoints for all services
- Use structured logging (JSON format)
- Include correlation IDs for distributed tracing

## Testing Requirements

- Write unit tests for all business logic
- Include edge cases and error scenarios in tests
- Use descriptive test names: `should_[expected]_when_[condition]`
- Mock external dependencies in unit tests
- Integration tests should use test containers

## Error Handling

- Use specific exception types (not generic catch-all)
- Include context in error messages
- Never expose stack traces or internal details to end users
- Log errors with sufficient context for debugging
- Implement retry logic with exponential backoff for transient failures

## Dependencies

- Prefer well-maintained, widely-used libraries
- Check for known vulnerabilities before adding dependencies
- Pin dependency versions for reproducible builds
- Minimize dependency count to reduce attack surface

## Git Conventions

- Branch names: `feature/<ticket>-description`, `fix/<ticket>-description`
- PR titles follow conventional commits format
- Keep PRs small and focused (< 400 lines changed ideal)
- Squash merge feature branches to main
